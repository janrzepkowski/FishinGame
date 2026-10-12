--!strict
--[[
	FishingController — wejście gracza i reakcja na zdarzenia z serwera.

	Cała obsługa akcji to jedna reguła:
	  stan Idle  -> „zarzucam"  (RequestCast)
	  inny stan  -> „podcinam"  (RequestReel)

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
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local Bobber = require(script.Parent.Parent.Effects.Bobber)
local CastAnimation = require(script.Parent.Parent.Effects.CastAnimation)
local CastMeter = require(script.Parent.Parent.UI.CastMeter)
local CatchShowcase = require(script.Parent.Parent.Effects.CatchShowcase)
local Celebration = require(script.Parent.Parent.UI.Celebration)
local Hotbar = require(script.Parent.Parent.UI.Hotbar)
local Hud = require(script.Parent.Parent.UI.Hud)

local ROD_ATTRIBUTE = "RodId"

local FishingController = {}

export type Phase = "Idle" | "Waiting" | "Biting" | "Fighting"

local player = Players.LocalPlayer
local phase: Phase = "Idle"
local phaseListeners: { (Phase) -> () } = {}
local reeling = false

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
	Jedyne wejście akcji gracza — spina `Tool.Activated` z desktopa
	i przycisk dotykowy. Dzięki temu obie ścieżki nie mogą się rozjechać.

	W czasie walki kliknięcie nie wysyła nic: tam liczy się TRZYMANIE,
	obsługiwane przez `setReeling`.
]]
function FishingController.primaryAction()
	if phase == "Fighting" then
		return
	end

	if not ensureEquipped() then
		return
	end

	if phase == "Idle" then
		Net.RequestCast:FireServer()
	else
		Net.RequestReel:FireServer()
	end
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
	tool.Activated:Connect(FishingController.primaryAction)
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
	CastAnimation.start()

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
		setPhase("Idle")
		CastMeter.hide()
		CastAnimation.reset()
		Bobber.clear()
		CatchShowcase.clear()
		Hud.setDepth(nil)
	end)

	Net.CastStarted.OnClientEvent:Connect(function(depth: number)
		setPhase("Waiting")
		CastMeter.showWaiting()
		Hud.setDepth(depth)
		-- Spławik wylatuje w momencie puszczenia żyłki przez animację,
		-- a nie na starcie zamachu — inaczej wyprzedzałby ruch ręki.
		CastAnimation.playCast(Bobber.launch)
	end)

	Net.BiteStarted.OnClientEvent:Connect(function(window: number)
		setPhase("Biting")
		CastMeter.showBite(window)
		CastAnimation.playBite()
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
		CastAnimation.reset()

		local caught = result.fish
		local from = Bobber.position()
		if result.outcome == "Caught" and caught then
			Bobber.splash()
			-- Ryba wyskakuje ze spławika, a baner nagrody pojawia się,
			-- gdy dotrze nad głowę gracza — oba efekty grają razem.
			CatchShowcase.play(caught, from, function()
				Celebration.catch(result)
			end)
		end

		-- Zwinięcie zamiast zniknięcia. Plusk zdąży się pokazać, bo
		-- `reelIn` trwa trzy razy dłużej niż jego animacja startowa.
		Bobber.reelIn()
		Hud.setDepth(nil)
	end)
end

return FishingController
