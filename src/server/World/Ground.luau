--!strict
--[[
	Ground — teren: ląd, plaża i zbiornik z prawdziwą wodą Robloxa.

	Dlaczego Terrain, a nie szklany Part:
	woda w Terrain to jedyna woda, którą silnik traktuje jak wodę. Dostajemy
	za darmo pływanie, wyporność, opór, animowane fale, załamanie światła
	i zmianę kamery pod powierzchnią. Part z Transparency = 0.4 był obrazkiem
	wody — gracz po nim chodził.

	Kształt dna bierzemy z `shared/Config/Lake`. To ten sam plik, z którego
	serwer liczy bonus za głębokość, a klient rysuje spławik i wskaźnik
	w HUD-zie — jedno źródło prawdy o kształcie jeziora.

	=========================================================================
	DLACZEGO JEZIORO NIE POWSTAJE PRZEZ FillBlock
	=========================================================================

	Bo woda w terenie Robloxa NIE JEST materiałem. Jest osobnym kanałem
	`LiquidOccupancy`, niezależnym od `SolidMaterial` i `SolidOccupancy`.
	`FillBlock(..., Enum.Material.Water)` próbuje to udawać i robi to
	niespójnie: wypełnienia materiałem stałym pomijają woksele z wodą,
	a wypełnienie wodą na istniejącym terenie potrafi nie zrobić nic.

	Ten plik przeszedł przez dwie wersje oparte na FillBlock i obie dały
	to samo: piaszczysta misa buduje się poprawnie, wody nie ma wcale.
	Objaw dla gracza — chodzenie po dnie i „bagno".

	Dlatego misę jeziora piszemy przez `WriteVoxelChannels`, woksel po
	wokselu, ustawiając JAWNIE:

	    poniżej dna      -> SolidMaterial = Sand, SolidOccupancy = 1
	    dno .. lustro    -> SolidOccupancy = 0,   LiquidOccupancy = 1
	    powyżej lustra   -> wszystko 0 (powietrze)

	Nie ma tu żadnej kolejności nadpisywania ani zgadywania, jak silnik
	pogodzi wodę z piaskiem — każdy woksel dostaje dokładnie to, co ma mieć.

	`FillBlock` zostaje tylko do lądu, gdzie żadna woda nie występuje
	i działa bez zarzutu.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LakeConfig = require(ReplicatedStorage.Shared.Config.Lake)

local Ground = {}

--[[
	Ląd sięga daleko poza jezioro, żeby horyzont nie kończył się urwiskiem.
	Musi sięgać poniżej BED_BOTTOM, inaczej pod dnem jeziora jest pustka.

	GÓRA WYPEŁNIENIA JEST NA y = -2, A NIE NA 0 — i to nie pomyłka.
	Gładki teren Robloxa rysuje powierzchnię (i kolizję) pół woksela PONAD
	w pełni zajętym wokselem. Wypełnienie do y = 0 dawało grunt na y = 2:
	bruk placu i podłogi stoisk siedziały 1,6 studa pod trawą, a plac był
	niewidoczny. Zmierzone raycastem: góra 0 -> grunt 2,00; góra -2 -> 0,02.
	Cała reszta mapy (plac, stoiska, pomost, sceneria) zakłada grunt na 0.
]]
local LAND_SIZE = Vector3.new(480, 48, 520)
local LAND_CENTER = Vector3.new(0, -26, -60)

-- Zajętość najwyższego woksela plaży. Z tego samego powodu co wyżej pełna
-- zajętość dawała plażę na y = 2; 0,5 to grunt na 0, a 0,625 zostawia
-- niski wał piasku (~0,5 studa) między trawą a wodą.
local BEACH_TOP_OCCUPANCY = 0.625

-- Pas piasku wokół lustra wody. Bez niego trawa wchodzi wprost do wody
-- i brzeg wygląda jak wycięty nożyczkami.
local BEACH_MARGIN = 12

-- Dno misy. Musi być poniżej najgłębszej półki, inaczej najgłębsze
-- wypełnienie wody nie miałoby pod sobą piasku.
local BED_BOTTOM = -44

-- Rozmiar woksela terenu. Wszystkie odczyty i wypełnienia są do niego
-- wyrównane — to nie jest liczba do zmieniania.
local VOXEL = 4

local function fill(center: Vector3, size: Vector3, material: Enum.Material)
	Workspace.Terrain:FillBlock(CFrame.new(center), size, material)
end

--[[
	Obszar misy jeziora: lustro wody plus pas plaży dookoła.

	Wyrównany do siatki wokseli. Sięga jeden woksel ponad lustro wody, żeby
	wyczyścić wszystko, co zostało tam po wypełnieniu lądu trawą.
]]
local function lakeRegion(): Region3
	local half = LakeConfig.HALF_SIZE + BEACH_MARGIN
	local cx, cz = LakeConfig.CENTER_X, LakeConfig.CENTER_Z

	return Region3.new(
		Vector3.new(cx - half, BED_BOTTOM, cz - half),
		Vector3.new(cx + half, LakeConfig.SURFACE_Y + VOXEL, cz + half)
	):ExpandToGrid(VOXEL)
end

--[[
	Zapisuje misę jeziora woksel po wokselu.

	Kształt dna bierze wprost z `LakeConfig.depthAt` — tej samej funkcji,
	którą serwer liczy bonus za głębokość, a klient wyświetla w HUD-zie.
	Teren nie może się więc rozjechać z konfiguracją: nie ma tu drugiej,
	równoległej definicji kształtu jeziora.

	Poza obrysem jeziora `depthAt` zwraca 0, więc piasek sięga do gruntu —
	to jest plaża. Wewnątrz powstaje woda od dna po lustro.
]]
local function writeLakeVoxels()
	local region = lakeRegion()
	local minCorner = region.CFrame.Position - region.Size / 2
	local counts = region.Size / VOXEL
	local sizeX = math.floor(counts.X + 0.5)
	local sizeY = math.floor(counts.Y + 0.5)
	local sizeZ = math.floor(counts.Z + 0.5)

	local materials = table.create(sizeX)
	local solid = table.create(sizeX)
	local liquid = table.create(sizeX)

	for ix = 1, sizeX do
		local worldX = minCorner.X + (ix - 0.5) * VOXEL
		local materialPlane = table.create(sizeY)
		local solidPlane = table.create(sizeY)
		local liquidPlane = table.create(sizeY)

		for iy = 1, sizeY do
			local worldY = minCorner.Y + (iy - 0.5) * VOXEL
			local materialRow = table.create(sizeZ)
			local solidRow = table.create(sizeZ)
			local liquidRow = table.create(sizeZ)

			for iz = 1, sizeZ do
				local worldZ = minCorner.Z + (iz - 0.5) * VOXEL

				local depth = LakeConfig.depthAt(Vector3.new(worldX, 0, worldZ))
				local bedY = LakeConfig.SURFACE_Y - depth

				local isBed = worldY < bedY
				local isWater = depth > 0 and worldY >= bedY and worldY < LakeConfig.SURFACE_Y

				-- Najwyższy woksel plaży jest zajęty częściowo — patrz
				-- BEACH_TOP_OCCUPANCY. Dna pod wodą to nie dotyczy.
				local isBeachTop = isBed and depth <= 0 and worldY > bedY - VOXEL

				materialRow[iz] = if isBed then Enum.Material.Sand else Enum.Material.Air
				solidRow[iz] = if not isBed then 0 elseif isBeachTop then BEACH_TOP_OCCUPANCY else 1
				liquidRow[iz] = if isWater then 1 else 0
			end

			materialPlane[iy] = materialRow
			solidPlane[iy] = solidRow
			liquidPlane[iy] = liquidRow
		end

		materials[ix] = materialPlane
		solid[ix] = solidPlane
		liquid[ix] = liquidPlane
	end

	Workspace.Terrain:WriteVoxelChannels(region, VOXEL, {
		SolidMaterial = materials,
		SolidOccupancy = solid,
		LiquidOccupancy = liquid,
	})
end

local function styleWater()
	local terrain = Workspace.Terrain

	-- Fale celowo drobne. Przy WaterWaveSize bliskim 1 spławik skacze
	-- o kilka studów i nie da się odczytać, kiedy ryba bierze.
	terrain.WaterWaveSize = 0.15
	terrain.WaterWaveSpeed = 9
	-- Odbicie pośrodku, i to z obu stron sprawdzone. Przy 0.65 tafla brała
	-- kolor wprost z nieba i jezioro świeciło cyjanem jak basen. Przy 0.25
	-- znikała faktura fal i woda robiła się płaską plamą farby.
	terrain.WaterReflectance = 0.35
	-- Nie wyżej: przy 0.55 prześwitywało piaszczyste dno i woda czytała
	-- się jako muł.
	terrain.WaterTransparency = 0.35
	-- Ciemniejszy niż turkus z palety (docs/art/ART_DIRECTION.md): silnik
	-- rozjaśnia wodę światłem, więc kolor z palety wprost dawał neon.
	terrain.WaterColor = Color3.fromRGB(30, 136, 160)
end

--[[ Domyślna trawa terenu jest oliwkowa i gryzie się z nasyconymi stoiskami.
     Wartość jest bardziej stonowana niż zieleń z palety
     (docs/art/ART_DIRECTION.md), bo tekstura terenu i korekcja kolorów
     podbijają nasycenie — hex z palety wprost wychodził jaskrawy. ]]
local function styleLand()
	Workspace.Terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(104, 150, 72))
end

--[[
	Chmury muszą być dzieckiem Terrain, więc powstają tutaj, a nie
	w `default.project.json` obok reszty oświetlenia: Rojo nie dosynchronizuje
	dziecka do istniejącego Terrain w otwartym Studio i chmury byłyby tylko
	w pliku z `rojo build`.
]]
local function styleSky()
	local terrain = Workspace.Terrain
	local existing = terrain:FindFirstChildOfClass("Clouds")
	local clouds = existing or Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.6
	clouds.Parent = terrain
end

--[[
	Mierzy, ile studów wody JEST NAPRAWDĘ w terenie nad danym punktem.

	Czyta kolumnę wokseli od lustra wody w dół i liczy nieprzerwane warstwy
	z zajętością cieczy. Zwraca -1, gdy odczyt się nie powiódł.

	To nie jest to samo co `LakeConfig.depthAt` — i o to właśnie chodzi.
	`depthAt` mówi, ile głębokości ZAKŁADA konfiguracja; ta funkcja mówi,
	ile silnik faktycznie postawił. Rozjazd tych dwóch liczb był przyczyną
	„bagna" i jest jedyną rzeczą, która odróżnia „zbudowało się" od
	„wygląda, jakby się zbudowało".
]]
local function measureWater(x: number, z: number): number
	local region = Region3.new(
		Vector3.new(x - VOXEL / 2, BED_BOTTOM, z - VOXEL / 2),
		Vector3.new(x + VOXEL / 2, LakeConfig.SURFACE_Y, z + VOXEL / 2)
	):ExpandToGrid(VOXEL)

	-- Czytamy kanał cieczy, nie materiał. Woda jest wyłącznie zajętością
	-- `LiquidOccupancy` — pytanie „czy materiał to Water" odpowiadałoby
	-- na inne pytanie niż to, które nas interesuje.
	local ok, result = pcall(function()
		return Workspace.Terrain:ReadVoxelChannels(region, VOXEL, { "LiquidOccupancy" })
	end)

	if not ok or not result then
		return -1
	end

	local channels: any = result
	local grid = channels.LiquidOccupancy
	if not grid then
		return -1
	end

	local layers = math.floor(region.Size.Y / VOXEL + 0.5)
	local depth = 0

	-- Woksele są indeksowane od dolnego rogu regionu, więc idziemy od góry.
	for y = layers, 1, -1 do
		if (grid[1][y][1] or 0) < 0.5 then
			break
		end
		depth += VOXEL
	end

	return depth
end

--[[
	Raport do Output: oczekiwana vs zmierzona głębokość w kilku punktach.

	Świadomie drukujemy to przy KAŻDYM starcie, a nie tylko przy błędzie.
	Kształt jeziora jest niewidoczny w edytorze (mapa powstaje w runtime),
	więc te cztery linijki to jedyny sposób, żeby ktokolwiek w zespole
	zobaczył, co właściwie zbudował — zanim zacznie szukać winy w kodzie ryb.
]]
local function reportDepths()
	local cx, cz = LakeConfig.CENTER_X, LakeConfig.CENTER_Z
	local half = LakeConfig.HALF_SIZE

	local probes = {
		{ label = "brzeg", x = cx, z = cz + half - 4 },
		{ label = "blisko brzegu", x = cx, z = cz + half - 20 },
		{ label = "srodek pomostu", x = cx, z = cz + half - 50 },
		{ label = "srodek jeziora", x = cx, z = cz },
	}

	local mismatched = false
	local lines = { "[Ground] profil jeziora (oczekiwane / zmierzone w terenie):" }

	for _, probe in probes do
		local expected = LakeConfig.depthAt(Vector3.new(probe.x, 0, probe.z))
		local actual = measureWater(probe.x, probe.z)

		if actual >= 0 and actual ~= expected then
			mismatched = true
		end

		table.insert(lines, `  {probe.label}: {expected} / {actual} studow`)
	end

	print(table.concat(lines, "\n"))

	if mismatched then
		warn(
			"[Ground] teren NIE zgadza sie z shared/Config/Lake.\n"
				.. "  Wode WYCINAMY w gotowym dnie przez WriteVoxelChannels.\n"
				.. "  Sprawdz, czy ktos nie wrocil do FillBlock z Enum.Material.Water."
		)
	end
end

--[[
	Buduje teren od zera. Idempotentne — czyści poprzedni, więc Rojo może
	wgrać zmianę w tym pliku bez restartu serwera.
]]
function Ground.build()
	Workspace.Terrain:Clear()

	-- Ląd przez FillBlock: nie ma tu wody, więc działa bez zastrzeżeń
	-- i jest wielokrotnie szybszy niż pisanie wokseli ręcznie.
	fill(LAND_CENTER, LAND_SIZE, Enum.Material.Grass)

	-- Misa jeziora wokselami — jedyny sposób, żeby dostać wodę (patrz
	-- komentarz na górze pliku).
	writeLakeVoxels()

	styleWater()
	styleLand()
	styleSky()
	reportDepths()
end

return table.freeze(Ground)
