--!strict
--[[
	EnvironmentController — pora dnia, pogoda i dźwięk otoczenia po stronie
	klienta.

	PORA DNIA: godzinę liczymy co klatkę z zegara serwerów
	(`Environment.clockAt`) i wpisujemy do `Lighting.ClockTime`. Nic nie
	idzie przez sieć, a słońce płynie gładko. Nocą podnosimy ekspozycję —
	bez tego jezioro o północy jest czarną plamą i nie widać spławika.

	POGODA: serwer ustawia atrybut na Workspace, my robimy z niego deszcz,
	chmury, mgłę i szum. Wszystko dochodzi i odchodzi płynnie; pogoda
	włączana skokiem wygląda jak błąd renderowania.

	Wartości bazowe (chmury, mgła) ZAPAMIĘTUJEMY przy starcie, zamiast
	wpisywać je tu na sztywno: są w `default.project.json` i `Ground`,
	a druga kopia rozjechałaby się przy pierwszym strojeniu obrazu.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Environment = require(Shared.Util.Environment)
local GameConfig = require(Shared.Config.Game)
local LakeConfig = require(Shared.Config.Lake)

local Ripple = require(script.Parent.Parent.Effects.Ripple)
local Sfx = require(script.Parent.Parent.Effects.Sfx)

local EnvironmentController = {}

-- Ile sekund trwa przejście między pogodami.
local WEATHER_FADE = 6
-- O ile rozjaśniamy obraz w środku nocy.
local NIGHT_EXPOSURE = 0.9
-- Jak daleko od brzegu słychać jeszcze jezioro.
local LAKE_HEARING = 90

local RAIN_HEIGHT = 34
local RAIN_AREA = 70
local RAIN_RATE = 2600
local RAIN_CLOUD_COVER = 0.95
local RAIN_DENSITY = 0.42
-- Chmury deszczowe są stalowe, a nocą prawie czarne. Białe chmury przy
-- podniesionej ekspozycji świeciły o północy jak mleczne szkło.
local RAIN_CLOUD_COLOR = Color3.fromRGB(128, 136, 148)
local NIGHT_CLOUD_DIM = 0.82

local generator = Random.new()

local started = false
-- Prawda po pierwszej pełnej klatce: pora dnia, ekspozycja, mgła i chmury
-- mają już docelowe wartości. Czeka na to ekran ładowania.
local ready = false
-- 0 = pogodnie, 1 = pełny deszcz. Dogania cel przez `WEATHER_FADE` sekund.
local rain = 0
local rainTarget = 0

local baseExposure = 0
local baseDensity = 0
local baseCover = 0
local baseCloudColor = Color3.new(1, 1, 1)

local emitterPart: BasePart? = nil
local emitter: ParticleEmitter? = nil
local rainLoop: Sound? = nil
local lakeLoop: Sound? = nil
local rippleBudget = 0

local function devClock(): number?
	if not RunService:IsStudio() then
		return nil
	end
	local frozen = Workspace:GetAttribute(GameConfig.DEV_CLOCK_ATTRIBUTE)
	return if typeof(frozen) == "number" then frozen % 24 else nil
end

local function currentClock(): number
	return devClock()
		or Environment.clockAt(Workspace:GetServerTimeNow(), GameConfig.DAY_LENGTH_SECONDS)
end

--[[ Deszcz to emiter cząstek na niewidzialnej płycie nad kamerą. Płyta
     jedzie za graczem, więc pada „wszędzie", a kosztuje tyle, co jeden
     emiter — nie trzeba pokrywać cząstkami całej mapy. ]]
local function buildRain()
	local part = Instance.new("Part")
	part.Name = "RainSource"
	part.Size = Vector3.new(RAIN_AREA, 1, RAIN_AREA)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Parent = Workspace

	local drops = Instance.new("ParticleEmitter")
	drops.Name = "Rain"
	drops.EmissionDirection = Enum.NormalId.Bottom
	drops.Speed = NumberRange.new(55, 65)
	drops.Lifetime = NumberRange.new(0.7, 0.8)
	drops.Rate = 0
	drops.Size = NumberSequence.new(0.6)
	-- UJEMNY squash wydłuża cząstkę wzdłuż toru lotu i robi z okrągłej
	-- plamki kreskę. Dodatni rozciąga ją w poprzek — krople leciały wtedy
	-- bokiem, jak poziome rysy na szybie. Zakres to -3..3.
	drops.Squash = NumberSequence.new(-3)
	drops.Orientation = Enum.ParticleOrientation.VelocityParallel
	drops.Transparency = NumberSequence.new(0.4)
	drops.Color = ColorSequence.new(Color3.fromRGB(206, 224, 238))
	drops.LightEmission = 0.4
	drops.Brightness = 1.5
	drops.SpreadAngle = Vector2.new(4, 4)
	drops.Parent = part

	emitterPart = part
	emitter = drops
end

--[[ Krople na tafli: kilka kręgów na sekundę wokół gracza, tylko nad wodą. ]]
local function rainRipples(delta: number, origin: Vector3)
	rippleBudget += delta * 14 * rain

	while rippleBudget >= 1 do
		rippleBudget -= 1

		local x = origin.X + generator:NextNumber(-45, 45)
		local z = origin.Z + generator:NextNumber(-45, 45)
		if LakeConfig.isOverWater(Vector3.new(x, 0, z)) then
			Ripple.spawn(Vector3.new(x, LakeConfig.SURFACE_Y + 0.05, z), 2.2, 0.6)
		end
	end
end

local function update(delta: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.CFrame.Position

	-- Pora dnia.
	local clock = currentClock()
	Lighting.ClockTime = clock

	-- Pogoda dogania cel ze stałą prędkością.
	local step = delta / WEATHER_FADE
	rain = if rain < rainTarget
		then math.min(rain + step, rainTarget)
		else math.max(rain - step, rainTarget)

	-- W deszczu jest ciemniej, w nocy rozjaśniamy — oba wpływy się sumują.
	Lighting.ExposureCompensation = baseExposure
		+ Environment.darkness(clock) * NIGHT_EXPOSURE
		- rain * 0.25

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = baseDensity + (RAIN_DENSITY - baseDensity) * rain
	end

	local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		clouds.Cover = baseCover + (RAIN_CLOUD_COVER - baseCover) * rain
		clouds.Color = baseCloudColor
			:Lerp(RAIN_CLOUD_COLOR, rain)
			:Lerp(Color3.new(0, 0, 0), Environment.darkness(clock) * NIGHT_CLOUD_DIM)
	end

	local drops, source = emitter, emitterPart
	if drops and source then
		drops.Rate = RAIN_RATE * rain
		source.CFrame = CFrame.new(origin.X, origin.Y + RAIN_HEIGHT, origin.Z)
	end

	if rain > 0 then
		rainRipples(delta, origin)
	end

	local rainSound = rainLoop
	if rainSound then
		rainSound.Volume = Sfx.baseVolume("rain") * rain
	end

	-- Jezioro słychać tym głośniej, im bliżej brzegu; na wodzie najgłośniej.
	local lakeSound = lakeLoop
	if lakeSound then
		local fromShore = math.max(-LakeConfig.edgeDistance(origin), 0)
		local nearness = math.clamp(1 - fromShore / LAKE_HEARING, 0, 1)
		lakeSound.Volume = Sfx.baseVolume("lake") * nearness
	end

	ready = true
end

local function readWeather()
	local weather = Workspace:GetAttribute(GameConfig.WEATHER_ATTRIBUTE)
	rainTarget = if weather == "Rain" then 1 else 0
end

function EnvironmentController.start()
	if started then
		return
	end
	started = true

	baseExposure = Lighting.ExposureCompensation
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	baseDensity = if atmosphere then atmosphere.Density else 0.25

	-- Porę dnia i ekspozycję ustawiamy OD RAZU, nie dopiero w pętli (która
	-- rusza po dojechaniu chmur). Inaczej gra startuje z godziną zapisaną
	-- w pliku miejsca i po chwili „przeskakuje" na właściwą — widać to jako
	-- zapalające się albo gasnące światło.
	local clock = currentClock()
	Lighting.ClockTime = clock
	Lighting.ExposureCompensation = baseExposure + Environment.darkness(clock) * NIGHT_EXPOSURE

	buildRain()
	rainLoop = Sfx.loop("rain")
	lakeLoop = Sfx.loop("lake")

	Workspace:GetAttributeChangedSignal(GameConfig.WEATHER_ATTRIBUTE):Connect(readWeather)
	readWeather()
	-- Gracz dołączający w środku ulewy widzi ją od razu, bez sześciu sekund
	-- „rozpadywania się" pogody, która trwa od kwadransa.
	rain = rainTarget

	-- Chmury tworzy serwer w trakcie budowy świata i mogą dojechać chwilę
	-- po starcie klienta. Bazowe pokrycie czytamy, gdy już są.
	task.spawn(function()
		local clouds = Workspace.Terrain:WaitForChild("Clouds", 30)
		if clouds and clouds:IsA("Clouds") then
			baseCover = clouds.Cover
			baseCloudColor = clouds.Color
		end
		RunService.RenderStepped:Connect(update)
	end)
end

--[[ Czy oświetlenie ma już docelowe wartości (patrz `ready`). ]]
function EnvironmentController.isReady(): boolean
	return ready
end

return table.freeze(EnvironmentController)
