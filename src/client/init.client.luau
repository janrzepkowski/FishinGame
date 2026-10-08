--!strict
--[[
	Punkt wejścia klienta.

	Jak na serwerze: tylko kolejność startu, zero logiki gry.

	  1. ScreenGui   — jeden na całą grę, `ResetOnSpawn = false`, więc HUD
	                   przeżywa śmierć gracza.
	  2. UI.mount    — ekrany budują swoje instancje, ale jeszcze bez danych.
	  3. subskrypcje — ProfileCache rozdaje snapshoty do ekranów.
	  4. kontrolery  — podpinają wejście gracza.
	  5. RequestProfile — prosimy serwer o dane, gdy już jest co nimi wypełnić.

	Punkt 5 musi być OSTATNI. Odwrócenie kolejności z punktem 2 oznacza
	snapshot przychodzący do niezamontowanego UI.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local FishingController = require(script.Controllers.FishingController)
local ProfileCache = require(script.ProfileCache)
local ShopController = require(script.Controllers.ShopController)

local CastMeter = require(script.UI.CastMeter)
local Hud = require(script.UI.Hud)
local InventoryPanel = require(script.UI.InventoryPanel)
local ShopPanel = require(script.UI.ShopPanel)
local Toast = require(script.UI.Toast)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screen = Instance.new("ScreenGui")
screen.Name = "FishinGameUI"
-- Bez tego cały HUD znika po śmierci i trzeba by go montować od nowa
-- przy każdym respawnie.
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

Hud.mount(screen)
CastMeter.mount(screen)
InventoryPanel.mount(screen)
ShopPanel.mount(screen)
Toast.mount(screen)

ProfileCache.onChanged(function(profile: Types.Profile)
	Hud.update(profile)
	InventoryPanel.update(profile)
	ShopPanel.update(profile)
end)

Net.Notify.OnClientEvent:Connect(function(message: string, kind: string?)
	Toast.show(message, kind)
end)

ProfileCache.start()
FishingController.start()
ShopController.start()

Net.RequestProfile:FireServer()
