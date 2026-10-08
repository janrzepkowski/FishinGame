--!strict
--[[
	ShopPanel — sklep z wędkami, otwierany promptem przy stoisku.

	Panel sam NIE decyduje, czy gracza stać na wędkę — tylko to pokazuje.
	Klik zawsze wysyła żądanie, a serwer je przyjmuje albo odrzuca z własnym
	komunikatem. Gdyby przycisk blokował się lokalnie, mielibyśmy dwa miejsca
	z tą samą regułą i prędzej czy później rozjechałyby się ze sobą.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Rods = require(Shared.Config.Rods)
local Types = require(Shared.Types)

local Theme = require(script.Parent.Theme)

local ShopPanel = {}

local root: Frame? = nil

type RowHandle = {
	frame: Frame,
	status: TextLabel,
	button: TextButton,
}

local rows: { [string]: RowHandle } = {}

-- Ostatni snapshot przekazany do `update`. Handler kliknięcia musi wiedzieć,
-- czy gracz już ma tę wędkę (zakładamy) czy nie (kupujemy). Trzymamy to tutaj,
-- zamiast ciągnąć do UI zależność od ProfileCache — i tak dostajemy profil
-- przy każdej zmianie.
local lastProfile: Types.Profile? = nil

local function buildRow(definition: Types.RodDefinition): RowHandle
	local status = Theme.label({
		Size = UDim2.new(1, -110, 0, 16),
		Position = UDim2.fromOffset(0, 24),
		TextSize = 12,
		TextColor3 = Theme.COLOR.textMuted,
		Text = "",
	})

	local button = Theme.create("TextButton", {
		Name = "Action",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(96, 30),
		BackgroundColor3 = Theme.COLOR.accent,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(10, 14, 20),
		AutoButtonColor = true,
		Text = "",
	}, Theme.corner(5)) :: TextButton

	local frame = Theme.create(
		"Frame",
		{
			Name = definition.id,
			Size = UDim2.new(1, -8, 0, 54),
			LayoutOrder = definition.order,
			BackgroundColor3 = Theme.COLOR.panelAlt,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
		},
		Theme.corner(6),
		Theme.create("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
		}),
		Theme.label({
			Size = UDim2.new(1, -110, 0, 20),
			Font = Theme.FONT_BOLD,
			TextSize = 15,
			Text = definition.displayName,
		}),
		status,
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

	return { frame = frame, status = status, button = button }
end

function ShopPanel.mount(parent: Instance)
	local rowList = Theme.create("ScrollingFrame", {
		Name = "List",
		Size = UDim2.new(1, 0, 1, -40),
		Position = UDim2.fromOffset(0, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.COLOR.stroke,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, Theme.verticalList(6)) :: ScrollingFrame

	local close = Theme.create("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Theme.COLOR.panelAlt,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = 15,
		TextColor3 = Theme.COLOR.textMuted,
		Text = "×",
	}, Theme.corner(5)) :: TextButton

	close.MouseButton1Click:Connect(function()
		ShopPanel.setVisible(false)
	end)

	root = Theme.panel(
		{
			Name = "Shop",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(420, 340),
			BackgroundTransparency = 0.04,
			Visible = false,
			Parent = parent,
		},
		Theme.padding(14),
		Theme.label({
			Size = UDim2.new(1, -30, 0, 24),
			Font = Theme.FONT_BOLD,
			TextSize = 18,
			Text = "Sklep wędkarski",
		}),
		close,
		rowList
	)

	for _, definition in Rods.all() do
		local handle = buildRow(definition)
		handle.frame.Parent = rowList
		rows[definition.id] = handle
	end
end

function ShopPanel.update(profile: Types.Profile)
	lastProfile = profile

	for rodId, handle in rows do
		local definition = Rods.find(rodId)
		if not definition then
			continue
		end

		local owned = profile.ownedRods[rodId] == true
		local equipped = profile.equippedRod == rodId

		handle.status.Text =
			`szczęście x{definition.luck}  ·  tempo brań x{definition.biteSpeed}  ·  okno {Format.seconds(
				definition.reelWindow
			)}`

		if equipped then
			handle.button.Text = "Założona"
			handle.button.BackgroundColor3 = Theme.COLOR.success
			handle.button.Active = false
		elseif owned then
			handle.button.Text = "Założ"
			handle.button.BackgroundColor3 = Theme.COLOR.accent
			handle.button.Active = true
		else
			handle.button.Text = Format.coins(definition.price)
			-- Przygaszamy to, czego gracza nie stać, ale przycisk zostaje
			-- klikalny — odmowę wraz z powodem wysyła serwer.
			handle.button.BackgroundColor3 = if profile.coins >= definition.price
				then Theme.COLOR.coin
				else Theme.COLOR.stroke
			handle.button.Active = true
		end
	end
end

function ShopPanel.setVisible(visible: boolean)
	if root then
		root.Visible = visible
	end
end

function ShopPanel.isVisible(): boolean
	return root ~= nil and root.Visible
end

return ShopPanel
