--!strict
--[[
	Market — plac startowy, spawn i dwa stoiska: skup ryb i sklep wędkarski.

	Każde stoisko budujemy w LOKALNYM układzie współrzędnych, względem
	`CFrame.lookAt(pozycja, skądPrzychodziGracz)`. Dzięki temu „przód" to
	zawsze lokalne -Z i nie trzeba liczyć w głowie, o ile obrócić każdą deskę.

	To nie jest wygoda, tylko poprawność z konstrukcji: lokalne -Z pokrywa się
	z `Enum.NormalId.Front` w Robloxie, więc szyld na ścianie frontowej
	na pewno patrzy na gracza. Przy ręcznym obracaniu części prędzej czy
	później jeden szyld wyląduje tyłem i nikt tego nie zauważy do premiery.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)

local Build = require(script.Parent.Build)

local Market = {}

local PLAZA_CENTER = Vector3.new(0, 0, 18)
local SPAWN_POSITION = Vector3.new(0, 0.55, 24)
local FISH_BUYER_POSITION = Vector3.new(-17, 0, -2)
local ROD_SHOP_POSITION = Vector3.new(17, 0, -2)

local STONE = Color3.fromRGB(138, 141, 148)
local STONE_DARK = Color3.fromRGB(104, 108, 116)
local WOOD = Color3.fromRGB(150, 110, 70)
local WOOD_DARK = Color3.fromRGB(104, 76, 50)

export type StallStyle = {
	accent: Color3,
	stripe: Color3,
	title: string,
	subtitle: string,
	promptAction: string,
	standKind: string,
}

-- ---------------------------------------------------------------------------
-- Plac i ścieżki
-- ---------------------------------------------------------------------------

local function buildPlaza(parent: Instance)
	local plaza = Build.model(parent, "Plaza")

	Build.block(plaza, {
		Name = "Floor",
		Size = Vector3.new(52, 0.4, 34),
		Position = PLAZA_CENTER + Vector3.new(0, 0.2, 0),
		Color = STONE,
		Material = Enum.Material.Cobblestone,
		CanCollide = true,
	})

	-- Ścieżka z placu na pomost. Prowadzi gracza bez tutoriala: widać,
	-- dokąd iść, zanim się przeczyta jakikolwiek napis.
	Build.block(plaza, {
		Name = "Path",
		Size = Vector3.new(9, 0.3, 36),
		Position = Vector3.new(0, 0.15, -16),
		Color = STONE_DARK,
		Material = Enum.Material.Cobblestone,
		CanCollide = true,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(12, 0.6, 12)
	spawn.Position = SPAWN_POSITION
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Material = Enum.Material.Marble
	spawn.Color = Color3.fromRGB(196, 201, 209)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	-- Zero sekund tarczy: gracz i tak nie ma z kim walczyć, a świecąca
	-- kula wokół postaci zasłaniałaby mu spławik przy pierwszym rzucie.
	spawn.Duration = 0
	spawn.Parent = plaza
end

-- ---------------------------------------------------------------------------
-- Stoisko
-- ---------------------------------------------------------------------------

local function buildStallShell(model: Model, base: CFrame, style: StallStyle): BasePart
	Build.block(model, {
		Name = "Platform",
		Size = Vector3.new(15, 0.5, 10),
		CFrame = base * CFrame.new(0, 0.25, 0),
		Color = WOOD_DARK,
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
	})

	Build.block(model, {
		Name = "BackWall",
		Size = Vector3.new(15, 6, 0.4),
		CFrame = base * CFrame.new(0, 3.2, 4.8),
		Color = WOOD,
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
	})

	for _, side in { -1, 1 } do
		Build.block(model, {
			Name = "SideWall",
			Size = Vector3.new(0.4, 6, 10),
			CFrame = base * CFrame.new(side * 7.3, 3.2, 0),
			Color = WOOD,
			Material = Enum.Material.WoodPlanks,
			CanCollide = true,
		})

		Build.block(model, {
			Name = "Post",
			Size = Vector3.new(0.6, 6, 0.6),
			CFrame = base * CFrame.new(side * 7, 3.2, -4.6),
			Color = WOOD_DARK,
			Material = Enum.Material.Wood,
			CanCollide = true,
		})
	end

	-- Lada — to w nią gracz „wchodzi" i przy niej stoi ProximityPrompt,
	-- więc zwracamy ją jako punkt zaczepienia dla ShopService.
	local counter = Build.block(model, {
		Name = "Counter",
		Size = Vector3.new(13, 2.4, 1.6),
		CFrame = base * CFrame.new(0, 1.7, -4),
		Color = style.accent,
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
	})

	Build.block(model, {
		Name = "CounterTop",
		Size = Vector3.new(13.8, 0.35, 2.3),
		CFrame = base * CFrame.new(0, 3.05, -4.1),
		Color = Color3.fromRGB(214, 198, 170),
		Material = Enum.Material.Wood,
		CanCollide = true,
	})

	return counter
end

local function buildRoof(model: Model, base: CFrame, style: StallStyle)
	-- Pochylenie w stronę gracza. Obrót wokół lokalnego X o UJEMNY kąt
	-- opuszcza lokalne -Z: przy dodatnim dach podniósłby się od frontu
	-- i wyglądałby jak trampolina.
	local roofCFrame = base * CFrame.new(0, 6.4, -0.3) * CFrame.Angles(math.rad(-14), 0, 0)

	Build.block(model, {
		Name = "Roof",
		Size = Vector3.new(17, 0.45, 12),
		CFrame = roofCFrame,
		Color = Color3.fromRGB(74, 80, 92),
		Material = Enum.Material.Slate,
		CanCollide = true,
	})

	-- Pasiasta markiza na przednim okapie. Buduje się ją w układzie DACHU,
	-- nie świata — inaczej każdy pasek trzeba by obracać osobno.
	local stripeCount = 9
	local stripeWidth = 17 / stripeCount

	for index = 1, stripeCount do
		local offsetX = -17 / 2 + (index - 0.5) * stripeWidth
		Build.block(model, {
			Name = "AwningStripe",
			Size = Vector3.new(stripeWidth - 0.05, 0.3, 1.6),
			CFrame = roofCFrame * CFrame.new(offsetX, -0.3, -6.4),
			Color = if index % 2 == 0 then style.stripe else Color3.fromRGB(242, 240, 234),
			Material = Enum.Material.Fabric,
		})
	end

	local sign = Build.block(model, {
		Name = "Sign",
		Size = Vector3.new(11, 2.4, 0.4),
		CFrame = base * CFrame.new(0, 8, -3.2),
		Color = Color3.fromRGB(42, 46, 56),
		Material = Enum.Material.Wood,
	})

	Build.signFace(sign, Enum.NormalId.Front, style.title, style.subtitle, style.accent)

	local lamp = Build.block(model, {
		Name = "Lamp",
		Size = Vector3.new(1.1, 0.5, 1.1),
		CFrame = base * CFrame.new(0, 5.6, -2.4),
		Color = Color3.fromRGB(255, 232, 178),
		Material = Enum.Material.Neon,
	})

	local light = Instance.new("PointLight")
	light.Brightness = 1.6
	light.Range = 22
	light.Color = Color3.fromRGB(255, 226, 176)
	light.Shadows = false
	light.Parent = lamp
end

local function buildCrate(model: Model, cframe: CFrame, size: number)
	Build.block(model, {
		Name = "Crate",
		Size = Vector3.new(size, size, size),
		CFrame = cframe,
		Color = Color3.fromRGB(158, 118, 76),
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
	})
end

local function buildBarrel(model: Model, cframe: CFrame)
	Build.cylinder(model, {
		Name = "Barrel",
		Size = Vector3.new(2.6, 1.9, 1.9),
		-- Cylinder w Robloxie leży wzdłuż osi X, więc stawiamy go obrotem
		-- wokół Z. Bez tego beczka leży na boku.
		CFrame = cframe * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(122, 86, 56),
		Material = Enum.Material.Wood,
		CanCollide = true,
	})
end

local function buildFishBuyerProps(model: Model, base: CFrame)
	-- Lód na ladzie i ryby na nim — od razu widać, co to za stoisko,
	-- bez czytania szyldu.
	Build.block(model, {
		Name = "Ice",
		Size = Vector3.new(9, 0.25, 1.8),
		CFrame = base * CFrame.new(0, 3.3, -4.1),
		Color = Color3.fromRGB(198, 230, 240),
		Material = Enum.Material.Ice,
		Transparency = 0.25,
	})

	local display = {
		Color3.fromRGB(176, 128, 72),
		Color3.fromRGB(122, 136, 150),
		Color3.fromRGB(232, 132, 110),
		Color3.fromRGB(88, 124, 96),
	}

	for index, color in display do
		Build.sphere(model, {
			Name = "DisplayFish",
			Size = Vector3.new(1.9, 0.7, 0.55),
			CFrame = base
				* CFrame.new(-3.6 + (index - 1) * 2.4, 3.6, -4.1)
				* CFrame.Angles(0, math.rad(12 * index), 0),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
		})
	end

	buildCrate(model, base * CFrame.new(-5.4, 1.2, 2.6), 1.9)
	buildCrate(model, base * CFrame.new(-5.4, 3, 2.6), 1.6)
	buildBarrel(model, base * CFrame.new(5.2, 1.5, 2.4))
end

local function buildRodShopProps(model: Model, base: CFrame)
	-- Stojak z wędkami na ścianie za ladą.
	Build.block(model, {
		Name = "RackBar",
		Size = Vector3.new(10, 0.3, 0.3),
		CFrame = base * CFrame.new(0, 4.4, 4.3),
		Color = WOOD_DARK,
		Material = Enum.Material.Wood,
	})

	local rodColors = {
		Color3.fromRGB(141, 102, 60),
		Color3.fromRGB(72, 86, 102),
		Color3.fromRGB(38, 40, 46),
		Color3.fromRGB(196, 158, 72),
	}

	for index, color in rodColors do
		Build.block(model, {
			Name = "DisplayRod",
			Size = Vector3.new(0.18, 5.2, 0.18),
			CFrame = base
				* CFrame.new(-3.6 + (index - 1) * 2.4, 3.1, 4.1)
				* CFrame.Angles(math.rad(8), 0, 0),
			Color = color,
			Material = Enum.Material.Wood,
		})
	end

	buildCrate(model, base * CFrame.new(5.4, 1.2, 2.6), 1.9)
	buildBarrel(model, base * CFrame.new(-5.2, 1.5, 2.4))
end

local function buildStall(
	parent: Instance,
	position: Vector3,
	style: StallStyle,
	props: (Model, CFrame) -> ()
): BasePart
	-- Gracz przychodzi od strony placu, czyli od +Z. `lookAt` ustawia
	-- lokalne -Z (czyli Enum.NormalId.Front) dokładnie w jego stronę.
	local base = CFrame.lookAt(position, position + Vector3.new(0, 0, 1))

	local model = Build.model(parent, style.title)
	local counter = buildStallShell(model, base, style)
	buildRoof(model, base, style)
	props(model, base)

	counter:SetAttribute(GameConfig.STAND_ATTRIBUTE, style.standKind)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = style.promptAction
	prompt.ObjectText = style.title
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 12
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter

	return counter
end

-- ---------------------------------------------------------------------------

export type Stands = {
	fishBuyer: BasePart,
	rodShop: BasePart,
}

function Market.build(parent: Instance): Stands
	local market = Build.model(parent, "Market")

	buildPlaza(market)

	local fishBuyer = buildStall(market, FISH_BUYER_POSITION, {
		accent = Color3.fromRGB(86, 164, 128),
		stripe = Color3.fromRGB(64, 142, 110),
		title = "Skup ryb",
		subtitle = "Sprzedaj cały połów",
		promptAction = "Sprzedaj ryby",
		standKind = GameConfig.STAND_FISH_BUYER,
	}, buildFishBuyerProps)

	local rodShop = buildStall(market, ROD_SHOP_POSITION, {
		accent = Color3.fromRGB(214, 160, 76),
		stripe = Color3.fromRGB(196, 132, 58),
		title = "Sklep wędkarski",
		subtitle = "Lepsza wędka = rzadsze ryby",
		promptAction = "Otwórz sklep",
		standKind = GameConfig.STAND_ROD_SHOP,
	}, buildRodShopProps)

	return { fishBuyer = fishBuyer, rodShop = rodShop }
end

return table.freeze(Market)
