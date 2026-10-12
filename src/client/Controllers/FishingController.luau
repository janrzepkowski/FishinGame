--!strict
--[[
	FishingController — wejście gracza i reakcja na zdarzenia z serwera.

	Cała obsługa akcji to jedna reguła:
	  stan Idle  -> wciśnięcie zaczyna ZAMACH, puszczenie RZUCA z mocą
	                odczytaną z wahadłowego paska (RequestCast)
	  inny stan  -> wciśnięcie „podcina" (RequestReel)

	Dzięki temu jeden przycisk obsługuje obie akcje, a podcięcie przed braniem
	jest możliwe — i karane. Wariant, w którym klient blokuje za wczesny klik,
	byłby wygodniejszy, ale wtedy kara nie istnieje i optymalną strategią
	zostaje autokliker.

	WĘDKA WYJMUJE SIĘ SAMA. W grze z jednym narzędziem wymaganie, żeby gracz
	najpierw znalazł je na pasku, to bariera bez żadnej wartości — szczególnie
	na telefonie. Obsługujemy to po stronie klienta; serwer nadal niezależnie
	sprawdza, czy wędka jest w ręce (`RodService.getHeldRod`).

	Na desktopie słuchamy `Tool.Activated`, a nie myszy wprost: Activated samo
	z siebie nie odpala się przy klikaniu w UI. Przy ręcznym czytaniu myszy
	każde kliknięcie w sklepie zarzucałoby wędkę.

	Stan jest NARZUCANY przez serwer (CastStarted / BiteStarted / CastResolved).
	Klient go nie zgaduje — przy rozjechaniu wygrywa serwer.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cast = require(Shared.Util.Cast)
local CastPose = require(Shared.Util.CastPose)
local GameConfig = require(Shared.Config.Game)
local Net = require(Shared.Net)
local Rods = require(Shared.Config.Rods)
local Spatial = require(Shared.Util.Spatial)
local Types = require(Shared.Types)

local Bobber = require(script.Parent.Parent.Effects.Bobber)
local CastMeter = require(script.Parent.Parent.UI.CastMeter)
local CatchFx = require(script.Parent.Parent.Effects.CatchFx)
local Celebration = require(script.Parent.Parent.UI.Celebration)
local Hotbar = require(script.Parent.Parent.UI.Hotbar)
local Hud = require(script.Parent.Parent.UI.Hud)
local ProfileCache = require(script.Parent.Parent.ProfileCache)

local ROD_ATTRIBUTE = "RodId"

local FishingController = {}

--[[ `Casting` to chwila między puszczeniem przycisku a odpowiedzią serwera:
     rzut wysłany, ale jeszcze niepotwierdzony. ]]
export type Phase = "Idle" | "Charging" | "Casting" | "Waiting" | "Biting" | "Fighting"

local player = Players.LocalPlayer
local phase: Phase = "Idle"
-- os.clock() początku zamachu. Ten sam moment dostaje pasek mocy, więc
-- moc przy puszczeniu jest dokładnie tą, którą gracz widział.
local chargeStartedAt: number? = nil
-- Moc ostatniego rzutu — poza postaci bierze z niej głębokość zamachu.
local castPower = 0
-- Rośnie przy każdym rzucie; opóźniony timeout rozpoznaje po nim, czy
-- nadal dotyczy TEGO rzutu.
local castSerial = 0
-- Ile czekamy na `CastStarted`, zanim uznamy, że serwer rzut odrzucił.
local CAST_CONFIRM_TIMEOUT = 1
local phaseListeners: { (Phase) -> () } = {}
local reeling = false
-- Gatunki, które gracz miał w bestiariuszu PRZED bieżącym połowem. Profil
-- i wynik zarzucenia przychodzą osobnymi Remote'ami w nieustalonej
-- kolejności, więc nowy wpis trafia tu z opóźnieniem — inaczej świeżo
-- złowiony gatunek nigdy nie zostałby rozpoznany jako nowy.
local knownSpecies: { [string]: boolean } = {}
local speciesLoaded = false
local SPECIES_SETTLE = 2

local function setPhase(next: Phase)
	phase = next
	for _, listener in table.clone(phaseListeners) do
		listener(next)
	end
end

local function isRod(instance: Instance): boolean
	return instance:IsA("Tool") and instance:GetAttribute(ROD_ATTRIBUTE) ~= nil
end

local function heldRod(): Tool?
	local character = player.Character
	if not character then
		return nil
	end

	local tool = character:FindFirstChildOfClass("Tool")
	return if tool and isRod(tool) then tool else nil
end

--[[ Wyjmuje wędkę z plecaka, jeśli gracz jej nie trzyma. ]]
local function ensureEquipped(): boolean
	if heldRod() then
		return true
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return false
	end

	for _, child in backpack:GetChildren() do
		if isRod(child) then
			humanoid:EquipTool(child :: Tool)
			return true
		end
	end

	return false
end

--[[
	Chowa wędkę do plecaka albo ją wyjmuje — klawisz `1` i kliknięcie
	w slot na pasku.

	Wyłączyliśmy wbudowany plecak Robloxa (patrz `UI/Hotbar`), a razem z nim
	zniknął standardowy skrót cyframi. Gracze odruchowo go szukają, więc
	trzeba go było odtworzyć — a przy okazji zrobić z niego PRZEŁĄCZNIK,
	nie samo wyjmowanie: bez tego nie dało się odłożyć wędki wcale.

	Działa tylko poza zarzuceniem. Schowanie wędki w trakcie holu zabrałoby
	Attachment, od którego klient rysuje żyłkę, i spławik zawisłby na niczym.
]]
function FishingController.toggleRod()
	if phase ~= "Idle" then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if heldRod() then
		humanoid:UnequipTools()
	else
		ensureEquipped()
	end
end

--[[
	Ustawia intencję holowania. Wysyła tylko przy ZMIANIE — serwer i tak
	odczytuje flagę raz na tick, więc strumień identycznych wiadomości
	byłby czystym marnotrawstwem pasma.
]]
function FishingController.setReeling(value: boolean)
	if phase ~= "Fighting" then
		-- Poza walką pamiętamy `false`, żeby kolejna walka nie zaczęła się
		-- z wciśniętym przyciskiem po poprzedniej.
		reeling = false
		return
	end

	if value == reeling then
		return
	end

	reeling = value
	Net.RequestReeling:FireServer(value)
end

--[[
	Wciśnięcie głównego przycisku — spina `Tool.Activated` z desktopa
	i przycisk dotykowy. Dzięki temu obie ścieżki nie mogą się rozjechać.

	W czasie walki wciśnięcie nie wysyła nic: tam liczy się TRZYMANIE,
	obsługiwane przez `setReeling`.
]]
function FishingController.press()
	-- Wciśnięcie coś znaczy tylko w trzech fazach: przed rzutem zaczyna
	-- zamach, a w czekaniu i przy braniu podcina. W pozostałych (zamach
	-- już trwa, rzut czeka na serwer, walka) nie robi nic.
	local current: Phase = phase
	if current ~= "Idle" and current ~= "Waiting" and current ~= "Biting" then
		return
	end

	if not ensureEquipped() then
		return
	end

	if phase == "Idle" then
		local startedAt = os.clock()
		chargeStartedAt = startedAt
		setPhase("Charging")
		CastMeter.showCharge(startedAt)
		-- Tylko po to, żeby inni gracze zobaczyli zamach. Mocy tu nie ma.
		Net.RequestCharge:FireServer(true)
	else
		Net.RequestReel:FireServer()
	end
end

--[[
	Puszczenie głównego przycisku: koniec zamachu, rzut.

	Przechodzimy w `Casting`: postać zastyga w zamachu do odpowiedzi serwera.
	Jeśli rzut przejdzie, `CastStarted` przestawi fazę na `Waiting` i ręka
	wykona wymach bez przerwy w ruchu. Jeśli nie (za daleko od wody, pełna
	torba), po krótkim czasie wracamy do `Idle` — gracz dostaje komunikat
	i może próbować ponownie, zamiast stać z wędką nad głową.
]]
function FishingController.release()
	local startedAt = chargeStartedAt
	if phase ~= "Charging" or not startedAt then
		return
	end

	chargeStartedAt = nil
	local power = Cast.powerAt(os.clock() - startedAt, GameConfig.CAST_POWER_PERIOD)
	castPower = power
	castSerial += 1
	local serial = castSerial

	setPhase("Casting")
	CastMeter.hide()
	Net.RequestCast:FireServer(power)

	task.delay(CAST_CONFIRM_TIMEOUT, function()
		-- Jawny typ: analiza zawęziła `phase` do "Charging" na początku
		-- funkcji i nie wie, że do tej chwili zdążyło się zmienić.
		local current: Phase = phase
		if current == "Casting" and castSerial == serial then
			setPhase("Idle")
		end
	end)
end

function FishingController.getPhase(): Phase
	return phase
end

--[[ Moc ostatniego rzutu, 0..1. ]]
function FishingController.getCastPower(): number
	return castPower
end

--[[ Przerywa zamach bez rzutu — np. gdy gracz schowa wędkę w jego trakcie. ]]
local function cancelCharge()
	if phase ~= "Charging" then
		return
	end

	chargeStartedAt = nil
	setPhase("Idle")
	CastMeter.hide()
	Net.RequestCharge:FireServer(false)
end

function FishingController.onPhaseChanged(listener: (Phase) -> ())
	table.insert(phaseListeners, listener)
	listener(phase)
end

local function bindTool(instance: Instance)
	if not isRod(instance) then
		return
	end

	-- Połączenie żyje tyle, co Tool. Przy zmianie wędki stary Tool jest
	-- niszczony, więc Roblox zbiera je razem z instancją.
	local tool = instance :: Tool
	tool.Activated:Connect(FishingController.press)
	-- `Deactivated` to puszczenie przycisku — bez niego zamach nie miałby końca.
	tool.Deactivated:Connect(FishingController.release)
	tool.Unequipped:Connect(cancelCharge)
end

local function watchCharacter(character: Model)
	local function syncEquipped()
		Hotbar.setEquipped(heldRod() ~= nil)
	end

	for _, child in character:GetChildren() do
		bindTool(child)
	end

	character.ChildAdded:Connect(function(child)
		bindTool(child)
		syncEquipped()
	end)
	-- Tool wyjęty z postaci wraca do plecaka jako ChildRemoved — bez tego
	-- slot zostawałby podświetlony mimo odłożonej wędki.
	character.ChildRemoved:Connect(syncEquipped)
	syncEquipped()

	-- Skubnięcia ogłasza serwer zmianą atrybutu na postaci — tym samym
	-- kanałem, z którego czytają je inni gracze.
	character:GetAttributeChangedSignal(GameConfig.ATTRIBUTE_NIBBLES):Connect(function()
		if phase == "Waiting" then
			Bobber.nibble()
		end
	end)

	-- Plecak powstaje razem z postacią, ale nie zawsze przed tym momentem.
	task.spawn(function()
		local backpack = player:WaitForChild("Backpack", 10)
		if not backpack then
			return
		end

		for _, child in backpack:GetChildren() do
			bindTool(child)
		end
		backpack.ChildAdded:Connect(function(child)
			bindTool(child)
			-- Nowa wędka ze sklepu: zakładamy ją od razu, zamiast kazać
			-- graczowi szukać jej na pasku po zakupie.
			if isRod(child) then
				task.defer(ensureEquipped)
			end
		end)

		ensureEquipped()
	end)
end

function FishingController.start()
	ProfileCache.onChanged(function(profile: Types.Profile)
		local function remember()
			for fishId in profile.records do
				knownSpecies[fishId] = true
			end
		end

		if speciesLoaded then
			task.delay(SPECIES_SETTLE, remember)
		else
			speciesLoaded = true
			remember()
		end
	end)

	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)

	--[[
		Hol na desktopie: TRZYMANIE lewego przycisku.

		`Tool.Activated` odpala się tylko przy kliknięciu i nie mówi nic
		o puszczeniu, więc samo nie wystarczy. Czytamy mysz wprost, ale
		REAGUJEMY WYŁĄCZNIE w fazie walki — poza nią obsługę przejmuje
		`Tool.Activated`, który z definicji nie łapie kliknięć w UI.

		`gameProcessed` odsiewa kliknięcia zużyte przez interfejs, żeby
		zamknięcie panelu w trakcie walki nie liczyło się jako holowanie.
	]]
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- `gameProcessed` odsiewa wejście zużyte przez UI i czat. Bez tego
		-- wpisanie „1" na czacie chowałoby wędkę.
		if gameProcessed then
			return
		end

		if input.KeyCode == Enum.KeyCode.One then
			FishingController.toggleRod()
			return
		end

		if phase ~= "Fighting" then
			return
		end

		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			FishingController.setReeling(true)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		-- Przy PUSZCZENIU nie sprawdzamy `gameProcessed`: jeśli gracz zacznie
		-- holować, a potem najedzie kursorem na panel, zdarzenie zostałoby
		-- odsiane i żyłka zerwałaby się mimo puszczenia przycisku.
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			FishingController.setReeling(false)
		end
	end)

	player.CharacterRemoving:Connect(function()
		-- Śmierć w trakcie łowienia: serwer też zeruje stan, ale niezależnie.
		-- Bez lokalnego sprzątania gracz wstaje z paskiem podcięcia na ekranie.
		chargeStartedAt = nil
		setPhase("Idle")
		CastMeter.hide()
		Bobber.clear()
		Hud.setDepth(nil)
	end)

	Net.CastStarted.OnClientEvent:Connect(function(depth: number, landing: Vector3)
		chargeStartedAt = nil
		setPhase("Waiting")
		CastMeter.showWaiting()
		Hud.setDepth(depth)

		-- Czas lotu z odległości, którą spławik faktycznie ma do pokonania.
		local position = Spatial.characterPosition(player)
		local distance = if position
			then (Vector3.new(landing.X, position.Y, landing.Z) - position).Magnitude
			else GameConfig.CAST_MIN_DISTANCE
		local tool = heldRod()
		local rodId = if tool then tool:GetAttribute(ROD_ATTRIBUTE) else nil
		local rod = if typeof(rodId) == "string" then Rods.find(rodId) else nil
		local flightTime = Cast.flightTime(distance, if rod then rod.castRange else distance)

		-- Spławik wylatuje w momencie puszczenia żyłki, a nie na starcie
		-- wymachu — inaczej wyprzedzałby ruch ręki. Wymach rysuje
		-- `AnglerController` z tej samej zmiany fazy.
		task.delay(CastPose.RELEASE_DELAY, function()
			if phase == "Waiting" then
				Bobber.launch(landing, flightTime)
			end
		end)
	end)

	Net.BiteStarted.OnClientEvent:Connect(function(window: number)
		setPhase("Biting")
		CastMeter.showBite(window)
		Bobber.dip()
	end)

	Net.FightStarted.OnClientEvent:Connect(function()
		setPhase("Fighting")
		reeling = false
		CastMeter.showFight()
		Bobber.beginFight()
	end)

	Net.FightUpdate.OnClientEvent:Connect(function(state: Types.FightState)
		CastMeter.updateFight(state)
		Bobber.setTension(state.tension, state.surging)
	end)

	Net.CastResolved.OnClientEvent:Connect(function(result: Types.CastResult)
		setPhase("Idle")
		reeling = false
		CastMeter.showResult(result)

		if result.outcome == "Caught" then
			-- Ryba wylatuje ze spławika, zanim ten zostanie zwinięty.
			if result.fish then
				local newSpecies = speciesLoaded and not knownSpecies[result.fish.fishId]
				local celebrated =
					Celebration.catch(result.fish, result.perfect, result.record, newSpecies)
				CatchFx.play(
					result.fish,
					result.perfect,
					result.record,
					Bobber.position(),
					celebrated
				)
			end
			Bobber.splash()
		end

		-- Zwinięcie zamiast zniknięcia. Plusk zdąży się pokazać, bo
		-- `reelIn` trwa trzy razy dłużej niż jego animacja startowa.
		Bobber.reelIn()
		Hud.setDepth(nil)
	end)
end

return FishingController
