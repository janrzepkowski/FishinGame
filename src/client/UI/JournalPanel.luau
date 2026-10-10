--!strict
--[[
	JournalPanel — bestiariusz i ranking w jednym oknie.

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

local Theme = require(script.Parent.Theme)

local JournalPanel = {}

local root: Frame? = nil
local bestiaryHolder: Frame? = nil
local rankHolder: Frame? = nil
local summaryLabel: TextLabel? = nil

local lastRecordSignature = ""

local function sectionHeader(text: string, order: number): TextLabel
	return Theme.label({
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = order,
		Font = Theme.FONT_BLACK,
		TextSize = Theme.TEXT.body,
		TextColor3 = Theme.COLOR.textMuted,
		Text = text,
	})
end

local function holder(order: number): Frame
	return Theme.create("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		BackgroundTransparency = 1,
	}, Theme.list(Theme.SPACE.xs)) :: Frame
end

-- ---------------------------------------------------------------------------
-- Bestiariusz
-- ---------------------------------------------------------------------------

local function buildBestiaryRow(
	definition: Types.FishDefinition,
	record: number?,
	order: number
): Frame
	local caught = record ~= nil
	local accent = Fish.RARITY_COLOR[definition.rarity]

	return Theme.create(
		"Frame",
		{
			Name = definition.id,
			Size = UDim2.new(1, -8, 0, 34),
			LayoutOrder = order,
			BackgroundColor3 = Theme.COLOR.panelAlt,
			BackgroundTransparency = if caught then 0.3 else 0.68,
			BorderSizePixel = 0,
		},
		Theme.corner(Theme.RADIUS.sm),
		Theme.create("Frame", {
			Size = UDim2.new(0, 3, 1, -12),
			Position = UDim2.fromOffset(0, 6),
			BackgroundColor3 = accent,
			BackgroundTransparency = if caught then 0 else 0.6,
			BorderSizePixel = 0,
		}),
		Theme.label({
			Size = UDim2.new(0.56, -14, 1, 0),
			Position = UDim2.fromOffset(12, 0),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT.small,
			-- Nieznane gatunki pokazujemy po nazwie, nie jako „???".
			-- Lista celów działa tylko wtedy, gdy wiadomo, co się na niej
			-- znajduje; zagadka zniechęca zamiast ciągnąć.
			TextColor3 = if caught then Theme.COLOR.text else Theme.COLOR.textMuted,
			Text = definition.displayName,
		}),
		Theme.label({
			Size = UDim2.new(0.44, -12, 1, 0),
			Position = UDim2.fromScale(0.56, 0),
			TextSize = Theme.TEXT.micro,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = if caught then accent else Theme.COLOR.textMuted,
			Text = if record then `rekord {Format.mass(record)}` else "niezłowiona",
		})
	) :: Frame
end

-- ---------------------------------------------------------------------------
-- Ranking
-- ---------------------------------------------------------------------------

local function buildRankRow(entry: Types.LeaderboardEntry, order: number): Frame
	return Theme.create(
		"Frame",
		{
			Name = `Rank{order}`,
			Size = UDim2.new(1, -8, 0, 26),
			LayoutOrder = order,
			BackgroundTransparency = 1,
		},
		Theme.label({
			Size = UDim2.fromScale(0.62, 1),
			Position = UDim2.fromOffset(8, 0),
			Font = if order <= 3 then Theme.FONT_BOLD else Theme.FONT,
			TextSize = Theme.TEXT.small,
			TextColor3 = if order <= 3 then Theme.COLOR.coin else Theme.COLOR.text,
			Text = `{order}.  {entry.name}`,
		}),
		Theme.label({
			Size = UDim2.new(0.38, -12, 1, 0),
			Position = UDim2.fromScale(0.62, 0),
			TextSize = Theme.TEXT.small,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Theme.COLOR.coin,
			Text = Format.coins(entry.value),
		})
	) :: Frame
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
		Size = UDim2.new(1, -46, 0, 16),
		Position = UDim2.fromOffset(0, 28),
		TextSize = Theme.TEXT.small,
		TextColor3 = Theme.COLOR.textMuted,
		Text = "",
	})

	local bestiary = holder(2)
	local ranks = holder(4)

	local list = Theme.create(
		"ScrollingFrame",
		{
			Name = "Sections",
			Size = UDim2.new(1, 0, 1, -56),
			Position = UDim2.fromOffset(0, 56),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = Theme.COLOR.stroke,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
		},
		Theme.list(Theme.SPACE.sm),
		sectionHeader("BESTIARIUSZ", 1),
		bestiary,
		sectionHeader("NAJLEPSI WĘDKARZE", 3),
		ranks
	) :: ScrollingFrame

	local close = Theme.closeButton({})
	close.MouseButton1Click:Connect(function()
		JournalPanel.setVisible(false)
	end)

	summaryLabel = summary
	bestiaryHolder = bestiary
	rankHolder = ranks

	root = Theme.panel(
		{
			Name = "Journal",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(420, 460),
			BackgroundTransparency = 0.02,
			Visible = false,
			Parent = parent,
		},
		Theme.padding(Theme.SPACE.lg, Theme.SPACE.md),
		Theme.label({
			Size = UDim2.new(1, -46, 0, 26),
			Font = Theme.FONT_BLACK,
			TextSize = Theme.TEXT.lead,
			Text = "Dziennik",
		}),
		summary,
		close,
		list
	)

	Theme.onLayout(function(device: Theme.Device, viewport: Vector2)
		local panel = root
		if not panel then
			return
		end

		if device == "Phone" then
			panel.Size =
				UDim2.fromOffset(math.min(viewport.X - 20, 420), math.min(viewport.Y - 90, 460))
		else
			panel.Size = UDim2.fromOffset(420, math.min(viewport.Y * 0.78, 500))
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
			buildBestiaryRow(definition, record, index).Parent = bestiary
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
		root.Visible = not root.Visible
	end
end

function JournalPanel.setVisible(visible: boolean)
	if root then
		root.Visible = visible
	end
end

function JournalPanel.isVisible(): boolean
	return root ~= nil and root.Visible
end

return JournalPanel
