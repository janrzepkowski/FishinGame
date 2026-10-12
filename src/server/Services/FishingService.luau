--!strict
--[[
	FishingService — pętla łowienia. Serwer jest tu jedynym źródłem prawdy.

	Przebieg jednego zarzucenia:

	  klient: RequestCharge  -> zamach; faza „Charging" widoczna dla innych
	  klient: RequestCast    -> walidacja (moc, wędka, cooldown, odległość,
	                            miejsce w torbie) i LOSOWANIE RYBY
	  serwer: CastStarted    -> klient pokazuje spławik i głębokość
	        [zwłoka 1,4-5,0 s * biteSpeed wędki, po drodze 0-3 skubnięcia]
	  serwer: BiteStarted    -> klient startuje pasek podcięcia
	  klient: RequestReel    -> serwer mierzy U SIEBIE czas reakcji
	  serwer: FightStarted   -> zaczyna się hol
	        [pętla 20 Hz: FightUpdate(postęp, napięcie, szarpnięcie)]
	  klient: RequestReeling -> intencja „trzymam" / „puściłem"
	  serwer: CastResolved   -> wynik

	Trzy decyzje projektowe, które warto zrozumieć przed zmianami:

	1. Gatunek jest losowany przy ZARZUCENIU, a nie po wyholowaniu, i nie
	   jest wysyłany klientowi aż do końca. Gdyby był, dałoby się napisać
	   skrypt porzucający walki z tanimi rybami.

	2. Czas reakcji na podcięcie liczy serwer: `os.clock() - biteAt`. Klient
	   mówi „teraz", nigdy „trafiłem w 0,2 s". Kosztem jest ping wchodzący
	   w pomiar — i tak ma być.

	3. Walkę symuluje serwer w stałym kroku, a klient wysyła WYŁĄCZNIE
	   boolean. Nie ma czego podrobić: podanie `true` w kółko to dokładnie
	   to samo, co trzymanie przycisku, czyli najszybszy sposób na zerwanie
	   żyłki.

	4. To, co postać ROBI, serwer ogłasza atrybutami na jej modelu
	   (`FishingPhase`, `CastPower`, `Tension`, punkt lądowania). Każdy
	   klient animuje z nich wszystkie postacie w zasięgu — serwer nie
	   wysyła pozy, tylko mówi, co się dzieje.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Cast = require(ReplicatedStorage.Shared.Util.Cast)
local Fight = require(ReplicatedStorage.Shared.Util.Fight)
local Fish = require(ReplicatedStorage.Shared.Config.Fish)
local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local LakeConfig = require(ReplicatedStorage.Shared.Config.Lake)
local Net = require(ReplicatedStorage.Shared.Net)
local Rng = require(ReplicatedStorage.Shared.Util.Rng)
local Rods = require(ReplicatedStorage.Shared.Config.Rods)
local Spatial = require(ReplicatedStorage.Shared.Util.Spatial)
local Types = require(ReplicatedStorage.Shared.Types)

local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local RodService = require(script.Parent.RodService)

type CastPhase = "Waiting" | "Biting" | "Fighting"

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
	-- os.clock() ostatniego skubnięcia; 0, gdy żadnego jeszcze nie było.
	nibbleAt: number,

	-- Wypełniane dopiero po zacięciu.
	perfect: boolean,
	params: Fight.Params?,
	progress: number,
	tension: number,
	reeling: boolean,
	fightStartedAt: number,
	surgeUntil: number,
	nextSurgeAt: number,
}

local FishingService = {}

local states: { [Player]: CastState } = {}
-- Gracze w trakcie zamachu -> znacznik zamachu. Znacznik pozwala
-- opóźnionemu timeoutowi rozpoznać, że to nadal TEN SAM zamach.
local charging: { [Player]: number } = {}
local chargeCounter = 0
-- Wartość atrybutu skubnięć. Rośnie przez cały czas życia serwera i nigdy
-- się nie powtarza: klient reaguje na ZMIANĘ atrybutu, a licznik zerowany
-- co zarzucenie dałby dwa razy z rzędu „1" — i drugie skubnięcie by przepadło.
local nibbleCounter = 0
local nextCastAt: { [Player]: number } = {}
local castCounter = 0
local generator = Random.new()

-- ---------------------------------------------------------------------------
-- Losowanie
-- ---------------------------------------------------------------------------

--[[
	Wybiera gatunek z uwzględnieniem szczęścia.

	Wzór: spawnWeight * luck ^ rarityTier. Przy luck = 1 rozkład jest
	dokładnie taki, jak w configu. Przy luck = 1,42 legendarne (tier 4)
	dostają 1,42^4 ≈ 4,07x większą wagę, a pospolite (tier 0) ani trochę.
	Dzięki temu lepsza wędka nie „daje więcej wszystkiego", tylko realnie
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
-- Stan widoczny dla wszystkich
-- ---------------------------------------------------------------------------

--[[
	Ogłasza fazę łowienia atrybutem na postaci.

	Atrybut, a nie Remote do wszystkich: gracz, który dołączy albo podejdzie
	w trakcie cudzej walki, dostaje aktualną wartość razem z postacią.
	Zdarzenie przepadłoby dla każdego, kogo nie było w chwili wysłania.
]]
local function publishPhase(player: Player, phase: Types.FishingPhase)
	local character = player.Character
	if not character then
		return
	end

	character:SetAttribute(GameConfig.ATTRIBUTE_PHASE, phase)

	if phase ~= "Fighting" then
		character:SetAttribute(GameConfig.ATTRIBUTE_TENSION, 0)
		character:SetAttribute(GameConfig.ATTRIBUTE_SURGING, false)
	end
end

--[[ Napięcie dla obserwatorów — kwantowane i tylko przy zmianie, żeby
     20 ticków walki na sekundę nie zamieniło się w 20 replikacji. ]]
local function publishTension(player: Player, tension: number, surging: boolean)
	local character = player.Character
	if not character then
		return
	end

	local step = GameConfig.TENSION_ATTRIBUTE_STEP
	local quantized = math.floor(math.clamp(tension, 0, 1) / step + 0.5) * step

	if character:GetAttribute(GameConfig.ATTRIBUTE_TENSION) ~= quantized then
		character:SetAttribute(GameConfig.ATTRIBUTE_TENSION, quantized)
	end
	if character:GetAttribute(GameConfig.ATTRIBUTE_SURGING) ~= surging then
		character:SetAttribute(GameConfig.ATTRIBUTE_SURGING, surging)
	end
end

local function isFastBite(): boolean
	-- `IsStudio` jest tu warunkiem twardym: atrybut na Workspace w żywej
	-- grze nie może skrócić nikomu czekania.
	return RunService:IsStudio()
		and Workspace:GetAttribute(GameConfig.DEV_FAST_BITE_ATTRIBUTE) == true
end

-- ---------------------------------------------------------------------------
-- Zakończenie zarzucenia
-- ---------------------------------------------------------------------------

local function resolve(player: Player, result: Types.CastResult)
	states[player] = nil
	publishPhase(player, "Idle")
	Net.CastResolved:FireClient(player, result)
end

local function fail(player: Player, outcome: Types.CastOutcome)
	resolve(player, { outcome = outcome, fish = nil, perfect = false, record = false })
end

--[[ Ryba wyholowana: zapis do profilu, rekordy, zadania, telemetria. ]]
local function land(player: Player, state: CastState)
	local definition = state.fish
	local caught = rollCatch(definition, state.perfect)

	local isRecord = false

	local applied = DataService.mutate(player, function(profile)
		table.insert(profile.inventory, caught)
		profile.totalCaught += 1

		local record = profile.records[definition.id]
		if record == nil or caught.mass > record then
			profile.records[definition.id] = caught.mass
			-- Pierwsza sztuka gatunku też jest rekordem, ale nie chcemy
			-- o tym krzyczeć — inaczej pierwsze 12 ryb to 12 fanfar.
			isRecord = record ~= nil
		end
	end)

	if not applied then
		-- Profil zniknął między walidacją a tym miejscem (gracz wyszedł).
		states[player] = nil
		return
	end

	resolve(player, {
		outcome = "Caught",
		fish = caught,
		perfect = state.perfect,
		record = isRecord,
	})

	Analytics.funnelStep(player, 3, "Landed")
end

-- ---------------------------------------------------------------------------
-- Pętla walki
-- ---------------------------------------------------------------------------

local function scheduleSurge(state: CastState, now: number)
	state.nextSurgeAt = now
		+ generator:NextNumber(GameConfig.FIGHT_SURGE_GAP_MIN, GameConfig.FIGHT_SURGE_GAP_MAX)
end

local function beginFight(player: Player, state: CastState)
	local profile = DataService.get(player)
	local rodId = if profile then profile.equippedRod else GameConfig.STARTING_ROD
	local rod = Rods.find(rodId) or Rods.expect(GameConfig.STARTING_ROD)

	local now = os.clock()

	state.phase = "Fighting"
	state.progress = 0
	state.tension = 0
	-- Start z PUSZCZONĄ żyłką. Gracz sam decyduje, kiedy zacząć holować,
	-- więc walka nie karze go za to, że jeszcze nie zdążył wcisnąć.
	state.reeling = false
	state.fightStartedAt = now
	state.surgeUntil = 0
	state.params = {
		strength = state.fish.fight.strength,
		stamina = state.fish.fight.stamina,
		lineStrength = rod.lineStrength,
		progressGain = GameConfig.FIGHT_PROGRESS_GAIN,
		tensionGain = GameConfig.FIGHT_TENSION_GAIN,
		surgeTension = GameConfig.FIGHT_SURGE_TENSION,
		surgeProgress = GameConfig.FIGHT_SURGE_PROGRESS,
		slackLoss = GameConfig.FIGHT_SLACK_LOSS,
		tensionRecovery = GameConfig.FIGHT_TENSION_RECOVERY,
	}

	scheduleSurge(state, now)

	publishPhase(player, "Fighting")
	Net.FightStarted:FireClient(player)
	Analytics.funnelStep(player, 2, "Hooked")
end

--[[ Jeden krok walki. Zwraca wynik, gdy walka się kończy, inaczej nil. ]]
local function stepFight(
	player: Player,
	state: CastState,
	dt: number,
	now: number
): Types.CastOutcome?
	local params = state.params
	if not params then
		return "Escaped"
	end

	-- Harmonogram szarpnięć.
	if now >= state.nextSurgeAt and now >= state.surgeUntil then
		state.surgeUntil = now
			+ generator:NextNumber(GameConfig.FIGHT_SURGE_MIN, GameConfig.FIGHT_SURGE_MAX)
		scheduleSurge(state, state.surgeUntil)
	end

	local surging = now < state.surgeUntil

	local next = Fight.step(
		{ progress = state.progress, tension = state.tension },
		params,
		dt,
		state.reeling,
		surging
	)

	state.progress = next.progress
	state.tension = next.tension

	if state.tension >= 1 then
		return "LineSnapped"
	end
	if state.progress >= 1 then
		return "Caught"
	end
	if now - state.fightStartedAt > GameConfig.FIGHT_TIMEOUT then
		return "Escaped"
	end

	publishTension(player, state.tension, surging)

	Net.FightUpdate:FireClient(
		player,
		{
			progress = state.progress,
			tension = math.min(state.tension, 1),
			surging = surging,
		} :: Types.FightState
	)

	return nil
end

-- ---------------------------------------------------------------------------
-- Handlery
-- ---------------------------------------------------------------------------

--[[ Kończy zamach bez rzutu i zdejmuje pozę z postaci. ]]
local function cancelCharge(player: Player)
	if charging[player] == nil then
		return
	end
	charging[player] = nil

	if not states[player] then
		publishPhase(player, "Idle")
	end
end

local function onRequestCharge(player: Player, wantsCharge: unknown)
	if typeof(wantsCharge) ~= "boolean" then
		return
	end

	if not wantsCharge then
		cancelCharge(player)
		return
	end

	if states[player] or charging[player] ~= nil then
		return -- trwa zarzucenie albo zamach już ogłoszony
	end

	if os.clock() < (nextCastAt[player] or 0) then
		return
	end

	if not RodService.getHeldRod(player) then
		return -- cicho: komunikat „weź wędkę" poleci przy samym rzucie
	end

	chargeCounter += 1
	local token = chargeCounter
	charging[player] = token
	publishPhase(player, "Charging")

	task.delay(GameConfig.CHARGE_TIMEOUT, function()
		if charging[player] == token then
			cancelCharge(player)
		end
	end)
end

local function onRequestCast(player: Player, rawPower: unknown)
	-- Wejście z klienta: najpierw typ, potem zakres (`clampPower` łapie NaN).
	if typeof(rawPower) ~= "number" then
		return
	end
	local power = Cast.clampPower(rawPower :: number)

	if states[player] then
		return -- już trwa zarzucenie
	end

	-- Od tego miejsca każde wyjście bez rzutu musi zdjąć pozę zamachu,
	-- inaczej postać zostałaby z wędką nad głową do timeoutu.
	local now = os.clock()
	if now < (nextCastAt[player] or 0) then
		cancelCharge(player)
		return -- cooldown; cicho, bo to zwykły spam klikaniem
	end

	local profile = DataService.get(player)
	if not profile then
		cancelCharge(player)
		return -- profil jeszcze się wczytuje
	end

	if not RodService.getHeldRod(player) then
		cancelCharge(player)
		Net.Notify:FireClient(player, "Weź wędkę do ręki.", "Warning")
		return
	end

	if #profile.inventory >= GameConfig.MAX_INVENTORY then
		charging[player] = nil
		Net.Notify:FireClient(player, "Torba pełna — sprzedaj połów w skupie.", "Warning")
		fail(player, "InventoryFull")
		return
	end

	local root = Spatial.characterRoot(player)
	if not root then
		cancelCharge(player)
		return -- respawn w toku
	end

	-- `edgeDistance` jest dodatnie nad wodą, ujemne na lądzie. Interesuje nas
	-- tylko to drugie: jak daleko od brzegu stoi gracz.
	local fromShore = math.max(-LakeConfig.edgeDistance(root.Position), 0)
	if fromShore > GameConfig.MAX_CAST_DISTANCE then
		cancelCharge(player)
		Net.Notify:FireClient(player, "Podejdź bliżej wody.", "Warning")
		return
	end

	local rod = Rods.find(profile.equippedRod) or Rods.expect(GameConfig.STARTING_ROD)

	-- Punkt lądowania liczy SERWER, z własnej pozycji postaci. Klient go
	-- nie podaje, tylko dostaje z powrotem w `CastStarted` — łącznie
	-- z dociągnięciem do wody (patrz komentarz przy CAST_SHORE_MARGIN).
	local distance = Cast.distanceFor(power, GameConfig.CAST_MIN_DISTANCE, rod.castRange)
	local target = LakeConfig.clampToWater(
		Spatial.castTarget(root.CFrame, distance),
		GameConfig.CAST_SHORE_MARGIN
	)
	local depth = LakeConfig.depthAt(target)
	if depth <= 0 then
		-- Nieosiągalne po dociągnięciu, chyba że ktoś zepsuje geometrię
		-- jeziora. Wtedy lepiej zobaczyć ostrzeżenie niż łowić w trawie.
		cancelCharge(player)
		warn("[FishingService] punkt zarzucenia poza wodą mimo clampToWater")
		return
	end

	-- Głębokość wchodzi w to samo szczęście, co wędka, więc jej wpływ też jest
	-- podnoszony do potęgi rzadkości. Dwa niezależne mnożniki rozdzieliłyby
	-- progresję „kup lepszy sprzęt" od „znajdź lepsze miejsce" — a chcemy,
	-- żeby jedno wzmacniało drugie.
	local depthLuck = 1 + LakeConfig.depthFactor(target) * GameConfig.DEPTH_LUCK_BONUS

	castCounter += 1
	local castId = castCounter

	states[player] = {
		castId = castId,
		phase = "Waiting",
		fish = pickFish(rod.luck * depthLuck),
		reelWindow = rod.reelWindow,
		biteAt = 0,
		nibbleAt = 0,
		perfect = false,
		params = nil,
		progress = 0,
		tension = 0,
		reeling = false,
		fightStartedAt = 0,
		surgeUntil = 0,
		nextSurgeAt = 0,
	}
	nextCastAt[player] = now + GameConfig.CAST_COOLDOWN
	charging[player] = nil

	local landing = Vector3.new(target.X, LakeConfig.SURFACE_Y, target.Z)
	local character = player.Character
	if character then
		-- Moc i cel PRZED fazą: klient reaguje na zmianę fazy i ma wtedy
		-- zastać już komplet danych o rzucie.
		character:SetAttribute(GameConfig.ATTRIBUTE_POWER, power)
		character:SetAttribute(GameConfig.ATTRIBUTE_TARGET, landing)
	end
	publishPhase(player, "Waiting")

	Net.CastStarted:FireClient(player, depth, landing)
	Analytics.funnelStep(player, 1, "Cast")

	local fastBite = isFastBite()
	local biteDelay = if fastBite
		then GameConfig.DEV_FAST_BITE_DELAY
		else generator:NextNumber(GameConfig.MIN_BITE_DELAY, GameConfig.MAX_BITE_DELAY)
			* rod.biteSpeed

	-- Skubnięcia: liczbę i momenty losujemy od razu, przy zarzuceniu.
	local rolls: { number } = {}
	if not fastBite then
		for _ = 1, generator:NextInteger(0, GameConfig.MAX_NIBBLES) do
			table.insert(rolls, generator:NextNumber())
		end
	end

	for _, nibbleDelay in Cast.nibbleTimes(biteDelay, rolls) do
		task.delay(nibbleDelay, function()
			local state = states[player]
			if not state or state.castId ~= castId or state.phase ~= "Waiting" then
				return
			end

			state.nibbleAt = os.clock()
			nibbleCounter += 1

			local model = player.Character
			if model then
				model:SetAttribute(GameConfig.ATTRIBUTE_NIBBLES, nibbleCounter)
			end
		end)
	end

	task.delay(biteDelay, function()
		local state = states[player]
		if not state or state.castId ~= castId or state.phase ~= "Waiting" then
			return
		end

		-- Gracz mógł w tym czasie odłożyć wędkę, umrzeć albo odejść od wody.
		-- Branie bez wędki w ręce wyglądałoby jak bug, więc anulujemy.
		if not RodService.getHeldRod(player) then
			fail(player, "Escaped")
			return
		end

		state.phase = "Biting"
		state.biteAt = os.clock()
		publishPhase(player, "Biting")
		Net.BiteStarted:FireClient(player, state.reelWindow)

		task.delay(state.reelWindow, function()
			local current = states[player]
			if not current or current.castId ~= castId or current.phase ~= "Biting" then
				return
			end
			fail(player, "Escaped")
		end)
	end)
end

local function onRequestReel(player: Player)
	local state = states[player]
	if not state then
		return -- nic nie trwa; klient się rozjechał albo ktoś spamuje Remote'em
	end

	if state.phase == "Fighting" then
		return -- hol trwa; sterowanie idzie przez RequestReeling
	end

	if state.phase ~= "Biting" then
		-- Podcięcie przed braniem: tracimy zarzucenie i krótka blokada.
		-- Bez tej kary optymalną strategią byłoby trzymanie autoklikera,
		-- który i tak kiedyś trafi w okno.
		local now = os.clock()
		nextCastAt[player] = now + GameConfig.TOO_EARLY_PENALTY

		-- Zacięcie tuż po skubnięciu to inny błąd niż klikanie w ciemno:
		-- gracz zareagował na sygnał, tylko nie na ten. Mówimy mu to
		-- osobnym wynikiem, bo inaczej nie nauczy się ich odróżniać.
		local spooked = state.nibbleAt > 0 and now - state.nibbleAt <= GameConfig.NIBBLE_WINDOW
		fail(player, if spooked then "Spooked" else "TooEarly")
		return
	end

	local elapsed = os.clock() - state.biteAt
	if elapsed > state.reelWindow then
		-- Wyścig z timeoutem z `task.delay`. Ten, kto pierwszy, ten lepszy —
		-- a `resolve` zeruje stan, więc drugi i tak wypadnie wyżej.
		return
	end

	state.perfect = elapsed <= state.reelWindow * GameConfig.PERFECT_REEL_FRACTION
	beginFight(player, state)
end

local function onRequestReeling(player: Player, reeling: unknown)
	-- Wejście z klienta. Bez tego sprawdzenia dowolna wartość trafiłaby
	-- wprost do symulacji.
	if typeof(reeling) ~= "boolean" then
		return
	end

	local state = states[player]
	if not state or state.phase ~= "Fighting" then
		return
	end

	-- Spam tym Remote'em jest darmowy: symulacja odczytuje flagę raz na tick,
	-- więc tysiąc wywołań między tickami kosztuje tyle, co jedno.
	state.reeling = reeling :: boolean
end

local function clearPlayer(player: Player)
	states[player] = nil
	charging[player] = nil
	nextCastAt[player] = nil
end

-- ---------------------------------------------------------------------------

function FishingService.start()
	Net.RequestCharge.OnServerEvent:Connect(onRequestCharge)
	Net.RequestCast.OnServerEvent:Connect(onRequestCast)
	Net.RequestReel.OnServerEvent:Connect(onRequestReel)
	Net.RequestReeling.OnServerEvent:Connect(onRequestReeling)

	Players.PlayerRemoving:Connect(clearPlayer)

	-- Śmierć w trakcie zarzucenia: bez tego gracz po respawnie dostałby
	-- `BiteStarted` do nieistniejącego już spławika.
	local function watchCharacter(player: Player)
		player.CharacterRemoving:Connect(function()
			states[player] = nil
			charging[player] = nil
		end)
	end

	for _, player in Players:GetPlayers() do
		watchCharacter(player)
	end
	Players.PlayerAdded:Connect(watchCharacter)

	--[[
		JEDNA pętla na wszystkie walki, nie korutyna na gracza.

		Przy korutynach dziesięciu walczących graczy to dziesięć wątków
		budzonych niezależnie; tutaj jest jeden stały krok i jedno miejsce,
		w którym widać koszt. Akumulator odkleja symulację od zmiennego
		czasu klatki — przy spadku FPS serwera walka zwalnia, zamiast
		przeskakiwać, co przy progu zerwania żyłki miałoby znaczenie.
	]]
	local accumulator = 0

	RunService.Heartbeat:Connect(function(delta)
		accumulator += delta
		if accumulator < GameConfig.FIGHT_TICK then
			return
		end

		local step = accumulator
		accumulator = 0
		local now = os.clock()

		-- Zbieramy wyniki i rozstrzygamy PO pętli: `resolve` usuwa wpis
		-- z `states`, a modyfikowanie tabeli w trakcie iteracji po niej
		-- jest w Luau niezdefiniowane.
		type Finished = { player: Player, outcome: Types.CastOutcome }
		local finished: { Finished } = {}

		for player, state in states do
			if state.phase ~= "Fighting" then
				continue
			end

			-- Adnotacja na zmiennej jest konieczna: bez niej Luau rozszerza
			-- wynik do zwykłego `string` i literał tabeli przestaje pasować
			-- do unii `CastOutcome`.
			local outcome: Types.CastOutcome? = stepFight(player, state, step, now)
			if outcome then
				local entry: Finished = { player = player, outcome = outcome }
				table.insert(finished, entry)
			end
		end

		for _, entry in finished do
			local state = states[entry.player]
			if not state then
				continue
			end

			if entry.outcome == "Caught" then
				land(entry.player, state)
			else
				if entry.outcome == "LineSnapped" then
					Analytics.custom(entry.player, "LineSnapped", 1)
				end
				fail(entry.player, entry.outcome)
			end
		end
	end)
end

return FishingService
