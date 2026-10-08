--!strict
--[[
	FishingService — pętla łowienia. Serwer jest tu jedynym źródłem prawdy.

	Przebieg jednego zarzucenia:

	  klient: RequestCast  ->  serwer waliduje (wędka w ręce, cooldown,
	                           odległość od wody, miejsce w ekwipunku)
	                           i LOSUJE RYBĘ JUŻ TERAZ
	  serwer: CastStarted  ->  klient pokazuje spławik
	        [losowa zwłoka 1,4-5,0 s * biteSpeed wędki]
	  serwer: BiteStarted  ->  klient startuje pasek podcięcia
	  klient: RequestReel  ->  serwer mierzy U SIEBIE czas reakcji
	  serwer: CastResolved ->  klient pokazuje wynik

	Dwie decyzje projektowe, które warto zrozumieć przed zmianami:

	1. Gatunek jest losowany przy zarzuceniu, ale NIE jest wysyłany klientowi
	   razem z `BiteStarted`. Gdyby był, klient wiedziałby, czy warto podcinać,
	   i dałoby się zrobić autoclickera tylko na legendarne.

	2. Czas reakcji liczy serwer: `os.clock() - biteAt`. Klient nie podaje
	   swojego wyniku, tylko mówi "teraz". Kosztem jest to, że ping wchodzi
	   w pomiar — i tak ma być, inaczej "trafność" byłaby polem do podrobienia.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fish = require(ReplicatedStorage.Shared.Config.Fish)
local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local Net = require(ReplicatedStorage.Shared.Net)
local Rng = require(ReplicatedStorage.Shared.Util.Rng)
local Rods = require(ReplicatedStorage.Shared.Config.Rods)
local Spatial = require(ReplicatedStorage.Shared.Util.Spatial)
local Types = require(ReplicatedStorage.Shared.Types)

local DataService = require(script.Parent.DataService)
local RodService = require(script.Parent.RodService)
local WorldBuilder = require(script.Parent.Parent.World.WorldBuilder)

type CastPhase = "Waiting" | "Biting"

type CastState = {
	-- Rosnący identyfikator. Opóźnione callbacki (`task.delay`) porównują go
	-- ze stanem bieżącym — bez tego timeout ze starego zarzucenia ubijałby
	-- nowe, rozpoczęte w międzyczasie.
	castId: number,
	phase: CastPhase,
	fish: Types.FishDefinition,
	reelWindow: number,
	-- os.clock() w momencie wysłania BiteStarted.
	biteAt: number,
}

local FishingService = {}

local states: { [Player]: CastState } = {}
local nextCastAt: { [Player]: number } = {}
local castCounter = 0
local generator = Random.new()

-- ---------------------------------------------------------------------------
-- Losowanie
-- ---------------------------------------------------------------------------

--[[
	Wybiera gatunek z uwzględnieniem `luck` wędki.

	Wzór: spawnWeight * luck ^ rarityTier. Przy luck = 1 rozkład jest dokładnie
	taki, jak w configu. Przy luck = 1,42 (wędka turniejowa) legendarne
	(tier 4) dostają 1,42^4 ≈ 4,07x większą wagę, a pospolite (tier 0) ani
	trochę. Dzięki temu lepsza wędka nie "daje więcej wszystkiego", a realnie
	przesuwa rozkład w stronę rzadkości.
]]
local function pickFish(luck: number): Types.FishDefinition
	local definitions = Fish.all()
	local weights = table.create(#definitions)

	for index, definition in definitions do
		local tier = Fish.RARITY_TIER[definition.rarity]
		weights[index] = definition.spawnWeight * luck ^ tier
	end

	local index = Rng.weightedIndex(generator, weights)
	-- weightedIndex zwraca 0 tylko przy pustym katalogu — wtedy nie ma czego
	-- łowić i to błąd konfiguracji, nie stan do obsłużenia w runtime.
	return definitions[if index > 0 then index else 1]
end

local function rollCatch(definition: Types.FishDefinition, perfect: boolean): Types.CaughtFish
	local mass =
		Rng.skewedNumber(generator, definition.minMass, definition.maxMass, GameConfig.MASS_SKEW)
	-- Zaokrąglamy od razu i trzymamy zaokrągloną wartość w profilu, żeby
	-- cena w UI zawsze zgadzała się z masą pokazaną obok niej.
	mass = math.floor(mass * 100 + 0.5) / 100

	local price = mass * definition.pricePerKg
	if perfect then
		price *= GameConfig.PERFECT_PRICE_BONUS
	end

	return {
		fishId = definition.id,
		mass = mass,
		price = math.max(1, math.floor(price + 0.5)),
	}
end

-- ---------------------------------------------------------------------------
-- Obsługa zarzucenia
-- ---------------------------------------------------------------------------

local function resolve(player: Player, result: Types.CastResult)
	states[player] = nil
	Net.CastResolved:FireClient(player, result)
end

local function onRequestCast(player: Player)
	if states[player] then
		return -- już trwa zarzucenie
	end

	local now = os.clock()
	if now < (nextCastAt[player] or 0) then
		return -- cooldown; cicho, bo to zwykły spam klikaniem
	end

	local profile = DataService.get(player)
	if not profile then
		return -- profil jeszcze się wczytuje
	end

	if not RodService.getHeldRod(player) then
		Net.Notify:FireClient(player, "Weź wędkę do ręki.", "Warning")
		return
	end

	if #profile.inventory >= GameConfig.MAX_INVENTORY then
		Net.Notify:FireClient(player, "Ekwipunek pełny — sprzedaj połów w skupie.", "Warning")
		Net.CastResolved:FireClient(
			player,
			{ outcome = "InventoryFull", fish = nil, perfect = false } :: Types.CastResult
		)
		return
	end

	local position = Spatial.characterPosition(player)
	if not position then
		return -- respawn w toku
	end

	local water = WorldBuilder.getWater()
	if not water then
		warn("[FishingService] brak strefy wody — czy WorldBuilder.build() został wywołany?")
		return
	end

	if Spatial.distanceToPart(position, water) > GameConfig.MAX_CAST_DISTANCE then
		Net.Notify:FireClient(player, "Podejdź bliżej wody.", "Warning")
		return
	end

	local rod = Rods.find(profile.equippedRod) or Rods.expect(GameConfig.STARTING_ROD)

	castCounter += 1
	local castId = castCounter

	states[player] = {
		castId = castId,
		phase = "Waiting",
		fish = pickFish(rod.luck),
		reelWindow = rod.reelWindow,
		biteAt = 0,
	}
	nextCastAt[player] = now + GameConfig.CAST_COOLDOWN

	Net.CastStarted:FireClient(player)

	local biteDelay = generator:NextNumber(GameConfig.MIN_BITE_DELAY, GameConfig.MAX_BITE_DELAY)
		* rod.biteSpeed

	task.delay(biteDelay, function()
		local state = states[player]
		if not state or state.castId ~= castId or state.phase ~= "Waiting" then
			return
		end

		-- Gracz mógł w tym czasie odłożyć wędkę, umrzeć albo odejść od wody.
		-- Branie bez wędki w ręce wyglądałoby jak bug, więc anulujemy.
		if not RodService.getHeldRod(player) then
			resolve(player, { outcome = "Escaped", fish = nil, perfect = false })
			return
		end

		state.phase = "Biting"
		state.biteAt = os.clock()
		Net.BiteStarted:FireClient(player, state.reelWindow)

		task.delay(state.reelWindow, function()
			local current = states[player]
			if not current or current.castId ~= castId or current.phase ~= "Biting" then
				return
			end
			resolve(player, { outcome = "Escaped", fish = nil, perfect = false })
		end)
	end)
end

local function onRequestReel(player: Player)
	local state = states[player]
	if not state then
		return -- nic nie trwa; klient się rozjechał albo ktoś spamuje Remote'em
	end

	if state.phase ~= "Biting" then
		-- Podcięcie przed braniem: tracimy zarzucenie i krótka blokada.
		-- Bez tej kary optymalną strategią byłoby trzymanie autoklikera,
		-- który i tak kiedyś trafi w okno.
		nextCastAt[player] = os.clock() + GameConfig.TOO_EARLY_PENALTY
		resolve(player, { outcome = "TooEarly", fish = nil, perfect = false })
		return
	end

	local elapsed = os.clock() - state.biteAt
	if elapsed > state.reelWindow then
		-- Wyścig z timeoutem z `task.delay`. Ten, kto pierwszy, ten lepszy —
		-- a `resolve` zeruje stan, więc drugi i tak wypadnie wyżej.
		return
	end

	local perfect = elapsed <= state.reelWindow * GameConfig.PERFECT_REEL_FRACTION
	local definition = state.fish
	local caught = rollCatch(definition, perfect)

	local applied = DataService.mutate(player, function(profile)
		table.insert(profile.inventory, caught)
		profile.totalCaught += 1

		local record = profile.records[definition.id]
		if record == nil or caught.mass > record then
			profile.records[definition.id] = caught.mass
		end
	end)

	if not applied then
		-- Profil zniknął między walidacją a tym miejscem (gracz wyszedł).
		states[player] = nil
		return
	end

	resolve(player, { outcome = "Caught", fish = caught, perfect = perfect })
end

local function clearPlayer(player: Player)
	states[player] = nil
	nextCastAt[player] = nil
end

function FishingService.start()
	Net.RequestCast.OnServerEvent:Connect(onRequestCast)
	Net.RequestReel.OnServerEvent:Connect(onRequestReel)

	Players.PlayerRemoving:Connect(clearPlayer)

	-- Śmierć w trakcie zarzucenia: bez tego gracz po respawnie dostałby
	-- `BiteStarted` do nieistniejącego już spławika.
	local function watchCharacter(player: Player)
		player.CharacterRemoving:Connect(function()
			states[player] = nil
		end)
	end

	for _, player in Players:GetPlayers() do
		watchCharacter(player)
	end
	Players.PlayerAdded:Connect(watchCharacter)
end

return FishingService
