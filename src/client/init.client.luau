--!strict
--[[
	Punkt wejścia klienta.

	Jak na serwerze: tylko kolejność startu i spięcie modułów, zero logiki gry.

	  1. ScreenGui   — jeden na całą grę, `ResetOnSpawn = false`, więc HUD
	                   przeżywa śmierć gracza.
	  2. Theme root  — ramka z jednym UIScale. Wszystkie panele montujemy
	                   w niej, nie wprost w ScreenGui, inaczej skalowanie
	                   nie obejmie ich wszystkich.
	  3. *.mount     — ekrany budują instancje, jeszcze bez danych.
	  4. subskrypcje — ProfileCache rozdaje snapshoty do ekranów.
	  5. kontrolery  — podpinają wejście gracza i efekty.
	  6. RequestProfile — prosimy serwer o dane, gdy już jest czym je wypełnić.

	Całość dzieje się za zasłoną `LoadingScreen`, która znika, gdy świat
	i profil są gotowe.

	Punkt 6 musi być OSTATNI. Serwer robi pierwszy `push` w `PlayerAdded`,
	co może się zdarzyć przed podłączeniem handlera przez klienta — jawne
	żądanie usuwa ten wyścig, zamiast liczyć na kolejkowanie Remote'ów.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local AnglerController = require(script.Controllers.AnglerController)
local EnvironmentController = require(script.Controllers.EnvironmentController)
local FishingController = require(script.Controllers.FishingController)
local LakeLife = require(script.Effects.LakeLife)
local NpcController = require(script.Controllers.NpcController)
local ProfileCache = require(script.ProfileCache)
local ShopController = require(script.Controllers.ShopController)
local TutorialController = require(script.Controllers.TutorialController)
local Underwater = require(script.Effects.Underwater)

local CastMeter = require(script.UI.CastMeter)
local Celebration = require(script.UI.Celebration)
local Hotbar = require(script.UI.Hotbar)
local Hud = require(script.UI.Hud)
local InventoryPanel = require(script.UI.InventoryPanel)
local JournalPanel = require(script.UI.JournalPanel)
local LoadingScreen = require(script.UI.LoadingScreen)
local MobileControls = require(script.UI.MobileControls)
local PromptBubble = require(script.UI.PromptBubble)
local ShopPanel = require(script.UI.ShopPanel)
local Theme = require(script.UI.Theme)
local Toast = require(script.UI.Toast)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Zasłona idzie PIERWSZA: wszystko poniżej buduje się już za nią.
LoadingScreen.show()

local screen = Instance.new("ScreenGui")
screen.Name = "FishinGameUI"
-- Bez tego cały HUD znika po śmierci i trzeba by go montować od nowa.
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- Odsuwa interfejs od górnego paska Robloxa i od wycięć w ekranach telefonów.
-- Bez tego licznik monet ląduje pod notchem na połowie urządzeń.
screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
screen.Parent = playerGui

local root = Theme.mountRoot(screen)

Hud.mount(root)
CastMeter.mount(root)
Hotbar.mount(root)
InventoryPanel.mount(root)
ShopPanel.mount(root)
JournalPanel.mount(root)
Toast.mount(root)
MobileControls.mount(root)
-- Ostatnia: warstwa nagród rysuje się nad całą resztą interfejsu.
Celebration.mount(root)

ProfileCache.onChanged(function(profile: Types.Profile)
	Hud.update(profile)
	Hotbar.update(profile)
	InventoryPanel.update(profile)
	ShopPanel.update(profile)
	JournalPanel.update(profile)
end)

Net.Notify.OnClientEvent:Connect(function(message: string, kind: string?)
	Toast.show(message, kind)
end)

Net.LeaderboardUpdated.OnClientEvent:Connect(function(entries: { Types.LeaderboardEntry })
	JournalPanel.setLeaderboard(entries)
end)

-- Przycisk dotykowy i `Tool.Activated` wołają dokładnie te same funkcje,
-- żeby obie ścieżki wejścia nie mogły się rozjechać.
MobileControls.setPrimaryAction(FishingController.press)
MobileControls.setPrimaryRelease(FishingController.release)
MobileControls.setReelingAction(FishingController.setReeling)

-- Slot na pasku i klawisz `1` wołają tę samą funkcję.
Hotbar.setAction(FishingController.toggleRod)

MobileControls.setInventoryAction(function()
	InventoryPanel.toggle()
	MobileControls.setInventoryHighlighted(InventoryPanel.isVisible())
end)

MobileControls.setJournalAction(function()
	JournalPanel.toggle()
	MobileControls.setJournalHighlighted(JournalPanel.isVisible())
end)

FishingController.onPhaseChanged(MobileControls.setPhase)

-- Szarpnięcie ryby musi być widoczne także na kciuku, nie tylko na pasku.
Net.FightUpdate.OnClientEvent:Connect(function(state: Types.FightState)
	MobileControls.setSurging(state.surging)
end)

ProfileCache.start()
Underwater.start()
FishingController.start()
-- Po FishingController: czyta z niego fazę lokalnego gracza.
AnglerController.start()
ShopController.start()
PromptBubble.start()
NpcController.start()
LakeLife.start()
EnvironmentController.start()
TutorialController.start()

Net.RequestProfile:FireServer()

-- Odsłaniamy grę dopiero, gdy mapa, światło, postać i profil są na miejscu.
task.spawn(LoadingScreen.finishWhenReady)
