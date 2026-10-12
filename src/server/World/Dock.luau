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

local WOOD_LIGHT = Color3.fromRGB(176, 134, 88)
local WOOD_DARK = Color3.fromRGB(148, 110, 70)
local WOOD_POST = Color3.fromRGB(104, 78, 52)

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
			Color = if index % 2 == 0 then WOOD_LIGHT else WOOD_DARK,
			Material = Enum.Material.WoodPlanks,
			CanCollide = true,
		})
	end

	-- Policzki po bokach zamykają schody wizualnie i zasłaniają boki bloków.
	local run = STEP_COUNT * STEP_DEPTH
	for _, side in { -1, 1 } do
		Build.wedge(parent, {
			Name = "StepCheek",
			Size = Vector3.new(0.4, DECK_TOP + STEP_BURIED, run),
			-- Klin w Robloxie opada w stronę -Z własnego układu, a schody
			-- opadają w stronę +Z świata — stąd obrót o pół obrotu.
			CFrame = CFrame.new(
				side * (WIDTH / 2 + 0.2),
				(DECK_TOP - STEP_BURIED) / 2,
				START_Z + run / 2
			) * CFrame.Angles(0, math.pi, 0),
			Color = WOOD_POST,
			Material = Enum.Material.Wood,
			CanCollide = true,
		})
	end
end

local function buildDeck(parent: Instance): number
	local plankCount = math.ceil(LENGTH / PLANK_LENGTH)

	for index = 1, plankCount do
		local centerZ = START_Z - (index - 0.5) * PLANK_LENGTH

		Build.block(parent, {
			Name = `Plank{index}`,
			Size = Vector3.new(WIDTH, PLANK_THICKNESS, PLANK_LENGTH - 0.12),
			Position = Vector3.new(0, DECK_Y, centerZ),
			-- Naprzemienne odcienie: bez nich pomost jest jedną plamą
			-- i z daleka nie widać, gdzie się kończy.
			Color = if index % 2 == 0 then WOOD_LIGHT else WOOD_DARK,
			Material = Enum.Material.WoodPlanks,
			CanCollide = true,
		})
	end

	return plankCount
end

local function buildRailings(parent: Instance)
	local railY = DECK_TOP + 1.15
	local postSpacing = 8
	local postCount = math.floor(LENGTH / postSpacing)

	for _, side in { -1, 1 } do
		local x = side * (WIDTH / 2 - 0.3)

		-- Barierka MUSI kolidować: bez tego gracz cofający się przed podcięciem
		-- wpada do wody i traci zarzucenie.
		Build.block(parent, {
			Name = "Rail",
			Size = Vector3.new(0.25, 0.25, LENGTH),
			Position = Vector3.new(x, railY, START_Z - LENGTH / 2),
			Color = WOOD_POST,
			Material = Enum.Material.Wood,
			CanCollide = true,
		})

		for index = 0, postCount do
			Build.block(parent, {
				Name = "RailPost",
				Size = Vector3.new(0.35, 1.3, 0.35),
				Position = Vector3.new(
					x,
					DECK_TOP + 0.65,
					START_Z - math.min(index * postSpacing, LENGTH)
				),
				Color = WOOD_POST,
				Material = Enum.Material.Wood,
				CanCollide = true,
			})
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
			Build.block(parent, {
				Name = "Pile",
				Size = Vector3.new(0.9, pileLength, 0.9),
				Position = Vector3.new(side * (WIDTH / 2 - 0.7), DECK_TOP - pileLength / 2 + 1, z),
				Color = WOOD_POST,
				Material = Enum.Material.Wood,
			})
		end
	end
end

local function buildLantern(parent: Instance)
	local z = Dock.END_Z + 1.6

	Build.block(parent, {
		Name = "LanternPost",
		Size = Vector3.new(0.4, 4.5, 0.4),
		Position = Vector3.new(WIDTH / 2 - 0.6, DECK_TOP + 2.25, z),
		Color = WOOD_POST,
		Material = Enum.Material.Wood,
	})

	local glass = Build.block(parent, {
		Name = "LanternGlass",
		Size = Vector3.new(1, 1.2, 1),
		Position = Vector3.new(WIDTH / 2 - 0.6, DECK_TOP + 4.4, z),
		Color = Color3.fromRGB(255, 226, 150),
		Material = Enum.Material.Neon,
	})

	local light = Instance.new("PointLight")
	light.Brightness = 2.2
	light.Range = 26
	light.Color = Color3.fromRGB(255, 214, 150)
	light.Shadows = false
	light.Parent = glass
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
