--!strict
--[[
	FishCard — karta ryby z podglądem 3D, wspólna dla ekwipunku,
	bestiariusza, wyniku połowu i animacji nagród.

	Wzór z gier z „petami": kwadratowa karta w kolorze rzadkości, model
	na środku, nazwa obrysowana na dole. Kolor ramki mówi o rzadkości,
	zanim gracz przeczyta cokolwiek — dokładnie tak, jak kolor paska
	w starej liście, tylko głośniej.

	Model pochodzi z `shared/Util/FishModel`, czyli jest tą samą rybą,
	która wyskakuje z wody po złowieniu. Obrazków nie ma i nie będzie
	(zasada 12 w CLAUDE.md).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fish = require(Shared.Config.Fish)
local FishModel = require(Shared.Util.FishModel)
local Types = require(Shared.Types)

local Theme = require(script.Parent.Theme)

local FishCard = {}

export type CardOptions = {
	size: Vector2,
	-- Ciemna sylwetka i szare tło — gatunek jeszcze nie złowiony.
	locked: boolean?,
	-- Mały napis w lewym górnym rogu (np. masa).
	corner: string?,
	-- Pigułka pod nazwą (np. cena albo rekord).
	footer: string?,
	footerColor: Color3?,
	order: number?,
}

--[[
	Podgląd 3D ryby z boku, głową w lewo.

	Nie używamy `Theme.modelPreview`: tamten kąt jest dobrany pod wędkę
	(długi kij po skosie), a ryba ma być widziana z profilu w 3/4 —
	z oboma oczami i ogonem w kadrze.
]]
function FishCard.preview(
	definition: Types.FishDefinition,
	props: { [string]: any },
	silhouette: boolean?
): ViewportFrame
	local frame = Instance.new("ViewportFrame")
	frame.BackgroundTransparency = 1
	frame.Ambient = Color3.fromRGB(210, 210, 220)
	frame.LightColor = Color3.fromRGB(255, 255, 255)
	frame.LightDirection = Vector3.new(-0.3, -1, -0.5)

	local target: any = frame
	for key, value in props do
		if key ~= "Parent" then
			target[key] = value
		end
	end

	local model = FishModel.build(definition, { silhouette = silhouette })
	-- Głowa (lokalne -Z) obrócona w lewo kadru i lekko do widza. Ryba
	-- patrząca na gracza jest „żywa", ryba z idealnego profilu to naklejka.
	model:PivotTo(CFrame.Angles(0, math.rad(68), math.rad(-6)))
	model.Parent = frame

	local length = FishModel.length(definition)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.CFrame = CFrame.lookAt(Vector3.new(0, length * 0.35, length * 2.2), Vector3.zero)
	camera.Parent = frame
	frame.CurrentCamera = camera

	if props.Parent then
		frame.Parent = props.Parent
	end
	return frame
end

--[[ Kolor rzadkości rozjaśniony na tło karty. ]]
local function cardTint(rarity: Types.Rarity): Color3
	return Fish.RARITY_COLOR[rarity]:Lerp(Color3.new(1, 1, 1), 0.55)
end

function FishCard.card(definition: Types.FishDefinition, options: CardOptions): Frame
	local locked = options.locked == true
	local rarityColor = Fish.RARITY_COLOR[definition.rarity]
	local width, height = options.size.X, options.size.Y
	local nameHeight = math.floor(height * 0.2)

	local card = Theme.create(
		"Frame",
		{
			Name = definition.id,
			Size = UDim2.fromOffset(width, height),
			LayoutOrder = options.order or 0,
			BackgroundColor3 = if locked
				then Theme.COLOR.panelHigh
				else cardTint(definition.rarity),
			BorderSizePixel = 0,
			ClipsDescendants = false,
		},
		Theme.corner(Theme.RADIUS.md),
		Theme.stroke(
			if locked then Theme.COLOR.textMuted else rarityColor:Lerp(Color3.new(0, 0, 0), 0.15),
			Theme.OUTLINE
		),
		Theme.create("UIGradient", {
			-- Jaśniejsza góra karty: model „stoi w świetle".
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.82, 0.82, 0.86)),
		})
	) :: Frame

	FishCard.preview(definition, {
		Name = "Preview",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, math.floor(height * 0.06)),
		Size = UDim2.fromOffset(width - 8, height - nameHeight - math.floor(height * 0.08)),
		ZIndex = 2,
		Parent = card,
	}, locked)

	local name = Theme.label({
		Name = "Name",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if options.footer then -nameHeight + 2 else -4),
		Size = UDim2.new(1, -6, 0, nameHeight),
		Font = Theme.FONT_BLACK,
		TextSize = math.clamp(math.floor(height * 0.14), 11, Theme.TEXT.lead),
		TextColor3 = if locked then Theme.COLOR.textMuted else Theme.COLOR.textInverse,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 4,
		Text = definition.displayName,
	})
	if not locked then
		Theme.outline(name, Theme.COLOR.stroke, 2)
	end
	name.Parent = card

	if options.corner then
		local tag = Theme.label({
			Name = "Corner",
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.new(1, -12, 0, 16),
			Font = Theme.FONT_BLACK,
			TextSize = Theme.TEXT.micro,
			TextColor3 = Theme.COLOR.textInverse,
			ZIndex = 4,
			Text = options.corner,
		})
		Theme.outline(tag, Theme.COLOR.stroke, 1.5)
		tag.Parent = card
	end

	if options.footer then
		local footer = Theme.label({
			Name = "Footer",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, -6, 0, nameHeight - 2),
			Font = Theme.FONT_BLACK,
			TextSize = math.clamp(math.floor(height * 0.12), 10, Theme.TEXT.body),
			TextColor3 = options.footerColor or Theme.COLOR.coin,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 4,
			Text = options.footer,
		})
		Theme.outline(footer, Theme.COLOR.stroke, 1.5)
		footer.Parent = card
	end

	-- Epickie i legendarne błyszczą. Połysk to sygnał „to jest cenne",
	-- który dziecko rozumie bez znajomości słowa „legendarna".
	if
		not locked
		and Fish.RARITY_TIER[definition.rarity] >= Fish.RARITY_TIER["Epic" :: Types.Rarity]
	then
		Theme.shine(card, if definition.rarity == "Legendary" then 1.6 else 2.6)
	end

	return card
end

return FishCard
