--!strict
--[[
	FishingController — wejście gracza i reakcja na zdarzenia z serwera.

	Cała obsługa kliknięcia to jedna reguła:
	  stan Idle  -> "zarzucam"  (RequestCast)
	  inny stan  -> "podcinam"  (RequestReel)

	Dzięki temu jeden przycisk obsługuje obie akcje, a podcięcie przed braniem
	jest możliwe — i karane. Wariant, w którym klient blokuje za wczesny klik,
	byłby wygodniejszy dla gracza, ale wtedy kara nie istnieje i optymalną
	strategią zostaje trzymanie autoklikera.

	Używamy `Tool.Activated`, a nie `UserInputService`, bo Activated samo
	z siebie nie odpala się przy klikaniu w UI. Przy ręcznym czytaniu myszy
	każde kliknięcie w sklepie zarzucałoby wędkę.

	Stan jest NARZUCANY przez serwer (CastStarted / BiteStarted / CastResolved).
	Klient go nie zgaduje i nie zmienia samodzielnie — przy rozjechaniu się
	wygrywa serwer.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local Bobber = require(script.Parent.Parent.Effects.Bobber)
local CastMeter = require(script.Parent.Parent.UI.CastMeter)

local ROD_ATTRIBUTE = "RodId"

local FishingController = {}

local player = Players.LocalPlayer
local phase: "Idle" | "Waiting" | "Biting" = "Idle"

local function onActivated()
	if phase == "Idle" then
		Net.RequestCast:FireServer()
	else
		Net.RequestReel:FireServer()
	end
end

local function bindTool(instance: Instance)
	if not instance:IsA("Tool") or instance:GetAttribute(ROD_ATTRIBUTE) == nil then
		return
	end
	-- Połączenie żyje tyle, co Tool. Przy zniszczeniu narzędzia (zmiana wędki)
	-- Roblox zbiera je razem z instancją, więc nie trzymamy go ręcznie.
	instance.Activated:Connect(onActivated)
end

local function watchCharacter(character: Model)
	for _, child in character:GetChildren() do
		bindTool(child)
	end
	character.ChildAdded:Connect(bindTool)
end

function FishingController.start()
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)

	player.CharacterRemoving:Connect(function()
		-- Śmierć w trakcie łowienia: serwer też zeruje stan, ale u niego
		-- dzieje się to niezależnie. Jeśli nie wyczyścimy tego lokalnie,
		-- gracz wstanie z paskiem podcięcia na ekranie.
		phase = "Idle"
		CastMeter.hide()
		Bobber.clear()
	end)

	Net.CastStarted.OnClientEvent:Connect(function()
		phase = "Waiting"
		CastMeter.showWaiting()
		Bobber.cast()
	end)

	Net.BiteStarted.OnClientEvent:Connect(function(window: number)
		phase = "Biting"
		CastMeter.showBite(window)
		Bobber.dip()
	end)

	Net.CastResolved.OnClientEvent:Connect(function(result: Types.CastResult)
		phase = "Idle"
		CastMeter.showResult(result)
		Bobber.clear()
	end)
end

return FishingController
