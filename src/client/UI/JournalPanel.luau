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

local FishCard = require(script.Parent.FishCard)
local Theme = require(script.Parent.Theme)

local JournalPanel = {}

local root: Frame? = nil
local bestiaryHolder: Frame? = nil
local rankHolder: Frame? = nil
local summaryLabel: TextLabel? = nil

local lastRecordSignature = ""

local CARD = Vector2.new(96, 112)
local MEDALS = {
	Color3.fromRGB(255, 202, 40),
	Color3.fromRGB(196, 210, 230),
	Color3.fromRGB(232, 150, 90),
}

local function sectionHeader(text: string, color: Color3, order: number): Frame
	-- Nagłówek sekcji jako mała, kolorowa pigułka — sekcje widać z daleka
	-- przy przewijaniu, zamiast szarego napisu, który zlewa się z tłem.
	return Theme.badge(text, color, { LayoutOrder = order, Size = UDim2.fromOffset(0, 28) })
end

local function holder(order: number, layout: Instance): Frame
	return Theme.create("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		BackgroundTransparency = 1,
	}, layout) :: Frame
end

-- ---------------------------------------------------------------------------
-- Bestiariusz
-- ---------------------------------------------------------------------------

local function buildBestiaryCard(
	definition: Types.FishDefinition,
	record: number?,
	order: number
): Frame
	-- Niezłowione gatunki są ciemną sylwetką, ale Z NAZWĄ, nie jako „???".
	-- Lista celów działa tylko wtedy, gdy wiadomo, co się na niej znajduje;
	-- sylwetka dokłada ciekawość („jak ona wygląda?"), nazwa daje cel.
	return FishCard.card(definition, {
		size = CARD,
		order = order,
		locked = record == nil,
		corner = Fish.RARITY_LABEL[definition.rarity],
		footer = if record then `🏆 {Format.mass(record)}` else "???",
		footerColor = if record then Theme.COLOR.coin else Theme.COLOR.textMuted,
	})
end

-- ---------------------------------------------------------------------------
-- Ranking
-- ---------------------------------------------------------------------------

local function buildRankRow(entry: Types.LeaderboardEntry, order: number): Frame
	local medal = MEDALS[order]
	local color = medal or Theme.COLOR.panelAlt

	local place = Theme.icon(tostring(order), medal or Theme.COLOR.accent, 30, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		TextSize = Theme.TEXT.small,
	})

	return Theme.create(
		"Frame",
		{
			Name = `Rank{order}`,
			Size = UDim2.new(1, -8, 0, 38),
			LayoutOrder = order,
			BackgroundColor3 = if medal then color:Lerp(Color3.new(1, 1, 1), 0.55) else color,
			BorderSizePixel = 0,
		},
		Theme.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Theme.stroke(Theme.COLOR.stroke, 2),
		place,
		Theme.label({
			Size = UDim2.new(0.6, -42, 1, 0),
			Position = UDim2.fromOffset(42, 0),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT.body,
			TextColor3 = Theme.COLOR.text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = entry.name,
		}),
		Theme.label({
			Size = UDim2.new(0.4, -14, 1, 0),
			Position = UDim2.fromScale(0.6, 0),
			Font = Theme.FONT_BLACK,
			TextSize = Theme.TEXT.body,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Theme.COLOR.coinText,
			Text = `$ {Format.coins(entry.value)}`,
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
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 48),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.small,
		TextColor3 = Theme.COLOR.textMuted,
		Text = "",
	})

	local bestiary = holder(
		2,
		Theme.create("UIGridLayout", {
			CellSize = UDim2.fromOffset(CARD.X, CARD.Y),
			CellPadding = UDim2.fromOffset(Theme.SPACE.sm, Theme.SPACE.sm),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		})
	)
	local ranks = holder(4, Theme.list(Theme.SPACE.xs))

	local list = Theme.create(
		"ScrollingFrame",
		{
			Name = "Sections",
			Size = UDim2.new(1, 0, 1, -74),
			Position = UDim2.fromOffset(0, 74),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			ScrollBarImageColor3 = Theme.COLOR.purple,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
		},
		Theme.padding(Theme.SPACE.xs),
		Theme.list(Theme.SPACE.md),
		sectionHeader("BESTIARIUSZ", Theme.COLOR.accent, 1),
		bestiary,
		sectionHeader("NAJLEPSI WĘDKARZE", Theme.COLOR.coin, 3),
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
			Size = UDim2.fromOffset(460, 500),
			Visible = false,
			Parent = parent,
		},
		Theme.padding(Theme.SPACE.md),
		Theme.header("Dziennik", Theme.COLOR.purple, { Size = UDim2.new(1, -48, 0, 42) }),
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
				UDim2.fromOffset(math.min(viewport.X - 20, 460), math.min(viewport.Y - 60, 500))
		else
			panel.Size = UDim2.fromOffset(460, math.min(viewport.Y * 0.82, 560))
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
			buildBestiaryCard(definition, record, index).Parent = bestiary
		end

		summary.Text = `Odkryte gatunki: {discovered} / {#Fish.all()}  ·  złap je wszystkie!`
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
			Font = Theme.FONT_BOLD,
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

function JournalPanel.setVisible(visible: boolean)
	local panel = root
	if not panel then
		return
	end
	if visible and not panel.Visible then
		Theme.pop(panel, 0.7)
	end
	panel.Visible = visible
end

function JournalPanel.toggle()
	if root then
		JournalPanel.setVisible(not root.Visible)
	end
end

function JournalPanel.isVisible(): boolean
	return root ~= nil and root.Visible
end

return JournalPanel
