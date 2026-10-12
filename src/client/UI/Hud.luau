--!strict
--[[
	Hud — stały panel z monetami, licznikiem, zajętością torby, wędką
	i głębokością wody pod spławikiem.

	Dwie decyzje projektowe:

	* Monety ANIMUJĄ się do nowej wartości zamiast przeskakiwać. Skok z 300
	  na 1200 po sprzedaży jest nie do odczytania — licznik przewijający się
	  przez pół sekundy mówi „dostałeś dużo" bez żadnego tekstu.

	* Torba ma pasek, nie tylko liczbę. „18 / 24" trzeba przeczytać i podzielić;
	  pasek w 3/4 widać kątem oka w trakcie łowienia.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)
local GameConfig = require(Shared.Config.Game)
local LakeConfig = require(Shared.Config.Lake)
local Rods = require(Shared.Config.Rods)
local Types = require(Shared.Types)

local Theme = require(script.Parent.Theme)

local Hud = {}

local root: Frame? = nil
local coinsLabel: TextLabel? = nil
local caughtLabel: TextLabel? = nil
local bagLabel: TextLabel? = nil
local bagFill: Frame? = nil
local rodLabel: TextLabel? = nil
local depthChip: Frame? = nil
local depthLabel: TextLabel? = nil

local displayedCoins = 0
local targetCoins = 0

local function statRow(order: number, icon: string, color: Color3): (Frame, TextLabel)
	local value = Theme.label({
		Size = UDim2.new(1, -26, 1, 0),
		Position = UDim2.fromOffset(26, 0),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.body,
		TextColor3 = Theme.COLOR.text,
		TextYAlignment = Enum.TextYAlignment.Center,
		Text = "",
	})

	local row = Theme.create(
		"Frame",
		{
			Name = `Stat{order}`,
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = order,
			BackgroundTransparency = 1,
		},
		Theme.label({
			Size = UDim2.fromOffset(22, 22),
			Font = Theme.FONT_BLACK,
			TextSize = Theme.TEXT.body,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = icon,
		}),
		value
	) :: Frame

	return row, value
end

function Hud.mount(parent: Instance)
	local coinsRow, coins = statRow(1, "◆", Theme.COLOR.coin)
	coins.TextColor3 = Theme.COLOR.coin
	coins.TextSize = Theme.TEXT.lead
	coins.Font = Theme.FONT_BLACK
	-- Licznik odświeża się tylko przy ZMIANIE wartości, a nowy gracz zaczyna
	-- od zera i zostaje przy zerze — bez tego wiersz monet byłby pusty.
	coins.Text = Format.coins(displayedCoins)

	local caughtRow, caught = statRow(2, "❖", Theme.COLOR.accent)
	local bagRow, bag = statRow(3, "▦", Theme.COLOR.textMuted)

	local track, fill = Theme.progress({
		Name = "BagTrack",
		Size = UDim2.new(1, 0, 0, 5),
		LayoutOrder = 4,
	}, Theme.COLOR.accent)

	local rod = Theme.label({
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 5,
		TextSize = Theme.TEXT.small,
		TextColor3 = Theme.COLOR.accent,
		Text = "",
	})

	local depthText = Theme.label({
		Size = UDim2.new(1, -22, 1, 0),
		Position = UDim2.fromOffset(22, 0),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.small,
		TextColor3 = Theme.COLOR.water,
		Text = "",
	})

	local depth = Theme.create(
		"Frame",
		{
			Name = "Depth",
			Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = 6,
			BackgroundTransparency = 1,
			Visible = false,
		},
		Theme.label({
			Size = UDim2.fromOffset(20, 20),
			Font = Theme.FONT_BLACK,
			TextSize = Theme.TEXT.small,
			TextColor3 = Theme.COLOR.water,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "≈",
		}),
		depthText
	) :: Frame

	coinsLabel = coins
	caughtLabel = caught
	bagLabel = bag
	bagFill = fill
	rodLabel = rod
	depthChip = depth
	depthLabel = depthText

	root = Theme.panel(
		{
			Name = "Hud",
			Position = UDim2.fromOffset(Theme.SPACE.lg, Theme.SPACE.lg),
			Size = UDim2.fromOffset(230, 150),
			BackgroundTransparency = 0.08,
			Parent = parent,
		},
		Theme.padding(Theme.SPACE.md),
		Theme.list(Theme.SPACE.xs),
		coinsRow,
		caughtRow,
		bagRow,
		track,
		rod,
		depth
	)

	-- Wysokość jest STAŁA, wyliczona z `Theme.HUD_BAND`, a nie automatyczna.
	-- Pod HUD-em stoją toasty i nie mogą podskakiwać za każdym razem, gdy
	-- pojawia się wskaźnik głębokości — czyli przy każdym zarzuceniu.
	--
	-- Na telefonie panel jest węższy: kciuk trzyma dół ekranu, a szeroka
	-- karta zasłoniłaby wodę w kluczowym momencie podcięcia.
	Theme.onLayout(function(device: Theme.Device)
		local panel = root
		if not panel then
			return
		end

		local margin = if device == "Phone" then Theme.SPACE.sm else Theme.SPACE.lg
		local width = if device == "Phone" then 182 else 230

		panel.Position = UDim2.fromOffset(margin, margin)
		panel.Size = UDim2.fromOffset(width, Theme.HUD_BAND[device] - margin * 2)
	end)

	RunService.RenderStepped:Connect(function(delta: number)
		local label = coinsLabel
		if not label or displayedCoins == targetCoins then
			return
		end

		-- Dociąganie wykładnicze: szybkie na początku, miękkie na końcu.
		-- Próg 0,5 zamyka sprawę, bo inaczej licznik dożywotnio dopełza
		-- ostatnie setne części monety.
		local step = (targetCoins - displayedCoins) * math.min(delta * 9, 1)
		displayedCoins += step

		if math.abs(targetCoins - displayedCoins) < 0.5 then
			displayedCoins = targetCoins
		end

		label.Text = Format.coins(displayedCoins)
	end)
end

function Hud.update(profile: Types.Profile)
	local coins, caught, bag, fill, rod = coinsLabel, caughtLabel, bagLabel, bagFill, rodLabel
	if not (coins and caught and bag and fill and rod) then
		return
	end

	if profile.coins > targetCoins then
		-- Krótki błysk na przyroście. Sprzedaż połowu to najważniejsze
		-- zdarzenie w pętli gry i ma być widoczne bez patrzenia na licznik.
		coins.TextColor3 = Theme.COLOR.success
		TweenService:Create(coins, TweenInfo.new(0.6), { TextColor3 = Theme.COLOR.coin }):Play()
	end

	targetCoins = profile.coins
	-- Przy pierwszym snapshocie nie animujemy od zera — gracz, który wraca
	-- z 50 tysiącami, nie ma oglądać, jak mu się doliczają.
	if displayedCoins == 0 and profile.totalCaught > 0 then
		displayedCoins = profile.coins
		coins.Text = Format.coins(profile.coins)
	end

	caught.Text = `Złowione: {profile.totalCaught}`

	local count = #profile.inventory
	local capacity = GameConfig.MAX_INVENTORY
	local ratio = count / capacity

	bag.Text = `Torba: {count} / {capacity}`
	fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	fill.BackgroundColor3 = if ratio >= 1
		then Theme.COLOR.danger
		elseif ratio >= 0.8 then Theme.COLOR.warning
		else Theme.COLOR.accent
	bag.TextColor3 = if ratio >= 1 then Theme.COLOR.danger else Theme.COLOR.text

	-- Nazwa z configu, nie z profilu: profil trzyma samo id, a nazwa może
	-- się zmienić bez migracji danych.
	local definition = Rods.find(profile.equippedRod)
	rod.Text = if definition then definition.displayName else profile.equippedRod
end

--[[
	Pokazuje głębokość pod spławikiem. `nil` chowa wskaźnik.

	Kolor idzie od barwy wody do złotej wraz z głębokością — gracz kojarzy
	„złoty = tu są lepsze ryby" bez czytania liczby.
]]
function Hud.setDepth(depth: number?)
	local chip, label = depthChip, depthLabel
	if not (chip and label) then
		return
	end

	if not depth or depth <= 0 then
		chip.Visible = false
		return
	end

	local factor = math.clamp(depth / LakeConfig.MAX_DEPTH, 0, 1)
	label.Text = `Głębokość {Format.meters(depth)}`
	label.TextColor3 = Theme.COLOR.water:Lerp(Theme.COLOR.coin, factor)
	chip.Visible = true
end

return Hud
