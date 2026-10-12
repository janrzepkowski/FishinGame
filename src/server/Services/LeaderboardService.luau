--!strict
--[[
	LeaderboardService — globalny ranking zarobków na OrderedDataStore.

	Rankingujemy `totalEarned` (suma zarobiona przez całe życie konta),
	a NIE `coins`. Gdyby liczyły się monety w kieszeni, zakup wędki cofałby
	gracza w rankingu — czyli gra karałaby za granie w nią zgodnie z zamysłem.

	=========================================================================
	DLACZEGO OrderedDataStore, A NIE ZWYKŁY DataStore
	=========================================================================
	Zwykły DataStore nie umie posortować. Żeby zrobić z niego ranking, trzeba
	by trzymać osobną listę wszystkich graczy i sortować ją ręcznie — co przy
	tysiącu kont oznacza odczyt tysiąca kluczy. OrderedDataStore robi to
	po stronie Robloxa jednym zapytaniem.

	Ograniczenie, o którym trzeba wiedzieć: OrderedDataStore przyjmuje
	WYŁĄCZNIE liczby całkowite. Stąd `math.floor` przy zapisie.

	=========================================================================
	DLACZEGO RANKING MA DWA ŹRÓDŁA
	=========================================================================
	Sam DataStore jest spóźniony o cykl zapisu i odczytu, a w Studio bez
	dostępu do API nie ma go wcale. Gracz sprzedawał połów i przez kilka
	minut nie widział w rankingu kolegi stojącego obok — a czasem nigdy,
	bo wynik gracza, który wyszedł przed cyklem, w ogóle nie był zapisywany.

	Dlatego do zapisanej czołówki dokładamy BIEŻĄCE wyniki graczy z tego
	serwera (`Ranking.merge`). Trzymamy je u siebie w `latest`, a nie
	czytamy z `DataService.get` w momencie zapisu: przy wyjściu gracza
	DataService zdejmuje profil we własnym handlerze `PlayerRemoving`
	i nasz handler dostawał już `nil`.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local Net = require(ReplicatedStorage.Shared.Net)
local Ranking = require(ReplicatedStorage.Shared.Util.Ranking)
local Types = require(ReplicatedStorage.Shared.Types)

local DataService = require(script.Parent.DataService)

local LeaderboardService = {}

local store: OrderedDataStore? = nil

-- Czołówka z ostatniego odczytu OrderedDataStore. Pusta, gdy DataStore
-- nie działa — wtedy ranking składa się z samych graczy na serwerze.
local storedRows: { Ranking.Row } = {}

-- Bieżący `totalEarned` każdego gracza na serwerze. Własna kopia, bo przy
-- wyjściu gracza profilu w DataService już nie ma (patrz nagłówek).
local latest: { [Player]: number } = {}

-- Ostatnia wartość zapisana dla gracza. Chroni przed pisaniem tej samej
-- liczby w kółko przy cyklicznym zapisie.
local submitted: { [Player]: number } = {}

-- Gracze z zaplanowanym zapisem po zmianie wyniku.
local pendingSubmit: { [Player]: boolean } = {}

-- userId -> nazwa. `GetNameFromUserIdAsync` to zapytanie sieciowe, a te same
-- osoby siedzą w czołówce godzinami — bez cache odpytywalibyśmy Roblox
-- o te same osiem nazw co minutę.
local nameCache: { [number]: string } = {}

local function resolveName(userId: number): string
	local known = nameCache[userId]
	if known then
		return known
	end

	-- Gracz na serwerze: nazwę mamy lokalnie, bez zapytania.
	local online = Players:GetPlayerByUserId(userId)
	if online then
		nameCache[userId] = online.DisplayName
		return online.DisplayName
	end

	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)

	local resolved = if ok and typeof(name) == "string" then name else `Gracz {userId}`
	nameCache[userId] = resolved
	return resolved
end

--[[
	Składa ranking z obu źródeł i rozsyła go wszystkim.

	Nie dotyka DataStore, więc można to wołać przy każdej sprzedaży —
	to tylko sortowanie kilkudziesięciu wierszy.
]]
local function broadcast()
	local live: { Ranking.Row } = {}
	for player, value in latest do
		table.insert(live, { userId = player.UserId, name = player.DisplayName, value = value })
	end

	local entries: { Types.LeaderboardEntry } = {}
	for _, row in Ranking.merge(storedRows, live, GameConfig.LEADERBOARD_SIZE) do
		table.insert(entries, { name = row.name, value = row.value })
	end

	Net.LeaderboardUpdated:FireAllClients(entries)
end

--[[
	Zapisuje wynik gracza. Cicho pomija, gdy DataStore nie działa.

	`UpdateAsync` z `math.max`, a NIE `SetAsync`. Przy jednym serwerze różnicy
	nie widać, ale przy kilkudziesięciu wygląda to tak: gracz gra, wychodzi,
	wchodzi na inny serwer i gra dalej. Jeśli spóźniony zapis ze starego
	serwera dotrze PO zapisie z nowego, `SetAsync` cofnąłby mu wynik.
	`totalEarned` rośnie monotonicznie, więc maksimum jest zawsze poprawne —
	a zapis, który przyszedł nie w kolejności, po prostu nic nie robi.

	Pomijamy też zapis, gdy wartość się nie zmieniła od ostatniego razu.
]]
function LeaderboardService.submit(player: Player)
	local activeStore = store
	local value = latest[player]
	if not activeStore or not value then
		return
	end

	if value <= 0 then
		-- Nie zaśmiecamy rankingu zerami. Gracz, który nic nie zarobił,
		-- nie ma po co być w indeksie.
		return
	end

	if (submitted[player] or 0) >= value then
		return
	end
	submitted[player] = value

	-- `player` może zniknąć, zanim zapis się skończy — klucz i nazwę
	-- bierzemy teraz, a nie w środku wątku.
	local key = tostring(player.UserId)
	local playerName = player.Name

	task.spawn(function()
		local ok, err = pcall(function()
			activeStore:UpdateAsync(key, function(stored)
				local previous = if typeof(stored) == "number" then stored else 0
				return math.max(previous, value)
			end)
		end)
		if not ok then
			-- Cofamy znacznik: następny cykl spróbuje ponownie, zamiast
			-- uznać nieudany zapis za zrobiony.
			if submitted[player] == value then
				submitted[player] = nil
			end
			warn(`[LeaderboardService] zapis {playerName} nie przeszedł: {tostring(err)}`)
		end
	end)
end

--[[ Zapis krótko po zmianie wyniku, ale nie przy każdej z osobna: seria
     sprzedaży w pół minuty kończy się jednym zapytaniem. ]]
local function scheduleSubmit(player: Player)
	if pendingSubmit[player] then
		return
	end
	pendingSubmit[player] = true

	task.delay(GameConfig.LEADERBOARD_SUBMIT_DEBOUNCE, function()
		if not pendingSubmit[player] then
			-- Gracz wyszedł; jego wynik zapisał już handler wyjścia.
			return
		end
		pendingSubmit[player] = nil
		LeaderboardService.submit(player)
	end)
end

local function refresh()
	local activeStore = store
	if not activeStore then
		return
	end

	local ok, pages = pcall(function()
		return activeStore:GetSortedAsync(false, GameConfig.LEADERBOARD_SIZE)
	end)

	if not ok or not pages then
		warn(`[LeaderboardService] odczyt rankingu nie przeszedł: {tostring(pages)}`)
		return
	end

	local okPage, page = pcall(function()
		return (pages :: DataStorePages):GetCurrentPage()
	end)

	if not okPage or not page then
		return
	end

	local rows: { Ranking.Row } = {}
	for _, entry in page :: { { key: string, value: number } } do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(rows, { userId = userId, name = resolveName(userId), value = entry.value })
		end
	end

	storedRows = rows
	broadcast()
end

function LeaderboardService.start()
	-- Śledzenie wyników podpinamy PRZED sprawdzeniem DataStore: bez niego
	-- ranking i tak działa, tylko obejmuje samych graczy z tego serwera.
	DataService.onProfileReady(function(player)
		local profile = DataService.get(player)
		latest[player] = if profile then math.floor(profile.totalEarned) else 0
		-- Rozsyłamy wszystkim, nie tylko wchodzącemu: pozostali mają
		-- zobaczyć nowego gracza od razu.
		broadcast()
	end)

	DataService.onProfileChanged(function(player, profile)
		local value = math.floor(profile.totalEarned)
		if value <= (latest[player] or 0) then
			-- Większość zmian profilu (złowiona ryba, zakup wędki) nie rusza
			-- zarobków i nie ma czego rozsyłać.
			return
		end

		latest[player] = value
		broadcast()
		scheduleSubmit(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local value = latest[player]
		LeaderboardService.submit(player)

		-- Wynik wychodzącego zostaje w czołówce do najbliższego odczytu
		-- DataStore, zamiast zniknąć na minutę i wrócić.
		if value and value > 0 then
			storedRows = Ranking.merge(storedRows, {
				{ userId = player.UserId, name = player.DisplayName, value = value },
			}, GameConfig.LEADERBOARD_SIZE)
		end

		latest[player] = nil
		submitted[player] = nil
		pendingSubmit[player] = nil
		broadcast()
	end)

	local ok, resolved = pcall(function()
		return DataStoreService:GetOrderedDataStore(GameConfig.LEADERBOARD_STORE)
	end)

	if not ok or not resolved then
		warn(
			"[LeaderboardService] OrderedDataStore niedostępny — ranking tylko z tej sesji.\n"
				.. "  Studio: Game Settings -> Security -> Enable Studio Access to API Services."
		)
		return
	end

	store = resolved

	--[[
		Zapis CYKLICZNY jako siatka bezpieczeństwa.

		Wynik idzie do DataStore krótko po każdej zmianie (`scheduleSubmit`)
		i przy wyjściu gracza. Cykl łapie to, co się nie udało: zapis
		odrzucony przez limit zapytań albo chwilową awarię DataStore.
		Niezmienione wartości są pomijane, więc w praktyce to kilka zapytań
		na minutę na serwer.
	]]
	task.spawn(function()
		while true do
			task.wait(GameConfig.LEADERBOARD_SUBMIT_INTERVAL)

			local pending: { Player } = {}
			for player in latest do
				table.insert(pending, player)
			end

			for _, player in pending do
				LeaderboardService.submit(player)
				-- Rozkładamy zapisy w czasie, zamiast wysyłać pięćdziesiąt
				-- naraz w tej samej klatce.
				task.wait(0.3)
			end
		end
	end)

	task.spawn(function()
		while true do
			refresh()
			task.wait(GameConfig.LEADERBOARD_REFRESH)
		end
	end)
end

return LeaderboardService
