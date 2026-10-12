--!strict
--[[
	Dock — pomost wychodzący nad jezioro.

	Pomost nie jest ozdobą: to jedyny sposób, żeby dojść nad głęboką wodę,
	a głębokość podbija szansę na rzadkie ryby (patrz FishingService).
	Dlatego biegnie w stronę środka jeziora, a nie wzdłuż brzegu.

	Pokład jest nisko (1,45 studa nad gruntem) celowo. Humanoid w Robloxie
	wchodzi na przeszkodę wysoką do ~2 studów — przy wyższym pokładzie gracz
	stałby obok pomostu i nie mógł na niego wejść. Schodki na początku są
	dodatkowym zabezpieczeniem, gdyby ktoś podniósł pokład.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LakeConfig = require(ReplicatedStorage.Shared.Config.Lake)

local Build = require(script.Parent.Build)

local Dock = {}

local DECK_Y = 1.2
local PLANK_THICKNESS = 0.5
local DECK_TOP = DECK_Y + PLANK_THICKNESS / 2

local WIDTH = 10
local PLANK_LENGTH = 4
-- Startujemy na lądzie (brzeg wody jest przy Z = -40) i wchodzimy nad wodę.
--
-- Długość NIE jest dobrana „na oko": koniec pomostu musi sięgać najgłębszej
-- półki, inaczej cała mechanika bonusu za głębokość jest nieosiągalna pieszo
-- i nikt nie ma powodu tu wchodzić. `Dock.build` sprawdza to na starcie.
local START_Z = -32
local LENGTH = 76

local STEP_COUNT = 3
-- Głębokość stopnia (w stronę lądu). 1,6 studa to wygodny krok dla postaci
-- wysokiej na 5,5 studa.
local STEP_DEPTH = 1.6
-- Ile bloku stopnia siedzi pod ziemią, żeby pod schodami nie było szpary.
local STEP_BURIED = 0.6

local C = Build.COLOR

-- Najmniejsza różnica wysokości między dwiema nakładającymi się płaskimi
-- powierzchniami. Mniejsza daje migotanie (z-fighting).
local LIP = 0.08

-- Deski w kolejnych pastelach: pomost czyta się z daleka jak tęczowa
-- wstążka prowadząca na głęboką wodę.
local PLANKS = { C.peach, C.vanilla, C.mint, C.sky, C.lilac, C.pink }
local RAIL = C.white
local POST_COLORS = { C.rose, C.sky, C.lemon, C.mint, C.grape, C.orange }

Dock.END_Z = START_Z - LENGTH

--[[
	Schody z gruntu na pokład.

	Trzy równe stopnie, każdy jako PEŁNY blok sięgający pod ziemię. Poprzednie
	dwie luźne deski wisiały nad ścieżką ze szparami pod spodem i wyglądały
	jak porzucone palety — a przy okazji były za krótkie, żeby wejść po nich
	bez podskoku na ostatnim odcinku.

	Wysokość stopnia wychodzi z wysokości pokładu, a nie z ręki: gdy ktoś
	podniesie pokład, schody urosną razem z nim.
]]
local function buildSteps(parent: Instance)
	for index = 1, STEP_COUNT do
		-- Stopień `index` kończy się na ułamku wysokości pokładu; ostatni
		-- zostawia jeszcze jeden równy krok na sam pokład.
		local top = DECK_TOP * index / (STEP_COUNT + 1)
		local height = top + STEP_BURIED
		local centerZ = START_Z + (STEP_COUNT - index + 0.5) * STEP_DEPTH

		Build.block(parent, {
			Name = `Step{index}`,
			Size = Vector3.new(WIDTH, height, STEP_DEPTH),
			Position = Vector3.new(0, top - height / 2, centerZ),
			Color = PLANKS[index],
			CanCollide = true,
		})
		-- Zaokrąglony nosek stopnia: walec wzdłuż krawędzi.
		Build.cylinder(parent, {
			Name = "StepNose",
			Size = Vector3.new(WIDTH, 0.5, 0.5),
			Position = Vector3.new(0, top - 0.25, centerZ + STEP_DEPTH / 2),
			Color = PLANKS[index],
		})
	end

	-- Kule po bokach zamykają schody wizualnie i zasłaniają boki bloków.
	local run = STEP_COUNT * STEP_DEPTH
	for _, side in { -1, 1 } do
		for index = 0, 2 do
			Build.sphere(parent, {
				Name = "StepBall",
				Size = Vector3.one * (2.6 - index * 0.5),
				Position = Vector3.new(
					side * (WIDTH / 2 + 0.6),
					0.5 - index * 0.1,
					START_Z + run * (0.15 + index * 0.4)
				),
				Color = POST_COLORS[index + (if side > 0 then 1 else 4)],
				CanCollide = true,
			})
		end
	end
end

local function buildDeck(parent: Instance): number
	local plankCount = math.ceil(LENGTH / PLANK_LENGTH)

	for index = 1, plankCount do
		local centerZ = START_Z - (index - 0.5) * PLANK_LENGTH
		local color = PLANKS[(index - 1) % #PLANKS + 1]

		Build.block(parent, {
			Name = `Plank{index}`,
			-- Deski stykają się bez szpar: szpara w pokładzie to miejsce,
			-- w którym grzęźnie stopa postaci.
			Size = Vector3.new(WIDTH, PLANK_THICKNESS, PLANK_LENGTH),
			Position = Vector3.new(0, DECK_Y, centerZ),
			Color = color,
			CanCollide = true,
		})

		-- Zaokrąglone czoła deski po obu bokach pomostu.
		for _, side in { -1, 1 } do
			Build.cylinder(parent, {
				Name = "PlankEnd",
				Size = Vector3.new(PLANK_LENGTH, PLANK_THICKNESS, PLANK_THICKNESS),
				CFrame = CFrame.new(side * WIDTH / 2, DECK_Y, centerZ)
					* CFrame.Angles(0, math.rad(90), 0),
				Color = color,
			})
		end
	end

	-- Okrągła platforma na końcu: miejsce, z którego rzuca się najdalej.
	--
	-- Platforma jest o `LIP` WYŻSZA od desek, na które nachodzi. Przy równej
	-- wysokości jej wierzch i wierzch desek leżały w jednej płaszczyźnie
	-- i migotały, walcząc o piksele (z-fighting). Próg 0,08 studa postać
	-- przechodzi bez podskoku.
	local platformTop = DECK_TOP + LIP
	Build.upright(
		parent,
		CFrame.new(0, platformTop - (PLANK_THICKNESS + LIP) / 2, Dock.END_Z + 1),
		WIDTH + 6,
		PLANK_THICKNESS + LIP,
		{ Name = "EndPlatform", Color = C.cream, CanCollide = true }
	)
	Build.upright(
		parent,
		CFrame.new(0, platformTop + LIP / 2, Dock.END_Z + 1),
		WIDTH - 1,
		LIP,
		{ Name = "EndPlatformDot", Color = C.pink, CastShadow = false }
	)

	return plankCount
end

local function buildRailings(parent: Instance)
	local railY = DECK_TOP + 1.2
	local postSpacing = 8
	local postCount = math.floor(LENGTH / postSpacing)

	for _, side in { -1, 1 } do
		local x = side * (WIDTH / 2 - 0.3)

		-- Barierka MUSI kolidować: bez tego gracz cofający się przed podcięciem
		-- wpada do wody i traci zarzucenie. Kolizję niesie niewidoczny blok,
		-- a widać okrągłą linę — walec jako bryła kolizji łapie postać gorzej.
		Build.block(parent, {
			Name = "RailCollider",
			Size = Vector3.new(0.4, 1.6, LENGTH),
			Position = Vector3.new(x, DECK_TOP + 0.8, START_Z - LENGTH / 2),
			Transparency = 1,
			CanCollide = true,
		})
		Build.cylinder(parent, {
			Name = "Rail",
			Size = Vector3.new(LENGTH, 0.4, 0.4),
			CFrame = CFrame.new(x, railY, START_Z - LENGTH / 2) * CFrame.Angles(0, math.rad(90), 0),
			Color = RAIL,
		})

		for index = 0, postCount do
			local z = START_Z - math.min(index * postSpacing, LENGTH)
			Build.candyCane(
				parent,
				CFrame.new(x, DECK_TOP, z),
				0.5,
				1.5,
				C.white,
				POST_COLORS[index % #POST_COLORS + 1]
			)
		end
	end
end

local function buildPiles(parent: Instance)
	-- Pale wbite w dno. Muszą sięgać poniżej NAJGŁĘBSZEJ półki, inaczej nad
	-- głębią wisiałyby w wodzie i widać by było, że pomost nie ma na czym stać.
	-- Przy brzegu zakopują się w piasku — niewidoczne i nieszkodliwe.
	local pileLength = LakeConfig.MAX_DEPTH + 8
	local spacing = 12
	local count = math.floor(LENGTH / spacing)

	for _, side in { -1, 1 } do
		for index = 0, count do
			local z = START_Z - math.min(index * spacing + 4, LENGTH - 2)
			local x = side * (WIDTH / 2 - 0.7)
			Build.upright(
				parent,
				CFrame.new(x, DECK_TOP - pileLength / 2 + 0.4, z),
				1.1,
				pileLength,
				{
					Name = "Pile",
					Color = C.cocoa,
				}
			)
			-- Biała opaska tuż nad wodą, jak na palu przystani.
			Build.upright(parent, CFrame.new(x, 0.45, z), 1.2, 0.5, {
				Name = "PileBand",
				Color = C.white,
				CastShadow = false,
			})
		end
	end
end

local function buildLantern(parent: Instance)
	for _, side in { -1, 1 } do
		local top = Build.candyCane(
			parent,
			CFrame.new(side * (WIDTH / 2 + 1.6), DECK_TOP, Dock.END_Z + 1),
			0.6,
			5,
			C.white,
			if side > 0 then C.rose else C.sky
		)

		local glass = Build.sphere(parent, {
			Name = "LanternGlass",
			Size = Vector3.one * 1.8,
			CFrame = top * CFrame.new(0, 0.7, 0),
			Color = C.vanilla,
			Material = Enum.Material.Neon,
		})

		local light = Instance.new("PointLight")
		light.Brightness = 1.8
		light.Range = 26
		light.Color = Color3.fromRGB(255, 226, 170)
		light.Shadows = false
		light.Parent = glass
	end
end

--[[ Punkt na końcu pomostu — używany jako podpowiedź „idź tam po rzadkie ryby". ]]
function Dock.deepSpot(): Vector3
	return Vector3.new(0, DECK_TOP, Dock.END_Z + 4)
end

function Dock.build(parent: Instance)
	local dock = Build.model(parent, "Dock")

	buildSteps(dock)
	buildDeck(dock)
	buildRailings(dock)
	buildPiles(dock)
	buildLantern(dock)

	-- Sanity check na etapie budowy, nie w runtime przy pierwszym zarzuceniu.
	-- Pomost ma sięgać NAJGŁĘBSZEJ wody — to jest jego jedyny powód istnienia.
	-- Gdy ktoś skróci pomost albo zmieni układ półek w shared/Config/Lake,
	-- bonus za głębokość po cichu stanie się nieosiągalny i nikt tego nie
	-- zauważy przez tydzień.
	local spot = Dock.deepSpot()
	local depth = LakeConfig.depthAt(spot)

	if depth < LakeConfig.MAX_DEPTH then
		warn(
			`[Dock] koniec pomostu stoi nad {depth} m, a najgłębiej jest `
				.. `{LakeConfig.MAX_DEPTH} m. Bonus za głębokość jest pieszo nieosiągalny.\n`
				.. "  Wydłuż LENGTH w Dock albo zmniejsz `inset` ostatniej półki w Config/Lake."
		)
	end
end

return table.freeze(Dock)
