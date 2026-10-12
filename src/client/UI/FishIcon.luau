--!strict
--[[
	FishIcon — podgląd 3D ryby do list: ekwipunek i bestiariusz.

	To `ViewportFrame` z tym samym modelem (`FishModel`), który wyskakuje
	z wody po wyholowaniu. Nie obrazek: obrazek trzeba wyrenderować, wgrać
	na Roblox i trzymać jego numer w kodzie, a przy dwunastu gatunkach to
	dwanaście assetów, które rozjadą się z modelem przy pierwszej zmianie.

	Ryba jest pokazana BOKIEM, lekko z góry — tak dzieci rysują ryby i tak
	najłatwiej rozpoznać gatunek po sylwetce.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local FishModel = require(Shared.Util.FishModel)

local Theme = require(script.Parent.Theme)

local FishIcon = {}

-- Kolor sylwetki gatunku, którego gracz jeszcze nie złowił.
local UNKNOWN = Color3.fromRGB(58, 66, 80)

--[[
	Tworzy podgląd gatunku `fishId`.

	`known = false` rysuje samą ciemną sylwetkę: w bestiariuszu widać, CO
	jest do złowienia i jak duże, ale kolory zostają nagrodą za połów.
]]
function FishIcon.create(fishId: string, props: { [string]: any }, known: boolean?): ViewportFrame
	local shape = FishModel.shape(fishId)
	local model = FishModel.build(fishId)

	if known == false then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Color = UNKNOWN
				descendant.Material = Enum.Material.SmoothPlastic
			end
		end
	end

	-- Odległość kamery z najdłuższego wymiaru: szczupak i złota rybka mają
	-- wypełniać okienko tak samo, mimo że różnią się długością dwukrotnie.
	local distance = math.max(shape.length, shape.height * 1.6) * 1.55 + 0.8
	local frame = Theme.modelPreview(props, model, distance)

	-- `modelPreview` ustawia model pod wędkę (ukośnie, od rączki). Rybę
	-- obracamy bokiem do kamery, pyskiem w lewo, z lekkim skrętem ku widzowi.
	model:PivotTo(CFrame.Angles(0, math.rad(68), 0))

	return frame
end

return table.freeze(FishIcon)
