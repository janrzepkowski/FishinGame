--!strict
--[[
	Scenery — drzewa, krzaki, kamienie i roślinność brzegowa wokół jeziora.

	Modele pochodzą z jednej paczki low-poly (`assets/NaturePack.rbxm`,
	w grze `ServerStorage.NaturePack`) — jednej, żeby cała natura miała tę
	samą rękę. Konstrukcje (stoiska, pomost) dalej stawia kod przez `Build`.
	Zasady: docs/art/ART_DIRECTION.md.

	Rozstawienie jest LOSOWE, ale DETERMINISTYCZNE: `Random.new(SEED)` zamiast
	globalnego `math.random`. Przy losowym ziarnie każdy serwer i każdy test
	w Studio miałby inny las, a zgłoszenie „stoję przy drzewie i nie mogę
	zarzucić" przestałoby cokolwiek znaczyć. Zmiana SEED = nowy, ale nadal
	powtarzalny układ.

	Rozstawiamy metodą odrzucania: losujemy punkt i sprawdzamy, czy nie wpada
	na wodę, plac, ścieżkę albo pomost. Prościej niż liczyć dozwolony obszar
	analitycznie, a przy kilkuset obiektach koszt jest bez znaczenia.

	KOMPOZYCJA, nie rozsypanka. Drzewa stoją w KĘPACH, a między kępami
	jest pusta łąka. Równomiernie rozrzucone drzewa czytają się jak szum —
	oko nie ma się na czym zatrzymać i mapa wygląda na pustą, choć drzew
	jest tyle samo.

	GDY PACZKI NIE MA albo jej siatki są puste, świat buduje się z prostych
	brył i wypisuje ostrzeżenie. Brak dekoracji nie może położyć serwera.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local LakeConfig = require(ReplicatedStorage.Shared.Config.Lake)

local Build = require(script.Parent.Build)

local Scenery = {}

local SEED = 20261008
local PACK_NAME = "NaturePack"

local AREA_X = 205
local AREA_Z_MIN = -250
local AREA_Z_MAX = 120

-- Plaża to niski wał piasku ponad poziomem trawy i wody (patrz
-- BEACH_TOP_OCCUPANCY w Ground). Rośliny brzegowe stoją na nim, nie w nim.
local BEACH_Y = 0.5

-- Kompozycja z paczki.
local GROVE_COUNT = 15
local LONE_TREE_COUNT = 9
local DEAD_TREE_COUNT = 5
local ROCK_COUNT = 22
local SHORE_STONE_COUNT = 20
local REED_CLUMP_COUNT = 44
local LILY_COUNT = 26
local MEADOW_PATCH_COUNT = 34

-- Układ awaryjny z prostych brył.
local FALLBACK_TREE_COUNT = 58
local FALLBACK_ROCK_COUNT = 34
local FALLBACK_REED_CLUMPS = 26

-- Paleta: docs/art/ART_DIRECTION.md. Zielenie roślinności są cieplejsze od
-- zieleni morskiej stoisk — ta jest zarezerwowana dla rzeczy zbudowanych
-- ręką człowieka.
local TRUNK = Color3.fromRGB(112, 82, 54)
local FOLIAGE = {
	Color3.fromRGB(82, 148, 62),
	Color3.fromRGB(98, 168, 70),
	Color3.fromRGB(70, 128, 58),
}
local REED_GREEN = Color3.fromRGB(104, 150, 72)
local LILY_GREEN = Color3.fromRGB(86, 156, 84)
local STONE = Color3.fromRGB(132, 136, 142)
local BLOSSOM = {
	Color3.fromRGB(240, 238, 232),
	Color3.fromRGB(232, 190, 96),
	Color3.fromRGB(196, 170, 222),
}

type Catalog = { [string]: Model }

--[[
	Jak traktować części sklonowanego modelu.

	`solid`  — czy pnie/kamienie mają kolidować. Korony NIGDY nie kolidują:
	           to one robiły kiedyś niewidzialne ściany w powietrzu.
	`shadow` — czy model rzuca cień. Drobnica nie rzuca: setki cieni po
	           trzcinach kosztują klatki i niczego nie dodają.
	`leaves` — kolor dla części roślinnych; nil zostawia barwę z paczki
	           przepuszczoną przez `accent`.
	`accent` — kolor dla wszystkiego, co nie jest drewnem ani zielenią
	           (kwiaty, owoce). Paczka ma tam czyste czerwienie i magenty,
	           a czerwień jest u nas zarezerwowana dla spławika.
]]
type Style = {
	solid: boolean,
	shadow: boolean,
	leaves: Color3?,
	accent: Color3?,
}

--[[
	Miejsca, w których nic nie stawiamy — bo tam chodzi gracz.

	Drzewo na ścieżce albo przy ladzie nie jest tylko brzydkie: blokuje
	ProximityPrompt i wygląda jak bug.
]]
local function isReserved(x: number, z: number): boolean
	local plaza = math.abs(x) <= 34 and z >= -16 and z <= 42
	local path = math.abs(x) <= 12 and z >= -44 and z <= -10
	local dock = math.abs(x) <= 16 and z <= -28
	return plaza or path or dock
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

local function edgeAt(x: number, z: number): number
	return LakeConfig.edgeDistance(Vector3.new(x, 0, z))
end

-- ---------------------------------------------------------------------------
-- Paczka modeli
-- ---------------------------------------------------------------------------

--[[
	Zbiera modele z paczki po nazwie. Zwraca nil, gdy paczki nie ma albo
	jest uszkodzona.

	Pusta siatka to realny przypadek, nie paranoja: wtyczka Rojo nie umie
	ustawić `MeshId` przy synchronizacji na żywo, więc `MeshPart` potrafi
	dojechać do Studio jako pusty klocek. `rojo build` robi to poprawnie.
]]
local function loadCatalog(): Catalog?
	local pack = ServerStorage:FindFirstChild(PACK_NAME)
	if not pack then
		warn(
			`[Scenery] brak ServerStorage.{PACK_NAME} — sceneria z prostych brył.\n`
				.. "  Paczka jest w assets/NaturePack.rbxm; zbuduj miejsce przez `rojo build`."
		)
		return nil
	end

	local catalog: Catalog = {}
	for _, descendant in pack:GetDescendants() do
		if descendant:IsA("Model") then
			catalog[descendant.Name] = descendant
		elseif descendant:IsA("MeshPart") and descendant.MeshId == "" then
			warn(
				`[Scenery] "{descendant:GetFullName()}" ma pustą siatkę — sceneria z prostych brył.\n`
					.. "  Rojo nie przenosi MeshId przy synchronizacji na żywo; użyj `rojo build`."
			)
			return nil
		end
	end

	return catalog
end

local function isWood(part: BasePart): boolean
	return part.Material == Enum.Material.Wood
end

local function isPlant(part: BasePart): boolean
	return part.Material == Enum.Material.LeafyGrass or part.Material == Enum.Material.Grass
end

--[[
	Stawia kopię modelu z paczki tak, żeby jego PODSTAWA stała na `groundY`.

	Modele mają pivot w różnych miejscach (część w środku bryły, część
	u podstawy), więc pozycjonujemy po obrysie, nie po pivocie — inaczej
	połowa drzew wisiałaby w powietrzu, a połowa siedziała po pas w ziemi.
]]
local function place(
	parent: Instance,
	catalog: Catalog,
	name: string,
	x: number,
	groundY: number,
	z: number,
	yaw: number,
	scale: number,
	style: Style
)
	local template = catalog[name]
	if not template then
		return
	end

	local model = template:Clone()
	model:ScaleTo(scale)

	local bounds, size = model:GetBoundingBox()
	local pivotInBounds = bounds:ToObjectSpace(model:GetPivot())
	local target = CFrame.new(x, groundY + size.Y / 2, z) * CFrame.Angles(0, yaw, 0)
	model:PivotTo(target * pivotInBounds)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = style.shadow

			if isWood(descendant) then
				descendant.Color = TRUNK
				descendant.CanCollide = style.solid
			elseif isPlant(descendant) then
				descendant.CanCollide = false
				if style.leaves then
					descendant.Color = style.leaves
				end
			else
				-- Kamień koliduje, kwiat nie.
				descendant.CanCollide = style.solid and descendant.Material == Enum.Material.Slate
				if descendant.Material == Enum.Material.Slate then
					descendant.Color = STONE
				elseif style.accent then
					descendant.Color = style.accent
				end
			end
		end
	end

	model.Parent = parent
end

local function pick<T>(generator: Random, options: { T }): T
	return options[generator:NextInteger(1, #options)]
end

local function yaw(generator: Random): number
	return generator:NextNumber(0, math.pi * 2)
end

--[[
	Kępa: kilka drzew, pod nimi krzaki, trawa i coś leżącego na ziemi.

	Wszystko w kępie dzieli jeden odcień zieleni. Las, w którym każde drzewo
	ma inny kolor, wygląda jak próbnik farb.
]]
local function buildGrove(
	parent: Instance,
	catalog: Catalog,
	generator: Random,
	centerX: number,
	centerZ: number,
	accept: (number, number) -> boolean
)
	local green = pick(generator, FOLIAGE)
	local radius = generator:NextNumber(9, 15)

	local function scatter(reach: number): (number?, number?)
		for _ = 1, 8 do
			local angle = yaw(generator)
			local distance = math.sqrt(generator:NextNumber()) * reach
			local x = centerX + math.cos(angle) * distance
			local z = centerZ + math.sin(angle) * distance
			if accept(x, z) then
				return x, z
			end
		end
		return nil, nil
	end

	for _ = 1, generator:NextInteger(3, 6) do
		local x, z = scatter(radius)
		if x and z then
			place(
				parent,
				catalog,
				pick(generator, { "Oak Tree", "Oak Tree", "Maple Tree" }),
				x,
				-0.3,
				z,
				yaw(generator),
				generator:NextNumber(1.7, 2.6),
				{ solid = true, shadow = true, leaves = green }
			)
		end
	end

	for _ = 1, generator:NextInteger(2, 4) do
		local x, z = scatter(radius + 3)
		if x and z then
			place(
				parent,
				catalog,
				pick(generator, { "Bush A", "Bush B" }),
				x,
				-0.1,
				z,
				yaw(generator),
				generator:NextNumber(1.3, 2),
				{ solid = false, shadow = true, leaves = green, accent = BLOSSOM[2] }
			)
		end
	end

	for _ = 1, generator:NextInteger(4, 8) do
		local x, z = scatter(radius + 5)
		if x and z then
			place(
				parent,
				catalog,
				pick(generator, { "Grass Tuft A", "Grass Tuft B" }),
				x,
				-0.1,
				z,
				yaw(generator),
				generator:NextNumber(1, 1.6),
				{ solid = false, shadow = false, leaves = green }
			)
		end
	end

	-- Jeden akcent na kępę: kłoda, pniak albo grzyby. Więcej robi z lasu
	-- skład drewna.
	local x, z = scatter(radius)
	if x and z then
		local accent = pick(generator, { "Log A", "Log B", "Stump A", "Stump B", "Mushroom B" })
		place(
			parent,
			catalog,
			accent,
			x,
			-0.15,
			z,
			yaw(generator),
			generator:NextNumber(1.1, 1.6),
			{ solid = accent ~= "Mushroom B", shadow = false, accent = BLOSSOM[1] }
		)
	end
end

local function buildFromPack(scenery: Instance, catalog: Catalog, generator: Random)
	-- Drzewa: na lądzie, z zapasem od brzegu, żeby korona nie wisiała nad wodą.
	local inland = function(x: number, z: number): boolean
		return not isReserved(x, z) and edgeAt(x, z) < -12
	end
	local onLand = function(x: number, z: number): boolean
		return not isReserved(x, z) and edgeAt(x, z) < -6
	end

	for _ = 1, GROVE_COUNT do
		local x, z = samplePoint(generator, inland, 24)
		if x and z then
			buildGrove(scenery, catalog, generator, x, z, onLand)
		end
	end

	for _ = 1, LONE_TREE_COUNT do
		local x, z = samplePoint(generator, inland, 24)
		if x and z then
			place(
				scenery,
				catalog,
				pick(generator, { "Oak Tree", "Maple Tree" }),
				x,
				-0.3,
				z,
				yaw(generator),
				generator:NextNumber(2, 2.9),
				{ solid = true, shadow = true, leaves = pick(generator, FOLIAGE) }
			)
		end
	end

	-- Suche drzewa tylko przy brzegu: sylwetka na tle wody, nie w lesie.
	local nearShore = function(x: number, z: number): boolean
		local edge = edgeAt(x, z)
		return not isReserved(x, z) and edge < -7 and edge > -22
	end

	for _ = 1, DEAD_TREE_COUNT do
		local x, z = samplePoint(generator, nearShore, 30)
		if x and z then
			place(
				scenery,
				catalog,
				pick(generator, { "Dead Tree A", "Dead Tree B" }),
				x,
				-0.3,
				z,
				yaw(generator),
				generator:NextNumber(1.6, 2.2),
				{ solid = true, shadow = true }
			)
		end
	end

	for _ = 1, ROCK_COUNT do
		local x, z = samplePoint(generator, onLand, 24)
		if x and z then
			place(
				scenery,
				catalog,
				pick(generator, { "Rock A", "Rock A", "Rock B" }),
				x,
				-0.35,
				z,
				yaw(generator),
				generator:NextNumber(1, 2.4),
				{ solid = true, shadow = true }
			)
		end
	end

	-- Łąka: kwiaty i trawa w plamach, blisko miejsc, którędy gracz chodzi.
	for _ = 1, MEADOW_PATCH_COUNT do
		local x, z = samplePoint(generator, onLand, 24)
		if x and z then
			local blossom = pick(generator, BLOSSOM)
			local flower = pick(generator, { "Daisy", "Sunflower", "Lavender", "Clover" })
			for _ = 1, generator:NextInteger(3, 6) do
				local px = x + generator:NextNumber(-4, 4)
				local pz = z + generator:NextNumber(-4, 4)
				if onLand(px, pz) then
					place(
						scenery,
						catalog,
						if generator:NextNumber() < 0.55 then flower else "Grass Tuft B",
						px,
						-0.05,
						pz,
						yaw(generator),
						generator:NextNumber(1, 1.5),
						{ solid = false, shadow = false, leaves = REED_GREEN, accent = blossom }
					)
				end
			end
		end
	end

	-- Linia brzegowa: plaża tuż przy wodzie. Jezioro nie ma płycizny
	-- (najpłytsza półka to 8 studów), więc trzciny stoją na piasku.
	local onBeach = function(x: number, z: number): boolean
		local edge = edgeAt(x, z)
		return not isReserved(x, z) and edge > -6 and edge < -0.5
	end

	for _ = 1, REED_CLUMP_COUNT do
		local x, z = samplePoint(generator, onBeach, 40)
		if x and z then
			for _ = 1, generator:NextInteger(2, 4) do
				local px = x + generator:NextNumber(-2.5, 2.5)
				local pz = z + generator:NextNumber(-2.5, 2.5)
				if onBeach(px, pz) then
					place(
						scenery,
						catalog,
						pick(generator, { "Reeds", "Cattails", "Cattails" }),
						px,
						BEACH_Y - 0.25,
						pz,
						yaw(generator),
						generator:NextNumber(1.2, 1.9),
						{ solid = false, shadow = false, leaves = REED_GREEN }
					)
				end
			end
		end
	end

	for _ = 1, SHORE_STONE_COUNT do
		local x, z = samplePoint(generator, onBeach, 40)
		if x and z then
			place(
				scenery,
				catalog,
				pick(generator, { "Shore Stones A", "Shore Stones B" }),
				x,
				BEACH_Y - 0.15,
				z,
				yaw(generator),
				generator:NextNumber(1.2, 2),
				{ solid = false, shadow = false }
			)
		end
	end

	-- Lilie na wodzie przy brzegu. Pas przed pomostem zostaje czysty
	-- (`isReserved`), żeby nic nie leżało tam, gdzie ląduje spławik.
	local shallows = function(x: number, z: number): boolean
		local edge = edgeAt(x, z)
		return not isReserved(x, z) and edge > 1.5 and edge < 11
	end

	for _ = 1, LILY_COUNT do
		local x, z = samplePoint(generator, shallows, 40)
		if x and z then
			place(
				scenery,
				catalog,
				pick(generator, { "Lily Pad A", "Lily Pad A", "Lily Pad B" }),
				x,
				LakeConfig.SURFACE_Y + 0.02,
				z,
				yaw(generator),
				generator:NextNumber(1.3, 2.2),
				{ solid = false, shadow = false, leaves = LILY_GREEN, accent = BLOSSOM[1] }
			)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Układ awaryjny: proste bryły
-- ---------------------------------------------------------------------------

local function fallbackTree(parent: Instance, generator: Random, x: number, z: number)
	local height = generator:NextNumber(7, 13)
	local lean = generator:NextNumber(-0.06, 0.06)
	local base = CFrame.new(x, 0, z) * CFrame.Angles(lean, yaw(generator), lean)

	Build.cylinder(parent, {
		Name = "Trunk",
		Size = Vector3.new(height, 1.1, 1.1),
		-- Walec w Robloxie leży wzdłuż osi X — obrót wokół Z stawia go pionowo.
		CFrame = base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = TRUNK,
		Material = Enum.Material.Wood,
		CanCollide = true,
	})

	local crownColor = pick(generator, FOLIAGE)

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
			Material = Enum.Material.LeafyGrass,
		})
	end
end

local function fallbackRock(parent: Instance, generator: Random, x: number, z: number)
	local size = generator:NextNumber(1.6, 4.4)
	Build.sphere(parent, {
		Name = "Rock",
		Size = Vector3.new(size * 1.3, size, size * 1.1),
		-- Wtopione w grunt na jakąś trzecią wysokości — kula leżąca
		-- na trawie wygląda jak piłka, nie jak głaz.
		CFrame = CFrame.new(x, size * 0.18, z) * CFrame.Angles(
			generator:NextNumber(0, 0.4),
			yaw(generator),
			generator:NextNumber(0, 0.4)
		),
		Color = STONE,
		Material = Enum.Material.Slate,
		CanCollide = true,
	})
end

local function fallbackReeds(parent: Instance, generator: Random, x: number, z: number)
	for _ = 1, generator:NextInteger(4, 8) do
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
			Color = REED_GREEN,
			Material = Enum.Material.Grass,
			CastShadow = false,
		})
	end
end

local function buildFallback(scenery: Instance, generator: Random)
	local onLand = function(x: number, z: number): boolean
		return not isReserved(x, z) and edgeAt(x, z) < -8
	end

	for _ = 1, FALLBACK_TREE_COUNT do
		local x, z = samplePoint(generator, onLand, 24)
		if x and z then
			fallbackTree(scenery, generator, x, z)
		end
	end

	for _ = 1, FALLBACK_ROCK_COUNT do
		local x, z = samplePoint(generator, onLand, 24)
		if x and z then
			fallbackRock(scenery, generator, x, z)
		end
	end

	local atShore = function(x: number, z: number): boolean
		local edge = edgeAt(x, z)
		return not isReserved(x, z) and edge > -5 and edge < 3
	end

	for _ = 1, FALLBACK_REED_CLUMPS do
		local x, z = samplePoint(generator, atShore, 40)
		if x and z then
			fallbackReeds(scenery, generator, x, z)
		end
	end
end

-- ---------------------------------------------------------------------------

function Scenery.build(parent: Instance)
	local generator = Random.new(SEED)
	local scenery = Build.folder(parent, "Scenery")

	local catalog = loadCatalog()
	if catalog then
		buildFromPack(scenery, catalog, generator)
	else
		buildFallback(scenery, generator)
	end
end

return table.freeze(Scenery)
