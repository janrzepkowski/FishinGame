--!strict
--[[
	Scenery — drzewa, krzaki, kamienie, kwiaty i roślinność jeziora.

	WSZYSTKO Z OKRĄGŁYCH BRYŁ. Drzewo to pień-walec i korona z kul, kamień
	to „pianka" (spłaszczona elipsoida), a nad łąką stoją wielkie lizaki.
	Wcześniej natura pochodziła z paczki low-poly (`assets/NaturePack.rbxm`)
	— jej kanciaste, ciemne siatki nie pasowały do cukierkowego świata
	i żadne przemalowanie tego nie zmieniało. Kule z `Build` są zaokrąglone
	z definicji, nie zależą od assetu i budują się też przy `rojo serve`.
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

	KOLIZJE: koliduje tylko to, o co gracz może się oprzeć — pnie i duże
	kamienie. Korony, krzaki i kwiaty nigdy: korona to kule zawieszone kilka
	metrów nad ziemią i z kolizją robiłaby niewidzialne ściany.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LakeConfig = require(ReplicatedStorage.Shared.Config.Lake)

local Build = require(script.Parent.Build)

local Scenery = {}

local C = Build.COLOR

local SEED = 20261008

local AREA_X = 205
local AREA_Z_MIN = -250
local AREA_Z_MAX = 120

local GROVE_COUNT = 16
local LOLLIPOP_COUNT = 9
local PINE_COUNT = 14
local ROCK_COUNT = 26
local MUSHROOM_PATCH_COUNT = 12
local MEADOW_PATCH_COUNT = 36
local REED_CLUMP_COUNT = 40
local SHORE_STONE_COUNT = 22
local LILY_COUNT = 26
local SEAWEED_PATCH_COUNT = 60
local BED_ROCK_COUNT = 30
local BUOY_COUNT = 8
local HILL_COUNT = 22

-- Korony: trzy zielenie i dwa „cukrowe" odcienie. Kępa bierze JEDEN kolor —
-- las, w którym każde drzewo jest inne, wygląda jak próbnik farb.
local CROWNS = { C.leaf, C.mint, C.lime, C.leaf, C.mint, C.pink, C.lilac }
local TRUNK = C.cocoa
local PEBBLES = { C.white, C.cream, C.lilac, C.sky, C.pink }
local BLOSSOMS = { C.rose, C.lemon, C.white, C.lilac, C.orange, C.sky }
local LOLLIPOPS = { C.rose, C.sky, C.grape, C.orange, C.aqua, C.lemon }
local REED = Color3.fromRGB(132, 214, 120)
-- Roślinność dna: chłodniejsza niż na lądzie, żeby pod wodą nie świeciła
-- jak trawnik.
local SEAWEED = {
	Color3.fromRGB(70, 196, 170),
	Color3.fromRGB(110, 210, 150),
	Color3.fromRGB(150, 130, 230),
}
local HILLS = {
	Color3.fromRGB(126, 214, 126),
	Color3.fromRGB(150, 226, 150),
	Color3.fromRGB(170, 232, 170),
}
local FAR_HILLS = { C.lilac, C.pink, C.sky, C.mint }

--[[
	Miejsca, w których nic nie stawiamy — bo tam chodzi gracz.

	Drzewo na ścieżce albo przy ladzie nie jest tylko brzydkie: blokuje
	ProximityPrompt i wygląda jak bug.
]]
local function isReserved(x: number, z: number): boolean
	local plaza = math.abs(x) <= 38 and z >= -20 and z <= 50
	local path = math.abs(x) <= 15 and z >= -44 and z <= -10
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

local function pick<T>(generator: Random, options: { T }): T
	return options[generator:NextInteger(1, #options)]
end

local function yaw(generator: Random): number
	return generator:NextNumber(0, math.pi * 2)
end

-- ---------------------------------------------------------------------------
-- Pojedyncze obiekty
-- ---------------------------------------------------------------------------

--[[ Drzewo „z waty": pień i korona z kilku kul. ]]
local function puffTree(parent: Instance, generator: Random, x: number, z: number, crown: Color3)
	local scale = generator:NextNumber(0.85, 1.35)
	local height = 7 * scale
	local base = CFrame.new(x, 0, z) * CFrame.Angles(0, yaw(generator), 0)

	Build.upright(parent, base * CFrame.new(0, height / 2 - 0.3, 0), 1.7 * scale, height, {
		Name = "Trunk",
		Color = TRUNK,
		CanCollide = true,
	})

	local main = 8.5 * scale
	Build.sphere(parent, {
		Name = "Crown",
		Size = Vector3.one * main,
		CFrame = base * CFrame.new(0, height + main * 0.25, 0),
		Color = crown,
	})

	-- Mniejsze kule dookoła: sylwetka chmurki zamiast jednej piłki.
	local lighter = crown:Lerp(Color3.new(1, 1, 1), 0.18)
	for index = 1, generator:NextInteger(2, 3) do
		local angle = index * 2.2 + generator:NextNumber(-0.4, 0.4)
		local size = main * generator:NextNumber(0.55, 0.72)
		Build.sphere(parent, {
			Name = "CrownPuff",
			Size = Vector3.one * size,
			CFrame = base * CFrame.new(
				math.cos(angle) * main * 0.42,
				height + main * generator:NextNumber(0.02, 0.3),
				math.sin(angle) * main * 0.42
			),
			Color = if index % 2 == 0 then lighter else crown,
		})
	end
end

--[[ Zaokrąglona choinka: trzy spłaszczone elipsoidy, coraz mniejsze. ]]
local function roundPine(parent: Instance, generator: Random, x: number, z: number, crown: Color3)
	local scale = generator:NextNumber(0.9, 1.5)
	local base = CFrame.new(x, 0, z)

	Build.upright(parent, base * CFrame.new(0, 2 * scale - 0.3, 0), 1.4 * scale, 4 * scale, {
		Name = "Trunk",
		Color = TRUNK,
		CanCollide = true,
	})

	for tier = 1, 3 do
		local width = (9 - tier * 2.1) * scale
		Build.ellipsoid(parent, {
			Name = "PineTier",
			Size = Vector3.new(width, 5 * scale, width),
			CFrame = base * CFrame.new(0, (3.2 + tier * 2.9) * scale, 0),
			Color = if tier == 2 then crown:Lerp(Color3.new(1, 1, 1), 0.14) else crown,
		})
	end
end

--[[ Wielki lizak: patyk i dwukolorowy krążek. Punkt orientacyjny łąki. ]]
local function lollipop(parent: Instance, generator: Random, x: number, z: number)
	local height = generator:NextNumber(11, 17)
	local disc = generator:NextNumber(6.5, 9)
	local color = pick(generator, LOLLIPOPS)
	local base = CFrame.new(x, 0, z) * CFrame.Angles(0, yaw(generator), 0)

	Build.upright(parent, base * CFrame.new(0, height / 2 - 0.3, 0), 0.7, height, {
		Name = "LollipopStick",
		Color = C.white,
		CanCollide = true,
	})

	-- Krążki stoją pionowo: oś walca (X) patrzy w bok, więc obracamy wokół Y.
	local face = base * CFrame.new(0, height + disc * 0.3, 0) * CFrame.Angles(0, math.rad(90), 0)
	local rings = { 1, 0.72, 0.44, 0.2 }
	for index, fraction in rings do
		Build.cylinder(parent, {
			Name = "LollipopRing",
			Size = Vector3.new(1.1 + index * 0.12, disc * fraction, disc * fraction),
			CFrame = face,
			Color = if index % 2 == 1 then color else C.white,
		})
	end
end

--[[ Krzak: trzy zrośnięte kule, czasem z kwiatkami. ]]
local function bush(parent: Instance, generator: Random, x: number, z: number, color: Color3)
	local size = generator:NextNumber(2.4, 3.8)
	for index = 1, 3 do
		local angle = index * 2.1
		local puff = size * generator:NextNumber(0.75, 1)
		Build.sphere(parent, {
			Name = "Bush",
			Size = Vector3.one * puff,
			Position = Vector3.new(
				x + math.cos(angle) * size * 0.4,
				puff * 0.3,
				z + math.sin(angle) * size * 0.4
			),
			Color = color,
			CastShadow = false,
		})
	end

	if generator:NextNumber() < 0.6 then
		local blossom = pick(generator, BLOSSOMS)
		for _ = 1, 4 do
			local angle = yaw(generator)
			Build.sphere(parent, {
				Name = "BushBlossom",
				Size = Vector3.one * 0.6,
				Position = Vector3.new(
					x + math.cos(angle) * size * 0.55,
					size * generator:NextNumber(0.5, 0.85),
					z + math.sin(angle) * size * 0.55
				),
				Color = blossom,
				CastShadow = false,
			})
		end
	end
end

--[[ Kamień-pianka: spłaszczona elipsoida wtopiona w grunt. ]]
local function pebble(
	parent: Instance,
	generator: Random,
	x: number,
	groundY: number,
	z: number,
	size: number,
	solid: boolean
)
	Build.ellipsoid(parent, {
		Name = "Pebble",
		Size = Vector3.new(size * 1.35, size * 0.8, size * 1.1),
		-- Wtopiony na jakąś jedną czwartą wysokości — leżący na trawie
		-- wygląda jak piłka, nie jak głaz.
		CFrame = CFrame.new(x, groundY + size * 0.2, z) * CFrame.Angles(0, yaw(generator), 0),
		Color = pick(generator, PEBBLES),
		CanCollide = solid,
		CastShadow = solid,
	})
end

--[[ Kwiatek: łodyżka, okrągły środek i wianek płatków-kulek. ]]
local function flower(parent: Instance, generator: Random, x: number, z: number, color: Color3)
	local height = generator:NextNumber(1.1, 1.9)

	Build.upright(parent, CFrame.new(x, height / 2, z), 0.16, height, {
		Name = "Stem",
		Color = REED,
		CastShadow = false,
	})
	Build.sphere(parent, {
		Name = "FlowerHeart",
		Size = Vector3.one * 0.5,
		Position = Vector3.new(x, height, z),
		Color = C.lemon,
		CastShadow = false,
	})
	for index = 1, 5 do
		local angle = index / 5 * math.pi * 2
		Build.sphere(parent, {
			Name = "Petal",
			Size = Vector3.one * 0.48,
			Position = Vector3.new(x + math.cos(angle) * 0.4, height, z + math.sin(angle) * 0.4),
			Color = color,
			CastShadow = false,
		})
	end
end

--[[ Muchomor: biała nóżka i kapelusz w kropki. ]]
local function mushroom(parent: Instance, generator: Random, x: number, z: number, color: Color3)
	local size = generator:NextNumber(1.4, 3.4)
	local stem = size * 0.9
	local base = CFrame.new(x, 0, z) * CFrame.Angles(0, yaw(generator), 0)

	Build.upright(parent, base * CFrame.new(0, stem / 2 - 0.1, 0), size * 0.45, stem, {
		Name = "MushroomStem",
		Color = C.cream,
		CanCollide = size > 2.4,
		CastShadow = false,
	})
	local cap = base * CFrame.new(0, stem, 0)
	Build.ellipsoid(parent, {
		Name = "MushroomCap",
		Size = Vector3.new(size * 1.5, size * 0.95, size * 1.5),
		CFrame = cap,
		Color = color,
	})
	for index = 1, 5 do
		local angle = index * 1.26
		Build.sphere(parent, {
			Name = "MushroomDot",
			Size = Vector3.one * size * 0.24,
			CFrame = cap
				* CFrame.new(math.cos(angle) * size * 0.5, size * 0.3, math.sin(angle) * size * 0.5),
			Color = C.white,
			CastShadow = false,
		})
	end
end

--[[ Trzcina: zielona łodyga, co druga z brązową „pałką" na czubku. ]]
local function reed(parent: Instance, generator: Random, x: number, groundY: number, z: number)
	local height = generator:NextNumber(2.4, 4.6)
	local stem = CFrame.new(x, groundY, z)
		* CFrame.Angles(generator:NextNumber(-0.12, 0.12), 0, generator:NextNumber(-0.12, 0.12))

	Build.upright(parent, stem * CFrame.new(0, height / 2, 0), 0.22, height, {
		Name = "Reed",
		Color = REED,
		CastShadow = false,
	})
	if generator:NextNumber() < 0.6 then
		Build.ellipsoid(parent, {
			Name = "Cattail",
			Size = Vector3.new(0.5, 1.2, 0.5),
			CFrame = stem * CFrame.new(0, height, 0),
			Color = C.cocoa,
			CastShadow = false,
		})
	end
end

--[[ Liść lilii: płaski krążek na tafli, czasem z kwiatem. ]]
local function lilyPad(parent: Instance, generator: Random, x: number, z: number)
	local size = generator:NextNumber(2.2, 3.8)
	-- Losowa wysokość: dwa liście, które na siebie zajdą, nie leżą wtedy
	-- w jednej płaszczyźnie i nie migoczą (z-fighting).
	local y = LakeConfig.SURFACE_Y + generator:NextNumber(0.04, 0.2)

	Build.upright(parent, CFrame.new(x, y, z), size, 0.12, {
		Name = "LilyPad",
		Color = pick(generator, { C.leaf, C.mint, C.lime }),
		CastShadow = false,
	})
	if generator:NextNumber() < 0.5 then
		Build.sphere(parent, {
			Name = "LilyFlower",
			Size = Vector3.one * size * 0.3,
			Position = Vector3.new(x, y + size * 0.12, z),
			Color = pick(generator, { C.pink, C.white, C.rose }),
			CastShadow = false,
		})
		Build.sphere(parent, {
			Name = "LilyHeart",
			Size = Vector3.one * size * 0.14,
			Position = Vector3.new(x, y + size * 0.24, z),
			Color = C.lemon,
			CastShadow = false,
		})
	end
end

--[[ Boja: czerwono-biała kula na wodzie. Wyznacza, dokąd sięga rzut. ]]
local function buoy(parent: Instance, x: number, z: number, color: Color3)
	local y = LakeConfig.SURFACE_Y
	Build.sphere(parent, {
		Name = "Buoy",
		Size = Vector3.one * 3,
		Position = Vector3.new(x, y + 0.5, z),
		Color = color,
	})
	Build.upright(parent, CFrame.new(x, y + 0.7, z), 3.06, 0.7, {
		Name = "BuoyBand",
		Color = C.white,
		CastShadow = false,
	})
	Build.upright(parent, CFrame.new(x, y + 2.6, z), 0.3, 1.6, {
		Name = "BuoyMast",
		Color = C.white,
		CastShadow = false,
	})
	Build.sphere(parent, {
		Name = "BuoyLight",
		Size = Vector3.one * 0.8,
		Position = Vector3.new(x, y + 3.6, z),
		Color = C.lemon,
		Material = Enum.Material.Neon,
		CastShadow = false,
	})
end

-- ---------------------------------------------------------------------------
-- Kompozycja
-- ---------------------------------------------------------------------------

--[[
	Kępa: kilka drzew jednego koloru, pod nimi krzaki i kamień albo grzyby.
]]
local function buildGrove(
	parent: Instance,
	generator: Random,
	centerX: number,
	centerZ: number,
	accept: (number, number) -> boolean
)
	local crown = pick(generator, CROWNS)
	local radius = generator:NextNumber(10, 16)
	local pines = generator:NextNumber() < 0.3

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

	for _ = 1, generator:NextInteger(3, 5) do
		local x, z = scatter(radius)
		if x and z then
			if pines then
				roundPine(parent, generator, x, z, crown)
			else
				puffTree(parent, generator, x, z, crown)
			end
		end
	end

	for _ = 1, generator:NextInteger(2, 4) do
		local x, z = scatter(radius + 4)
		if x and z then
			bush(parent, generator, x, z, crown:Lerp(Color3.new(1, 1, 1), 0.1))
		end
	end

	-- Jeden akcent na kępę. Więcej robi z lasu skład rekwizytów.
	local x, z = scatter(radius)
	if x and z then
		if generator:NextNumber() < 0.5 then
			mushroom(parent, generator, x, z, C.cherry)
		else
			pebble(parent, generator, x, 0, z, generator:NextNumber(2.4, 4), true)
		end
	end
end

--[[
	Dno jeziora: kępy wodorostów i kamienie.

	Jezioro bez dna to niebieska tafla — gracz, który wpadnie do wody albo
	spojrzy z pomostu w dół, ma zobaczyć, że pod spodem coś rośnie.

	WYSOKOŚĆ jest przycięta do głębokości: wodorost wystający ponad taflę
	na środku jeziora wyglądałby jak błąd. Pas pod pomostem zostaje pusty
	(`isReserved`), żeby nic nie przesłaniało spławika od spodu.
]]
local function buildLakeBed(scenery: Instance, generator: Random)
	-- Gładki teren rysuje dno pół woksela (2 study) ponad wypełnieniem —
	-- to samo zjawisko, co przy poziomie gruntu w `Ground`.
	local function bedY(depth: number): number
		return LakeConfig.SURFACE_Y - depth + 2
	end

	local function sampleBed(minDepth: number): (number?, number?, number?)
		for _ = 1, 40 do
			local angle = yaw(generator)
			local distance = math.sqrt(generator:NextNumber()) * LakeConfig.HALF_SIZE
			local x = LakeConfig.CENTER_X + math.cos(angle) * distance
			local z = LakeConfig.CENTER_Z + math.sin(angle) * distance
			local depth = LakeConfig.depthAt(Vector3.new(x, 0, z))
			if depth >= minDepth and not isReserved(x, z) then
				return x, z, depth
			end
		end
		return nil, nil, nil
	end

	for _ = 1, SEAWEED_PATCH_COUNT do
		local x, z, depth = sampleBed(8)
		if x and z and depth then
			local color = pick(generator, SEAWEED)
			-- Zapas 3 studów pod taflą.
			local tallest = math.clamp(depth - 5, 2.5, 12)

			for _ = 1, generator:NextInteger(3, 5) do
				local px = x + generator:NextNumber(-3, 3)
				local pz = z + generator:NextNumber(-3, 3)
				if LakeConfig.depthAt(Vector3.new(px, 0, pz)) == depth then
					local height = generator:NextNumber(tallest * 0.4, tallest)
					Build.ellipsoid(scenery, {
						Name = "Seaweed",
						Size = Vector3.new(0.9, height, 0.9),
						CFrame = CFrame.new(px, bedY(depth) + height / 2 - 0.4, pz)
							* CFrame.Angles(
								generator:NextNumber(-0.15, 0.15),
								0,
								generator:NextNumber(-0.15, 0.15)
							),
						Color = color,
						CastShadow = false,
					})
				end
			end
		end
	end

	for _ = 1, BED_ROCK_COUNT do
		local x, z, depth = sampleBed(8)
		if x and z and depth then
			pebble(scenery, generator, x, bedY(depth) - 0.4, z, generator:NextNumber(2, 5), false)
		end
	end
end

--[[
	Wzgórza na horyzoncie: wielkie kopuły wokół grywalnego obszaru.

	Płaski teren kończył się prostą kreską pod niebem. Kopuły zamykają
	widok miękką, falistą linią — bliżej zielone, dalej pastelowe jak
	góry we mgle. Stoją POZA obszarem scenerii, więc gracz do nich nie
	dochodzi i nie potrzebują kolizji.
]]
local function buildHills(scenery: Instance, generator: Random)
	local centerX, centerZ = 0, -65

	for index = 1, HILL_COUNT do
		local angle = (index - 1) / HILL_COUNT * math.pi * 2 + generator:NextNumber(-0.08, 0.08)
		local near = index % 2 == 0
		local distance = if near
			then generator:NextNumber(225, 250)
			else generator:NextNumber(300, 340)
		local width = if near
			then generator:NextNumber(110, 150)
			else generator:NextNumber(170, 230)
		local height = if near then generator:NextNumber(40, 64) else generator:NextNumber(90, 140)

		Build.ellipsoid(scenery, {
			Name = if near then "Hill" else "FarHill",
			Size = Vector3.new(width, height * 2, width * generator:NextNumber(0.8, 1.1)),
			-- Środek na poziomie gruntu: widać górną połowę elipsoidy.
			CFrame = CFrame.new(
				centerX + math.cos(angle) * distance * 1.05,
				-4,
				centerZ + math.sin(angle) * distance * 1.2
			) * CFrame.Angles(0, yaw(generator), 0),
			Color = if near then pick(generator, HILLS) else pick(generator, FAR_HILLS),
			CastShadow = false,
		})
	end
end

local function buildLand(scenery: Instance, generator: Random)
	-- Drzewa: na lądzie, z zapasem od brzegu, żeby korona nie wisiała nad wodą.
	local inland = function(x: number, z: number): boolean
		return not isReserved(x, z) and edgeAt(x, z) < -14
	end
	local onLand = function(x: number, z: number): boolean
		return not isReserved(x, z) and edgeAt(x, z) < -7
	end

	for _ = 1, GROVE_COUNT do
		local x, z = samplePoint(generator, inland, 24)
		if x and z then
			buildGrove(scenery, generator, x, z, onLand)
		end
	end

	for _ = 1, PINE_COUNT do
		local x, z = samplePoint(generator, inland, 24)
		if x and z then
			roundPine(scenery, generator, x, z, pick(generator, { C.leaf, C.mint }))
		end
	end

	for _ = 1, LOLLIPOP_COUNT do
		local x, z = samplePoint(generator, inland, 24)
		if x and z then
			lollipop(scenery, generator, x, z)
		end
	end

	for _ = 1, ROCK_COUNT do
		local x, z = samplePoint(generator, onLand, 24)
		if x and z then
			pebble(scenery, generator, x, 0, z, generator:NextNumber(1.4, 3.6), true)
		end
	end

	for _ = 1, MUSHROOM_PATCH_COUNT do
		local x, z = samplePoint(generator, onLand, 24)
		if x and z then
			local color = pick(generator, { C.cherry, C.grape, C.orange })
			for _ = 1, generator:NextInteger(2, 4) do
				local px = x + generator:NextNumber(-3.5, 3.5)
				local pz = z + generator:NextNumber(-3.5, 3.5)
				if onLand(px, pz) then
					mushroom(scenery, generator, px, pz, color)
				end
			end
		end
	end

	-- Łąka: kwiaty w plamach jednego koloru, blisko miejsc, którędy gracz chodzi.
	for _ = 1, MEADOW_PATCH_COUNT do
		local x, z = samplePoint(generator, onLand, 24)
		if x and z then
			local blossom = pick(generator, BLOSSOMS)
			for _ = 1, generator:NextInteger(3, 6) do
				local px = x + generator:NextNumber(-4, 4)
				local pz = z + generator:NextNumber(-4, 4)
				if onLand(px, pz) then
					flower(scenery, generator, px, pz, blossom)
				end
			end
		end
	end
end

local function buildShore(scenery: Instance, generator: Random)
	-- Linia brzegowa: plaża tuż przy wodzie. Jezioro nie ma płycizny
	-- (najpłytsza półka to 8 studów), więc trzciny stoją na piasku.
	local onBeach = function(x: number, z: number): boolean
		local edge = edgeAt(x, z)
		return not isReserved(x, z) and edge > -6 and edge < -0.5
	end

	for _ = 1, REED_CLUMP_COUNT do
		local x, z = samplePoint(generator, onBeach, 40)
		if x and z then
			for _ = 1, generator:NextInteger(3, 6) do
				local px = x + generator:NextNumber(-2, 2)
				local pz = z + generator:NextNumber(-2, 2)
				if onBeach(px, pz) then
					reed(scenery, generator, px, -0.3, pz)
				end
			end
		end
	end

	for _ = 1, SHORE_STONE_COUNT do
		local x, z = samplePoint(generator, onBeach, 40)
		if x and z then
			for _ = 1, generator:NextInteger(1, 3) do
				pebble(
					scenery,
					generator,
					x + generator:NextNumber(-1.5, 1.5),
					-0.1,
					z + generator:NextNumber(-1.5, 1.5),
					generator:NextNumber(0.8, 1.8),
					false
				)
			end
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
			lilyPad(scenery, generator, x, z)
		end
	end

	-- Boje dalej od brzegu, też poza pasem pomostu.
	local open = function(x: number, z: number): boolean
		local edge = edgeAt(x, z)
		return not isReserved(x, z) and math.abs(x) > 26 and edge > 18 and edge < 40
	end

	for index = 1, BUOY_COUNT do
		local x, z = samplePoint(generator, open, 60)
		if x and z then
			buoy(scenery, x, z, if index % 2 == 0 then C.cherry else C.orange)
		end
	end
end

-- ---------------------------------------------------------------------------

function Scenery.build(parent: Instance)
	local generator = Random.new(SEED)
	local scenery = Build.folder(parent, "Scenery")

	buildLand(scenery, generator)
	buildShore(scenery, generator)
	buildLakeBed(scenery, generator)
	buildHills(scenery, generator)
end

return table.freeze(Scenery)
