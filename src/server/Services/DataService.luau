--!strict
--[[
	DataService — profile graczy: wczytanie, zmiana, zapis, replikacja.

	ŻELAZNA ZASADA ZESPOŁOWA: żaden inny moduł nie modyfikuje profilu wprost.
	Każda zmiana idzie przez `DataService.mutate`. Dzięki temu w jednym miejscu
	dzieje się:
	  * replikacja snapshotu do klienta,
	  * aktualizacja leaderstats,
	  * oznaczenie profilu jako "brudny" do zapisu.
	Gdy ktoś zmieni `profile.coins` z boku, UI się rozjedzie z serwerem i będziecie
	tego szukać godzinę. Nie ma od tego wyjątków.

	OGRANICZENIE, O KTÓRYM TRZEBA WIEDZIEĆ:
	Nie ma tu session lockingu. Jeśli ten sam gracz trafi na dwa serwery naraz
	(teleport między miejscami, szybki rejoin), ostatni zapis wygrywa i da się
	zduplikować przedmioty. Dla MVP to akceptowalne, bo mamy jedno miejsce.
	Przed publicznym wydaniem: przejdźcie na ProfileStore
	(`wally add grilme99/profilestore`) — robi lock, retry i migracje za nas.
	Nie piszcie tego sami, to jest trudniejsze, niż wygląda.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local Net = require(ReplicatedStorage.Shared.Net)
local Rods = require(ReplicatedStorage.Shared.Config.Rods)
local Types = require(ReplicatedStorage.Shared.Types)

type Profile = Types.Profile
type CaughtFish = Types.CaughtFish

local DataService = {}

local profiles: { [Player]: Profile } = {}
local store: DataStore? = nil
local persistenceEnabled = false

-- Serwisy, które chcą coś zrobić dokładnie raz, gdy profil się wczyta.
local readyListeners: { (Player) -> () } = {}

-- ---------------------------------------------------------------------------
-- Domyślny profil i walidacja wczytanych danych
-- ---------------------------------------------------------------------------

local function defaultProfile(): Profile
	return {
		coins = GameConfig.STARTING_COINS,
		totalCaught = 0,
		ownedRods = { [GameConfig.STARTING_ROD] = true },
		equippedRod = GameConfig.STARTING_ROD,
		inventory = {},
		records = {},
		totalEarned = 0,
	}
end

local function readNumber(value: unknown, fallback: number, minimum: number): number
	if typeof(value) ~= "number" then
		return fallback
	end
	local number = value :: number
	-- NaN nie jest równy sobie. Bez tej kontroli jedno NaN w DataStore
	-- zatruwa cały profil i każda arytmetyka na nim daje NaN.
	if number ~= number or number == math.huge or number == -math.huge then
		return fallback
	end
	return math.max(number, minimum)
end

--[[
	Przepisuje surowe dane z DataStore na poprawny `Profile`.

	Wszystko, czego nie rozpoznajemy, jest wyrzucane. Brzmi brutalnie, ale
	alternatywą jest wpuszczenie do gry profilu o nieznanym kształcie i
	wywrócenie się trzy warstwy dalej, gdy `#profile.inventory` dostanie string.
	Ta funkcja jest też naszą ścieżką migracji: gdy dojdzie nowe pole,
	stare profile dostaną dla niego wartość domyślną i tyle.
]]
local function sanitize(raw: unknown): Profile
	local profile = defaultProfile()

	if typeof(raw) ~= "table" then
		return profile
	end

	local data = raw :: { [string]: unknown }

	profile.coins = math.floor(readNumber(data.coins, profile.coins, 0))
	profile.totalCaught = math.floor(readNumber(data.totalCaught, 0, 0))

	if typeof(data.ownedRods) == "table" then
		for rodId, owned in data.ownedRods :: { [string]: unknown } do
			-- Odrzucamy wędki, których już nie ma w configu (usunięty tier).
			if typeof(rodId) == "string" and owned == true and Rods.find(rodId) then
				profile.ownedRods[rodId] = true
			end
		end
	end
	-- Startowa wędka zawsze jest — inaczej gracz zostałby bez narzędzia.
	profile.ownedRods[GameConfig.STARTING_ROD] = true

	if typeof(data.equippedRod) == "string" then
		local rodId = data.equippedRod :: string
		if profile.ownedRods[rodId] then
			profile.equippedRod = rodId
		end
	end

	if typeof(data.inventory) == "table" then
		for _, entry in data.inventory :: { unknown } do
			if #profile.inventory >= GameConfig.MAX_INVENTORY then
				break
			end
			if typeof(entry) ~= "table" then
				continue
			end

			local fishEntry = entry :: { [string]: unknown }
			if typeof(fishEntry.fishId) ~= "string" then
				continue
			end

			local caught: CaughtFish = {
				fishId = fishEntry.fishId :: string,
				mass = readNumber(fishEntry.mass, 0, 0),
				price = math.floor(readNumber(fishEntry.price, 0, 0)),
			}
			table.insert(profile.inventory, caught)
		end
	end

	if typeof(data.records) == "table" then
		for fishId, mass in data.records :: { [string]: unknown } do
			if typeof(fishId) == "string" then
				profile.records[fishId] = readNumber(mass, 0, 0)
			end
		end
	end

	-- `totalEarned` doszło po pierwszym wydaniu. Stare profile nie mają tego
	-- pola i dostają 0 — czyli weterani startują w rankingu od zera. Lepsze
	-- to niż zgadywanie wartości z `coins`, bo monety są wydawane i dałyby
	-- liczbę niższą od prawdy u każdego, kto cokolwiek kupił.
	profile.totalEarned = math.floor(readNumber(data.totalEarned, 0, 0))

	-- Pola, których tu nie ma, są po prostu pomijane — i to jest cała nasza
	-- ścieżka migracji W OBIE STRONY. Usunięcie funkcji (np. zadań dziennych)
	-- nie wymaga żadnego kodu czyszczącego: stare profile mają w DataStore
	-- osierocony klucz, którego `sanitize` nie przepisuje, i przy pierwszym
	-- zapisie znika sam.
	return profile
end

-- ---------------------------------------------------------------------------
-- Warstwa DataStore
-- ---------------------------------------------------------------------------

local function keyFor(player: Player): string
	return `player_{player.UserId}`
end

--[[
	Ponawia operację na DataStore z rosnącym odstępem.

	DataStore'y padają — limit zapytań, chwilowa awaria Roblox, timeout.
	Jedna nieudana próba to nie powód, żeby gracz stracił postęp.
]]
local function retry<T>(label: string, operation: () -> T): (boolean, T?)
	for attempt = 1, GameConfig.DATASTORE_RETRIES do
		local ok, result = pcall(operation)
		if ok then
			return true, result
		end

		warn(
			`[DataService] {label}: próba {attempt}/{GameConfig.DATASTORE_RETRIES} nieudana — {tostring(
				result
			)}`
		)

		if attempt < GameConfig.DATASTORE_RETRIES then
			task.wait(GameConfig.DATASTORE_RETRY_DELAY * attempt)
		end
	end

	return false, nil
end

--[[
	Sprawdza raz na starcie, czy DataStore w ogóle działa.

	W Studio bez "Enable Studio Access to API Services" każdy odczyt rzuca
	błędem. Zamiast zalewać output ostrzeżeniem przy każdym graczu, mówimy
	to raz, wyraźnie, i jedziemy dalej na pamięci. Gra ma się dać testować
	nawet bez włączonego API — zgadywanie "dlaczego nic się nie zapisuje"
	to strata czasu całego zespołu.
]]
local function probePersistence()
	local ok, resolved = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DATASTORE_NAME)
	end)

	if not ok or not resolved then
		store = nil
		persistenceEnabled = false
	else
		local activeStore = resolved :: DataStore
		store = activeStore
		local probeOk, err = pcall(function()
			activeStore:GetAsync("__probe")
		end)
		persistenceEnabled = probeOk
		if not probeOk then
			warn(`[DataService] odczyt z DataStore nie działa: {tostring(err)}`)
		end
	end

	if not persistenceEnabled then
		warn(
			"[DataService] POSTĘP NIE JEST ZAPISYWANY. Gra działa na danych w pamięci.\n"
				.. "  Studio: Game Settings -> Security -> Enable Studio Access to API Services.\n"
				.. "  Lokalny plik bez publikacji: DataStore nie zadziała w ogóle — opublikuj miejsce."
		)
	end
end

local function loadProfile(player: Player): Profile
	if not persistenceEnabled or not store then
		return defaultProfile()
	end

	local activeStore = store :: DataStore
	local ok, raw = retry(`wczytanie {player.Name}`, function()
		-- GetAsync zwraca (wartość, DataStoreKeyInfo). Przypisujemy do jednej
		-- zmiennej, żeby `retry` dostało pojedynczą wartość, a nie parę.
		local value = activeStore:GetAsync(keyFor(player))
		return value
	end)

	if not ok then
		-- Świadomie NIE dajemy pustego profilu po nieudanym odczycie —
		-- zapis nadpisałby prawdziwe dane gracza zerami. Lepiej niech
		-- zagra tę sesję "na czysto" i nic nie zapisze.
		warn(`[DataService] nie udało się wczytać {player.Name} — sesja bez zapisu`)
		return defaultProfile()
	end

	return sanitize(raw)
end

local function saveProfile(player: Player, profile: Profile): boolean
	if not persistenceEnabled or not store then
		return false
	end

	local activeStore = store :: DataStore
	-- UpdateAsync, nie SetAsync: jeśli coś zapisało się w międzyczasie,
	-- dostajemy aktualną wartość i decydujemy świadomie. SetAsync po prostu
	-- nadpisuje i gubi zmiany.
	local ok = retry(`zapis {player.Name}`, function()
		activeStore:UpdateAsync(keyFor(player), function()
			return profile
		end)
		return true
	end)

	return ok
end

-- ---------------------------------------------------------------------------
-- Leaderstats
-- ---------------------------------------------------------------------------
-- To tylko projekcja profilu na wbudowaną tabelę wyników Roblox.
-- Trzymamy ją tutaj, bo odświeża się dokładnie wtedy, co profil.

local COINS_STAT = "Monety"
local CAUGHT_STAT = "Złowione"

--[[
	Zwraca folder leaderstats, tworząc go przy pierwszym wywołaniu.

	Osobna funkcja z konkretnym typem zwrotu, a nie `if not container then
	container = ... end` w jednym ciele: po takim przypisaniu analizator Luau
	nadal widzi `Instance?` i każde kolejne użycie jest błędem "could be nil".
	Wczesny return rozwiązuje to bez ani jednego rzutowania.
]]
local function ensureLeaderstats(player: Player): Folder
	local existing = player:FindFirstChild("leaderstats")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"

	local coins = Instance.new("IntValue")
	coins.Name = COINS_STAT
	coins.Parent = folder

	local caught = Instance.new("IntValue")
	caught.Name = CAUGHT_STAT
	caught.Parent = folder

	folder.Parent = player
	return folder
end

local function syncLeaderstats(player: Player, profile: Profile)
	local container = ensureLeaderstats(player)

	local coinsValue = container:FindFirstChild(COINS_STAT)
	if coinsValue and coinsValue:IsA("IntValue") then
		coinsValue.Value = profile.coins
	end

	local caughtValue = container:FindFirstChild(CAUGHT_STAT)
	if caughtValue and caughtValue:IsA("IntValue") then
		caughtValue.Value = profile.totalCaught
	end
end

-- ---------------------------------------------------------------------------
-- API publiczne
-- ---------------------------------------------------------------------------

--[[ Profil gracza albo nil, gdy jeszcze się wczytuje / gracz już wyszedł. ]]
function DataService.get(player: Player): Profile?
	return profiles[player]
end

--[[
	Czeka, aż profil się wczyta. YIELDUJE. Zwraca nil, gdy minął timeout
	albo gracz w międzyczasie wyszedł.

	Potrzebne serwisom, które startują na `CharacterAdded`: postać powstaje
	od razu, a odczyt z DataStore trwa. Bez tego wędka trafiałaby do plecaka
	zanim wiadomo, którą gracz ma założoną.
]]
function DataService.waitFor(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 10)

	while true do
		local profile = profiles[player]
		if profile then
			return profile
		end
		if not player:IsDescendantOf(Players) or os.clock() >= deadline then
			return nil
		end
		task.wait(0.1)
	end
end

--[[
	Wysyła pełny snapshot profilu do klienta i odświeża leaderstats.

	Snapshot, nie diff: profil ma kilka kilobajtów, a diffowanie to własny
	protokół, własne bugi i własne testy. Nie warto na tym etapie.
]]
function DataService.push(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end

	syncLeaderstats(player, profile)
	Net.ProfileUpdated:FireClient(player, profile)
end

--[[
	Rejestruje reakcję na wczytanie profilu gracza.

	Zastępuje wzorzec „zapętl `waitFor` w każdym serwisie": tamto działa,
	ale każdy serwis odpytuje osobno i każdy musi sam obsłużyć przypadek
	gracza, który wyszedł w trakcie. Tutaj jest to raz, w jednym miejscu.

	Callback leci też dla graczy, którzy mają profil JUŻ TERAZ — serwis
	startujący po DataService (albo wgrany hot-reloadem) nie może ich pominąć.
]]
function DataService.onProfileReady(listener: (Player) -> ())
	table.insert(readyListeners, listener)

	for player in profiles do
		task.spawn(listener, player)
	end
end

--[[
	Jedyna droga do zmiany profilu.

	Zwraca false, gdy profil nie jest gotowy — wywołujący ma wtedy przerwać
	swoją operację, a nie udawać, że się udała.

	    local ok = DataService.mutate(player, function(profile)
	        profile.coins += 100
	    end)
]]
function DataService.mutate(player: Player, mutator: (Profile) -> ()): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end

	mutator(profile)
	DataService.push(player)
	return true
end

function DataService.save(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	return saveProfile(player, profile)
end

function DataService.start()
	probePersistence()

	local function onPlayerAdded(player: Player)
		local profile = loadProfile(player)

		-- Gracz mógł wyjść w trakcie odczytu z DataStore (to zajmuje chwilę).
		-- Bez tej kontroli trzymalibyśmy w pamięci profil kogoś, kogo już nie ma,
		-- i próbowali do niego strzelać Remote'em.
		if not player:IsDescendantOf(Players) then
			return
		end

		profiles[player] = profile
		DataService.push(player)

		for _, listener in table.clone(readyListeners) do
			-- `task.spawn`, bo listener może yieldować (np. zapis po
			-- wygenerowaniu zadań), a to nie może blokować wejścia kolejnych
			-- graczy. `xpcall` — bo jeden wywrócony serwis nie może zabrać
			-- ze sobą pozostałych.
			task.spawn(function()
				xpcall(listener, function(err)
					warn(`[DataService] listener profilu rzucił błędem: {tostring(err)}`)
					warn(debug.traceback(nil, 2))
				end, player)
			end)
		end
	end

	-- Gracze, którzy weszli przed startem tego serwisu (przy Rojo sync
	-- i hot-reloadzie zdarza się to notorycznie).
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	-- Klient prosi o snapshot po zamontowaniu UI (patrz Net.RequestProfile).
	-- Throttle, bo to publiczny endpoint: bez niego spam Remote'em zmusza
	-- serwer do serializowania profilu tyle razy na sekundę, ile wyrobi klient.
	local lastRequestAt: { [Player]: number } = {}
	Net.RequestProfile.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if now - (lastRequestAt[player] or -1) < 1 then
			return
		end
		lastRequestAt[player] = now
		DataService.push(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRequestAt[player] = nil
	end)

	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		profiles[player] = nil
		if profile then
			saveProfile(player, profile)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(GameConfig.AUTOSAVE_INTERVAL)

			-- Najpierw zdjęcie listy graczy, potem zapisy. Iterowanie po
			-- `profiles` z `task.wait` w środku to proszenie się o błąd:
			-- gracz dołączający w trakcie dodaje klucz do tabeli, po której
			-- aktualnie chodzi `next`, a to w Luau jest niezdefiniowane.
			local pending: { Player } = {}
			for player in profiles do
				table.insert(pending, player)
			end

			for _, player in pending do
				local profile = profiles[player]
				if profile then
					saveProfile(player, profile)
					-- Rozkładamy zapisy w czasie, zamiast walić wszystkimi
					-- naraz w limit zapytań DataStore.
					task.wait(0.4)
				end
			end
		end
	end)

	game:BindToClose(function()
		-- W Studio BindToClose odpala się przy każdym zatrzymaniu testu.
		-- Bez tego wyjścia każdy Stop kosztowałby kilka sekund czekania.
		if RunService:IsStudio() and not persistenceEnabled then
			return
		end

		for player, profile in profiles do
			saveProfile(player, profile)
		end
	end)
end

return DataService
