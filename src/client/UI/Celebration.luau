--!strict
--[[
	Celebration — „kasynowe" animacje nagród: rekord, nowy gatunek, rzadka
	ryba, perfekcyjne podcięcie, duża sprzedaż, nowa wędka.

	=========================================================================
	PO CO
	=========================================================================
	Gra jest dla dzieci, a pętla „zarzuć → poczekaj → wyholuj" sama w sobie
	jest spokojna. Nagroda musi być GŁOŚNA i krótka: wyskakujący baner
	z promieniami, mieniący się napis, licznik kręcący się jak bęben
	automatu, konfetti, monety lecące do licznika. Wszystko trwa 2-3 s
	i niczego nie blokuje.

	=========================================================================
	GDZIE
	=========================================================================
	Baner siedzi w GÓRNYM ŚRODKU, nie w środku ekranu. Zasada „środek
	należy do rozgrywki" (CLAUDE.md, punkt 8) zostaje: górny środek jest
	wolny na każdej platformie (czat po lewej, lista graczy po prawej),
	a baner znika, zanim gracz zarzuci ponownie.

	Konfetti przelatuje przez cały ekran, ale jest przezroczyste dla
	kliknięć (`Active = false`) i znika po 2,5 s — to dekoracja, nie okno.

	=========================================================================
	SKALA NAGRODY
	=========================================================================
	Nie każda ryba dostaje fanfary — inaczej nic nie znaczą. Poziom liczymy
	z wyniku: legenda > nowy gatunek > rekord > epicka > rzadka > perfekcja.
	Zwykła płoć bez rekordu nie dostaje niczego poza paskiem łowienia.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Fish = require(Shared.Config.Fish)
local Format = require(Shared.Util.Format)
local Rods = require(Shared.Config.Rods)
local Types = require(Shared.Types)

local FishCard = require(script.Parent.FishCard)
local Hud = require(script.Parent.Hud)
local Theme = require(script.Parent.Theme)

local Celebration = {}

local BANNER = Vector2.new(440, 190)
local BANNER_PHONE = Vector2.new(320, 160)
local LIFETIME = 2.8
local ROLL_TIME = 1.1
local RAYS = 12

local RAINBOW = {
	Color3.fromRGB(255, 92, 120),
	Color3.fromRGB(255, 176, 32),
	Color3.fromRGB(255, 230, 60),
	Color3.fromRGB(76, 214, 98),
	Color3.fromRGB(66, 164, 255),
	Color3.fromRGB(156, 100, 255),
}

type Level = {
	title: string,
	color: Color3,
	-- 1..3: ile konfetti, jak duży baner, ile gwiazdek.
	intensity: number,
}

local layer: Frame? = nil
local banner: Frame? = nil
local generation = 0
local spinConnection: RBXScriptConnection? = nil

local lastCoins: number? = nil
local lastRodCount: number? = nil

-- ---------------------------------------------------------------------------
-- Klocki
-- ---------------------------------------------------------------------------

--[[ Złoty, przesuwający się gradient na tekście — „mieniący się" napis. ]]
local function shimmer(label: TextLabel, color: Color3)
	local gradient = Theme.create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color),
			ColorSequenceKeypoint.new(0.45, color:Lerp(Color3.new(1, 1, 1), 0.75)),
			ColorSequenceKeypoint.new(0.55, color:Lerp(Color3.new(1, 1, 1), 0.75)),
			ColorSequenceKeypoint.new(1, color),
		}),
		Offset = Vector2.new(-1, 0),
		Parent = label,
	}) :: UIGradient

	TweenService:Create(
		gradient,
		TweenInfo.new(0.9, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{ Offset = Vector2.new(1, 0) }
	):Play()
end

--[[
	Obracające się promienie za banerem — klasyczne „słoneczko" z automatów.
	Zwykłe ramki z gradientem przezroczystości, obracane przez `Rotation`
	kontenera. Bez obrazka.
]]
local function rays(parent: Instance, color: Color3, size: number): Frame
	local holder = Theme.create("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = parent,
	}) :: Frame

	for index = 1, RAYS do
		Theme.create(
			"Frame",
			{
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(0, 26, 1, 0),
				Rotation = (index - 1) * (180 / RAYS),
				BackgroundColor3 = if index % 2 == 0 then color else Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				ZIndex = 1,
				Parent = holder,
			},
			Theme.create("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0.35),
					NumberSequenceKeypoint.new(1, 1),
				}),
			})
		)
	end

	return holder
end

local function star(parent: Instance, color: Color3)
	local size = math.random(22, 40)
	local label = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(size, size),
		Font = Theme.FONT_BLACK,
		TextSize = size,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 6,
		Text = "★",
		Parent = parent,
	})
	Theme.outline(label, Theme.COLOR.stroke, 2)

	local angle = math.random() * math.pi * 2
	local reach = 0.35 + math.random() * 0.25
	TweenService:Create(
		label,
		TweenInfo.new(0.7 + math.random() * 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{
			Position = UDim2.fromScale(
				0.5 + math.cos(angle) * reach,
				0.45 + math.sin(angle) * reach * 0.8
			),
			Rotation = math.random(-180, 180),
		}
	):Play()

	task.delay(1.2, function()
		TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end
		task.delay(0.45, function()
			label:Destroy()
		end)
	end)
end

--[[ Deszcz konfetti przez cały ekran. Nie łapie kliknięć. ]]
local function confettiRain(count: number)
	local parent = layer
	if not parent then
		return
	end

	for _ = 1, count do
		local piece = Theme.create("Frame", {
			Name = "Confetti",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(math.random(), -0.05),
			Size = UDim2.fromOffset(math.random(8, 14), math.random(14, 22)),
			Rotation = math.random(0, 360),
			BackgroundColor3 = RAINBOW[math.random(1, #RAINBOW)],
			BorderSizePixel = 0,
			Active = false,
			ZIndex = 20,
			Parent = parent,
		}, Theme.corner(3)) :: Frame

		local fall = 1.6 + math.random() * 0.9
		local drift = (math.random() - 0.5) * 0.25
		TweenService
			:Create(piece, TweenInfo.new(fall, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				Position = UDim2.fromScale(piece.Position.X.Scale + drift, 1.08),
				Rotation = piece.Rotation + math.random(-540, 540),
			})
			:Play()

		task.delay(fall + 0.05, function()
			piece:Destroy()
		end)
	end
end

--[[
	Licznik „bębnowy": liczba kręci się od zera do celu, coraz wolniej,
	i podskakuje przy każdym przeskoku. Kończy mocnym „bum".
]]
local function rollNumber(label: TextLabel, target: number, prefix: string, myGeneration: number)
	local startedAt = os.clock()
	local lastShown = -1

	local roll: RBXScriptConnection? = nil
	roll = RunService.RenderStepped:Connect(function()
		if generation ~= myGeneration or not label.Parent then
			if roll then
				roll:Disconnect()
			end
			return
		end

		local t = math.clamp((os.clock() - startedAt) / ROLL_TIME, 0, 1)
		-- Wygaszanie jak bęben automatu: szybko na starcie, wolno przy końcu.
		local eased = 1 - (1 - t) ^ 3
		local shown = math.floor(target * eased + 0.5)

		if shown ~= lastShown then
			lastShown = shown
			label.Text = `{prefix}{Format.coins(shown)}`
			Theme.bump(label, 0.06)
		end

		if t >= 1 then
			if roll then
				roll:Disconnect()
			end
			label.Text = `{prefix}{Format.coins(target)}`
			Theme.bump(label, 0.35)
		end
	end)
end

local function stopSpin()
	if spinConnection then
		spinConnection:Disconnect()
		spinConnection = nil
	end
end

local function dismiss(myGeneration: number)
	task.delay(LIFETIME, function()
		local current = banner
		if generation ~= myGeneration or not current then
			return
		end

		local scale = current:FindFirstChild("PopScale")
		if scale and scale:IsA("UIScale") then
			TweenService:Create(
				scale,
				TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In),
				{ Scale = 0 }
			):Play()
		end

		task.delay(0.27, function()
			if generation == myGeneration and banner == current then
				stopSpin()
				current:Destroy()
				banner = nil
			end
		end)
	end)
end

--[[
	Buduje i pokazuje baner. `fish` opcjonalnie dokłada podgląd ryby
	z prawej, `value` — kręcący się licznik.
]]
local function showBanner(
	level: Level,
	subtitle: string,
	fish: Types.FishDefinition?,
	value: number?,
	chips: { string }
)
	local parent = layer
	if not parent then
		return
	end

	generation += 1
	local myGeneration = generation
	stopSpin()
	if banner then
		banner:Destroy()
		banner = nil
	end

	local size = if Theme.isPhone() then BANNER_PHONE else BANNER
	local boost = 1 + (level.intensity - 1) * 0.08

	local frame = Theme.create("Frame", {
		Name = "Celebration",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Theme.SPACE.sm),
		Size = UDim2.fromOffset(size.X * boost, size.Y * boost),
		BackgroundTransparency = 1,
		Active = false,
		ZIndex = 10,
		Parent = parent,
	}) :: Frame
	banner = frame

	local spinner = rays(frame, level.color, size.X * 1.1)

	local card = Theme.panel({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 30),
		Size = UDim2.new(1, -40, 1, -44),
		BackgroundColor3 = level.color:Lerp(Color3.new(1, 1, 1), 0.82),
		ZIndex = 2,
		Parent = frame,
	})
	Theme.create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.86, 0.86, 0.9)),
		Parent = card,
	})

	local title = Theme.label({
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(1, 0, 0, 56),
		Font = Theme.FONT_BLACK,
		TextSize = if Theme.isPhone() then 36 else 46,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 7,
		Text = level.title,
		Parent = frame,
	})
	Theme.outline(title, Theme.COLOR.stroke, 4)
	shimmer(title, level.color)

	local textWidth = if fish then UDim2.new(1, -120, 0, 0) else UDim2.new(1, -20, 0, 0)

	local sub = Theme.label({
		Name = "Subtitle",
		Position = UDim2.fromOffset(14, 34),
		Size = textWidth + UDim2.fromOffset(0, 26),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.lead,
		TextColor3 = Theme.COLOR.text,
		TextXAlignment = if fish then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
		Text = subtitle,
		Parent = card,
	})
	sub.RichText = true

	if value then
		local amount = Theme.label({
			Name = "Value",
			Position = UDim2.fromOffset(14, 60),
			Size = textWidth + UDim2.fromOffset(0, 40),
			Font = Theme.FONT_BLACK,
			TextSize = Theme.TEXT.hero,
			TextColor3 = Theme.COLOR.coin,
			TextXAlignment = if fish then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
			ZIndex = 3,
			Text = "$ 0",
			Parent = card,
		})
		Theme.outline(amount, Theme.COLOR.stroke, 3)
		rollNumber(amount, value, "$ ", myGeneration)
	end

	if #chips > 0 then
		local row = Theme.create("Frame", {
			Name = "Chips",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 14, 1, -8),
			Size = textWidth + UDim2.fromOffset(0, 24),
			BackgroundTransparency = 1,
			ZIndex = 3,
			Parent = card,
		}, Theme.list(Theme.SPACE.xs, Enum.FillDirection.Horizontal)) :: Frame

		for index, chip in chips do
			local badge =
				Theme.badge(chip, RAINBOW[(index % #RAINBOW) + 1], { LayoutOrder = index })
			badge.ZIndex = 4
			badge.Parent = row
			task.delay(0.25 + index * 0.15, function()
				if badge.Parent then
					Theme.pop(badge, 0.2, 0.4)
				end
			end)
		end
	end

	if fish then
		local preview = FishCard.preview(fish, {
			Name = "Fish",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 4, 0.55, 0),
			Size = UDim2.fromOffset(130, 110),
			ZIndex = 5,
			Parent = card,
		})
		Theme.pop(preview, 0.2, 0.55)
	end

	Theme.pop(frame, 0.2, 0.45)

	for _ = 1, 3 + level.intensity * 3 do
		star(frame, RAINBOW[math.random(1, #RAINBOW)])
	end
	confettiRain(10 + level.intensity * 18)

	-- Promienie kręcą się przez cały czas życia banera.
	spinConnection = RunService.RenderStepped:Connect(function(delta: number)
		spinner.Rotation = (spinner.Rotation + delta * 40) % 360
	end)

	dismiss(myGeneration)
end

-- ---------------------------------------------------------------------------
-- Monety lecące do licznika
-- ---------------------------------------------------------------------------

--[[
	Złote monety wylatują z dołu ekranu i lecą po łuku do ikony monet
	w HUD-zie. Liczba monet rośnie z kwotą, ale z sufitem — 40 ramek
	naraz to już tylko szum.
]]
local function coinShower(amount: number)
	local parent = layer
	local targetIcon = Hud.coinTarget()
	if not parent or not targetIcon then
		return
	end

	local count = math.clamp(math.floor(math.log10(math.max(amount, 1)) * 5), 4, 18)
	-- `Absolute*` są w pikselach ekranu, a `Offset` w pikselach projektu —
	-- korzeń ma UIScale, więc bez dzielenia monety lądowałyby obok licznika.
	local scale = Theme.scale()
	local origin = parent.AbsolutePosition
	local target = (targetIcon.AbsolutePosition + targetIcon.AbsoluteSize / 2 - origin) / scale
	local area = parent.AbsoluteSize / scale
	local startPoint = Vector2.new(area.X * 0.5, area.Y * 0.7)

	for index = 1, count do
		task.delay(index * 0.05, function()
			local coin = Theme.icon("$", Theme.COLOR.coin, 30, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(
					startPoint.X + math.random(-60, 60),
					startPoint.Y + math.random(-30, 30)
				),
				ZIndex = 25,
				Active = false,
				Parent = parent,
			})
			Theme.pop(coin, 0.2, 0.2)

			local from = Vector2.new(coin.Position.X.Offset, coin.Position.Y.Offset)
			local control = Vector2.new(from.X + math.random(-120, 120), from.Y - 160)
			local startedAt = os.clock()
			local duration = 0.55 + math.random() * 0.2

			local fly: RBXScriptConnection? = nil
			fly = RunService.RenderStepped:Connect(function()
				local t = math.clamp((os.clock() - startedAt) / duration, 0, 1)
				-- Krzywa Béziera 2. stopnia: łuk w górę, potem do licznika.
				local a = from:Lerp(control, t)
				local b = control:Lerp(target, t)
				local point = a:Lerp(b, t * t)
				coin.Position = UDim2.fromOffset(point.X, point.Y)

				if t >= 1 then
					if fly then
						fly:Disconnect()
					end
					coin:Destroy()
					Theme.bump(targetIcon, 0.25)
				end
			end)
		end)
	end

	-- „+$ 1 234" unoszące się przy liczniku.
	local plus = Theme.label({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(target.X + 26, target.Y),
		Size = UDim2.fromOffset(200, 34),
		Font = Theme.FONT_BLACK,
		TextSize = Theme.TEXT.title,
		TextColor3 = Theme.COLOR.success,
		ZIndex = 26,
		Text = `+$ {Format.coins(amount)}`,
		Parent = parent,
	})
	Theme.outline(plus, Theme.COLOR.stroke, 2.5)
	Theme.pop(plus, 0.3, 0.4)

	TweenService:Create(
		plus,
		TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.6),
		{ Position = plus.Position - UDim2.fromOffset(0, 30), TextTransparency = 1 }
	):Play()
	task.delay(2.1, function()
		plus:Destroy()
	end)
end

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

function Celebration.mount(parent: Instance)
	layer = Theme.create("Frame", {
		Name = "CelebrationLayer",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		-- Warstwa na cały ekran NIE może łapać kliknięć — zablokowałaby
		-- kamerę i przycisk zarzucania na czas animacji.
		Active = false,
		ZIndex = 50,
		Parent = parent,
	}) :: Frame
end

--[[
	Wybiera poziom nagrody dla złowionej ryby. `nil` = bez fanfar.

	Kolejność ma znaczenie: legenda zawsze wygrywa, a „nowy gatunek" jest
	ważniejszy od „rekordu", bo zdarza się raz na gatunek na całe życie konta.
]]
local function levelFor(definition: Types.FishDefinition, result: Types.CastResult): Level?
	local tier = Fish.RARITY_TIER[definition.rarity]

	if definition.rarity == "Legendary" then
		return { title = "LEGENDA!!!", color = Theme.COLOR.coin, intensity = 3 }
	end
	if result.newSpecies then
		return {
			title = "NOWA RYBKA!",
			color = Theme.COLOR.pink,
			intensity = if tier >= 2 then 3 else 2,
		}
	end
	if result.record then
		return { title = "NOWY REKORD!", color = Theme.COLOR.warning, intensity = 2 }
	end
	if definition.rarity == "Epic" then
		return { title = "EPICKA!", color = Theme.COLOR.purple, intensity = 2 }
	end
	if definition.rarity == "Rare" then
		return { title = "RZADKA!", color = Theme.COLOR.accent, intensity = 1 }
	end
	if result.perfect then
		return { title = "PERFEKCYJNIE!", color = Theme.COLOR.success, intensity = 1 }
	end
	return nil
end

--[[ Wołane w szczycie wyskoku ryby (patrz `Effects/CatchShowcase`). ]]
function Celebration.catch(result: Types.CastResult)
	local caught = result.fish
	if result.outcome ~= "Caught" or not caught then
		return
	end

	local definition = Fish.find(caught.fishId)
	if not definition then
		return
	end

	local level = levelFor(definition, result)
	if not level then
		return
	end

	local chips = {}
	if result.perfect then
		table.insert(chips, "PERFEKT x1,5")
	end
	if result.record and level.title ~= "NOWY REKORD!" then
		table.insert(chips, "REKORD")
	end
	if result.newSpecies and level.title ~= "NOWA RYBKA!" then
		table.insert(chips, "NOWY GATUNEK")
	end
	table.insert(chips, Fish.RARITY_LABEL[definition.rarity])

	showBanner(
		level,
		`<b>{definition.displayName}</b>  ·  {Format.mass(caught.mass)}`,
		definition,
		caught.price,
		chips
	)
end

--[[
	Reakcja na nowy snapshot profilu: monety lecące do licznika po
	sprzedaży i fanfary za nową wędkę.

	Różnicę liczymy tutaj, a nie na serwerze, bo to czysto wizualna reakcja
	na stan, który i tak przychodzi w snapshocie — dodatkowy Remote
	„sprzedałeś za X" powielałby tę samą informację drugim kanałem.

	Pierwszy snapshot tylko zapamiętujemy: gracz wracający z 50 tysiącami
	nie ma dostać deszczu monet za samo wejście do gry.
]]
function Celebration.onProfile(profile: Types.Profile)
	local rodCount = 0
	for _ in profile.ownedRods do
		rodCount += 1
	end

	local previousCoins = lastCoins
	local previousRods = lastRodCount
	lastCoins = profile.coins
	lastRodCount = rodCount

	if previousCoins == nil or previousRods == nil then
		return
	end

	if profile.coins > previousCoins then
		coinShower(profile.coins - previousCoins)
	end

	if rodCount > previousRods then
		local rod = Rods.find(profile.equippedRod)
		showBanner(
			{ title = "NOWA WĘDKA!", color = Theme.COLOR.success, intensity = 2 },
			if rod then `<b>{rod.displayName}</b>` else "Lepszy sprzęt = rzadsze ryby!",
			nil,
			nil,
			{ "Więcej szczęścia", "Mocniejsza żyłka" }
		)
	end
end

return Celebration
