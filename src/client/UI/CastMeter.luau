--!strict
--[[
	CastMeter — pasek rozgrywki na dole ekranu.

	Cztery stany, jeden po drugim:

	  Zarzucono  czekanie na branie
	  PODETNIJ   okno na zacięcie (pasek ucieka)
	  HOLUJ      walka: dwa paski idące w przeciwne strony
	  wynik      co się stało

	WAŻNE: paski są TYLKO podpowiedzią wizualną. O wszystkim decyduje serwer.
	Klient dostaje stan walki 20 razy na sekundę i interpoluje między
	próbkami — bez tego paski skakałyby co 50 ms i nie dałoby się na nich
	polegać przy decyzji „puścić czy trzymać".

	Nie próbujcie symulować walki lokalnie dla gładkości. Interpolacja
	w stronę ostatniego znanego stanu jest bezpieczna (najwyżej zostaje
	o pół klatki w tyle), a własna symulacja rozjechałaby się z serwerem
	i pokazywała zerwaną żyłkę tam, gdzie serwer widzi złowioną rybę.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cast = require(Shared.Util.Cast)
local Fish = require(Shared.Config.Fish)
local Format = require(Shared.Util.Format)
local GameConfig = require(Shared.Config.Game)
local Types = require(Shared.Types)

local Theme = require(script.Parent.Theme)

local CastMeter = {}

local DESKTOP_SIZE = Vector2.new(430, 158)
local PHONE_SIZE = Vector2.new(330, 150)

-- Jak szybko paski doganiają stan z serwera. 14/s domyka różnicę
-- w ~0,07 s, czyli szybciej, niż trwa jeden tick serwera.
local LERP_SPEED = 14

local root: Frame? = nil
local accentBar: Frame? = nil
local titleLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil

local progressFill: Frame? = nil
local perfectZone: Frame? = nil
local tensionRow: Frame? = nil
local tensionFill: Frame? = nil
local tensionLabel: TextLabel? = nil

local biteStartedAt: number? = nil
local biteWindow = 0
local renderConnection: RBXScriptConnection? = nil

-- Cele interpolacji dla walki.
local fighting = false
local targetProgress = 0
local targetTension = 0
local shownProgress = 0
local shownTension = 0
local surging = false

-- Rośnie przy każdej zmianie stanu. Opóźnione „schowaj się" porównuje swoją
-- generację z bieżącą i odpuszcza, jeśli w międzyczasie coś się zmieniło.
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
	fighting = false

	if accentBar then
		accentBar.BackgroundColor3 = accent
	end
	if root then
		root.Visible = true
	end

	return generation
end

local function setTensionVisible(visible: boolean)
	if tensionRow then
		tensionRow.Visible = visible
	end
	if perfectZone then
		perfectZone.Visible = not visible and perfectZone.Visible
	end
end

function CastMeter.mount(parent: Instance)
	local bar = Theme.create("Frame", {
		Name = "Accent",
		Size = UDim2.new(0, 8, 1, -16),
		Position = UDim2.fromOffset(0, 8),
		BackgroundColor3 = Theme.COLOR.accent,
		BorderSizePixel = 0,
	}, Theme.corner(Theme.RADIUS.sm), Theme.stroke(Theme.COLOR.outline, 2)) :: Frame

	local title = Theme.label({
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 1,
		Font = Theme.FONT_DISPLAY,
		TextSize = Theme.TEXT.title,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
	})
	Theme.outline(title, Theme.COLOR.outline, 2.5)

	local hint = Theme.label({
		-- Dwie linijki: podpowiedzi po polsku bywają długie, a ucięte
		-- w połowie zdania nie mówią graczowi, co zrobił źle.
		Size = UDim2.new(1, 0, 0, 32),
		LayoutOrder = 2,
		TextSize = Theme.TEXT.small,
		TextColor3 = Theme.COLOR.textMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Text = "",
	})

	local track, fill = Theme.progress({
		Name = "Progress",
		Size = UDim2.new(1, -4, 0, 22),
		LayoutOrder = 3,
	}, Theme.COLOR.accent)

	fill.Size = UDim2.fromScale(1, 1)

	local zone = Theme.create(
		"Frame",
		{
			Name = "PerfectZone",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(GameConfig.PERFECT_REEL_FRACTION, 1),
			BackgroundColor3 = Theme.COLOR.success,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = track,
		},
		Theme.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Theme.stroke(Theme.COLOR.white, 2)
	) :: Frame

	-- Pasek napięcia z podpisem. Podpis jest konieczny: dwa paski jeden pod
	-- drugim bez etykiet to zagadka, a gracz ma na nią pół sekundy.
	local tensionTrack, tensionBar = Theme.progress({
		Name = "TensionTrack",
		Size = UDim2.new(1, -66, 0, 14),
		Position = UDim2.fromOffset(62, 1),
	}, Theme.COLOR.success)

	local tensionCaption = Theme.label({
		Size = UDim2.fromOffset(58, 16),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.small,
		TextColor3 = Theme.COLOR.textMuted,
		Text = "ŻYŁKA",
	})

	local tension = Theme.create("Frame", {
		Name = "Tension",
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 4,
		BackgroundTransparency = 1,
		Visible = false,
	}, tensionCaption, tensionTrack) :: Frame

	accentBar = bar
	titleLabel = title
	hintLabel = hint
	progressFill = fill
	perfectZone = zone
	tensionRow = tension
	tensionFill = tensionBar
	tensionLabel = tensionCaption

	local content = Theme.create("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -18, 1, 0),
		Position = UDim2.fromOffset(18, 0),
		BackgroundTransparency = 1,
	}, Theme.list(Theme.SPACE.sm), title, hint, track, tension) :: Frame

	-- Kotwica w LEWYM DOLNYM rogu. Wcześniej pasek stał na dole wyśrodkowany
	-- i przy łowieniu zasłaniał dokładnie to, na co gracz patrzy — wodę
	-- ze spławikiem. Cały interfejs trzyma się teraz lewej krawędzi,
	-- a środek i prawa strona zostają dla rozgrywki.
	root = Theme.panel({
		Name = "CastMeter",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, Theme.SPACE.lg, 1, -Theme.SPACE.lg),
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

		local size = if device == "Phone" then PHONE_SIZE else DESKTOP_SIZE
		panel.Size = UDim2.fromOffset(size.X, size.Y)
		-- Wysokość bierzemy z `Theme.castBottom`, nie z lokalnej stałej:
		-- komunikaty układają się nad tym paskiem i muszą znać tę samą liczbę.
		panel.Position = UDim2.new(0, Theme.edgeMargin(device), 1, -Theme.castBottom(device))
	end)
end

--[[
	Zamach: wahadłowy pasek mocy.

	Pasek liczy moc z tej samej funkcji (`Cast.powerAt`) i tego samego
	momentu startu, z których kontroler wyliczy moc przy puszczeniu.
	Gdyby rysował własną animację, gracz puszczałby na „pełnym" pasku
	i dostawał rzut na pół dystansu.
]]
function CastMeter.showCharge(startedAt: number)
	beginState(Theme.COLOR.accent)
	setTensionVisible(false)

	if titleLabel then
		titleLabel.Text = "Zamach"
		titleLabel.TextColor3 = Theme.COLOR.text
	end
	if hintLabel then
		hintLabel.Text = "Puść, żeby rzucić. Pełny pasek = najdalej."
	end
	if perfectZone then
		perfectZone.Visible = false
	end

	local bar = progressFill
	renderConnection = RunService.RenderStepped:Connect(function()
		if not bar then
			stopRender()
			return
		end

		local power = Cast.powerAt(os.clock() - startedAt, GameConfig.CAST_POWER_PERIOD)
		bar.Size = UDim2.fromScale(power, 1)
		bar.BackgroundColor3 = Theme.COLOR.accent:Lerp(Theme.COLOR.coin, power)
	end)
end

--[[ Zarzucenie przyjęte — czekamy na branie. ]]
function CastMeter.showWaiting()
	beginState(Theme.COLOR.water)
	setTensionVisible(false)

	if titleLabel then
		titleLabel.Text = "Zarzucono"
		titleLabel.TextColor3 = Theme.COLOR.textMuted
	end
	if hintLabel then
		hintLabel.Text = "Czekaj na branie. Skubnięcie to jeszcze nie ryba."
	end
	if progressFill then
		progressFill.Size = UDim2.fromScale(0, 1)
	end
	if perfectZone then
		perfectZone.Visible = false
	end
end

--[[ Ryba bierze. `window` to okno w sekundach podane przez serwer. ]]
function CastMeter.showBite(window: number)
	beginState(Theme.COLOR.warning)
	setTensionVisible(false)

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

	local bar = progressFill
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

--[[
	Zacięcie udane — zaczyna się hol.

	Od tego momentu paski są sterowane strumieniem z serwera, a ta pętla
	tylko dogania wartości. Dlatego zerujemy `shown*`: start walki musi
	wyglądać jak start, a nie jak ciąg dalszy poprzedniej.
]]
function CastMeter.showFight()
	beginState(Theme.COLOR.success)
	fighting = true

	targetProgress = 0
	targetTension = 0
	shownProgress = 0
	shownTension = 0
	surging = false

	setTensionVisible(true)
	if perfectZone then
		perfectZone.Visible = false
	end

	if progressFill then
		progressFill.Size = UDim2.fromScale(0, 1)
		progressFill.BackgroundColor3 = Theme.COLOR.accent
	end

	renderConnection = RunService.RenderStepped:Connect(function(delta: number)
		local progress = progressFill
		local tension = tensionFill
		if not (progress and tension) then
			stopRender()
			return
		end

		local alpha = math.min(delta * LERP_SPEED, 1)
		shownProgress += (targetProgress - shownProgress) * alpha
		shownTension += (targetTension - shownTension) * alpha

		progress.Size = UDim2.fromScale(math.clamp(shownProgress, 0, 1), 1)
		tension.Size = UDim2.fromScale(math.clamp(shownTension, 0, 1), 1)

		-- Napięcie zmienia kolor progresywnie: zielone, żółte przy 50%,
		-- czerwone przy 100%. Gracz widzi, ile ma zapasu, nie patrząc
		-- na długość paska.
		tension.BackgroundColor3 = if shownTension < 0.5
			then Theme.COLOR.success:Lerp(Theme.COLOR.warning, shownTension * 2)
			else Theme.COLOR.warning:Lerp(Theme.COLOR.danger, (shownTension - 0.5) * 2)
	end)
end

--[[ Stan walki z serwera. Zapisujemy cele; rysuje pętla z `showFight`. ]]
function CastMeter.updateFight(state: Types.FightState)
	if not fighting then
		return
	end

	targetProgress = state.progress
	targetTension = state.tension

	if state.surging == surging then
		return
	end
	surging = state.surging

	-- Szarpnięcie musi być widoczne JEDNYM spojrzeniem — gracz ma na
	-- reakcję ułamek sekundy i nie zdąży odczytać tempa przyrostu paska.
	if titleLabel then
		titleLabel.Text = if surging then "PUŚĆ!" else "HOLUJ"
		titleLabel.TextColor3 = if surging then Theme.COLOR.danger else Theme.COLOR.success
	end
	if hintLabel then
		hintLabel.Text = if surging
			then "Ryba szarpie — napięcie rośnie trzy razy szybciej"
			else "Trzymaj, żeby holować. Puszczaj przy szarpnięciu."
	end
	if accentBar then
		accentBar.BackgroundColor3 = if surging then Theme.COLOR.danger else Theme.COLOR.success
	end
	if tensionLabel then
		tensionLabel.TextColor3 = if surging then Theme.COLOR.danger else Theme.COLOR.textMuted
	end
end

local function describeCatch(
	caught: Types.CaughtFish,
	perfect: boolean,
	record: boolean
): (string, string, Color3)
	local definition = Fish.find(caught.fishId)
	if not definition then
		return caught.fishId, `{Format.coins(caught.price)} monet`, Theme.COLOR.text
	end

	local accent = Fish.RARITY_COLOR[definition.rarity]
	local rarity = Fish.RARITY_LABEL[definition.rarity]

	local extras = ""
	if perfect then
		extras ..= "  ·  <b>PERFEKCYJNE</b>"
	end
	if record then
		extras ..= "  ·  <b>NOWY REKORD</b>"
	end

	return definition.displayName,
		`{rarity}  ·  {Format.mass(caught.mass)}  ·  {Format.coins(caught.price)} monet{extras}`,
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
		local name, details, color = describeCatch(result.fish, result.perfect, result.record)
		accent = color
		title.Text = name
		title.TextColor3 = color
		hint.Text = details
	elseif result.outcome == "LineSnapped" then
		title.Text = "Zerwana żyłka"
		title.TextColor3 = Theme.COLOR.danger
		hint.Text = "Za długo holowałeś przy szarpnięciu. Mocniejsza wędka wybacza więcej."
	elseif result.outcome == "Escaped" then
		title.Text = "Ryba uciekła"
		title.TextColor3 = Theme.COLOR.danger
		hint.Text = "Za późno — podcinaj, gdy pasek jeszcze leci."
	elseif result.outcome == "Spooked" then
		title.Text = "Spłoszona"
		title.TextColor3 = Theme.COLOR.danger
		hint.Text = "To było tylko skubnięcie. Czekaj, aż spławik zniknie pod wodą."
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
	setTensionVisible(false)

	if progressFill then
		progressFill.Size = UDim2.fromScale(0, 1)
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

	task.delay(2.6, function()
		if generation == shownGeneration and root then
			root.Visible = false
		end
	end)
end

function CastMeter.hide()
	beginState(Theme.COLOR.accent)
	setTensionVisible(false)
	if root then
		root.Visible = false
	end
end

return CastMeter
