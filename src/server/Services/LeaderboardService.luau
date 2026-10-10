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
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)

local DataService = require(script.Parent.DataService)

local LeaderboardService = {}

local store: OrderedDataStore? = nil
local cached: { Types.LeaderboardEntry } = {}

-- Ostatnia wartość zapisana dla gracza. Chroni przed pisaniem tej samej
-- liczby w kółko przy cyklicznym zapisie.
local submitted: { [Player]: number } = {}

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
	Zapisuje wynik gracza. Cicho pomija, gdy DataStore nie działa.

	`UpdateAsync` z `math.max`, a NIE `SetAsync`. Przy jednym serwerze różnicy
	nie widać, ale przy kilkudziesięciu wygląda to tak: gracz gra, wychodzi,
	wchodzi na inny serwer i gra dalej. Jeśli spóźniony zapis ze starego
	serwera dotrze PO zapisie z nowego, `SetAsync` cofnąłby mu wynik.
	`totalEarned` rośnie monotonicznie, więc maksimum jest zawsze poprawne —
	a zapis, który przyszedł nie w kolejności, po prostu nic nie robi.

	Pomijamy też zapis, gdy wartość się nie zmieniła od ostatniego razu.
	Przy cyklicznym zapisie co kilka minut większość graczy nic nie sprzedała
	i pisanie tej samej liczby zjadałoby limit zapytań bez powodu.
]]
function LeaderboardService.submit(player: Player)
	local activeStore = store
	local profile = DataService.get(player)
	if not activeStore or not profile then
		return
	end

	local value = math.floor(profile.totalEarned)
	if value <= 0 then
		-- Nie zaśmiecamy rankingu zerami. Gracz, który nic nie zarobił,
		-- nie ma po co być w indeksie.
		return
	end

	if (submitted[player] or 0) >= value then
		return
	end
	submitted[player] = value

	task.spawn(function()
		local ok, err = pcall(function()
			activeStore:UpdateAsync(tostring(player.UserId), function(stored)
				local previous = if typeof(stored) == "number" then stored else 0
				return math.max(previous, value)
			end)
		end)
		if not ok then
			-- Cofamy znacznik: następny cykl spróbuje ponownie, zamiast
			-- uznać nieudany zapis za zrobiony.
			submitted[player] = nil
			warn(`[LeaderboardService] zapis {player.Name} nie przeszedł: {tostring(err)}`)
		end
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

	local entries: { Types.LeaderboardEntry } = {}
	for _, row in page :: { { key: string, value: number } } do
		local userId = tonumber(row.key)
		if userId then
			table.insert(entries, { name = resolveName(userId), value = row.value })
		end
	end

	cached = entries

	for _, player in Players:GetPlayers() do
		Net.LeaderboardUpdated:FireClient(player, entries)
	end
end

function LeaderboardService.start()
	-- Nowy gracz dostaje aktualny ranking od razu, bez czekania na najbliższe
	-- odświeżenie. Podpinamy to PRZED sprawdzeniem DataStore: gdy ranking jest
	-- wyłączony, klient dostaje pustą listę i rysuje „ranking niedostępny"
	-- zamiast zostawać z pustą sekcją bez wyjaśnienia.
	DataService.onProfileReady(function(player)
		Net.LeaderboardUpdated:FireClient(player, cached)
	end)

	local ok, resolved = pcall(function()
		return DataStoreService:GetOrderedDataStore(GameConfig.LEADERBOARD_STORE)
	end)

	if not ok or not resolved then
		warn(
			"[LeaderboardService] OrderedDataStore niedostępny — ranking wyłączony.\n"
				.. "  Studio: Game Settings -> Security -> Enable Studio Access to API Services."
		)
		return
	end

	store = resolved

	Players.PlayerRemoving:Connect(function(player)
		LeaderboardService.submit(player)
		submitted[player] = nil
	end)

	--[[
		Zapis CYKLICZNY, nie tylko przy wyjściu.

		Sam zapis na wyjściu wygląda poprawnie, dopóki serwer kończy się
		normalnie. W praktyce serwery padają, a Roblox nie gwarantuje, że
		`PlayerRemoving` zdąży dokończyć zapis — wtedy gracz traci cały
		dorobek sesji w rankingu.

		Pisanie po każdej sprzedaży byłoby drugą skrajnością: przy 50 graczach
		na serwerze i sprzedaży co pół minuty to ~100 zapisów na minutę,
		czyli zjadanie limitu na dane, które i tak odświeżamy raz na minutę.

		Cykl co 2 minuty plus pominięcie niezmienionych wartości daje w praktyce
		kilka zapisów na minutę na serwer — mieści się w budżecie z dużym zapasem.
	]]
	task.spawn(function()
		while true do
			task.wait(GameConfig.LEADERBOARD_SUBMIT_INTERVAL)

			for _, player in Players:GetPlayers() do
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
