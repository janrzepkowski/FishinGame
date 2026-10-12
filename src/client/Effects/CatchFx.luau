--!strict
--[[
	CatchFx — ryba naprawdę wyskakuje z wody, a połów jest świętem.

	Po wyholowaniu model złowionego gatunku (`FishModel`) wylatuje łukiem
	ze spławika, zawisa przed graczem, żeby dało się go obejrzeć, i wpada
	do torby. Nad rybą wisi tabliczka z nazwą, wagą i ceną, która dolicza
	się od zera.

	IM RZADSZA RYBA, TYM WIĘKSZE ŚWIĘTO: więcej iskier, konfetti, poświata,
	dłuższe zawiśnięcie i lekkie „uderzenie" kamery. Rekord wagi i perfekcyjne
	podcięcie dokładają własne napisy. Pospolita płoć dostaje skromny plusk —
	gdyby każda ryba wybuchała fajerwerkami, legendarna niczym by się nie
	wyróżniała.

	To nagroda za to, co gracz JUŻ złowił. Nie ma tu losowania, zakładów
	ani niczego do kupienia — gra jest dla dzieci.

	Efekt jest lokalny: widzi go tylko gracz, który złowił rybę.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Fish = require(Shared.Config.Fish)
local FishModel = require(Shared.Util.FishModel)
local Format = require(Shared.Util.Format)
local Types = require(Shared.Types)

local Theme = require(script.Parent.Parent.UI.Theme)

local CatchFx = {}

local CONTAINER_NAME = "CatchFx"

-- Lot ze spławika do gracza.
local FLIGHT_TIME = 0.8
-- Zawiśnięcie przed graczem: podstawa plus dodatek za każdy poziom rzadkości.
local SHOW_TIME = 1.5
local SHOW_TIME_PER_TIER = 0.35
-- Wpadnięcie do torby.
local STOW_TIME = 0.3

local CONFETTI = {
	Color3.fromRGB(255, 206, 48),
	Color3.fromRGB(96, 222, 74),
	Color3.fromRGB(64, 208, 255),
	Color3.fromRGB(255, 104, 182),
	Color3.fromRGB(170, 104, 255),
}

local player = Players.LocalPlayer
local container: Folder? = nil
local playing: Model? = nil

local function getContainer(): Folder
	local existing = container
	if existing and existing.Parent then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = CONTAINER_NAME
	folder.Parent = Workspace
	container = folder
	return folder
end

--[[ Niewidzialna część niosąca emitery cząstek; sama się sprząta. ]]
local function burstAnchor(position: Vector3, life: number): BasePart
	local part = Instance.new("Part")
	part.Name = "Burst"
	part.Size = Vector3.new(0.4, 0.4, 0.4)
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Parent = getContainer()

	task.delay(life, function()
		part:Destroy()
	end)
	return part
end

--[[ Iskry w kolorze rzadkości: rozchodzą się kuliście i gasną. ]]
local function sparkle(position: Vector3, color: Color3, count: number)
	local anchor = burstAnchor(position, 2)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.Speed = NumberRange.new(8, 18)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 4
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 0.9
	emitter.Parent = anchor
	emitter:Emit(count)
end

--[[ Konfetti: kolorowe płatki wyrzucone w górę, opadające z obrotem. ]]
local function confetti(position: Vector3, count: number)
	local anchor = burstAnchor(position, 3.5)

	for _, color in CONFETTI do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 0
		emitter.Lifetime = NumberRange.new(1.6, 2.6)
		emitter.Speed = NumberRange.new(14, 26)
		emitter.SpreadAngle = Vector2.new(55, 55)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Acceleration = Vector3.new(0, -34, 0)
		emitter.Drag = 1.5
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-260, 260)
		emitter.Size = NumberSequence.new(0.32)
		-- Spłaszczenie robi z okrągłej cząstki płatek.
		emitter.Squash = NumberSequence.new(-1.2)
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.8, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Color = ColorSequence.new(color)
		emitter.LightEmission = 0.3
		emitter.Parent = anchor
		emitter:Emit(math.ceil(count / #CONFETTI))
	end
end

--[[ Krótkie „uderzenie" kamery: pole widzenia rozszerza się i wraca. ]]
local function punchCamera(strength: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local base = camera.FieldOfView
	camera.FieldOfView = base + strength
	TweenService:Create(
		camera,
		TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = base }
	):Play()
end

--[[
	Tabliczka nad rybą: nazwa, rzadkość z wagą i cena doliczana od zera.

	Rodzicem jest sama ryba (część w świecie), nie PlayerGui — tabliczka
	żyje dokładnie tak długo jak model i znika razem z nim.
]]
local function buildLabel(
	adornee: BasePart,
	definition: Types.FishDefinition,
	caught: Types.CaughtFish,
	perfect: boolean,
	record: boolean,
	compact: boolean
)
	local accent = Fish.RARITY_COLOR[definition.rarity]

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CatchLabel"
	billboard.Adornee = adornee
	billboard.LightInfluence = 0
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	billboard.Size = UDim2.fromOffset(300, 130)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)

	local banner = ""
	if record and perfect then
		banner = "NOWY REKORD!  ·  PERFEKCYJNE!"
	elseif record then
		banner = "NOWY REKORD!"
	elseif perfect then
		banner = "PERFEKCYJNE!"
	end

	local bannerLabel = Theme.label({
		Name = "Banner",
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 1,
		Font = Theme.FONT_DISPLAY,
		TextSize = Theme.TEXT.body,
		TextColor3 = Theme.COLOR.coin,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = banner,
		Visible = banner ~= "",
	})
	Theme.outline(bannerLabel, Theme.COLOR.outline, 2)

	local nameLabel = Theme.label({
		Name = "Name",
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = 2,
		Font = Theme.FONT_DISPLAY,
		TextSize = Theme.TEXT.title + 4,
		TextColor3 = accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = definition.displayName,
	})
	Theme.outline(nameLabel, Theme.COLOR.outline, 3)

	local detailLabel = Theme.label({
		Name = "Detail",
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 3,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.small,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = `{Fish.RARITY_LABEL[definition.rarity]}  ·  {Format.mass(caught.mass)}`,
	})
	Theme.outline(detailLabel, Theme.COLOR.outline, 2)

	local priceLabel = Theme.label({
		Name = "Price",
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 4,
		Font = Theme.FONT_DISPLAY,
		TextSize = Theme.TEXT.title,
		TextColor3 = Theme.COLOR.coin,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "+0",
	})
	Theme.outline(priceLabel, Theme.COLOR.outline, 2.5)

	if compact then
		-- Nazwę, rzadkość i rekord pokazuje już baner u góry ekranu
		-- (`UI/Celebration`). Dwa napisy o tym samym nachodziły na siebie
		-- i na rybę, więc tutaj zostaje sama cena — POD rybą, z dala od banera.
		bannerLabel.Visible = false
		nameLabel.Visible = false
		detailLabel.Visible = false
		billboard.Size = UDim2.fromOffset(220, 40)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, -2.4, 0)
	end

	local stack = Theme.create("Frame", {
		Name = "Stack",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, Theme.list(2), bannerLabel, nameLabel, detailLabel, priceLabel) :: Frame

	-- Tabliczka „wyskakuje", a nie po prostu się pojawia.
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = stack
	TweenService:Create(
		scale,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()

	if banner ~= "" and not compact then
		-- Pulsujący napis: jedyny element, który rusza się przez cały pokaz.
		local pulse = Instance.new("UIScale")
		pulse.Parent = bannerLabel
		TweenService:Create(
			pulse,
			TweenInfo.new(0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = 1.14 }
		):Play()
	end

	stack.Parent = billboard
	billboard.Parent = adornee

	-- Cena dolicza się od zera — licznik, który rośnie, cieszy bardziej niż
	-- gotowa liczba.
	local counted = Instance.new("NumberValue")
	counted.Value = 0
	counted.Changed:Connect(function(value)
		priceLabel.Text = `+{Format.coins(value)}`
	end)
	local tween = TweenService:Create(
		counted,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = caught.price }
	)
	tween.Completed:Once(function()
		priceLabel.Text = `+{Format.coins(caught.price)}`
		counted:Destroy()
	end)
	tween:Play()
end

--[[
	Odgrywa wyskok i pokaz złowionej ryby.

	`from` to miejsce, z którego ryba wylatuje (pozycja spławika). Gdy go
	nie ma, startujemy z punktu przed graczem na poziomie wody.

	`celebrated` — połów dostał baner na ekranie; tabliczka nad rybą
	skraca się wtedy do samej ceny, żeby napisy się nie dublowały.
]]
function CatchFx.play(
	caught: Types.CaughtFish,
	perfect: boolean,
	record: boolean,
	from: Vector3?,
	celebrated: boolean?
)
	local definition = Fish.find(caught.fishId)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not definition or not root or not root:IsA("BasePart") then
		return
	end

	-- Jedna ryba naraz: szybkie zarzucenia nie zostawiają ryb w powietrzu.
	if playing then
		playing:Destroy()
		playing = nil
	end

	local tier = Fish.RARITY_TIER[definition.rarity]
	local accent = Fish.RARITY_COLOR[definition.rarity]

	-- Okaz jest wyraźnie większy od drobnej sztuki tego samego gatunku.
	local span = math.max(definition.maxMass - definition.minMass, 0.001)
	local fraction = math.clamp((caught.mass - definition.minMass) / span, 0, 1)
	local model = FishModel.build(caught.fishId, 0.85 + 0.75 * fraction)
	local body = model.PrimaryPart
	if not body then
		model:Destroy()
		return
	end

	model.Parent = getContainer()
	playing = model

	local start = from or (root.CFrame * CFrame.new(0, -3, -12)).Position
	local arc = 6 + tier * 1.2
	local showTime = SHOW_TIME + tier * SHOW_TIME_PER_TIER
	local special = record or tier >= 2

	if special then
		local highlight = Instance.new("Highlight")
		highlight.FillColor = accent
		highlight.FillTransparency = 0.72
		highlight.OutlineColor = Color3.new(1, 1, 1)
		highlight.OutlineTransparency = 0.15
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = model
	end

	sparkle(start, accent, 10 + tier * 8)

	local startedAt = os.clock()
	local arrived = false
	local connection: RBXScriptConnection

	connection = RunService.RenderStepped:Connect(function()
		if not model.Parent then
			connection:Disconnect()
			return
		end

		-- Cel liczymy co klatkę: gracz może się obrócić albo odejść,
		-- a ryba ma zawisnąć przed nim, nie tam, gdzie stał sekundę temu.
		-- Przy banerze ryba wisi niżej: góra ekranu należy wtedy do napisu.
		local hover = (root.CFrame * CFrame.new(0.4, if celebrated then 0.4 else 1.6, -5)).Position
		local elapsed = os.clock() - startedAt

		if elapsed < FLIGHT_TIME then
			local t = elapsed / FLIGHT_TIME
			local flat = start:Lerp(hover, t)
			local position = flat + Vector3.new(0, arc * 4 * t * (1 - t), 0)
			-- W locie ryba koziołkuje — wygląda, jakby naprawdę się wyrwała.
			model:PivotTo(CFrame.new(position) * CFrame.Angles(t * math.pi * 4, t * 3, 0))
			return
		end

		if not arrived then
			arrived = true
			buildLabel(body, definition, caught, perfect, record, celebrated == true)
			sparkle(hover, accent, 16 + tier * 14)
			-- Każdy połów dostaje garść konfetti; rzadkość dokłada resztę.
			confetti(hover, 14 + tier * 30 + (if record then 50 else 0))
			if special then
				punchCamera(4 + tier * 1.5)
			end
		end

		local shown = elapsed - FLIGHT_TIME
		if shown < showTime then
			-- Pokaz: ryba kołysze się i obraca powoli, żeby pokazać oba boki.
			local bob = math.sin(shown * 3.2) * 0.25
			local facing =
				CFrame.lookAt(hover, Vector3.new(root.Position.X, hover.Y, root.Position.Z))
			model:PivotTo(
				facing
					* CFrame.new(0, bob, 0)
					* CFrame.Angles(0, math.rad(90) + math.sin(shown * 1.6) * 0.5, 0)
			)
			return
		end

		local stow = (shown - showTime) / STOW_TIME
		if stow >= 1 then
			connection:Disconnect()
			if playing == model then
				playing = nil
			end
			model:Destroy()
			return
		end

		-- Do torby: ryba maleje i wpada graczowi w ręce.
		local target = root.Position + Vector3.new(0, 0.5, 0)
		model:ScaleTo(math.max((0.85 + 0.75 * fraction) * (1 - stow), 0.05))
		model:PivotTo(CFrame.new(hover:Lerp(target, stow * stow)))
	end)
end

return table.freeze(CatchFx)
