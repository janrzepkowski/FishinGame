--!strict
--[[
	WorldBuilder — mapa budowana z kodu.

	Dlaczego z kodu, a nie w Studio:
	Plik .rbxl jest binarny. Gdy dwie osoby edytują mapę w Studio i obie
	zacommitują plik, git nie umie tego zmergować — ktoś odtwarza swoją pracę
	ręcznie. Dopóki mapa to greybox (woda + pomost + dwa stoiska), kod jest
	tańszy: merguje się jak tekst i widać go na PR-ze.

	Gdy dojdzie do prawdziwego level designu:
	  1. zróbcie model w Studio,
	  2. File -> Export Selection -> assets/Map.rbxm,
	  3. w default.project.json, pod "Workspace":
	       "Map": { "$path": "assets/Map.rbxm" }
	  4. ten moduł zostawcie tylko do wystawiania punktów zaczepienia
	     (`getWater`, `getFishBuyer`, `getRodShop`) — znajdowanych po nazwie
	     w zaimportowanym modelu.
	Plik .rbxm ma jednego właściciela i zmienia się rzadko, więc jest OK w repo.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)

local WorldBuilder = {}

-- ---------------------------------------------------------------------------
-- Układ poziomu
-- ---------------------------------------------------------------------------
-- Woda wystaje 0,25 studa nad baseplate i jest półprzezroczysta, więc czytamy
-- ją jako płyciznę nad dnem. To greybox — nie walczymy tu o urodę.
local WATER_SIZE = Vector3.new(180, 6.25, 180)
local WATER_CENTER = Vector3.new(0, -2.875, -140)

-- Pomost startuje na brzegu i wychodzi nad wodę.
local SHORE_Z = -40
local DOCK_LENGTH = 48
local DOCK_WIDTH = 8
-- 1,2 studa, nie 3. Humanoid w Robloxie wchodzi na przeszkodę wysoką do ~2
-- studów; przy pokładzie na 3,25 gracz stałby obok pomostu i nie mógł na niego
-- wejść. Przy 1,45 (1,2 + połowa grubości deski) wchodzi się bez schodków,
-- a pokład nadal jest wyraźnie nad lustrem wody (0,25).
local DOCK_HEIGHT = 1.2
local PLANK_THICKNESS = 0.5
local PLANK_LENGTH = 6

-- Płyta spawnu leży na baseplate (góra baseplate to y = 0), nie wisi nad nim.
-- Przy y = 4,5 gracz spadałby po zejściu z płyty.
local SPAWN_POSITION = Vector3.new(0, 0.5, 24)
local FISH_BUYER_POSITION = Vector3.new(-16, 2.5, 10)
local ROD_SHOP_POSITION = Vector3.new(16, 2.5, 10)

local CONTAINER_NAME = "World"

local water: BasePart? = nil
local fishBuyer: BasePart? = nil
local rodShop: BasePart? = nil

-- ---------------------------------------------------------------------------
-- Pomocnicze
-- ---------------------------------------------------------------------------

local function makePart(name: string, size: Vector3, position: Vector3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function makeLabel(text: string, subtitle: string, adornee: BasePart)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(220, 60)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 120
	billboard.Adornee = adornee

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.58)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Text = text
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeTransparency = 0.4
	title.Parent = billboard

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.Size = UDim2.fromScale(1, 0.42)
	hint.Position = UDim2.fromScale(0, 0.58)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextScaled = true
	hint.Text = subtitle
	hint.TextColor3 = Color3.fromRGB(205, 212, 222)
	hint.TextStrokeTransparency = 0.6
	hint.Parent = billboard

	billboard.Parent = adornee
end

local function makePrompt(
	actionText: string,
	keyCode: Enum.KeyCode,
	parent: BasePart
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = parent.Name
	prompt.KeyboardKeyCode = keyCode
	prompt.MaxActivationDistance = 12
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
end

-- ---------------------------------------------------------------------------
-- Budowa
-- ---------------------------------------------------------------------------

local function buildWater(parent: Instance): BasePart
	local part = makePart("Water", WATER_SIZE, WATER_CENTER, parent)
	part.Material = Enum.Material.Glass
	part.Color = Color3.fromRGB(46, 104, 138)
	part.Transparency = 0.42
	part.Reflectance = 0.12
	-- Gracz ma łowić z brzegu/pomostu, nie wchodzić do wody.
	part.CanCollide = true
	return part
end

local function buildDock(parent: Instance)
	local dock = Instance.new("Folder")
	dock.Name = "Dock"
	dock.Parent = parent

	local plankCount = math.ceil(DOCK_LENGTH / PLANK_LENGTH)

	for index = 1, plankCount do
		local centerZ = SHORE_Z - (index - 0.5) * PLANK_LENGTH
		local plank = makePart(
			`Plank{index}`,
			Vector3.new(DOCK_WIDTH, PLANK_THICKNESS, PLANK_LENGTH - 0.15),
			Vector3.new(0, DOCK_HEIGHT, centerZ),
			dock
		)
		plank.Material = Enum.Material.WoodPlanks
		-- Deski naprzemiennie jaśniejsze/ciemniejsze — bez tego pomost jest
		-- jedną wielką plamą i nie widać, gdzie się kończy.
		plank.Color = if index % 2 == 0
			then Color3.fromRGB(152, 114, 76)
			else Color3.fromRGB(138, 102, 66)

		-- Słupki tylko co drugą deskę — i tak ich nie widać, a to połowa części.
		if index % 2 == 1 then
			for _, side in { -1, 1 } do
				-- Słupek sięga poniżej dna pokładu i wystaje nad niego ~0,45
				-- studa, więc czyta się jako pal do wiązania łódki. Celowo
				-- nisko: wyższe byłyby barierką i zasłaniałyby wodę.
				local post = makePart(
					`Post{index}{side}`,
					Vector3.new(0.6, 5, 0.6),
					Vector3.new(side * (DOCK_WIDTH / 2 - 0.4), DOCK_HEIGHT - 1.8, centerZ),
					dock
				)
				post.Material = Enum.Material.Wood
				post.Color = Color3.fromRGB(104, 76, 50)
			end
		end
	end
end

local function buildStand(
	name: string,
	position: Vector3,
	color: Color3,
	parent: Instance
): BasePart
	local stand = makePart(name, Vector3.new(6, 5, 3), position, parent)
	stand.Material = Enum.Material.WoodPlanks
	stand.Color = color

	local roof =
		makePart("Roof", Vector3.new(7.5, 0.4, 4.5), position + Vector3.new(0, 3, 0), stand)
	roof.Material = Enum.Material.Slate
	roof.Color = Color3.fromRGB(72, 78, 88)

	return stand
end

local function buildSpawn(parent: Instance)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = SPAWN_POSITION
	spawn.Anchored = true
	spawn.Material = Enum.Material.Pavement
	spawn.Color = Color3.fromRGB(132, 138, 146)
	spawn.Duration = 0
	spawn.Parent = parent
end

--[[
	Buduje mapę. Idempotentne — ponowne wywołanie kasuje stary świat i stawia
	nowy. Dzięki temu Rojo może wgrać zmianę w tym pliku bez restartu serwera.
]]
function WorldBuilder.build()
	local existing = Workspace:FindFirstChild(CONTAINER_NAME)
	if existing then
		existing:Destroy()
	end

	local container = Instance.new("Folder")
	container.Name = CONTAINER_NAME
	container.Parent = Workspace

	water = buildWater(container)
	buildDock(container)
	buildSpawn(container)

	local buyer =
		buildStand("Skup ryb", FISH_BUYER_POSITION, Color3.fromRGB(94, 118, 92), container)
	buyer:SetAttribute(GameConfig.STAND_ATTRIBUTE, GameConfig.STAND_FISH_BUYER)
	makeLabel("Skup ryb", "Sprzedaj cały połów", buyer)
	makePrompt("Sprzedaj ryby", Enum.KeyCode.E, buyer)
	fishBuyer = buyer

	local shop =
		buildStand("Sklep wędkarski", ROD_SHOP_POSITION, Color3.fromRGB(118, 104, 82), container)
	shop:SetAttribute(GameConfig.STAND_ATTRIBUTE, GameConfig.STAND_ROD_SHOP)
	makeLabel("Sklep wędkarski", "Kup lepszą wędkę", shop)
	makePrompt("Otwórz sklep", Enum.KeyCode.E, shop)
	rodShop = shop
end

-- ---------------------------------------------------------------------------
-- Punkty zaczepienia dla serwisów
-- ---------------------------------------------------------------------------
-- Zwracają `nil` przed `build()`. Wywołujący MUSI to obsłużyć — serwis nie ma
-- prawa wywalić serwera tylko dlatego, że ktoś pozmieniał kolejność startu.

function WorldBuilder.getWater(): BasePart?
	return water
end

function WorldBuilder.getFishBuyer(): BasePart?
	return fishBuyer
end

function WorldBuilder.getRodShop(): BasePart?
	return rodShop
end

return WorldBuilder
