--!strict
--[[
	InventoryPanel — siatka kart złowionych ryb, każda z modelem 3D.

	Przebudowujemy całą siatkę przy każdej zmianie profilu, zamiast dopisywać
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
	Przy kartach z ViewportFrame to jeszcze ważniejsze niż przy wierszach.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fish = require(Shared.Config.Fish)
local Format = require(Shared.Util.Format)
local GameConfig = require(Shared.Config.Game)
local Types = require(Shared.Types)

local FishCard = require(script.Parent.FishCard)
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

local CELL = Vector2.new(92, 112)
local CELL_PHONE = Vector2.new(84, 104)
local HEADER_SPACE = 74

local cellSize = CELL
local lastProfile: Types.Profile? = nil

--[[
	Karta złowionej ryby: model 3D, masa w rogu, cena na dole.

	Siatka kart zamiast listy wierszy, jak w ekwipunku petów z gier
	referencyjnych: ryba jest NAGRODĄ i ma być oglądana, a nie czytana.
	Lista nazw była tabelką z księgowości.
]]
local function buildCard(caught: Types.CaughtFish, order: number): Frame
	local definition = Fish.find(caught.fishId)
	if not definition then
		-- Gatunek usunięty z configu, a wciąż w czyimś profilu. Pokazujemy
		-- pustą kartę z id, zamiast wywracać cały panel.
		return Theme.create(
			"Frame",
			{
				Name = `Unknown{order}`,
				Size = UDim2.fromOffset(cellSize.X, cellSize.Y),
				LayoutOrder = order,
				BackgroundColor3 = Theme.COLOR.panelHigh,
			},
			Theme.corner(Theme.RADIUS.md),
			Theme.label({
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextWrapped = true,
				Text = caught.fishId,
			})
		) :: Frame
	end

	return FishCard.card(definition, {
		size = cellSize,
		order = order,
		corner = Format.mass(caught.mass),
		footer = `$ {Format.coins(caught.price)}`,
		footerColor = Theme.COLOR.coin,
	})
end

function InventoryPanel.mount(parent: Instance)
	local summary = Theme.label({
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 48),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.small,
		TextColor3 = Theme.COLOR.textMuted,
		Text = "",
	})

	local empty = Theme.label({
		Size = UDim2.new(1, -20, 0, 60),
		Position = UDim2.fromScale(0, 0.4),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.body,
		TextColor3 = Theme.COLOR.textMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Text = "Pusto! 🎣\nIdź na pomost i zarzuć wędkę.",
		Visible = false,
	})

	local layout = Theme.create("UIGridLayout", {
		CellSize = UDim2.fromOffset(CELL.X, CELL.Y),
		CellPadding = UDim2.fromOffset(Theme.SPACE.sm, Theme.SPACE.sm),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}) :: UIGridLayout

	local rowList = Theme.create("ScrollingFrame", {
		Name = "List",
		Size = UDim2.new(1, 0, 1, -HEADER_SPACE),
		Position = UDim2.fromOffset(0, HEADER_SPACE),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.COLOR.accent,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, Theme.padding(Theme.SPACE.xs), layout) :: ScrollingFrame

	local close = Theme.closeButton({})
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
			Visible = false,
			Parent = parent,
		},
		Theme.padding(Theme.SPACE.md),
		Theme.header("Połów", Theme.COLOR.accent, { Size = UDim2.new(1, -48, 0, 42) }),
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

		local nextCell = if device == "Phone" then CELL_PHONE else CELL
		layout.CellSize = UDim2.fromOffset(nextCell.X, nextCell.Y)
		if nextCell ~= cellSize then
			cellSize = nextCell
			-- Karty mają wymiar w pikselach (podgląd 3D liczy z niego kamerę),
			-- więc zmiana klasy urządzenia wymusza ich przebudowę.
			renderedSignature = ""
			local profile = lastProfile
			if profile then
				InventoryPanel.update(profile)
			end
		end

		if device == "Phone" then
			-- Arkusz od dołu: kciuk sięga do krawędzi ekranu, a woda zostaje
			-- widoczna w górnej połowie.
			panel.AnchorPoint = Vector2.new(0.5, 1)
			panel.Position = UDim2.new(0.5, 0, 1, -Theme.SPACE.sm)
			panel.Size =
				UDim2.fromOffset(math.min(viewport.X - 24, 420), math.min(viewport.Y * 0.6, 380))
		else
			panel.AnchorPoint = Vector2.new(1, 0.5)
			panel.Position = UDim2.new(1, -Theme.SPACE.lg, 0.5, 0)
			-- Trzy kolumny kart plus padding i pasek przewijania.
			panel.Size = UDim2.fromOffset(
				CELL.X * 3 + Theme.SPACE.sm * 2 + Theme.SPACE.md * 2 + 18,
				math.min(viewport.Y * 0.7, 480)
			)
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

	lastProfile = profile

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
		-- Najnowsza ryba na początku siatki: to ją gracz chce zobaczyć
		-- po złowieniu, a nie przewijać do końca.
		buildCard(caught, -index).Parent = container
	end

	local count = #profile.inventory
	empty.Visible = count == 0

	if count == 0 then
		summary.Text = `0 / {GameConfig.MAX_INVENTORY} szt.`
	else
		summary.Text = `{count} / {GameConfig.MAX_INVENTORY} ryb  ·  warte $ {Format.coins(total)}`
	end

	summary.TextColor3 = if count >= GameConfig.MAX_INVENTORY
		then Theme.COLOR.warning
		else Theme.COLOR.textMuted
end

function InventoryPanel.setVisible(visible: boolean)
	local panel = root
	if not panel then
		return
	end
	if visible and not panel.Visible then
		Theme.pop(panel, 0.7)
	end
	panel.Visible = visible
end

function InventoryPanel.toggle()
	if root then
		InventoryPanel.setVisible(not root.Visible)
	end
end

function InventoryPanel.isVisible(): boolean
	return root ~= nil and root.Visible
end

return InventoryPanel
