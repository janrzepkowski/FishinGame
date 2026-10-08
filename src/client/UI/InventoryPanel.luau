--!strict
--[[
	InventoryPanel — lista złowionych ryb (klawisz B).

	Przebudowujemy całą listę przy każdej zmianie profilu, zamiast dopisywać
	pojedyncze wiersze. Przy limicie 24 sztuk to kilkadziesiąt instancji —
	tanio, a kod nie musi śledzić, który wiersz odpowiada której rybie.
	Gdyby limit urósł do setek, dopiero wtedy warto przejść na recykling wierszy.
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

local function buildRow(caught: Types.CaughtFish, order: number): Frame
	local definition = Fish.find(caught.fishId)
	local accent = if definition then Fish.RARITY_COLOR[definition.rarity] else Theme.COLOR.text
	local name = if definition then definition.displayName else caught.fishId

	return Theme.create(
		"Frame",
		{
			Name = `Row{order}`,
			Size = UDim2.new(1, -8, 0, 30),
			LayoutOrder = order,
			BackgroundColor3 = Theme.COLOR.panelAlt,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
		},
		Theme.corner(5),
		Theme.create("UIPadding", {
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
		-- Pionowy pasek w kolorze rzadkości — czyta się szybciej niż tekst.
		Theme.create("Frame", {
			Size = UDim2.new(0, 3, 1, -10),
			Position = UDim2.fromOffset(-5, 5),
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
		}),
		Theme.label({
			Size = UDim2.fromScale(0.52, 1),
			Font = Theme.FONT_BOLD,
			TextColor3 = accent,
			Text = name,
		}),
		Theme.label({
			Size = UDim2.fromScale(0.24, 1),
			Position = UDim2.fromScale(0.52, 0),
			TextColor3 = Theme.COLOR.textMuted,
			Text = Format.mass(caught.mass),
		}),
		Theme.label({
			Size = UDim2.fromScale(0.24, 1),
			Position = UDim2.fromScale(0.76, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Theme.COLOR.coin,
			Text = Format.coins(caught.price),
		})
	) :: Frame
end

function InventoryPanel.mount(parent: Instance)
	-- Nagłówek i podsumowanie pozycjonujemy wprost, bo lista poniżej też ma
	-- stałą pozycję. Mieszanie UIListLayout z ręcznym Position w jednym
	-- rodzicu kończy się tym, że LayoutOrder jest cicho ignorowany.
	local summary = Theme.label({
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 26),
		TextSize = 13,
		TextColor3 = Theme.COLOR.textMuted,
		Text = "",
	})

	local rowList = Theme.create("ScrollingFrame", {
		Name = "List",
		Size = UDim2.new(1, 0, 1, -56),
		Position = UDim2.fromOffset(0, 56),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.COLOR.stroke,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, Theme.verticalList(4)) :: ScrollingFrame

	summaryLabel = summary
	list = rowList

	root = Theme.panel(
		{
			Name = "Inventory",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.fromOffset(330, 400),
			BackgroundTransparency = 0.06,
			Visible = false,
			Parent = parent,
		},
		Theme.padding(12),
		Theme.label({
			Size = UDim2.new(1, 0, 0, 22),
			Font = Theme.FONT_BOLD,
			TextSize = 17,
			Text = "Połów",
		}),
		summary,
		rowList
	)
end

function InventoryPanel.update(profile: Types.Profile)
	local container = list
	local summary = summaryLabel
	if not (container and summary) then
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

	summary.Text = `{#profile.inventory} / {GameConfig.MAX_INVENTORY} szt.  ·  warte {Format.coins(
		total
	)} monet`

	if #profile.inventory == 0 then
		summary.Text = "Pusto. Idź nad wodę i zarzuć wędkę."
	end
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

return InventoryPanel
