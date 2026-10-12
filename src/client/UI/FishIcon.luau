--!strict
--[[
	FishIcon — ikona gatunku do list: ekwipunek i bestiariusz.

	Kafelek w kolorze rzadkości, a w nim `ViewportFrame` z tym samym modelem
	(`FishModel`), który wyskakuje z wody po wyholowaniu. Nie obrazek:
	obrazek trzeba wyrenderować, wgrać na Roblox i trzymać jego numer
	w kodzie, a przy dwunastu gatunkach to dwanaście assetów, które rozjadą
	się z modelem przy pierwszej zmianie. Każdy gatunek ma własny model,
	więc każdy ma też własną, niepowtarzalną ikonę — za darmo.

	Ryba jest pokazana BOKIEM, lekko z góry — tak dzieci rysują ryby i tak
	najłatwiej rozpoznać gatunek po sylwetce.

	Rzadkie ryby dostają za plecami obracające się promienie: kafelek
	legendarnej ryby ma się wyróżniać w siatce, zanim gracz przeczyta nazwę.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Fish = require(Shared.Config.Fish)
local FishModel = require(Shared.Util.FishModel)

local Theme = require(script.Parent.Theme)

local FishIcon = {}

-- Kolor sylwetki gatunku, którego gracz jeszcze nie złowił.
local UNKNOWN = Color3.fromRGB(16, 28, 84)
-- Od tego poziomu rzadkości kafelek dostaje promienie.
local RAYS_FROM_TIER = 2

--[[
	Tworzy kafelek gatunku `fishId`.

	`known = false` rysuje samą ciemną sylwetkę ze znakiem zapytania:
	w bestiariuszu widać, CO jest do złowienia i jak duże, ale kolory
	zostają nagrodą za połów.
]]
function FishIcon.create(fishId: string, props: { [string]: any }, known: boolean?): Frame
	local definition = Fish.find(fishId)
	local model = FishModel.build(fishId)
	local hidden = known == false

	local accent = if definition then Fish.RARITY_COLOR[definition.rarity] else Theme.COLOR.accent
	local tier = if definition then Fish.RARITY_TIER[definition.rarity] else 0

	if hidden then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Color = UNKNOWN
				descendant.Material = Enum.Material.SmoothPlastic
			end
		end
	end

	local merged: { [string]: any } = {
		Name = "FishIcon",
		BackgroundColor3 = if hidden then Theme.COLOR.well else accent,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}
	for key, value in props do
		merged[key] = value
	end

	local tile = Theme.create(
		"Frame",
		merged,
		Theme.corner(Theme.RADIUS.md),
		Theme.stroke(Theme.COLOR.outline, 2),
		-- Jasny środek, ciemniejsze brzegi: kafelek wygląda jak podświetlona
		-- gablotka, a ryba odcina się od tła.
		Theme.create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.new(0.62, 0.62, 0.72)),
			}),
		})
	) :: Frame

	if not hidden and tier >= RAYS_FROM_TIER then
		Theme.sunburst({
			Size = UDim2.fromScale(1.7, 1.7),
			SizeConstraint = Enum.SizeConstraint.RelativeXX,
			ZIndex = 1,
			Parent = tile,
		}, Color3.new(1, 1, 1), 10)
	end

	-- Odległość kamery z OBRYSU modelu, nie z samego korpusu: welon Złotej
	-- Rybki i jej korona wystają daleko poza korpus i ucinała je krawędź
	-- kafelka. Szczupak i złota rybka wypełniają kafelek tak samo, mimo że
	-- różnią się długością dwukrotnie.
	local _, extents = model:GetBoundingBox()
	local distance = math.max(extents.Z * 1.25, extents.Y * 2.1)
	Theme.modelPreview({
		Name = "Model",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = tile,
	}, model, distance)

	-- `modelPreview` ustawia model pod wędkę (ukośnie, od rączki). Rybę
	-- obracamy bokiem do kamery, pyskiem w lewo, z lekkim skrętem ku widzowi.
	model:PivotTo(CFrame.Angles(0, math.rad(66), 0) * CFrame.Angles(0, 0, math.rad(-6)))

	if hidden then
		local mark = Theme.label({
			Name = "Unknown",
			Size = UDim2.fromScale(1, 1),
			Font = Theme.FONT_DISPLAY,
			TextScaled = true,
			TextColor3 = Theme.COLOR.textMuted,
			TextTransparency = 0.15,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 3,
			Text = "?",
			Parent = tile,
		})
		Theme.create("UIPadding", {
			PaddingTop = UDim.new(0.22, 0),
			PaddingBottom = UDim.new(0.22, 0),
			Parent = mark,
		})
	end

	return tile
end

return table.freeze(FishIcon)
