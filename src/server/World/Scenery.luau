--!strict
--[[
	Scenery — drzewa, kamienie, trzciny, kwiatki i grzybki wokół jeziora.

	Rozstawienie jest LOSOWE, ale DETERMINISTYCZNE: `Random.new(SEED)` zamiast
	globalnego `math.random`. Przy losowym ziarnie każdy serwer i każdy test
	w Studio miałby inny las, a zgłoszenie „stoję przy drzewie i nie mogę
	zarzucić" przestałoby cokolwiek znaczyć. Zmiana SEED = nowy, ale nadal
	powtarzalny układ.

	Rozstawiamy metodą odrzucania: losujemy punkt i sprawdzamy, czy nie wpada
	na wodę, plac, ścieżkę albo pomost. Prościej niż liczyć dozwolony obszar
	analitycznie, a przy ~130 obiektach koszt jest bez znaczenia.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LakeConfig = require(ReplicatedStorage.Shared.Config.Lake)

local Build = require(script.Parent.Build)

local Scenery = {}

local SEED = 20261008

local TREE_COUNT = 58
local ROCK_COUNT = 34
local REED_CLUMPS = 26
local FLOWER_PATCHES = 46
local MUSHROOMS = 18

local AREA_X = 205
local AREA_Z_MIN = -250
local AREA_Z_MAX = 120

--[[
	Paleta CUKIERKOWA. Gra jest dla dzieci, a referencją są jasne,
	zabawkowe światy z gier na Robloxie: soczysta zieleń, korony jak
	lizaki, co któreś drzewo kwitnie na różowo. Przygaszona, „leśna"
	paleta z poprzedniej wersji gryzła się z kolorowym interfejsem.
]]
local TRUNK = Color3.fromRGB(196, 128, 86)
local FOLIAGE = {
	Color3.fromRGB(96, 206, 92),
	Color3.fromRGB(124, 222, 100),
	Color3.fromRGB(72, 190, 110),
	Color3.fromRGB(150, 230, 96),
}
-- Kwitnące drzewa: rzadziej niż zielone, żeby las nie zamienił się w watę.
local BLOSSOM = {
	Color3.fromRGB(255, 160, 200),
	Color3.fromRGB(255, 196, 120),
	Color3.fromRGB(196, 160, 255),
}
local FLOWERS = {
	Color3.fromRGB(255, 92, 120),
	Color3.fromRGB(255, 214, 64),
	Color3.fromRGB(156, 120, 255),
	Color3.fromRGB(80, 180, 255),
	Color3.fromRGB(255, 255, 255),
}

--[[
	Miejsca, w których nic nie stawiamy — bo tam chodzi gracz.

	Drzewo na ścieżce albo przy ladzie nie jest tylko brzydkie: blokuje
	ProximityPrompt i wygląda jak bug.
]]
local function isReserved(x: number, z: number): boolean
	local plaza = math.abs(x) <= 32 and z >= -14 and z <= 40
	local path = math.abs(x) <= 11 and z >= -42 and z <= -10
	local dock = math.abs(x) <= 15 and z <= -28
	return plaza or path or dock
end

local function buildTree(parent: Instance, generator: Random, x: number, z: number)
	local height = generator:NextNumber(7, 12)
	local lean = generator:NextNumber(-0.05, 0.05)
	local base = CFrame.new(x, 0, z) * CFrame.Angles(lean, generator:NextNumber(0, 6.28), lean)
	local trunkWidth = generator:NextNumber(1.1, 1.5)

	Build.cylinder(parent, {
		Name = "Trunk",
		Size = Vector3.new(height, trunkWidth, trunkWidth),
		-- Walec w Robloxie leży wzdłuż osi X — obrót wokół Z stawia go pionowo.
		CFrame = base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = TRUNK,
		CanCollide = true,
	})

	-- Zaokrąglona stopa pnia — drzewo „stoi", zamiast być wbitym kołkiem.
	Build.ellipsoid(parent, {
		Name = "TrunkBase",
		Size = Vector3.new(trunkWidth * 2, trunkWidth * 0.9, trunkWidth * 2),
		CFrame = base * CFrame.new(0, 0.1, 0),
		Color = TRUNK:Lerp(Color3.new(0, 0, 0), 0.12),
	})

	local blossom = generator:NextNumber() < 0.22
	local palette = if blossom then BLOSSOM else FOLIAGE
	local crownColor = palette[generator:NextInteger(1, #palette)]

	-- Korona: jedna duża elipsoida i dwie mniejsze „chmurki" po bokach.
	-- Elipsoidy, nie kule — `Ball` wymusza równe wymiary i wcześniej każda
	-- „spłaszczona" korona i tak wychodziła kulą.
	local radius = generator:NextNumber(4.4, 6)
	Build.ellipsoid(parent, {
		Name = "Crown",
		Size = Vector3.new(radius * 2.1, radius * 1.7, radius * 2.1),
		CFrame = base * CFrame.new(0, height + radius * 0.35, 0),
		Color = crownColor,
	})

	for _, side in { -1, 1 } do
		local puff = radius * generator:NextNumber(0.55, 0.75)
		Build.ellipsoid(parent, {
			Name = "CrownPuff",
			Size = Vector3.new(puff * 2, puff * 1.7, puff * 2),
			CFrame = base
				* CFrame.new(side * radius * 0.85, height - puff * 0.1, generator:NextNumber(-1, 1)),
			Color = crownColor:Lerp(Color3.new(1, 1, 1), 0.08),
		})
	end

	-- Kwitnące drzewa dostają „owoce" — kilka kolorowych kulek na koronie.
	if blossom then
		for _ = 1, 5 do
			local angle = generator:NextNumber(0, math.pi * 2)
			Build.sphere(parent, {
				Name = "Fruit",
				Size = Vector3.one * 0.9,
				CFrame = base * CFrame.new(
					math.cos(angle) * radius * 0.95,
					height + generator:NextNumber(-0.5, radius * 0.6),
					math.sin(angle) * radius * 0.95
				),
				Color = FLOWERS[generator:NextInteger(1, 2)],
			})
		end
	end
end

local function buildRock(parent: Instance, generator: Random, x: number, z: number)
	local size = generator:NextNumber(1.6, 4.4)
	local rock = Build.ellipsoid(parent, {
		Name = "Rock",
		Size = Vector3.new(size * 1.4, size, size * 1.15),
		-- Wtopione w grunt na jakąś trzecią wysokości — kamień leżący
		-- na trawie wygląda jak piłka, nie jak głaz.
		CFrame = CFrame.new(x, size * 0.18, z)
			* CFrame.Angles(0, generator:NextNumber(0, 6.28), generator:NextNumber(0, 0.25)),
		-- Pastelowy, lekko fioletowy szary — kamień z bajki, nie z kamieniołomu.
		Color = Color3.fromRGB(176, 180, 214)
			:Lerp(Color3.fromRGB(214, 206, 230), generator:NextNumber()),
		CanCollide = true,
	})
	rock.CanQuery = false
end

local function buildReeds(parent: Instance, generator: Random, x: number, z: number)
	local count = generator:NextInteger(4, 8)

	for _ = 1, count do
		local height = generator:NextNumber(2, 4.2)
		local tilt =
			CFrame.Angles(generator:NextNumber(-0.18, 0.18), 0, generator:NextNumber(-0.18, 0.18))
		local base = CFrame.new(
			x + generator:NextNumber(-1.8, 1.8),
			-0.6,
			z + generator:NextNumber(-1.8, 1.8)
		) * tilt

		Build.cylinder(parent, {
			Name = "Reed",
			Size = Vector3.new(height, 0.18, 0.18),
			CFrame = base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(110, 200, 90),
		})

		-- Pałka wodna na czubku — kształt, który każde dziecko zna z bajek.
		if generator:NextNumber() < 0.6 then
			Build.ellipsoid(parent, {
				Name = "Cattail",
				Size = Vector3.new(0.42, 1.1, 0.42),
				CFrame = base * CFrame.new(0, height - 0.3, 0),
				Color = Color3.fromRGB(176, 104, 70),
			})
		end
	end
end

--[[ Kępka kwiatków: kilka łodyżek z kolorowymi główkami. ]]
local function buildFlowers(parent: Instance, generator: Random, x: number, z: number)
	local color = FLOWERS[generator:NextInteger(1, #FLOWERS)]

	for _ = 1, generator:NextInteger(3, 6) do
		local px = x + generator:NextNumber(-1.6, 1.6)
		local pz = z + generator:NextNumber(-1.6, 1.6)
		local height = generator:NextNumber(0.8, 1.5)

		Build.block(parent, {
			Name = "Stem",
			Size = Vector3.new(0.12, height, 0.12),
			CFrame = CFrame.new(px, height / 2, pz),
			Color = Color3.fromRGB(90, 190, 80),
		})
		Build.sphere(parent, {
			Name = "Blossom",
			Size = Vector3.one * 0.7,
			CFrame = CFrame.new(px, height + 0.2, pz),
			Color = color,
		})
		Build.sphere(parent, {
			Name = "BlossomEye",
			Size = Vector3.one * 0.32,
			CFrame = CFrame.new(px, height + 0.45, pz),
			Color = Color3.fromRGB(255, 220, 70),
		})
	end
end

--[[ Muchomorek: czerwony kapelusz w białe kropki. ]]
local function buildMushroom(parent: Instance, generator: Random, x: number, z: number)
	local size = generator:NextNumber(1, 2.2)

	Build.cylinder(parent, {
		Name = "MushroomStem",
		Size = Vector3.new(size * 1.1, size * 0.55, size * 0.55),
		CFrame = CFrame.new(x, size * 0.55, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 244, 226),
	})

	local capCFrame = CFrame.new(x, size * 1.15, z)
	Build.ellipsoid(parent, {
		Name = "MushroomCap",
		Size = Vector3.new(size * 1.8, size * 0.9, size * 1.8),
		CFrame = capCFrame,
		Color = Color3.fromRGB(255, 72, 90),
	})

	for index = 1, 4 do
		local angle = index * math.pi / 2 + generator:NextNumber(-0.3, 0.3)
		Build.sphere(parent, {
			Name = "MushroomDot",
			Size = Vector3.one * size * 0.28,
			CFrame = capCFrame * CFrame.new(
				math.cos(angle) * size * 0.5,
				size * 0.25,
				math.sin(angle) * size * 0.5
			),
			Color = Color3.fromRGB(255, 255, 255),
		})
	end
end

--[[
	Losuje punkt spełniający `accept`. Po `attempts` nieudanych próbach
	zwraca nil zamiast kręcić się w nieskończoność — gdyby ktoś zawęził
	dozwolony obszar do zera, świat ma się zbudować bez lasu, a nie zawiesić
	start serwera.
]]
local function samplePoint(
	generator: Random,
	accept: (number, number) -> boolean,
	attempts: number
): (number?, number?)
	for _ = 1, attempts do
		local x = generator:NextNumber(-AREA_X, AREA_X)
		local z = generator:NextNumber(AREA_Z_MIN, AREA_Z_MAX)
		if accept(x, z) then
			return x, z
		end
	end
	return nil, nil
end

function Scenery.build(parent: Instance)
	local generator = Random.new(SEED)
	local scenery = Build.folder(parent, "Scenery")

	-- Drzewa: na lądzie, z zapasem od brzegu, żeby korona nie wisiała nad wodą.
	local onLand = function(x: number, z: number): boolean
		if isReserved(x, z) then
			return false
		end
		return LakeConfig.edgeDistance(Vector3.new(x, 0, z)) < -8
	end

	for _ = 1, TREE_COUNT do
		local x, z = samplePoint(generator, onLand, 24)
		if x and z then
			buildTree(scenery, generator, x, z)
		end
	end

	for _ = 1, ROCK_COUNT do
		local x, z = samplePoint(generator, onLand, 24)
		if x and z then
			buildRock(scenery, generator, x, z)
		end
	end

	-- Trzciny: dokładnie na linii brzegowej, po obu jej stronach.
	local atShore = function(x: number, z: number): boolean
		if isReserved(x, z) then
			return false
		end
		local edge = LakeConfig.edgeDistance(Vector3.new(x, 0, z))
		return edge > -5 and edge < 3
	end

	for _ = 1, REED_CLUMPS do
		local x, z = samplePoint(generator, atShore, 40)
		if x and z then
			buildReeds(scenery, generator, x, z)
		end
	end

	-- Kwiatki i grzybki: drobne, gęsto, blisko ścieżek — to one robią
	-- z zielonej płaszczyzny „łąkę z bajki".
	for _ = 1, FLOWER_PATCHES do
		local x, z = samplePoint(generator, onLand, 24)
		if x and z then
			buildFlowers(scenery, generator, x, z)
		end
	end

	for _ = 1, MUSHROOMS do
		local x, z = samplePoint(generator, onLand, 24)
		if x and z then
			buildMushroom(scenery, generator, x, z)
		end
	end
end

return table.freeze(Scenery)
