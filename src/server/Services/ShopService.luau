--!strict
--[[
	ShopService — sprzedaż połowu i zakup wędek.

	Klient ma na stoiskach ProximityPrompt, ale prompt NIE jest walidacją:
	da się go wywołać Remote'em bez podchodzenia do stoiska. Dlatego każda
	transakcja sprawdza odległość tutaj, po stronie serwera.

	Wzorzec na przyszłość: każdy handler zaczyna się od walidacji wejścia
	(`typeof`), potem walidacji stanu (profil, odległość, stać go?), a dopiero
	na końcu modyfikuje profil. W tej kolejności, zawsze. Odwrócenie jej
	kończy się częściowo wykonaną transakcją.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Util.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local Net = require(ReplicatedStorage.Shared.Net)
local Rods = require(ReplicatedStorage.Shared.Config.Rods)
local Spatial = require(ReplicatedStorage.Shared.Util.Spatial)

local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local RodService = require(script.Parent.RodService)
local WorldBuilder = require(script.Parent.Parent.World.WorldBuilder)

local ShopService = {}

--[[ Czy gracz stoi wystarczająco blisko stoiska. ]]
local function isNear(player: Player, stand: BasePart?): boolean
	if not stand then
		return false
	end

	local position = Spatial.characterPosition(player)
	if not position then
		return false
	end

	return Spatial.distanceToPart(position, stand) <= GameConfig.SHOP_INTERACT_DISTANCE
end

local function onRequestSellAll(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	if not isNear(player, WorldBuilder.getFishBuyer()) then
		Net.Notify:FireClient(player, "Musisz stać przy skupie ryb.", "Warning")
		return
	end

	if #profile.inventory == 0 then
		Net.Notify:FireClient(player, "Nie masz czego sprzedać.", "Info")
		return
	end

	-- Cenę liczymy z zapisanego `price`, a nie z aktualnego cennika. Dzięki temu
	-- zmiana `pricePerKg` w configu nie przewalutuje komuś połowu w połowie sesji.
	local total = 0
	local count = #profile.inventory
	for _, caught in profile.inventory do
		total += caught.price
	end

	DataService.mutate(player, function(target)
		target.coins += total
		-- `totalEarned` rośnie tylko w górę i nigdy nie maleje przy wydawaniu.
		-- To on zasila ranking — patrz LeaderboardService.
		target.totalEarned += total
		target.inventory = {}
	end)

	Net.Notify:FireClient(
		player,
		`Sprzedano {count} szt. za {Format.coins(total)} monet.`,
		"Success"
	)

	local updated = DataService.get(player)
	Analytics.funnelStep(player, 4, "Sold")
	Analytics.coinsEarned(player, total, if updated then updated.coins else total, "FishSale")
end

local function onRequestBuyRod(player: Player, rodId: unknown)
	-- Wejście z klienta. Bez tego sprawdzenia `Rods.find(rodId)` dostałoby
	-- tabelę albo Instance i wywaliło handler.
	if typeof(rodId) ~= "string" then
		return
	end

	local definition = Rods.find(rodId :: string)
	if not definition then
		return
	end

	local profile = DataService.get(player)
	if not profile then
		return
	end

	if not isNear(player, WorldBuilder.getRodShop()) then
		Net.Notify:FireClient(player, "Musisz stać przy sklepie wędkarskim.", "Warning")
		return
	end

	if profile.ownedRods[definition.id] then
		Net.Notify:FireClient(player, "Już masz tę wędkę.", "Info")
		return
	end

	if profile.coins < definition.price then
		local missing = definition.price - profile.coins
		Net.Notify:FireClient(player, `Brakuje {Format.coins(missing)} monet.`, "Warning")
		return
	end

	DataService.mutate(player, function(target)
		target.coins -= definition.price
		target.ownedRods[definition.id] = true
		-- Auto-zakładamy świeżo kupioną wędkę. Nikt nie kupuje lepszego
		-- sprzętu, żeby dalej łowić starym.
		target.equippedRod = definition.id
	end)

	task.spawn(RodService.refresh, player)
	Net.Notify:FireClient(player, `Kupiono: {definition.displayName}`, "Success")

	local updated = DataService.get(player)
	Analytics.coinsSpent(
		player,
		definition.price,
		if updated then updated.coins else 0,
		definition.id
	)
end

local function onRequestEquipRod(player: Player, rodId: unknown)
	if typeof(rodId) ~= "string" then
		return
	end

	local definition = Rods.find(rodId :: string)
	if not definition then
		return
	end

	local profile = DataService.get(player)
	if not profile then
		return
	end

	if not profile.ownedRods[definition.id] then
		return -- nie posiada; cicho, bo to albo desync UI, albo próba oszustwa
	end

	if profile.equippedRod == definition.id then
		return
	end

	DataService.mutate(player, function(target)
		target.equippedRod = definition.id
	end)

	task.spawn(RodService.refresh, player)
	Net.Notify:FireClient(player, `Założono: {definition.displayName}`, "Info")
end

function ShopService.start()
	Net.RequestSellAll.OnServerEvent:Connect(onRequestSellAll)
	Net.RequestBuyRod.OnServerEvent:Connect(onRequestBuyRod)
	Net.RequestEquipRod.OnServerEvent:Connect(onRequestEquipRod)
end

return ShopService
