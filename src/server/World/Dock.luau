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

-- Ciepłe, jasne „drewno" jak z klocków i białe wykończenia — ta sama
-- cukierkowa paleta co plac i stoiska.
local WOOD_LIGHT = Color3.fromRGB(255, 206, 150)
local WOOD_DARK = Color3.fromRGB(246, 176, 118)
local WOOD_POST = Color3.fromRGB(222, 136, 96)
local TRIM = Color3.fromRGB(255, 255, 255)

Dock.END_Z = START_Z - LENGTH

local function buildSteps(parent: Instance)
	for index = 1, 2 do
		Build.block(parent, {
			Name = `Step{index}`,
			Size = Vector3.new(WIDTH - 2, 0.5, 2),
			Position = Vector3.new(0, index * 0.45 - 0.25, START_Z + (3 - index) * 2),
			Color = WOOD_DARK,
			Material = Enum.Material.SmoothPlastic,
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
			Material = Enum.Material.SmoothPlastic,
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
			Material = Enum.Material.SmoothPlastic,
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
				Material = Enum.Material.SmoothPlastic,
				CanCollide = true,
			})

			-- Biała kulka na każdym słupku: barierka czyta się jak zabawka,
			-- a nie jak ogrodzenie budowy.
			Build.sphere(parent, {
				Name = "RailKnob",
				Size = Vector3.one * 0.6,
				Position = Vector3.new(
					x,
					DECK_TOP + 1.45,
					START_Z - math.min(index * postSpacing, LENGTH)
				),
				Color = TRIM,
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
				Material = Enum.Material.SmoothPlastic,
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
		Material = Enum.Material.SmoothPlastic,
	})

	local glass = Build.sphere(parent, {
		Name = "LanternGlass",
		Size = Vector3.new(1.4, 1.4, 1.4),
		Position = Vector3.new(WIDTH / 2 - 0.6, DECK_TOP + 4.4, z),
		Color = Color3.fromRGB(255, 226, 150),
		Material = Enum.Material.Neon,
	})

	Build.ellipsoid(parent, {
		Name = "LanternCap",
		Size = Vector3.new(1.6, 0.7, 1.6),
		Position = Vector3.new(WIDTH / 2 - 0.6, DECK_TOP + 5.2, z),
		Color = Color3.fromRGB(255, 92, 120),
	})

	local light = Instance.new("PointLight")
	light.Brightness = 2.2
	light.Range = 26
	light.Color = Color3.fromRGB(255, 214, 150)
	light.Shadows = false
	light.Parent = glass
end

--[[
	Pasiaste boje na wodzie wzdłuż pomostu — znaczą „tu jest głęboko"
	bez żadnego napisu: im dalej, tym więcej boi. Pływają na lustrze
	wody i nie kolidują, więc nie przeszkadzają w pływaniu ani w rzucie.
]]
local function buildBuoys(parent: Instance)
	local spots = {
		Vector3.new(-14, 0, START_Z - 30),
		Vector3.new(14, 0, START_Z - 44),
		Vector3.new(-16, 0, START_Z - 58),
		Vector3.new(16, 0, START_Z - 70),
	}

	for index, spot in spots do
		local base = Vector3.new(spot.X, LakeConfig.SURFACE_Y, spot.Z)
		Build.ellipsoid(parent, {
			Name = "Buoy",
			Size = Vector3.new(2.2, 2.6, 2.2),
			Position = base + Vector3.new(0, 0.6, 0),
			Color = if index % 2 == 0
				then Color3.fromRGB(255, 92, 120)
				else Color3.fromRGB(255, 196, 40),
		})
		Build.cylinder(parent, {
			Name = "BuoyStripe",
			Size = Vector3.new(0.5, 2.3, 2.3),
			CFrame = CFrame.new(base + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = TRIM,
		})
		Build.sphere(parent, {
			Name = "BuoyTop",
			Size = Vector3.one * 0.7,
			Position = base + Vector3.new(0, 2.1, 0),
			Color = TRIM,
		})
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
	buildBuoys(dock)

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
