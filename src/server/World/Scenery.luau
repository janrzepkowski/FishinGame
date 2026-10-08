--!strict
--[[
	Scenery — drzewa, kamienie i trzciny wokół jeziora.

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

local AREA_X = 205
local AREA_Z_MIN = -250
local AREA_Z_MAX = 120

local TRUNK = Color3.fromRGB(96, 70, 48)
local FOLIAGE = {
	Color3.fromRGB(72, 122, 64),
	Color3.fromRGB(88, 140, 74),
	Color3.fromRGB(62, 106, 58),
	Color3.fromRGB(104, 152, 82),
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
	local height = generator:NextNumber(7, 13)
	local lean = generator:NextNumber(-0.06, 0.06)
	local base = CFrame.new(x, 0, z) * CFrame.Angles(lean, generator:NextNumber(0, 6.28), lean)

	Build.cylinder(parent, {
		Name = "Trunk",
		Size = Vector3.new(height, 1.1, 1.1),
		-- Walec w Robloxie leży wzdłuż osi X — obrót wokół Z stawia go pionowo.
		CFrame = base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = TRUNK,
		Material = Enum.Material.Wood,
		CanCollide = true,
	})

	local crownColor = FOLIAGE[generator:NextInteger(1, #FOLIAGE)]

	for layer = 1, 3 do
		local radius = generator:NextNumber(4.2, 6) * (1 - (layer - 1) * 0.22)
		Build.sphere(parent, {
			Name = "Crown",
			Size = Vector3.new(radius * 2, radius * 1.5, radius * 2),
			CFrame = base * CFrame.new(
				generator:NextNumber(-0.8, 0.8),
				height * 0.78 + (layer - 1) * radius * 0.55,
				generator:NextNumber(-0.8, 0.8)
			),
			Color = crownColor,
			Material = Enum.Material.Grass,
		})
	end
end

local function buildRock(parent: Instance, generator: Random, x: number, z: number)
	local size = generator:NextNumber(1.6, 4.4)
	Build.sphere(parent, {
		Name = "Rock",
		Size = Vector3.new(size * 1.3, size, size * 1.1),
		-- Wtopione w grunt na jakąś trzecią wysokości — kula leżąca
		-- na trawie wygląda jak piłka, nie jak głaz.
		CFrame = CFrame.new(x, size * 0.18, z) * CFrame.Angles(
			generator:NextNumber(0, 0.4),
			generator:NextNumber(0, 6.28),
			generator:NextNumber(0, 0.4)
		),
		Color = Color3.fromRGB(126, 128, 132),
		Material = Enum.Material.Slate,
		CanCollide = true,
	})
end

local function buildReeds(parent: Instance, generator: Random, x: number, z: number)
	local count = generator:NextInteger(4, 8)

	for _ = 1, count do
		local height = generator:NextNumber(2, 4.2)
		Build.block(parent, {
			Name = "Reed",
			Size = Vector3.new(0.16, height, 0.16),
			CFrame = CFrame.new(
				x + generator:NextNumber(-1.8, 1.8),
				height / 2 - 0.6,
				z + generator:NextNumber(-1.8, 1.8)
			) * CFrame.Angles(
				generator:NextNumber(-0.18, 0.18),
				0,
				generator:NextNumber(-0.18, 0.18)
			),
			Color = Color3.fromRGB(118, 142, 78),
			Material = Enum.Material.Grass,
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
end

return table.freeze(Scenery)
