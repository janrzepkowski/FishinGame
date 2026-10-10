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

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local Bobber = require(script.Parent.Parent.Effects.Bobber)
local CastAnimation = require(script.Parent.Parent.Effects.CastAnimation)
local CastMeter = require(script.Parent.Parent.UI.CastMeter)
local Hud = require(script.Parent.Parent.UI.Hud)

local ROD_ATTRIBUTE = "RodId"

local FishingController = {}

export type Phase = "Idle" | "Waiting" | "Biting"

local player = Players.LocalPlayer
local phase: Phase = "Idle"
local phaseListeners: { (Phase) -> () } = {}

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
	Jedyne wejście akcji gracza — spina `Tool.Activated` z desktopa
	i przycisk dotykowy. Dzięki temu obie ścieżki nie mogą się rozjechać.
]]
function FishingController.primaryAction()
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
	for _, child in character:GetChildren() do
		bindTool(child)
	end
	character.ChildAdded:Connect(bindTool)

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

	player.CharacterRemoving:Connect(function()
		-- Śmierć w trakcie łowienia: serwer też zeruje stan, ale niezależnie.
		-- Bez lokalnego sprzątania gracz wstaje z paskiem podcięcia na ekranie.
		setPhase("Idle")
		CastMeter.hide()
		CastAnimation.reset()
		Bobber.clear()
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

	Net.CastResolved.OnClientEvent:Connect(function(result: Types.CastResult)
		setPhase("Idle")
		CastMeter.showResult(result)
		CastAnimation.reset()

		if result.outcome == "Caught" then
			Bobber.splash()
		end

		-- Zwinięcie zamiast zniknięcia. Plusk zdąży się pokazać, bo
		-- `reelIn` trwa trzy razy dłużej niż jego animacja startowa.
		Bobber.reelIn()
		Hud.setDepth(nil)
	end)
end

return FishingController
