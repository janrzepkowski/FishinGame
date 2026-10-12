--!strict
--[[
	TutorialController — podpowiedzi dla nowego gracza, w chwili, gdy są
	potrzebne.

	Nie ma tu ekranu samouczka ani strzałek. Gra jest dla dzieci: nikt nie
	czyta instrukcji przed zabawą, za to każdy przeczyta jedno zdanie, które
	pojawia się dokładnie wtedy, gdy nie wie, co zrobić. Każda podpowiedź
	jest przypięta do sytuacji (pierwszy zamach, pierwsze czekanie, pierwsza
	walka) i pokazuje się RAZ na sesję.

	Podpowiedzi dostaje tylko ktoś, kto dopiero zaczyna — po kilku złowionych
	rybach milkną. Stan trzymamy w pamięci, nie w profilu: powtórka kilku
	zdań po powrocie do gry nikomu nie szkodzi, a nie wymaga zmiany zapisu.

	Komunikaty idą przez `Toast`, czyli w lewy dolny róg — środek ekranu
	zostaje dla wody i spławika.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LakeConfig = require(Shared.Config.Lake)
local Spatial = require(Shared.Util.Spatial)
local Types = require(Shared.Types)

local FishingController = require(script.Parent.FishingController)
local ProfileCache = require(script.Parent.Parent.ProfileCache)
local Toast = require(script.Parent.Parent.UI.Toast)

local Players = game:GetService("Players")

local TutorialController = {}

-- Po tylu złowionych rybach gracz już wie, o co chodzi.
local GRADUATE_AT = 3
-- Jak blisko wody trzeba podejść, żeby dostać podpowiedź o zamachu.
local NEAR_WATER = 30

local player = Players.LocalPlayer
local shown: { [string]: boolean } = {}
local caughtSoFar = 0
local inventoryCount = 0
local profileReady = false

local function hint(key: string, message: string)
	if shown[key] or not profileReady or caughtSoFar >= GRADUATE_AT then
		return
	end
	shown[key] = true
	Toast.show(message, "Info")
end

local function onPhase(phase: FishingController.Phase)
	if phase == "Charging" then
		hint("charge", "Puść przycisk, gdy pasek jest pełny — rzucisz najdalej.")
	elseif phase == "Waiting" then
		hint("wait", "Spławik tylko drgnął? To skubnięcie. Czekaj, aż zniknie pod wodą!")
	elseif phase == "Biting" then
		hint("bite", "Bierze! Kliknij teraz!")
	elseif phase == "Fighting" then
		hint("fight", "Trzymaj, żeby holować. Puść, gdy ryba szarpie!")
	end
end

local function onProfile(profile: Types.Profile)
	local previous = caughtSoFar
	caughtSoFar = profile.totalCaught
	inventoryCount = #profile.inventory
	profileReady = true

	if previous == 0 and caughtSoFar == 1 then
		-- Pierwsza ryba w torbie: pokazujemy, co się z nią robi.
		shown.sell = true
		Toast.show("Pierwsza ryba! Zanieś ją do skupu przy placu i sprzedaj.", "Success")
	end
end

--[[ Podpowiedzi zależne od miejsca: sprawdzane co chwilę, nie co klatkę. ]]
local function watchPlace()
	while caughtSoFar < GRADUATE_AT do
		task.wait(1)

		local position = Spatial.characterPosition(player)
		if position and profileReady then
			local fromShore = -LakeConfig.edgeDistance(position)

			if caughtSoFar == 0 and fromShore > NEAR_WATER then
				hint("go", "Idź ścieżką na pomost — nad wodą zaczyna się łowienie.")
			elseif fromShore <= NEAR_WATER and FishingController.getPhase() == "Idle" then
				if inventoryCount == 0 then
					hint(
						"cast",
						"Przytrzymaj przycisk, żeby się zamachnąć. Puść, żeby rzucić!"
					)
				end
			end
		end
	end
end

function TutorialController.start()
	ProfileCache.onChanged(onProfile)
	FishingController.onPhaseChanged(onPhase)
	task.spawn(watchPlace)
end

return table.freeze(TutorialController)
