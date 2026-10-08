--!strict
--[[
	InventoryPanel — lista złowionych ryb.

	Przebudowujemy całą listę przy każdej zmianie profilu, zamiast dopisywać
	pojedyncze wiersze. Przy limicie 24 sztuk to kilkadziesiąt instancji —
	tanio, a kod nie musi śledzić, który wiersz odpowiada której rybie.
	Gdyby limit urósł do setek, dopiero wtedy warto przejść na recykling.

	Na telefonie panel zamienia się w arkusz przyklejony do dołu ekranu.
	Boczna kolumna z desktopu zajęłaby tam połowę szerokości i zasłoniła wodę.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fish = require(Shared.Config.Fish)
local Format = require(Shared.Util.Format)
local GameConfig = require(Shared.Config.Game)
local Types = require(Shared.Types)

local Theme = require(script.Parent.Theme)

local InventoryPanel = {}

local root: Frame? = nil
local list: ScrollingFrame? = nil
local summaryLabel: TextLabel? = nil
local emptyLabel: TextLabel? = nil

local function buildRow(caught: Types.CaughtFish, order: number): Frame
	local definition = Fish.find(caught.fishId)
	local accent = if definition then Fish.RARITY_COLOR[definition.rarity] else Theme.COLOR.text
	local name = if definition then definition.displayName else caught.fishId
	local rarity = if definition then Fish.RARITY_LABEL[definition.rarity] else "?"

	return Theme.create(
		"Frame",
		{
			Name = `Row{order}`,
			Size = UDim2.new(1, -10, 0, 46),
			LayoutOrder = order,
			BackgroundColor3 = Theme.COLOR.panelAlt,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
		},
		Theme.corner(Theme.RADIUS.md),
		-- Pasek rzadkości po lewej. Kolor czyta się szybciej niż słowo,
		-- a przy przewijaniu listy to jedyne, co gracz naprawdę skanuje.
		Theme.create("Frame", {
			Size = UDim2.new(0, 4, 1, -14),
			Position = UDim2.fromOffset(0, 7),
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
		}, Theme.corner(Theme.RADIUS.sm)),
		Theme.label({
			Size = UDim2.new(0.58, -14, 0, 20),
			Position = UDim2.fromOffset(14, 5),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT.body,
			TextColor3 = Theme.COLOR.text,
			Text = name,
		}),
		Theme.label({
			Size = UDim2.new(0.58, -14, 0, 16),
			Position = UDim2.fromOffset(14, 24),
			TextSize = Theme.TEXT.micro,
			TextColor3 = accent,
			Text = `{rarity} · {Format.mass(caught.mass)}`,
		}),
		Theme.label({
			Size = UDim2.new(0.42, -14, 1, 0),
			Position = UDim2.fromScale(0.58, 0),
			Font = Theme.FONT_BLACK,
			TextSize = Theme.TEXT.body,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Theme.COLOR.coin,
			Text = Format.coins(caught.price),
		})
	) :: Frame
end

function InventoryPanel.mount(parent: Instance)
	local summary = Theme.label({
		Size = UDim2.new(1, -34, 0, 16),
		Position = UDim2.fromOffset(0, 26),
		TextSize = Theme.TEXT.small,
		TextColor3 = Theme.COLOR.textMuted,
		Text = "",
	})

	local empty = Theme.label({
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.fromScale(0, 0.4),
		TextSize = Theme.TEXT.small,
		TextColor3 = Theme.COLOR.textMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Text = "Pusto.\nIdź na pomost i zarzuć wędkę.",
		Visible = false,
	})

	local rowList = Theme.create("ScrollingFrame", {
		Name = "List",
		Size = UDim2.new(1, 0, 1, -54),
		Position = UDim2.fromOffset(0, 54),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.COLOR.stroke,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, Theme.list(Theme.SPACE.xs)) :: ScrollingFrame

	local close = Theme.button({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		-- 32 px to minimum, w które da się trafić palcem bez celowania.
		Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = Theme.COLOR.panelAlt,
		TextColor3 = Theme.COLOR.textMuted,
		TextSize = Theme.TEXT.lead,
		Text = "✕",
	})

	close.MouseButton1Click:Connect(function()
		InventoryPanel.setVisible(false)
	end)

	summaryLabel = summary
	emptyLabel = empty
	list = rowList

	root = Theme.panel(
		{
			Name = "Inventory",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -Theme.SPACE.lg, 0.5, 0),
			Size = UDim2.fromOffset(340, 420),
			BackgroundTransparency = 0.04,
			Visible = false,
			Parent = parent,
		},
		Theme.padding(Theme.SPACE.lg, Theme.SPACE.md),
		Theme.label({
			Size = UDim2.new(1, -34, 0, 24),
			Font = Theme.FONT_BLACK,
			TextSize = Theme.TEXT.lead,
			Text = "Połów",
		}),
		summary,
		close,
		rowList,
		empty
	)

	Theme.onLayout(function(device: Theme.Device, viewport: Vector2)
		local panel = root
		if not panel then
			return
		end

		if device == "Phone" then
			-- Arkusz od dołu: kciuk sięga do krawędzi ekranu, a woda zostaje
			-- widoczna w górnej połowie.
			panel.AnchorPoint = Vector2.new(0.5, 1)
			panel.Position = UDim2.new(0.5, 0, 1, -Theme.SPACE.sm)
			panel.Size =
				UDim2.fromOffset(math.min(viewport.X - 24, 420), math.min(viewport.Y * 0.55, 360))
		else
			panel.AnchorPoint = Vector2.new(1, 0.5)
			panel.Position = UDim2.new(1, -Theme.SPACE.lg, 0.5, 0)
			panel.Size = UDim2.fromOffset(340, math.min(viewport.Y * 0.68, 460))
		end
	end)
end

function InventoryPanel.update(profile: Types.Profile)
	local container = list
	local summary = summaryLabel
	local empty = emptyLabel
	if not (container and summary and empty) then
		return
	end

	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local total = 0
	for index, caught in profile.inventory do
		total += caught.price
		buildRow(caught, index).Parent = container
	end

	local count = #profile.inventory
	empty.Visible = count == 0

	if count == 0 then
		summary.Text = `0 / {GameConfig.MAX_INVENTORY} szt.`
	else
		summary.Text =
			`{count} / {GameConfig.MAX_INVENTORY} szt.  ·  warte {Format.coins(total)} monet`
	end

	summary.TextColor3 = if count >= GameConfig.MAX_INVENTORY
		then Theme.COLOR.warning
		else Theme.COLOR.textMuted
end

function InventoryPanel.toggle()
	if root then
		root.Visible = not root.Visible
	end
end

function InventoryPanel.setVisible(visible: boolean)
	if root then
		root.Visible = visible
	end
end

function InventoryPanel.isVisible(): boolean
	return root ~= nil and root.Visible
end

return InventoryPanel
