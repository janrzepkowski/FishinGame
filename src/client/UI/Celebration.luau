--!strict
--[[
	Celebration — „jackpot" na ekranie: baner, promienie, konfetti i monety
	lecące do licznika.

	Trzy okazje:
	  * RZADKA RYBA, REKORD albo NOWY GATUNEK — baner z promieniami u góry
	    ekranu, błysk i konfetti. Rekord dostaje migające „żarówki" jak
	    na automacie i wagę doliczaną od zera.
	  * SPRZEDAŻ — monety wysypują się na środku i lecą do licznika w HUD-zie,
	    a nad nimi wyskakuje „+kwota".

	TO NIE JEST HAZARD. Nie ma tu losowania, zakładu ani niczego do kupienia:
	świętujemy to, co gracz JUŻ złowił albo sprzedał. Bierzemy z automatów
	wyłącznie język nagrody (światła, licznik, deszcz monet) — gra jest
	dla dzieci.

	Pospolita płoć NIE dostaje banera. Gdyby każda ryba wywoływała fajerwerki,
	legendarna niczym by się nie wyróżniała.

	Baner siedzi u góry ekranu i znika sam po dwóch sekundach: środek zostaje
	dla wody i spławika (zasada 8 z CLAUDE.md).
]]

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Fish = require(Shared.Config.Fish)
local Format = require(Shared.Util.Format)
local Types = require(Shared.Types)

local Theme = require(script.Parent.Theme)

local Celebration = {}

local BANNER_TIME = 2.4
local CONFETTI_COLORS = {
	Theme.COLOR.coin,
	Theme.COLOR.success,
	Theme.COLOR.accent,
	Theme.COLOR.pink,
	Theme.COLOR.purple,
	Theme.COLOR.white,
}
-- Najwięcej monet naraz. Więcej niczego nie dodaje, a każda to kilka
-- instancji i dwa tweeny.
local MAX_COINS = 18

local generator = Random.new()

local layer: Frame? = nil
local banner: Frame? = nil

local function tween(target: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local created = TweenService:Create(target, info, goal)
	created:Play()
	return created
end

--[[ Skala korzenia UI. Pozycje ekranowe (`AbsolutePosition`) są w pikselach,
     a nasze offsety w jednostkach PRZED skalowaniem — bez tej poprawki monety
     leciałyby obok licznika na każdym ekranie innym niż projektowy. ]]
local function rootScale(): number
	local frame = layer
	local parent = frame and frame.Parent
	local scale = parent and parent:FindFirstChildOfClass("UIScale")
	return if scale then math.max(scale.Scale, 0.01) else 1
end

--[[ Punkt ekranu przeliczony na offset wewnątrz warstwy. ]]
local function toLocal(frame: Frame, absolute: Vector2): Vector2
	return (absolute - frame.AbsolutePosition) / rootScale()
end

function Celebration.mount(parent: Instance)
	layer = Theme.create("Frame", {
		Name = "Celebration",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		-- Warstwa leży na wierzchu, ale nie może zjadać kliknięć.
		Active = false,
		ZIndex = 50,
		Parent = parent,
	}) :: Frame
end

-- ---------------------------------------------------------------------------
-- Cegiełki
-- ---------------------------------------------------------------------------

--[[ Błysk całego ekranu w kolorze nagrody. ]]
local function flash(frame: Frame, color: Color3)
	local sheet = Theme.create("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Active = false,
		Parent = frame,
	})
	tween(sheet, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}).Completed:Once(function()
		sheet:Destroy()
	end)
end

--[[ Konfetti: kolorowe prostokąciki spadające z góry z obrotem. ]]
local function confetti(frame: Frame, count: number)
	for _ = 1, count do
		local size = generator:NextNumber(8, 15)
		local startX = generator:NextNumber(0.05, 0.95)
		local life = generator:NextNumber(1.3, 2.3)

		local piece = Theme.create("Frame", {
			Name = "Confetti",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(startX, 0, 0, -20),
			Size = UDim2.fromOffset(size, size * generator:NextNumber(0.45, 1)),
			Rotation = generator:NextNumber(0, 360),
			BackgroundColor3 = CONFETTI_COLORS[generator:NextInteger(1, #CONFETTI_COLORS)],
			BorderSizePixel = 0,
			Active = false,
			Parent = frame,
		}, Theme.corner(3))

		tween(piece, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(
				startX + generator:NextNumber(-0.08, 0.08),
				0,
				generator:NextNumber(0.55, 0.95),
				0
			),
			Rotation = generator:NextNumber(-720, 720),
		})
		task.delay(life * 0.7, function()
			tween(piece, TweenInfo.new(life * 0.3), { BackgroundTransparency = 1 })
		end)
		task.delay(life, function()
			piece:Destroy()
		end)
	end
end

--[[ Pigułka banera: kolorowe tło, kontur, biały napis z obrysem. ]]
local function ribbon(text: string, color: Color3, height: number, textSize: number): Frame
	local label = Theme.label({
		Name = "Text",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.FONT_DISPLAY,
		TextSize = textSize,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 3,
		Text = text,
	})
	Theme.outline(label, Theme.COLOR.outline, 3)

	return Theme.create(
		"Frame",
		{
			Name = "Ribbon",
			Size = UDim2.fromOffset(0, height),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		},
		Theme.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Theme.stroke(Theme.COLOR.outline, Theme.OUTLINE + 1),
		Theme.candyGradient(0.18),
		Theme.padding(0, height * 0.55),
		label
	) :: Frame
end

--[[
	Rząd „żarówek" pod banerem rekordu, migających na zmianę — światła
	automatu, które mówią „wygrałeś" szybciej niż napis.
]]
local function marquee(parent: Instance, order: number)
	local row = Theme.create(
		"Frame",
		{
			Name = "Marquee",
			Size = UDim2.fromOffset(0, 14),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = order,
			BackgroundTransparency = 1,
			Parent = parent,
		},
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			VerticalAlignment = Enum.VerticalAlignment.Center,
		})
	)

	for index = 1, 11 do
		local bulb = Theme.create(
			"Frame",
			{
				Size = UDim2.fromOffset(12, 12),
				BackgroundColor3 = if index % 2 == 0 then Theme.COLOR.coin else Theme.COLOR.white,
				BorderSizePixel = 0,
				Parent = row,
			},
			Theme.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			Theme.stroke(Theme.COLOR.outline, 2)
		)

		-- Co druga żarówka startuje w przeciwnej fazie: światło „biegnie".
		task.delay(if index % 2 == 0 then 0 else 0.16, function()
			if bulb.Parent then
				tween(
					bulb,
					TweenInfo.new(
						0.16,
						Enum.EasingStyle.Linear,
						Enum.EasingDirection.InOut,
						-1,
						true
					),
					{ BackgroundColor3 = Theme.COLOR.pink }
				)
			end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Połów
-- ---------------------------------------------------------------------------

--[[
	Świętuje połów. Nic nie robi dla zwykłej, pospolitej ryby.
	Zwraca, czy baner został pokazany.

	`newSpecies` — pierwsza w życiu sztuka tego gatunku (nowy wpis
	w bestiariuszu).
]]
function Celebration.catch(
	caught: Types.CaughtFish,
	perfect: boolean,
	record: boolean,
	newSpecies: boolean
): boolean
	local frame = layer
	local definition = Fish.find(caught.fishId)
	if not frame or not definition then
		return false
	end

	local tier = Fish.RARITY_TIER[definition.rarity]
	local accent = Fish.RARITY_COLOR[definition.rarity]
	local rare = tier >= 2

	if not (rare or record or newSpecies) then
		return false
	end

	-- Jeden baner naraz: szybkie połowy nie układają się w stos.
	if banner then
		banner:Destroy()
		banner = nil
	end

	flash(frame, if record then Theme.COLOR.coin else accent)
	confetti(frame, 16 + tier * 10 + (if record then 24 else 0))

	local stack = Theme.create(
		"Frame",
		{
			Name = "Stack",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex = 2,
		},
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		})
	) :: Frame

	-- Najważniejsza wiadomość na górze, największa.
	local headline: string
	local headlineColor: Color3
	if record then
		headline, headlineColor = "NOWY REKORD!", Theme.COLOR.coin
	elseif newSpecies then
		headline, headlineColor = "NOWY GATUNEK!", Theme.COLOR.pink
	else
		headline, headlineColor = `{string.upper(Fish.RARITY_LABEL[definition.rarity])}!`, accent
	end

	local top = ribbon(headline, headlineColor, 44, Theme.TEXT.title + 4)
	top.LayoutOrder = 1
	top.Parent = stack

	if record then
		marquee(stack, 2)
	end

	local detail = ribbon(
		`{definition.displayName}  ·  {Format.mass(0)}`,
		if record or newSpecies then accent else Theme.COLOR.panel,
		30,
		Theme.TEXT.body
	)
	detail.LayoutOrder = 3
	detail.Parent = stack

	if perfect then
		local bonus = ribbon("PERFEKCYJNE PODCIĘCIE!", Theme.COLOR.success, 24, Theme.TEXT.small)
		bonus.LayoutOrder = 4
		bonus.Parent = stack
	end

	local holder = Theme.create(
		"Frame",
		{
			Name = "Banner",
			AnchorPoint = Vector2.new(0.5, 0),
			-- Przy samej górnej krawędzi: ryba wisi w środku ekranu i baner
			-- nie może na nią nachodzić.
			Position = UDim2.new(0.5, 0, 0, 8),
			Size = UDim2.fromOffset(520, 130),
			BackgroundTransparency = 1,
			Active = false,
			Parent = frame,
		},
		Theme.sunburst({
			Position = UDim2.new(0.5, 0, 0, 24),
			Size = UDim2.fromOffset(250, 250),
			ZIndex = 1,
		}, headlineColor:Lerp(Color3.new(1, 1, 1), 0.35), 14),
		stack
	) :: Frame
	banner = holder

	-- Baner „wbija się" na ekran z przestrzeleniem i lekkim przechyłem.
	local scale = Theme.create("UIScale", { Scale = 0.2, Parent = holder }) :: UIScale
	holder.Rotation = -8
	tween(
		scale,
		TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	tween(holder, TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
		Rotation = 0,
	})

	-- Nagłówek pulsuje przez cały pokaz.
	local pulse = Theme.create("UIScale", { Parent = top }) :: UIScale
	tween(
		pulse,
		TweenInfo.new(0.34, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = 1.08 }
	)

	-- Waga dolicza się od zera jak licznik na automacie.
	local detailLabel = detail:FindFirstChild("Text")
	local counted = Instance.new("NumberValue")
	counted.Changed:Connect(function(value)
		if detailLabel and detailLabel:IsA("TextLabel") then
			detailLabel.Text = `{definition.displayName}  ·  {Format.mass(value)}`
		end
	end)
	tween(counted, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Value = caught.mass,
	}).Completed:Once(function()
		if detailLabel and detailLabel:IsA("TextLabel") then
			detailLabel.Text = `{definition.displayName}  ·  {Format.mass(caught.mass)}`
		end
		counted:Destroy()
	end)

	-- Rekord i legenda wiszą dłużej.
	local life = BANNER_TIME + (if record then 0.8 else 0) + (if tier >= 4 then 0.6 else 0)
	task.delay(life, function()
		if not holder.Parent then
			return
		end
		tween(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Scale = 0,
		}).Completed:Once(function()
			if banner == holder then
				banner = nil
			end
			holder:Destroy()
		end)
	end)

	return true
end

-- ---------------------------------------------------------------------------
-- Monety
-- ---------------------------------------------------------------------------

--[[
	Deszcz monet po sprzedaży: monety wysypują się na środku ekranu i lecą
	do `target` (ikona monet w HUD-zie). Nad nimi wyskakuje „+kwota".

	Każda moneta, która doleci, szturcha licznik — przy dużej sprzedaży
	pigułka monet dosłownie podskakuje od wpadających pieniędzy.
]]
function Celebration.coins(amount: number, target: GuiObject?)
	local frame = layer
	if not frame or amount <= 0 then
		return
	end

	local origin = Vector2.new(frame.AbsoluteSize.X * 0.5, frame.AbsoluteSize.Y * 0.56)
		/ rootScale()
	local destination = if target
		then toLocal(frame, target.AbsolutePosition + target.AbsoluteSize / 2)
		else Vector2.new(40, 40)

	-- Liczba monet rośnie z kwotą, ale logarytmicznie: 100 i 10 000 mają
	-- wyglądać różnie, a nie różnić się stukrotnie liczbą instancji.
	local count = math.clamp(math.floor(4 + math.log10(amount + 1) * 3.5), 5, MAX_COINS)

	for index = 1, count do
		local coin = Theme.icon("$", Theme.COLOR.coin, 30, {
			Name = "Coin",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(origin.X, origin.Y),
			ZIndex = 4,
			Parent = frame,
		})

		-- Najpierw rozprysk na boki, potem lot do licznika.
		local angle = generator:NextNumber(0, math.pi * 2)
		local spread = generator:NextNumber(50, 150)
		local burst = origin + Vector2.new(math.cos(angle), math.sin(angle) * 0.7) * spread
		local delay = (index - 1) * 0.035

		task.delay(delay, function()
			tween(coin, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(burst.X, burst.Y),
			})
		end)
		task.delay(delay + 0.36, function()
			tween(coin, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(destination.X, destination.Y),
				Size = UDim2.fromOffset(18, 18),
			}).Completed:Once(function()
				coin:Destroy()
				if target and target.Parent then
					Theme.bump(target, 0.3)
				end
			end)
		end)
	end

	-- „+kwota" wyskakuje, wisi chwilę i odpływa w górę.
	local gain = ribbon(`+{Format.coins(amount)}`, Theme.COLOR.coin, 48, Theme.TEXT.hero)
	gain.AnchorPoint = Vector2.new(0.5, 0.5)
	gain.Position = UDim2.fromOffset(origin.X, origin.Y - 70)
	gain.ZIndex = 5
	gain.Parent = frame
	Theme.pop(gain, 0.2, 0.4)

	task.delay(1.1, function()
		tween(gain, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromOffset(origin.X, origin.Y - 150),
		})
		local scale = gain:FindFirstChild("PopScale")
		if scale then
			tween(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
				Scale = 0,
			})
		end
		task.delay(0.5, function()
			gain:Destroy()
		end)
	end)

	if amount >= 500 then
		confetti(frame, 22)
	end
end

return Celebration
