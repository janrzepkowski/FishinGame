--!strict
--[[
	LakeLife — życie w jeziorze: ławice pod wodą i ryby wyskakujące nad taflę.

	Efekt CZYSTO LOKALNY i czysto dekoracyjny. Te ryby nie mają nic wspólnego
	z tym, co gracz złowi — o połowie decyduje `FishingService`. Ich zadanie
	to sprawić, żeby jezioro wyglądało na zamieszkane: gracz, który widzi
	rybę wyskakującą trzy metry od spławika, wierzy, że w tej wodzie coś jest.

	Dlatego nic tu nie idzie przez sieć i nic nie musi być zgodne między
	graczami — każdy klient ma własne ławice.

	KOSZT: kilkadziesiąt zakotwiczonych części przesuwanych jednym
	`BulkMoveTo` na klatkę, i tylko wtedy, gdy kamera jest blisko jeziora.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local LakeConfig = require(Shared.Config.Lake)

local Ripple = require(script.Parent.Ripple)
local Sfx = require(script.Parent.Sfx)

local LakeLife = {}

local CONTAINER_NAME = "LakeLife"

local SCHOOL_COUNT = 14
local FISH_PER_SCHOOL = 6
-- Ławice pływają wszędzie, gdzie jest woda — także na najpłytszej półce
-- przy brzegu, bo to tam gracz wchodzi do jeziora.
local MIN_SCHOOL_DEPTH = 8

-- Gdy gracz jest w wodzie, co tyle sekund najdalsza ławica przenosi się
-- w jego pobliże. Jezioro ma 200 studów średnicy: bez tego pływak mógłby
-- przepłynąć je całe i nie spotkać ani jednej ryby.
local FOLLOW_INTERVAL = 3
local FOLLOW_NEAR = 14
local FOLLOW_FAR = 26
-- Dalej niż tyle od brzegu jeziora ławic i tak nie widać.
local ACTIVE_MARGIN = 140

local JUMP_INTERVAL_MIN = 5
local JUMP_INTERVAL_MAX = 12
local JUMP_TIME = 0.85
local JUMP_HEIGHT = 3.2

-- Paleta: srebro, oliwka i jeden ciepły akcent. Czerwieni nie ma —
-- jest zarezerwowana dla spławika (docs/art/ART_DIRECTION.md).
local FISH_COLORS = {
	Color3.fromRGB(176, 190, 198),
	Color3.fromRGB(122, 146, 112),
	Color3.fromRGB(206, 152, 74),
	Color3.fromRGB(96, 122, 138),
}

type Fish = {
	body: BasePart,
	tail: BasePart,
	-- Przesunięcie w ławicy: kąt na okręgu, promień i wysokość.
	angle: number,
	radius: number,
	height: number,
}

type School = {
	centerX: number,
	centerZ: number,
	y: number,
	speed: number,
	fish: { Fish },
}

local generator = Random.new()
local container: Folder? = nil
local schools: { School } = {}
local started = false

local function getContainer(): Folder
	local existing = container
	if existing and existing.Parent then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = CONTAINER_NAME
	folder.Parent = Workspace
	container = folder
	return folder
end

local function decor(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
end

--[[ Ryba z dwóch brył: korpus i płetwa ogonowa. Przód to -Z. ]]
local function makeFish(scale: number, color: Color3): (BasePart, BasePart)
	local body = Instance.new("Part")
	body.Name = "Fish"
	body.Size = Vector3.new(0.3, 0.55, 1.5) * scale
	body.Color = color
	decor(body)
	body.Parent = getContainer()

	local tail = Instance.new("WedgePart")
	tail.Name = "Tail"
	tail.Size = Vector3.new(0.12, 0.6, 0.55) * scale
	tail.Color = color:Lerp(Color3.new(0, 0, 0), 0.25)
	decor(tail)
	tail.Parent = getContainer()

	return body, tail
end

local function tailOffset(scale: number): CFrame
	return CFrame.new(0, 0, 1.0 * scale)
end

--[[ Losowy punkt nad wodą o głębokości co najmniej `minDepth`. ]]
local function pointOverWater(minDepth: number): (number?, number?)
	for _ = 1, 30 do
		local angle = generator:NextNumber(0, math.pi * 2)
		local distance = math.sqrt(generator:NextNumber()) * LakeConfig.HALF_SIZE
		local x = LakeConfig.CENTER_X + math.cos(angle) * distance
		local z = LakeConfig.CENTER_Z + math.sin(angle) * distance
		if LakeConfig.depthAt(Vector3.new(x, 0, z)) >= minDepth then
			return x, z
		end
	end
	return nil, nil
end

--[[ Wysokość ławicy: w górnej połowie toni, gdzie widać ją także znad
     wody, ale zawsze z zapasem nad dnem (dno leży 2 study ponad wypełnieniem
     terenu — patrz `Ground`). ]]
local function schoolY(depth: number): number
	local deepest = math.max(depth * 0.5, 3.5)
	return LakeConfig.SURFACE_Y - generator:NextNumber(2.5, math.max(deepest, 2.6))
end

local function buildSchools()
	for _ = 1, SCHOOL_COUNT do
		local x, z = pointOverWater(MIN_SCHOOL_DEPTH)
		if x and z then
			local depth = LakeConfig.depthAt(Vector3.new(x, 0, z))
			local color = FISH_COLORS[generator:NextInteger(1, #FISH_COLORS)]
			local scale = generator:NextNumber(1, 2.1)

			local school: School = {
				centerX = x,
				centerZ = z,
				y = schoolY(depth),
				speed = generator:NextNumber(0.25, 0.5)
					* (if generator:NextNumber() < 0.5 then 1 else -1),
				fish = {},
			}

			for index = 1, FISH_PER_SCHOOL do
				local body, tail = makeFish(scale, color)
				table.insert(school.fish, {
					body = body,
					tail = tail,
					angle = (index / FISH_PER_SCHOOL) * 0.9 + generator:NextNumber(-0.08, 0.08),
					radius = generator:NextNumber(5, 8),
					height = generator:NextNumber(-0.8, 0.8),
				})
			end

			table.insert(schools, school)
		end
	end
end

local function nearLake(): boolean
	local camera = Workspace.CurrentCamera
	if not camera then
		return false
	end

	local position = camera.CFrame.Position
	local dx = position.X - LakeConfig.CENTER_X
	local dz = position.Z - LakeConfig.CENTER_Z
	local reach = LakeConfig.HALF_SIZE + ACTIVE_MARGIN
	return dx * dx + dz * dz <= reach * reach
end

local function updateSchools()
	if not nearLake() then
		return
	end

	local now = os.clock()
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}

	for _, school in schools do
		for _, fish in school.fish do
			local angle = now * school.speed + fish.angle
			local position = Vector3.new(
				school.centerX + math.cos(angle) * fish.radius,
				school.y + fish.height + math.sin(now * 1.3 + fish.angle * 7) * 0.25,
				school.centerZ + math.sin(angle) * fish.radius
			)
			-- Styczna do okręgu; znak prędkości odwraca kierunek płynięcia.
			local heading = Vector3.new(-math.sin(angle), 0, math.cos(angle))
				* math.sign(school.speed)
			local frame = CFrame.lookAt(position, position + heading)
			-- Machanie ogonem: obrót płetwy wokół osi pionowej.
			local wag = math.sin(now * 9 + fish.angle * 11) * 0.5

			table.insert(parts, fish.body)
			table.insert(frames, frame)
			table.insert(parts, fish.tail)
			table.insert(
				frames,
				frame
					* CFrame.Angles(0, wag, 0)
					* tailOffset(fish.body.Size.Z / 1.5)
					-- Klin ma opadać ku końcowi ogona.
					* CFrame.Angles(0, math.pi, 0)
			)
		end
	end

	if #parts > 0 then
		Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

--[[
	Ryba wyskakuje nad wodę: łuk, krąg przy wyjściu i krąg przy wejściu.

	To jest ten moment, dla którego ten moduł istnieje — ruch nad taflą
	przyciąga wzrok z drugiego końca jeziora.
]]
local function jump()
	local x, z = pointOverWater(8)
	if not (x and z) then
		return
	end

	local scale = generator:NextNumber(1, 1.8)
	local body, tail = makeFish(scale, FISH_COLORS[generator:NextInteger(1, #FISH_COLORS)])
	local direction = generator:NextNumber(0, math.pi * 2)
	local forward = Vector3.new(math.cos(direction), 0, math.sin(direction))
	local length = generator:NextNumber(3, 5)
	local start = Vector3.new(x, LakeConfig.SURFACE_Y, z)
	local startedAt = os.clock()

	Ripple.spawn(start, 5, 0.8)

	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - startedAt) / JUMP_TIME

		if t >= 1 then
			connection:Disconnect()
			Ripple.spawn(start + forward * length, 7, 1)
			Sfx.playAt("splash", start + forward * length, 0.6)
			body:Destroy()
			tail:Destroy()
			return
		end

		local position = start
			+ forward * (length * t)
			+ Vector3.new(0, JUMP_HEIGHT * 4 * t * (1 - t), 0)
		-- Ryba patrzy wzdłuż toru lotu: w górę na początku, w dół na końcu.
		local slope = JUMP_HEIGHT * 4 * (1 - 2 * t) / length
		local frame = CFrame.lookAt(position, position + forward + Vector3.new(0, slope, 0))

		body.CFrame = frame
		tail.CFrame = frame * tailOffset(scale) * CFrame.Angles(0, math.pi, 0)
	end)
end

--[[
	Ryby tam, gdzie pływa gracz.

	Gdy kamera jest nad wodą, najdalsza ławica przenosi się w pobliże —
	poza zasięg wzroku pod wodą, żeby wpłynęła w kadr, a nie w nim wyskoczyła.
]]
local function gatherNearSwimmer()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local origin = camera.Focus.Position
	if LakeConfig.depthAt(origin) <= 0 then
		return
	end

	local farthest: School? = nil
	local farthestDistance = FOLLOW_FAR
	for _, school in schools do
		local dx = school.centerX - origin.X
		local dz = school.centerZ - origin.Z
		local distance = math.sqrt(dx * dx + dz * dz)
		if distance > farthestDistance then
			farthest = school
			farthestDistance = distance
		end
	end

	if not farthest then
		return
	end

	for _ = 1, 12 do
		local angle = generator:NextNumber(0, math.pi * 2)
		local distance = generator:NextNumber(FOLLOW_NEAR, FOLLOW_FAR)
		local x = origin.X + math.cos(angle) * distance
		local z = origin.Z + math.sin(angle) * distance
		local depth = LakeConfig.depthAt(Vector3.new(x, 0, z))
		if depth >= MIN_SCHOOL_DEPTH then
			farthest.centerX = x
			farthest.centerZ = z
			farthest.y = schoolY(depth)
			return
		end
	end
end

function LakeLife.start()
	if started then
		return
	end
	started = true

	buildSchools()
	RunService.RenderStepped:Connect(updateSchools)

	task.spawn(function()
		while true do
			task.wait(FOLLOW_INTERVAL)
			gatherNearSwimmer()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(generator:NextNumber(JUMP_INTERVAL_MIN, JUMP_INTERVAL_MAX))
			if nearLake() then
				jump()
			end
		end
	end)
end

return table.freeze(LakeLife)
