--!strict
--[[
	Hud — stały pasek w lewym górnym rogu: monety, licznik złowionych,
	zajętość ekwipunku i założona wędka.

	Moduł jest singletonem (jeden HUD na ekran). Przy wielu instancjach tego
	samego panelu trzeba by przejść na fabrykę zwracającą handle — na razie
	byłaby to komplikacja bez powodu.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)
local GameConfig = require(Shared.Config.Game)
local Rods = require(Shared.Config.Rods)
local Types = require(Shared.Types)

local Theme = require(script.Parent.Theme)

local Hud = {}

local coinsLabel: TextLabel? = nil
local caughtLabel: TextLabel? = nil
local bagLabel: TextLabel? = nil
local rodLabel: TextLabel? = nil

local function row(order: number, text: string, color: Color3): TextLabel
	return Theme.label({
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = order,
		Font = Theme.FONT_BOLD,
		TextSize = 15,
		TextColor3 = color,
		Text = text,
	})
end

function Hud.mount(parent: Instance)
	-- Lokalne, nieopcjonalne uchwyty. Pola modułu są typu `TextLabel?`
	-- (przed `mount` nic nie istnieje), a `Theme.panel` oczekuje `Instance` —
	-- przekazanie pola wprost byłoby błędem "could be nil".
	local coins = row(1, "0", Theme.COLOR.coin)
	local caught = row(2, "0", Theme.COLOR.text)
	local bag = row(3, "0", Theme.COLOR.textMuted)
	local rod = row(4, "", Theme.COLOR.accent)

	coinsLabel = coins
	caughtLabel = caught
	bagLabel = bag
	rodLabel = rod

	Theme.panel({
		Name = "Hud",
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(220, 108),
		BackgroundTransparency = 0.12,
		Parent = parent,
	}, Theme.padding(12), Theme.verticalList(4), coins, caught, bag, rod)
end

function Hud.update(profile: Types.Profile)
	local coins, caught, bag, rod = coinsLabel, caughtLabel, bagLabel, rodLabel
	if not (coins and caught and bag and rod) then
		return -- jeszcze nie zamontowany
	end

	coins.Text = `Monety: {Format.coins(profile.coins)}`
	caught.Text = `Złowione: {profile.totalCaught}`
	bag.Text = `Ekwipunek: {#profile.inventory} / {GameConfig.MAX_INVENTORY}`

	-- Nazwa z configu, nie z profilu: profil trzyma samo id, a nazwa może
	-- się zmienić bez migracji danych.
	local definition = Rods.find(profile.equippedRod)
	rod.Text = if definition then definition.displayName else profile.equippedRod

	-- Pełny ekwipunek to stan, który blokuje rozgrywkę — ma kłuć w oczy.
	bag.TextColor3 = if #profile.inventory >= GameConfig.MAX_INVENTORY
		then Theme.COLOR.warning
		else Theme.COLOR.textMuted
end

return Hud
