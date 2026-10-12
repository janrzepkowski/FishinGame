--!strict
--[[
	JournalPanel — bestiariusz i ranking w jednym oknie.

	Bestiariusz to siatka kafelków z ikoną każdego gatunku — kolekcja
	naklejek do uzupełnienia. Niezłowione gatunki są ciemnymi sylwetkami.

	Dwie sekcje jedna pod drugą zamiast dwóch paneli i dwóch klawiszy.
	Gracz uczy się jednego skrótu, a sekcje widać przewijając — zakładki
	wymagałyby kliknięcia, żeby w ogóle dowiedzieć się, że coś tam jest.

	Bestiariusz rysujemy z `profile.records`, które serwer zapisywał już
	wcześniej i których nigdy nie pokazywaliśmy. Dane były, brakowało okna.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fish = require(Shared.Config.Fish)
local Format = require(Shared.Util.Format)
local Types = require(Shared.Types)

local FishIcon = require(script.Parent.FishIcon)
local Theme = require(script.Parent.Theme)

local JournalPanel = {}

local root: Frame? = nil
local bestiaryHolder: Frame? = nil
local rankHolder: Frame? = nil
local summaryLabel: TextLabel? = nil

local lastRecordSignature = ""

-- Kafelek gatunku w bestiariuszu.
local CELL = Vector2.new(96, 116)
local GAP = 8
local COLUMNS = 4
local WINDOW_WIDTH = COLUMNS * CELL.X + (COLUMNS - 1) * GAP + 46

-- Kolory trzech pierwszych miejsc w rankingu: złoto, srebro, brąz.
local MEDALS = {
	Color3.fromRGB(255, 206, 48),
	Color3.fromRGB(206, 220, 240),
	Color3.fromRGB(240, 150, 84),
}

local function sectionHeader(text: string, color: Color3, order: number): Frame
	local label = Theme.label({
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FONT_DISPLAY,
		TextSize = Theme.TEXT.body,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 3,
		Text = text,
	})
	Theme.outline(label, Theme.COLOR.outline, 2)

	return Theme.create(
		"Frame",
		{
			Size = UDim2.new(1, -8, 0, 28),
			LayoutOrder = order,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		},
		Theme.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Theme.stroke(Theme.COLOR.outline, 2),
		Theme.candyGradient(0.16),
		label
	) :: Frame
end

local function holder(order: number, layout: Instance): Frame
	return Theme.create("Frame", {
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		BackgroundTransparency = 1,
	}, layout) :: Frame
end

-- ---------------------------------------------------------------------------
-- Bestiariusz
-- ---------------------------------------------------------------------------

local function buildBestiaryCell(
	definition: Types.FishDefinition,
	record: number?,
	order: number
): Frame
	local caught = record ~= nil
	local accent = Fish.RARITY_COLOR[definition.rarity]

	local nameLabel = Theme.label({
		Name = "FishName",
		Size = UDim2.new(1, -8, 0, 16),
		Position = UDim2.fromOffset(4, 68),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.small,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		-- Nieznane gatunki pokazujemy po nazwie, nie jako „???".
		-- Lista celów działa tylko wtedy, gdy wiadomo, co się na niej
		-- znajduje; zagadka zniechęca zamiast ciągnąć.
		TextColor3 = if caught then Theme.COLOR.text else Theme.COLOR.textMuted,
		Text = definition.displayName,
	})
	Theme.outline(nameLabel, Theme.COLOR.outline, 1.5)

	local cell = Theme.card(
		{
			Name = definition.id,
			LayoutOrder = order,
			BackgroundColor3 = if caught then Theme.COLOR.panelAlt else Theme.COLOR.well,
		},
		-- Niezłowiony gatunek to ciemna sylwetka: widać, co jest do zdobycia,
		-- a kolory zostają nagrodą za połów.
		FishIcon.create(definition.id, {
			Name = "Icon",
			Size = UDim2.new(1, -12, 0, 58),
			Position = UDim2.fromOffset(6, 6),
		}, caught),
		nameLabel,
		Theme.label({
			Name = "Record",
			Size = UDim2.new(1, -6, 0, 26),
			Position = UDim2.fromOffset(3, 86),
			TextSize = Theme.TEXT.micro,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			TextColor3 = if caught then Theme.COLOR.coin else Theme.COLOR.textMuted,
			Text = if record
				then `rekord {Format.mass(record)}`
				-- Podpowiedź, kiedy szukać: „bierze nocą" mówi graczowi,
				-- co zrobić, a samo „niezłowiona" tylko stwierdza fakt.
				else (Fish.hint(definition) or "do złowienia"),
		})
	)

	local stroke = cell:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if caught then accent else Theme.COLOR.outline
		stroke.Thickness = if caught then 3 else 2
	end

	return cell
end

-- ---------------------------------------------------------------------------
-- Ranking
-- ---------------------------------------------------------------------------

local function buildRankRow(entry: Types.LeaderboardEntry, order: number): Frame
	local medal = MEDALS[order]

	local place = Theme.icon(tostring(order), medal or Theme.COLOR.panelHigh, 26, {
		Name = "Place",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 5, 0.5, 0),
	})

	return Theme.card(
		{
			Name = `Rank{order}`,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = order,
		},
		place,
		Theme.label({
			Size = UDim2.new(0.62, -40, 1, 0),
			Position = UDim2.fromOffset(40, 0),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT.small,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = medal or Theme.COLOR.text,
			Text = entry.name,
		}),
		Theme.label({
			Size = UDim2.new(0.38, -12, 1, 0),
			Position = UDim2.fromScale(0.62, 0),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT.small,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextColor3 = Theme.COLOR.coin,
			Text = Format.coins(entry.value),
		})
	)
end

-- ---------------------------------------------------------------------------

local function clearChildren(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function JournalPanel.mount(parent: Instance)
	local summary = Theme.label({
		Name = "Summary",
		Size = UDim2.new(1, 0, 0, 20),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.small,
		TextColor3 = Theme.COLOR.textMuted,
		Text = "",
	})

	local bestiary = holder(
		2,
		Theme.create("UIGridLayout", {
			CellSize = UDim2.fromOffset(CELL.X, CELL.Y),
			CellPadding = UDim2.fromOffset(GAP, GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
	)
	local ranks = holder(4, Theme.list(Theme.SPACE.sm))

	local list = Theme.create(
		"ScrollingFrame",
		{
			Name = "Sections",
			Size = UDim2.new(1, 0, 1, -28),
			Position = UDim2.fromOffset(0, 28),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			ScrollBarImageColor3 = Theme.COLOR.white,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
		},
		Theme.list(Theme.SPACE.md),
		-- Kontury kafelków rysują się na zewnątrz ramek — margines chroni
		-- je przed przycięciem przez krawędź listy.
		Theme.padding(4),
		sectionHeader("BESTIARIUSZ", Theme.COLOR.success, 1),
		bestiary,
		sectionHeader("NAJLEPSI WĘDKARZE", Theme.COLOR.coin, 3),
		ranks
	) :: ScrollingFrame

	summaryLabel = summary
	bestiaryHolder = bestiary
	rankHolder = ranks

	local window, body = Theme.window(
		{
			Name = "Journal",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(WINDOW_WIDTH, 480),
			Visible = false,
			Parent = parent,
		},
		"Dziennik",
		Theme.COLOR.purple,
		function()
			JournalPanel.setVisible(false)
		end
	)

	summary.Parent = body
	list.Parent = body
	root = window

	Theme.onLayout(function(device: Theme.Device, viewport: Vector2)
		local panel = root
		if not panel then
			return
		end

		if device == "Phone" then
			panel.Size = UDim2.fromOffset(
				math.min(viewport.X - 20, WINDOW_WIDTH),
				math.min(viewport.Y - 90, 480)
			)
		else
			panel.Size = UDim2.fromOffset(WINDOW_WIDTH, math.min(viewport.Y * 0.8, 540))
		end
	end)
end

function JournalPanel.update(profile: Types.Profile)
	local bestiary = bestiaryHolder
	local summary = summaryLabel
	if not (bestiary and summary) then
		return
	end

	-- Przebudowa tylko przy realnej zmianie. `update` dostaje KAŻDY snapshot
	-- profilu, także ten po samej zmianie monet, a lista bestiariusza to
	-- kilkadziesiąt instancji.
	local recordSignature = ""
	for _, definition in Fish.all() do
		recordSignature ..= `{profile.records[definition.id] or 0}|`
	end

	if recordSignature ~= lastRecordSignature then
		lastRecordSignature = recordSignature
		clearChildren(bestiary)

		local discovered = 0
		for index, definition in Fish.all() do
			local record = profile.records[definition.id]
			if record then
				discovered += 1
			end
			buildBestiaryCell(definition, record, index).Parent = bestiary
		end

		summary.Text = `Odkryte gatunki: {discovered} / {#Fish.all()}`
	end
end

--[[ Ranking przychodzi osobnym Remote'em, nie w profilu — jest wspólny
     dla wszystkich graczy, więc nie ma czego trzymać w profilu. ]]
function JournalPanel.setLeaderboard(entries: { Types.LeaderboardEntry })
	local ranks = rankHolder
	if not ranks then
		return
	end

	clearChildren(ranks)

	if #entries == 0 then
		Theme.label({
			Size = UDim2.new(1, -8, 0, 24),
			TextSize = Theme.TEXT.small,
			TextColor3 = Theme.COLOR.textMuted,
			Text = "Ranking jeszcze się zbiera.",
			Parent = ranks,
		})
		return
	end

	for index, entry in entries do
		buildRankRow(entry, index).Parent = ranks
	end
end

function JournalPanel.toggle()
	if root then
		Theme.setVisible(root, not root.Visible)
	end
end

function JournalPanel.setVisible(visible: boolean)
	if root then
		Theme.setVisible(root, visible)
	end
end

function JournalPanel.isVisible(): boolean
	return root ~= nil and root.Visible
end

return JournalPanel
