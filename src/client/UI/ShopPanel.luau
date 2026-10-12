--!strict
--[[
	ShopPanel — sklep z wędkami.

	Statystyki pokazujemy PASKAMI, nie liczbami. „szczęście 1.25" nic nie mówi,
	dopóki nie zestawi się tego z 1.12 i 1.42 w pamięci. Paski znormalizowane
	do najlepszej wędki w katalogu dają odpowiedź na pytanie, które gracz
	naprawdę zadaje: „o ile to lepsze od tego, co mam".

	Tempo brań jest ODWRÓCONE przy normalizacji: w configu niższy `biteSpeed`
	oznacza szybsze branie, a dłuższy pasek musi zawsze znaczyć „lepiej".

	Panel sam NIE decyduje, czy gracza stać — tylko to pokazuje. Klik zawsze
	wysyła żądanie, a serwer je przyjmuje albo odrzuca z własnym komunikatem.
	Gdyby przycisk blokował się lokalnie, ta sama reguła żyłaby w dwóch
	miejscach i prędzej czy później by się rozjechały.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local RodModel = require(Shared.Util.RodModel)
local Rods = require(Shared.Config.Rods)
local Types = require(Shared.Types)

local Theme = require(script.Parent.Theme)

local ShopPanel = {}

local root: Frame? = nil
local coinsLabel: TextLabel? = nil

type RowHandle = {
	frame: Frame,
	button: TextButton,
}

local rows: { [string]: RowHandle } = {}

-- Ostatni snapshot przekazany do `update`. Handler kliknięcia musi wiedzieć,
-- czy gracz już ma tę wędkę (zakładamy) czy nie (kupujemy).
local lastProfile: Types.Profile? = nil

-- ---------------------------------------------------------------------------
-- Normalizacja statystyk — liczona raz, przy wczytaniu modułu
-- ---------------------------------------------------------------------------

type StatSpec = {
	label: string,
	color: Color3,
	value: (Types.RodDefinition) -> number,
}

local STATS: { StatSpec } = {
	{
		label = "Szczęście",
		color = Theme.COLOR.coin,
		value = function(rod)
			return rod.luck
		end,
	},
	{
		label = "Tempo brań",
		color = Theme.COLOR.accent,
		value = function(rod)
			-- Mniej = szybciej, więc odwracamy, żeby dłuższy pasek zawsze
			-- znaczył „lepiej".
			return -rod.biteSpeed
		end,
	},
	{
		label = "Okno",
		color = Theme.COLOR.success,
		value = function(rod)
			return rod.reelWindow
		end,
	},
	{
		-- Wytrzymałość żyłki jest tu ostatnia, ale w praktyce najważniejsza:
		-- to ona decyduje, czy da się wyholować silną rybę, czy zrywa się linka.
		label = "Żyłka",
		color = Theme.COLOR.danger,
		value = function(rod)
			return rod.lineStrength
		end,
	},
}

local function normalizer(spec: StatSpec): (Types.RodDefinition) -> number
	local minimum = math.huge
	local maximum = -math.huge

	for _, rod in Rods.all() do
		local value = spec.value(rod)
		minimum = math.min(minimum, value)
		maximum = math.max(maximum, value)
	end

	local span = maximum - minimum

	return function(rod: Types.RodDefinition): number
		if span <= 0 then
			return 1
		end
		-- Minimum dostaje 0.18, nie 0: pasek o zerowej długości wygląda
		-- jak brak statystyki, a nie jak najsłabsza wędka w katalogu.
		return 0.18 + 0.82 * ((spec.value(rod) - minimum) / span)
	end
end

local NORMALIZERS: { (Types.RodDefinition) -> number } = {}
for index, spec in STATS do
	NORMALIZERS[index] = normalizer(spec)
end

-- ---------------------------------------------------------------------------

-- Szerokość podglądu 3D i wynikające z niej wcięcia tekstu. Wszystkie
-- teksty w wierszu zaczynają się za podglądem, a kończą przed przyciskiem.
local PREVIEW = 70
local TEXT_X = PREVIEW + Theme.SPACE.md
local TEXT_INSET = TEXT_X + 118

local function buildStatBars(parent: Instance, definition: Types.RodDefinition)
	local slice = 1 / #STATS

	for index, spec in STATS do
		local track, fill = Theme.progress({
			Name = spec.label,
			Size = UDim2.new(slice, -6, 0, 5),
			Position = UDim2.fromScale((index - 1) * slice, 0),
		}, spec.color)

		fill.Size = UDim2.fromScale(NORMALIZERS[index](definition), 1)
		track.Parent = parent
	end
end

local function buildRow(definition: Types.RodDefinition): RowHandle
	local button = Theme.button({
		Name = "Action",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(104, 38),
		BackgroundColor3 = Theme.COLOR.accent,
		TextSize = Theme.TEXT.small,
		Text = "",
	})

	local status = Theme.label({
		Name = "StatLegend",
		Size = UDim2.new(1, -TEXT_INSET, 0, 16),
		Position = UDim2.fromOffset(TEXT_X, 24),
		TextSize = Theme.TEXT.micro,
		TextColor3 = Theme.COLOR.textMuted,
		-- Legenda jest STAŁA — paski niżej pokazują wartości. Powtarzanie
		-- liczb w tekście zdublowałoby to, co i tak widać.
		Text = "szczęście · tempo brań · okno · żyłka",
	})

	local statArea = Theme.create("Frame", {
		Name = "Stats",
		Size = UDim2.new(1, -TEXT_INSET, 0, 5),
		Position = UDim2.fromOffset(TEXT_X, 46),
		BackgroundTransparency = 1,
	}) :: Frame

	buildStatBars(statArea, definition)

	-- Podgląd 3D tej samej wędki, którą gracz dostanie do ręki — model
	-- pochodzi z `shared/Util/RodModel`, nie z osobnego obrazka.
	local preview = Theme.modelPreview({
		Name = "Preview",
		Size = UDim2.fromOffset(PREVIEW, PREVIEW),
		Position = UDim2.fromOffset(0, 0),
		BackgroundColor3 = Theme.COLOR.panel,
		BackgroundTransparency = 0.35,
	}, RodModel.toPreview(definition), 7.5)

	Theme.corner(Theme.RADIUS.sm).Parent = preview

	local frame = Theme.create(
		"Frame",
		{
			Name = definition.id,
			Size = UDim2.new(1, -10, 0, 84),
			LayoutOrder = definition.order,
			BackgroundColor3 = Theme.COLOR.panelAlt,
			BorderSizePixel = 0,
		},
		Theme.corner(Theme.RADIUS.md),
		Theme.stroke(Theme.COLOR.stroke, 2),
		Theme.padding(Theme.SPACE.sm, Theme.SPACE.md),
		preview,
		Theme.label({
			Size = UDim2.new(1, -TEXT_INSET, 0, 22),
			Position = UDim2.fromOffset(TEXT_X, 2),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT.body,
			Text = definition.displayName,
		}),
		status,
		statArea,
		button
	) :: Frame

	button.MouseButton1Click:Connect(function()
		local profile = lastProfile
		if profile and profile.ownedRods[definition.id] then
			Net.RequestEquipRod:FireServer(definition.id)
		else
			Net.RequestBuyRod:FireServer(definition.id)
		end
	end)

	return { frame = frame, button = button }
end

function ShopPanel.mount(parent: Instance)
	local rowList = Theme.create("ScrollingFrame", {
		Name = "List",
		Size = UDim2.new(1, 0, 1, -76),
		Position = UDim2.fromOffset(0, 76),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.COLOR.success,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, Theme.list(Theme.SPACE.sm)) :: ScrollingFrame

	local close = Theme.closeButton({})
	close.MouseButton1Click:Connect(function()
		ShopPanel.setVisible(false)
	end)

	local coins = Theme.label({
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 48),
		Font = Theme.FONT_BLACK,
		TextSize = Theme.TEXT.body,
		TextColor3 = Theme.COLOR.coinText,
		Text = "",
	})

	coinsLabel = coins

	root = Theme.panel(
		{
			Name = "Shop",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(460, 380),
			Visible = false,
			Parent = parent,
		},
		Theme.padding(Theme.SPACE.md),
		Theme.header("Sklep wędkarski", Theme.COLOR.success, { Size = UDim2.new(1, -48, 0, 42) }),
		coins,
		close,
		rowList
	)

	for _, definition in Rods.all() do
		local handle = buildRow(definition)
		handle.frame.Parent = rowList
		rows[definition.id] = handle
	end

	Theme.onLayout(function(device: Theme.Device, viewport: Vector2)
		local panel = root
		if not panel then
			return
		end

		if device == "Phone" then
			-- Prawie pełny ekran: cztery karty z paskami nie zmieszczą się
			-- czytelnie w okienku na telefonie.
			panel.Size =
				UDim2.fromOffset(math.min(viewport.X - 20, 460), math.min(viewport.Y - 90, 440))
		else
			panel.Size = UDim2.fromOffset(460, math.min(viewport.Y * 0.72, 420))
		end
	end)
end

function ShopPanel.update(profile: Types.Profile)
	lastProfile = profile

	local coins = coinsLabel
	if coins then
		coins.Text = `Masz $ {Format.coins(profile.coins)}`
	end

	for rodId, handle in rows do
		local definition = Rods.find(rodId)
		if not definition then
			continue
		end

		local owned = profile.ownedRods[rodId] == true
		local equipped = profile.equippedRod == rodId
		local affordable = profile.coins >= definition.price

		if equipped then
			handle.button.Text = "Założona"
			Theme.setButtonColor(handle.button, Theme.COLOR.success)
			handle.button.TextColor3 = Theme.COLOR.textInverse
		elseif owned then
			handle.button.Text = "Załóż"
			Theme.setButtonColor(handle.button, Theme.COLOR.accent)
			handle.button.TextColor3 = Theme.COLOR.textInverse
		else
			handle.button.Text = `$ {Format.coins(definition.price)}`
			-- Przygaszamy to, czego gracza nie stać, ale przycisk zostaje
			-- klikalny — odmowę wraz z powodem wysyła serwer.
			Theme.setButtonColor(
				handle.button,
				if affordable then Theme.COLOR.coin else Theme.COLOR.panelHigh
			)
			handle.button.TextColor3 = if affordable
				then Theme.COLOR.textInverse
				else Theme.COLOR.textMuted
		end

		-- Założona wędka świeci na zielono — „to twoja" bez czytania przycisku.
		handle.frame.BackgroundColor3 = if equipped
			then Theme.COLOR.success:Lerp(Color3.new(1, 1, 1), 0.7)
			else Theme.COLOR.panelAlt
	end
end

function ShopPanel.setVisible(visible: boolean)
	local panel = root
	if not panel then
		return
	end
	if visible and not panel.Visible then
		Theme.pop(panel, 0.7)
	end
	panel.Visible = visible
end

function ShopPanel.isVisible(): boolean
	return root ~= nil and root.Visible
end

return ShopPanel
