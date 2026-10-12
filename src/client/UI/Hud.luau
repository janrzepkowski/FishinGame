--!strict
--[[
	Hud — stałe „pigułki" w lewym górnym rogu: monety, złowione ryby, torba,
	wędka i głębokość wody pod spławikiem.

	Styl z gier dla dzieci na Robloxie: każda statystyka to osobna, kolorowa
	pigułka z okrągłą ikoną wystającą z lewej krawędzi i białą liczbą
	z obrysem. Bez wspólnej ciemnej karty — pigułki „pływają" nad grą
	i zajmują tylko tyle miejsca, ile mają tekstu.

	Decyzje, które zostały z poprzedniej wersji:

	* Monety ANIMUJĄ się do nowej wartości zamiast przeskakiwać. Skok z 300
	  na 1200 po sprzedaży jest nie do odczytania — licznik przewijający się
	  przez pół sekundy mówi „dostałeś dużo" bez żadnego tekstu. Do tego
	  pigułka podskakuje (`Theme.bump`), a złote monety z `Celebration`
	  lecą właśnie do jej ikony.

	* Torba ma pasek, nie tylko liczbę. „18 / 24" trzeba przeczytać
	  i podzielić; pigułka wypełniona w 3/4 widać kątem oka.
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

local PILL_HEIGHT = 34
local ICON = 40
local WIDTH = 200
local WIDTH_PHONE = 164

local root: Frame? = nil
local coinsPill: Frame? = nil
local coinsIcon: TextLabel? = nil
local coinsLabel: TextLabel? = nil
local caughtLabel: TextLabel? = nil
local bagLabel: TextLabel? = nil
local bagFill: Frame? = nil
local rodLabel: TextLabel? = nil
local depthPill: Frame? = nil
local depthLabel: TextLabel? = nil

local displayedCoins = 0
local targetCoins = 0
local firstSnapshot = true

--[[
	Pigułka: kolorowe tło, okrągła ikona wystająca z lewej, biała liczba
	z obrysem. Zwraca pigułkę, jej napis i ikonę (do niej lecą monety).
]]
local function pill(
	order: number,
	glyph: string,
	color: Color3,
	height: number
): (Frame, TextLabel, TextLabel)
	local value = Theme.label({
		Name = "Value",
		Size = UDim2.new(1, -(ICON - 6), 1, 0),
		Position = UDim2.fromOffset(ICON - 2, 0),
		Font = Theme.FONT_BLACK,
		TextSize = if height > PILL_HEIGHT - 4 then Theme.TEXT.lead else Theme.TEXT.small,
		TextColor3 = Theme.COLOR.textInverse,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
		Text = "",
	})
	Theme.outline(value, Theme.COLOR.stroke, 2)

	local icon = Theme.icon(glyph, color:Lerp(Color3.new(1, 1, 1), 0.15), ICON, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -6, 0.5, 0),
		ZIndex = 4,
	})

	local frame = Theme.create(
		"Frame",
		{
			Name = `Pill{order}`,
			Size = UDim2.new(1, -8, 0, height),
			Position = UDim2.fromOffset(8, 0),
			LayoutOrder = order,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		},
		Theme.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Theme.stroke(),
		Theme.candyGradient(0.2),
		icon,
		value
	) :: Frame

	return frame, value, icon
end

function Hud.mount(parent: Instance)
	local coinsRow, coins, coinIcon = pill(1, "$", Theme.COLOR.coin, PILL_HEIGHT + 4)
	local caughtRow, caught = pill(2, "🐟", Theme.COLOR.accent, PILL_HEIGHT)

	-- Torba: pigułka-pasek. Tło jasne, a kolor wypełnia się wraz z zajętością.
	local bagRow, bag = pill(3, "🎒", Theme.COLOR.panelHigh, PILL_HEIGHT)
	local gradient = bagRow:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient:Destroy()
	end
	local fill = Theme.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.COLOR.success,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = bagRow,
	}, Theme.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), Theme.candyGradient(0.2)) :: Frame

	local rodRow, rod = pill(4, "🎣", Theme.COLOR.purple, PILL_HEIGHT - 6)

	local depthRow, depthText = pill(5, "≈", Theme.COLOR.water, PILL_HEIGHT - 6)
	depthRow.Visible = false

	coinsPill = coinsRow
	coinsIcon = coinIcon
	coinsLabel = coins
	caughtLabel = caught
	bagLabel = bag
	bagFill = fill
	rodLabel = rod
	depthPill = depthRow
	depthLabel = depthText

	root = Theme.create("Frame", {
		Name = "Hud",
		Position = UDim2.fromOffset(Theme.SPACE.lg, Theme.SPACE.lg),
		Size = UDim2.fromOffset(WIDTH, 150),
		BackgroundTransparency = 1,
		Parent = parent,
	}, Theme.list(Theme.SPACE.sm), coinsRow, caughtRow, bagRow, rodRow, depthRow) :: Frame

	-- Wysokość jest STAŁA, wyliczona z `Theme.HUD_BAND`, a nie automatyczna.
	-- Pod HUD-em stoją toasty i nie mogą podskakiwać za każdym razem, gdy
	-- pojawia się wskaźnik głębokości — czyli przy każdym zarzuceniu.
	--
	-- Na telefonie pigułki są węższe: kciuk trzyma dół ekranu, a szeroki
	-- HUD zasłoniłby wodę w kluczowym momencie podcięcia.
	Theme.onLayout(function(device: Theme.Device)
		local panel = root
		if not panel then
			return
		end

		local margin = Theme.edgeMargin(device)
		local width = if device == "Phone" then WIDTH_PHONE else WIDTH

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
		local step = (targetCoins - displayedCoins) * math.min(delta * 7, 1)
		displayedCoins += step

		if math.abs(targetCoins - displayedCoins) < 0.5 then
			displayedCoins = targetCoins
		end

		label.Text = Format.coins(displayedCoins)
	end)
end

--[[ Ikona monet — cel, do którego `Celebration` posyła lecące monety. ]]
function Hud.coinTarget(): GuiObject?
	return coinsIcon
end

function Hud.update(profile: Types.Profile)
	local coins, caught, bag, fill, rod = coinsLabel, caughtLabel, bagLabel, bagFill, rodLabel
	if not (coins and caught and bag and fill and rod) then
		return
	end

	-- Przy pierwszym snapshocie nie animujemy od zera — gracz, który wraca
	-- z 50 tysiącami, nie ma oglądać, jak mu się doliczają.
	if firstSnapshot then
		firstSnapshot = false
		displayedCoins = profile.coins
		coins.Text = Format.coins(profile.coins)
	elseif profile.coins > targetCoins then
		-- Pigułka podskakuje przy KAŻDYM przyroście. Sprzedaż połowu to
		-- najważniejsze zdarzenie w pętli gry i ma być widoczna bez
		-- patrzenia na liczbę.
		local coinPill = coinsPill
		if coinPill then
			Theme.bump(coinPill, 0.22)
			coins.TextColor3 = Theme.COLOR.success:Lerp(Color3.new(1, 1, 1), 0.3)
			TweenService:Create(coins, TweenInfo.new(0.8), { TextColor3 = Theme.COLOR.textInverse })
				:Play()
		end
	end
	targetCoins = profile.coins

	caught.Text = `{Format.coins(profile.totalCaught)} ryb`

	local count = #profile.inventory
	local capacity = GameConfig.MAX_INVENTORY
	local ratio = count / capacity

	bag.Text = `{count} / {capacity}`
	TweenService:Create(fill, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Size = UDim2.fromScale(math.clamp(ratio, 0.001, 1), 1),
	}):Play()
	fill.BackgroundColor3 = if ratio >= 1
		then Theme.COLOR.danger
		elseif ratio >= 0.8 then Theme.COLOR.warning
		else Theme.COLOR.success

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
	local chip, label = depthPill, depthLabel
	if not (chip and label) then
		return
	end

	if not depth or depth <= 0 then
		chip.Visible = false
		return
	end

	local factor = math.clamp(depth / LakeConfig.MAX_DEPTH, 0, 1)
	label.Text = `Głębia {Format.meters(depth)}`
	chip.BackgroundColor3 = Theme.COLOR.water:Lerp(Theme.COLOR.coin, factor)
	if not chip.Visible then
		chip.Visible = true
		Theme.pop(chip, 0.5)
	end
end

return Hud
