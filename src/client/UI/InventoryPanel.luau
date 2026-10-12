--!strict
--[[
	InventoryPanel — złowione ryby jako siatka kafelków.

	Przebudowujemy całą listę przy każdej zmianie profilu, zamiast dopisywać
	pojedyncze wiersze. Przy limicie 24 sztuk to kilkadziesiąt instancji —
	tanio, a kod nie musi śledzić, który wiersz odpowiada której rybie.
	Gdyby limit urósł do setek, dopiero wtedy warto przejść na recykling.

	Na telefonie panel zamienia się w arkusz przyklejony do dołu ekranu.
	Boczna kolumna z desktopu zajęłaby tam połowę szerokości i zasłoniła wodę.

	OPTYMALIZACJA: `update` dostaje KAŻDY snapshot profilu — także ten po
	samej zmianie monet. Bez kontroli przebudowywalibyśmy 24 wiersze
	(≈ 150 instancji) przy każdym złowieniu i każdej transakcji, czyli
	w najgorszym możliwym momencie: w trakcie animacji wyciągania ryby.
	Dlatego liczymy tani podpis ekwipunku i wychodzimy, gdy się nie zmienił.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fish = require(Shared.Config.Fish)
local Format = require(Shared.Util.Format)
local GameConfig = require(Shared.Config.Game)
local Types = require(Shared.Types)

local FishIcon = require(script.Parent.FishIcon)
local Theme = require(script.Parent.Theme)

local InventoryPanel = {}

local root: Frame? = nil
local list: ScrollingFrame? = nil
local summaryLabel: TextLabel? = nil
local emptyLabel: TextLabel? = nil

-- Podpis ostatnio narysowanej listy. Patrz uwaga o optymalizacji w nagłówku.
local renderedSignature = ""

--[[
	Tani podpis ekwipunku: liczność + id, masy i ceny.

	Nie jest to hash kryptograficzny i nie musi być — chodzi wyłącznie
	o wykrycie, czy lista wygląda inaczej niż ta już narysowana. Dwa różne
	ekwipunki o identycznym podpisie są nieodróżnialne także dla gracza.
]]
local function signatureOf(inventory: { Types.CaughtFish }): string
	local parts = table.create(#inventory + 1)
	parts[1] = tostring(#inventory)

	for index, caught in inventory do
		parts[index + 1] = `{caught.fishId}:{caught.mass}:{caught.price}`
	end

	return table.concat(parts, "|")
end

-- Kafelek ryby w siatce. Wymiary są tutaj, bo z nich wynika szerokość okna.
local CELL = Vector2.new(98, 128)
local GAP = 8
local COLUMNS = 3
local WINDOW_WIDTH = COLUMNS * CELL.X + (COLUMNS - 1) * GAP + 46
-- Odstęp od prawej krawędzi: tam stoją okrągłe przyciski torby i dziennika
-- (`MobileControls`), a okno nie może ich zasłaniać.
local SIDE_INSET = 104

--[[
	Kafelek jednej ryby: ikona gatunku, nazwa, waga i cena.

	Siatka kafelków zamiast listy wierszy: ryby ogląda się jak kolekcję
	naklejek, a nie jak tabelkę. Ramka ma kolor rzadkości — przy przewijaniu
	to jedyne, co gracz naprawdę skanuje.
]]
local function buildCell(caught: Types.CaughtFish, order: number): Frame
	local definition = Fish.find(caught.fishId)
	local accent = if definition then Fish.RARITY_COLOR[definition.rarity] else Theme.COLOR.text
	local name = if definition then definition.displayName else caught.fishId

	local nameLabel = Theme.label({
		Name = "FishName",
		Size = UDim2.new(1, -8, 0, 16),
		Position = UDim2.fromOffset(4, 70),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.small,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = name,
	})
	Theme.outline(nameLabel, Theme.COLOR.outline, 1.5)

	local cell = Theme.card(
		{
			Name = `Fish{order}`,
			LayoutOrder = order,
		},
		-- Ikona 3D tej samej ryby, która wyskoczyła z wody.
		FishIcon.create(caught.fishId, {
			Name = "Icon",
			Size = UDim2.new(1, -12, 0, 60),
			Position = UDim2.fromOffset(6, 6),
		}),
		nameLabel,
		Theme.label({
			Name = "Mass",
			Size = UDim2.new(1, -8, 0, 14),
			Position = UDim2.fromOffset(4, 86),
			TextSize = Theme.TEXT.micro,
			TextColor3 = Theme.COLOR.textMuted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = Format.mass(caught.mass),
		}),
		Theme.badge(Format.coins(caught.price), Theme.COLOR.coin, {
			Name = "Price",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -5),
		})
	)

	local stroke = cell:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = accent
		stroke.Thickness = 3
	end

	return cell
end

function InventoryPanel.mount(parent: Instance)
	local summary = Theme.label({
		Name = "Summary",
		Size = UDim2.new(1, 0, 0, 20),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.small,
		TextColor3 = Theme.COLOR.textMuted,
		Text = "",
	})

	local empty = Theme.label({
		Size = UDim2.new(1, -20, 0, 60),
		Position = UDim2.new(0, 10, 0.38, 0),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.body,
		TextColor3 = Theme.COLOR.textMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Text = "Pusto!\nIdź na pomost i zarzuć wędkę.",
		Visible = false,
	})

	local grid = Theme.create(
		"ScrollingFrame",
		{
			Name = "Grid",
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
		Theme.create("UIGridLayout", {
			CellSize = UDim2.fromOffset(CELL.X, CELL.Y),
			CellPadding = UDim2.fromOffset(GAP, GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		-- Kontur kafelka rysuje się NA ZEWNĄTRZ ramki; bez marginesu
		-- przycinałaby go krawędź przewijanej listy.
		Theme.padding(4)
	) :: ScrollingFrame

	summaryLabel = summary
	emptyLabel = empty
	list = grid

	local window, body = Theme.window(
		{
			Name = "Inventory",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -SIDE_INSET, 0.5, 0),
			Size = UDim2.fromOffset(WINDOW_WIDTH, 440),
			Visible = false,
			Parent = parent,
		},
		"Połów",
		Theme.COLOR.pink,
		function()
			InventoryPanel.setVisible(false)
		end
	)

	summary.Parent = body
	grid.Parent = body
	empty.Parent = body
	root = window

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
			panel.Size = UDim2.fromOffset(
				math.min(viewport.X - 24, WINDOW_WIDTH),
				math.min(viewport.Y * 0.58, 380)
			)
		else
			panel.AnchorPoint = Vector2.new(1, 0.5)
			panel.Position = UDim2.new(1, -SIDE_INSET, 0.5, 0)
			panel.Size = UDim2.fromOffset(WINDOW_WIDTH, math.min(viewport.Y * 0.7, 480))
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

	local signature = signatureOf(profile.inventory)
	if signature == renderedSignature then
		return
	end
	renderedSignature = signature

	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local total = 0
	for index, caught in profile.inventory do
		total += caught.price
		buildCell(caught, index).Parent = container
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
		Theme.setVisible(root, not root.Visible)
	end
end

function InventoryPanel.setVisible(visible: boolean)
	if root then
		Theme.setVisible(root, visible)
	end
end

function InventoryPanel.isVisible(): boolean
	return root ~= nil and root.Visible
end

return InventoryPanel
