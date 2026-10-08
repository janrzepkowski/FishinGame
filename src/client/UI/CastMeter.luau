--!strict
--[[
	CastMeter — pasek minigry na dole ekranu.

	Trzy stany:
	  Waiting — "czekaj na branie", pulsujący napis
	  Biting  — pasek opadający od 1 do 0 przez `reelWindow` sekund,
	            z zieloną strefą na początku (bonus za szybkie podcięcie)
	  wynik   — krótki komunikat i zniknięcie

	WAŻNE: ten pasek jest TYLKO podpowiedzią wizualną. O trafieniu decyduje
	serwer, mierząc czas od swojego `BiteStarted`. Klient startuje animację
	o jeden ping później, więc jego pasek jest minimalnie z tyłu względem
	serwerowego okna. Nie próbujcie tego "naprawiać" wysyłaniem czasu
	z klienta — to otwiera drzwi do podrabiania trafień.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fish = require(Shared.Config.Fish)
local Format = require(Shared.Util.Format)
local GameConfig = require(Shared.Config.Game)
local Types = require(Shared.Types)

local Theme = require(script.Parent.Theme)

local CastMeter = {}

local root: Frame? = nil
local fill: Frame? = nil
local perfectZone: Frame? = nil
local titleLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil

local biteStartedAt: number? = nil
local biteWindow = 0
local renderConnection: RBXScriptConnection? = nil

-- Rośnie przy każdej zmianie stanu paska. Opóźnione "schowaj się" porównuje
-- swoją generację z bieżącą i odpuszcza, jeśli w międzyczasie coś się zmieniło.
-- Bez tego timer ze starego wyniku gasiłby świeżo rozpoczęte zarzucenie.
local generation = 0

local function setVisible(visible: boolean)
	if root then
		root.Visible = visible
	end
end

local function stopRender()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	biteStartedAt = nil
end

--[[ Przejście do nowego stanu paska. Zwraca numer generacji dla timerów. ]]
local function beginState(): number
	stopRender()
	generation += 1
	return generation
end

function CastMeter.mount(parent: Instance)
	local bar = Theme.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.COLOR.accent,
		BorderSizePixel = 0,
	}, Theme.corner(4)) :: Frame

	local zone = Theme.create("Frame", {
		Name = "PerfectZone",
		-- Strefa bonusu to POCZĄTEK okna, więc rysujemy ją od prawej —
		-- pasek opada w lewo, czyli najpierw mija strefę zieloną.
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(GameConfig.PERFECT_REEL_FRACTION, 1),
		BackgroundColor3 = Theme.COLOR.success,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, Theme.corner(4)) :: Frame

	local title = Theme.label({
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 1,
		Font = Theme.FONT_BOLD,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
	})

	local hint = Theme.label({
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 2,
		TextSize = 13,
		TextColor3 = Theme.COLOR.textMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
	})

	local track = Theme.create("Frame", {
		Name = "Track",
		Size = UDim2.new(1, 0, 0, 14),
		LayoutOrder = 3,
		BackgroundColor3 = Theme.COLOR.panelAlt,
		BorderSizePixel = 0,
	}, Theme.corner(4), bar, zone) :: Frame

	fill = bar
	perfectZone = zone
	titleLabel = title
	hintLabel = hint

	root = Theme.panel({
		Name = "CastMeter",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(380, 96),
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = parent,
	}, Theme.padding(12), Theme.verticalList(6), title, hint, track)
end

--[[ Zarzucenie przyjęte przez serwer — czekamy na branie. ]]
function CastMeter.showWaiting()
	beginState()

	if titleLabel then
		titleLabel.Text = "Zarzucono..."
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

	setVisible(true)
end

--[[ Ryba bierze. `window` to okno w sekundach podane przez serwer. ]]
function CastMeter.showBite(window: number)
	beginState()

	biteWindow = math.max(window, 0.05)
	biteStartedAt = os.clock()

	if titleLabel then
		titleLabel.Text = "PODETNIJ!"
		titleLabel.TextColor3 = Theme.COLOR.warning
	end
	if hintLabel then
		hintLabel.Text =
			`Lewy przycisk myszy — zielona strefa = bonus x{GameConfig.PERFECT_PRICE_BONUS}`
	end
	if perfectZone then
		perfectZone.Visible = true
	end

	setVisible(true)

	renderConnection = RunService.RenderStepped:Connect(function()
		local startedAt = biteStartedAt
		local bar = fill
		if not startedAt or not bar then
			stopRender()
			return
		end

		local remaining = math.clamp(1 - (os.clock() - startedAt) / biteWindow, 0, 1)
		bar.Size = UDim2.fromScale(remaining, 1)

		if remaining <= 0 then
			stopRender()
		end
	end)
end

--[[ Wynik zarzucenia. Pasek chowa się sam po chwili. ]]
function CastMeter.showResult(result: Types.CastResult)
	local shownGeneration = beginState()

	if fill then
		fill.Size = UDim2.fromScale(0, 1)
	end
	if perfectZone then
		perfectZone.Visible = false
	end

	local title = titleLabel
	local hint = hintLabel
	if not (title and hint) then
		return
	end

	if result.outcome == "Caught" and result.fish then
		local caught = result.fish
		local definition = Fish.find(caught.fishId)

		title.Text = if definition then definition.displayName else caught.fishId
		title.TextColor3 = if definition
			then Fish.RARITY_COLOR[definition.rarity]
			else Theme.COLOR.text

		local rarity = if definition then Fish.RARITY_LABEL[definition.rarity] else "?"
		local bonus = if result.perfect then "  ·  PERFEKCYJNE PODCIĘCIE" else ""
		hint.Text =
			`{rarity}  ·  {Format.mass(caught.mass)}  ·  {Format.coins(caught.price)} monet{bonus}`
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
		title.Text = "Ekwipunek pełny"
		title.TextColor3 = Theme.COLOR.warning
		hint.Text = "Sprzedaj połów w skupie ryb."
	end

	setVisible(true)

	task.delay(2.2, function()
		-- Nic się od tamtej pory nie zmieniło — można chować.
		if generation == shownGeneration then
			setVisible(false)
		end
	end)
end

function CastMeter.hide()
	beginState()
	setVisible(false)
end

return CastMeter
