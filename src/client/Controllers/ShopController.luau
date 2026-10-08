--!strict
--[[
	ShopController — interakcje przy stoiskach i skrót do ekwipunku.

	Prompty obsługujemy po stronie KLIENTA (`ProximityPromptService`), bo to
	tylko otwarcie okna. Sama transakcja idzie Remote'em, a serwer niezależnie
	sprawdza, czy gracz faktycznie stoi przy stoisku (patrz ShopService.isNear).
	Prompt to wygoda dla gracza, nie zabezpieczenie.
]]

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.Game)
local Net = require(Shared.Net)

local InventoryPanel = require(script.Parent.Parent.UI.InventoryPanel)
local ShopPanel = require(script.Parent.Parent.UI.ShopPanel)

local INVENTORY_KEY = Enum.KeyCode.B

local ShopController = {}

function ShopController.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local stand = prompt.Parent
		if not stand then
			return
		end

		local kind = stand:GetAttribute(GameConfig.STAND_ATTRIBUTE)
		if kind == GameConfig.STAND_FISH_BUYER then
			Net.RequestSellAll:FireServer()
		elseif kind == GameConfig.STAND_ROD_SHOP then
			ShopPanel.setVisible(true)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- `gameProcessed` jest prawdziwe, gdy wejście zostało już zużyte przez
		-- UI albo czat. Bez tej kontroli wpisanie "b" na czacie otwierałoby
		-- ekwipunek.
		if gameProcessed then
			return
		end

		if input.KeyCode == INVENTORY_KEY then
			InventoryPanel.toggle()
		end
	end)
end

return ShopController
