--!strict
--[[
	CastMeter — pasek minigry na dole ekranu.

	Stany: Zarzucono (czekanie) -> PODETNIJ (okno) -> wynik.

	WAŻNE: pasek jest TYLKO podpowiedzią wizualną. O trafieniu decyduje serwer,
	mierząc czas od swojego `BiteStarted`. Klient startuje animację o jeden
	ping później, więc jego pasek jest minimalnie z tyłu. Nie „naprawiajcie"
	tego wysyłaniem czasu z klienta — to otwiera drzwi do podrabiania trafień.

	Zielona strefa jest po PRAWEJ, bo pasek opada w lewo: pierwsze chwile okna
	to jego prawa część. Narysowanie jej po lewej (gdzie pasek kończy bieg)
	uczyłoby gracza odwrotnego odruchu.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fish = require(Shared.Config.Fish)
local Format = require(Shared.Util.Format)
local GameConfig = require(Shared.Config.Game)
local Types = require(Shared.Types)

local Theme = require(script.Parent.Theme)

local CastMeter = {}

local DESKTOP_SIZE = Vector2.new(420, 118)
local PHONE_SIZE = Vector2.new(320, 104)

local root: Frame? = nil
local accentBar: Frame? = nil
local fill: Frame? = nil
local perfectZone: Frame? = nil
local titleLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil

local biteStartedAt: number? = nil
local biteWindow = 0
local renderConnection: RBXScriptConnection? = nil

-- Rośnie przy każdej zmianie stanu. Opóźnione „schowaj się" porównuje swoją
-- generację z bieżącą i odpuszcza, jeśli w międzyczasie coś się zmieniło.
-- Bez tego timer ze starego wyniku gasiłby świeżo rozpoczęte zarzucenie.
local generation = 0

local function stopRender()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	biteStartedAt = nil
end

local function beginState(accent: Color3): number
	stopRender()
	generation += 1

	if accentBar then
		accentBar.BackgroundColor3 = accent
	end
	if root then
		root.Visible = true
	end

	return generation
end

function CastMeter.mount(parent: Instance)
	local bar = Theme.create("Frame", {
		Name = "Accent",
		Size = UDim2.new(0, 4, 1, -20),
		Position = UDim2.fromOffset(0, 10),
		BackgroundColor3 = Theme.COLOR.accent,
		BorderSizePixel = 0,
	}, Theme.corner(Theme.RADIUS.sm)) :: Frame

	local title = Theme.label({
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = 1,
		Font = Theme.FONT_BLACK,
		TextSize = Theme.TEXT.title,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
	})

	local hint = Theme.label({
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 2,
		TextSize = Theme.TEXT.small,
		TextColor3 = Theme.COLOR.textMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
	})

	local meterTrack, meterFill = Theme.progress({
		Name = "Track",
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 3,
	}, Theme.COLOR.accent)

	meterFill.Size = UDim2.fromScale(1, 1)

	local zone = Theme.create("Frame", {
		Name = "PerfectZone",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(GameConfig.PERFECT_REEL_FRACTION, 1),
		BackgroundColor3 = Theme.COLOR.success,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = meterTrack,
	}, Theme.corner(Theme.RADIUS.sm), Theme.stroke(Theme.COLOR.success, 1)) :: Frame

	accentBar = bar
	titleLabel = title
	hintLabel = hint
	fill = meterFill
	perfectZone = zone

	local content = Theme.create("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
	}, Theme.list(Theme.SPACE.xs), title, hint, meterTrack) :: Frame

	root = Theme.panel({
		Name = "CastMeter",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -120),
		Size = UDim2.fromOffset(DESKTOP_SIZE.X, DESKTOP_SIZE.Y),
		BackgroundTransparency = 0.06,
		Visible = false,
		Parent = parent,
	}, Theme.padding(Theme.SPACE.md), bar, content)

	Theme.onLayout(function(device: Theme.Device)
		local panel = root
		if not panel then
			return
		end

		-- Na telefonie pasek idzie wyżej: dolny pas ekranu zajmują przyciski
		-- dotykowe i wirtualny drążek Robloxa.
		if device == "Phone" then
			panel.Size = UDim2.fromOffset(PHONE_SIZE.X, PHONE_SIZE.Y)
			panel.Position = UDim2.new(0.5, 0, 1, -190)
		else
			panel.Size = UDim2.fromOffset(DESKTOP_SIZE.X, DESKTOP_SIZE.Y)
			panel.Position = UDim2.new(0.5, 0, 1, -120)
		end
	end)
end

--[[ Zarzucenie przyjęte — czekamy na branie. ]]
function CastMeter.showWaiting()
	beginState(Theme.COLOR.water)

	if titleLabel then
		titleLabel.Text = "Zarzucono"
		titleLabel.TextColor3 = Theme.COLOR.textMuted
	end
	if hintLabel then
		hintLabel.Text = "Czekaj na branie. Nie podcinaj za wcześnie."
	end
	if fill then
		fill.Size = UDim2.fromScale(0, 1)
	end
	if perfectZone then
		perfectZone.Visible = false
	end
end

--[[ Ryba bierze. `window` to okno w sekundach podane przez serwer. ]]
function CastMeter.showBite(window: number)
	beginState(Theme.COLOR.warning)

	biteWindow = math.max(window, 0.05)
	biteStartedAt = os.clock()

	if titleLabel then
		titleLabel.Text = "PODETNIJ!"
		titleLabel.TextColor3 = Theme.COLOR.warning
	end
	if hintLabel then
		hintLabel.Text = `Zielona strefa = bonus x{GameConfig.PERFECT_PRICE_BONUS} do ceny`
	end
	if perfectZone then
		perfectZone.Visible = true
	end

	local bar = fill
	renderConnection = RunService.RenderStepped:Connect(function()
		local startedAt = biteStartedAt
		if not startedAt or not bar then
			stopRender()
			return
		end

		local remaining = math.clamp(1 - (os.clock() - startedAt) / biteWindow, 0, 1)
		bar.Size = UDim2.fromScale(remaining, 1)
		-- Z zielonego w czerwony wraz z uciekającym czasem: kolor niesie
		-- tę samą informację co długość, tylko czyta się ją szybciej.
		bar.BackgroundColor3 = Theme.COLOR.danger:Lerp(Theme.COLOR.success, remaining)

		if remaining <= 0 then
			stopRender()
		end
	end)
end

local function describeCatch(caught: Types.CaughtFish, perfect: boolean): (string, string, Color3)
	local definition = Fish.find(caught.fishId)
	if not definition then
		return caught.fishId, Format.coins(caught.price) .. " monet", Theme.COLOR.text
	end

	local accent = Fish.RARITY_COLOR[definition.rarity]
	local rarity = Fish.RARITY_LABEL[definition.rarity]
	local bonus = if perfect then "  ·  <b>PERFEKCYJNE</b>" else ""

	return definition.displayName,
		`{rarity}  ·  {Format.mass(caught.mass)}  ·  {Format.coins(caught.price)} monet{bonus}`,
		accent
end

--[[ Wynik zarzucenia. Pasek chowa się sam po chwili. ]]
function CastMeter.showResult(result: Types.CastResult)
	local title = titleLabel
	local hint = hintLabel
	if not (title and hint) then
		return
	end

	local accent = Theme.COLOR.danger

	if result.outcome == "Caught" and result.fish then
		local name, details, color = describeCatch(result.fish, result.perfect)
		accent = color
		title.Text = name
		title.TextColor3 = color
		hint.Text = details
	elseif result.outcome == "Escaped" then
		title.Text = "Ryba uciekła"
		title.TextColor3 = Theme.COLOR.danger
		hint.Text = "Za późno — podcinaj, gdy pasek jeszcze leci."
	elseif result.outcome == "TooEarly" then
		title.Text = "Za wcześnie"
		title.TextColor3 = Theme.COLOR.danger
		hint.Text =
			`Spławik nawet nie drgnął. Blokada {Format.seconds(GameConfig.TOO_EARLY_PENALTY)}.`
	else
		accent = Theme.COLOR.warning
		title.Text = "Torba pełna"
		title.TextColor3 = Theme.COLOR.warning
		hint.Text = "Sprzedaj połów w skupie ryb."
	end

	local shownGeneration = beginState(accent)

	if fill then
		fill.Size = UDim2.fromScale(0, 1)
	end
	if perfectZone then
		perfectZone.Visible = false
	end

	-- Delikatne „wyskoczenie" karty. Ruch przyciąga wzrok skuteczniej niż
	-- kolor, a wynik zarzucenia to moment, w którym gracz ma spojrzeć w dół.
	local panel = root
	if panel then
		local resting = panel.Position
		panel.Position = resting + UDim2.fromOffset(0, 10)
		TweenService:Create(
			panel,
			TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = resting }
		):Play()
	end

	task.delay(2.4, function()
		if generation == shownGeneration and root then
			root.Visible = false
		end
	end)
end

function CastMeter.hide()
	beginState(Theme.COLOR.accent)
	if root then
		root.Visible = false
	end
end

return CastMeter
