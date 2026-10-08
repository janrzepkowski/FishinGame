--!strict
--[[
	Bobber — spławik, żyłka, kręgi na wodzie i plusk. Efekt CZYSTO LOKALNY.

	Instancje tworzone przez klienta nie replikują się na serwer ani do innych
	graczy — i o to chodzi. Spławik nie wpływa na rozgrywkę (o złowieniu
	decyduje FishingService), więc nie ma powodu obciążać nim sieci.
	Konsekwencja: inni gracze nie widzą twojej żyłki. Gdy to zacznie
	przeszkadzać, efekt trzeba przenieść na serwer — ale wtedy płacimy
	replikacją za każdy rzut każdego gracza.

	Punkt zarzucenia liczymy `Spatial.castTarget` — DOKŁADNIE tą samą funkcją,
	której używa serwer do sprawdzenia głębokości. Gdyby klient liczył po
	swojemu, spławik lądowałby gdzie indziej niż miejsce, z którego naprawdę
	bierze ryba.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.Game)
local LakeConfig = require(Shared.Config.Lake)
local Spatial = require(Shared.Util.Spatial)

local Bobber = {}

local CONTAINER_NAME = "ClientEffects"

local player = Players.LocalPlayer

local container: Folder? = nil
local bobber: BasePart? = nil
local beam: Beam? = nil
local floatConnection: RBXScriptConnection? = nil
local restY = LakeConfig.SURFACE_Y

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

--[[ Attachment na czubku wędki. Szukamy rekurencyjnie, bo model wędki
     składa się z kilku części i czubek może się przenieść między nimi. ]]
local function rodTip(): Attachment?
	local character = player.Character
	if not character then
		return nil
	end

	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then
		return nil
	end

	local tip = tool:FindFirstChild("Tip", true)
	return if tip and tip:IsA("Attachment") then tip else nil
end

--[[ Rozchodzący się krąg na wodzie. Sam się sprząta. ]]
local function ripple(position: Vector3, maxDiameter: number, life: number)
	local ring = Instance.new("Part")
	ring.Name = "Ripple"
	ring.Shape = Enum.PartType.Cylinder
	-- Walec leży wzdłuż osi X — obrót wokół Z kładzie go płasko na wodzie.
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Size = Vector3.new(0.08, 0.6, 0.6)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(198, 232, 244)
	ring.Transparency = 0.45
	ring.Parent = getContainer()

	local info = TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(ring, info, {
		Size = Vector3.new(0.05, maxDiameter, maxDiameter),
		Transparency = 1,
	}):Play()

	task.delay(life + 0.05, function()
		ring:Destroy()
	end)
end

local function stopFloating()
	if floatConnection then
		floatConnection:Disconnect()
		floatConnection = nil
	end
end

function Bobber.clear()
	stopFloating()

	if beam then
		beam:Destroy()
		beam = nil
	end
	if bobber then
		bobber:Destroy()
		bobber = nil
	end
end

--[[
	Rzuca spławik na wodę przed graczem.

	Nic nie robi, gdy nie ma postaci albo wędki w ręce — to nie są błędy,
	tylko normalne stany (respawn, pierwsza klatka po wejściu).
]]
function Bobber.cast()
	Bobber.clear()

	local root = Spatial.characterRoot(player)
	if not root then
		return
	end

	local target = Spatial.castTarget(root.CFrame, GameConfig.CAST_DISTANCE)
	local landing = LakeConfig.clampToWater(target, GameConfig.CAST_SHORE_MARGIN)
	restY = landing.Y + 0.2

	local float = Instance.new("Part")
	float.Name = "Bobber"
	float.Shape = Enum.PartType.Ball
	float.Size = Vector3.new(0.65, 0.65, 0.65)
	float.Color = Color3.fromRGB(230, 72, 72)
	float.Material = Enum.Material.SmoothPlastic
	float.Anchored = true
	float.CanCollide = false
	float.CanQuery = false
	float.CanTouch = false
	float.Position = Vector3.new(landing.X, restY, landing.Z)
	float.Parent = getContainer()

	local floatAttachment = Instance.new("Attachment")
	floatAttachment.Name = "Line"
	floatAttachment.Parent = float

	local tip = rodTip()
	if tip then
		local line = Instance.new("Beam")
		line.Name = "Line"
		line.Attachment0 = tip
		line.Attachment1 = floatAttachment
		line.Width0 = 0.035
		line.Width1 = 0.035
		line.Color = ColorSequence.new(Color3.fromRGB(232, 238, 246))
		line.Transparency = NumberSequence.new(0.2)
		line.FaceCamera = true
		line.Parent = float
		beam = line
	end

	bobber = float
	ripple(float.Position, 7, 1.1)

	-- Kołysanie na fali. Amplituda jest celowo mała (3 cm): spławik ma
	-- „żyć", ale gracz musi odróżnić kołysanie od szarpnięcia przy braniu.
	local phase = math.random() * math.pi * 2
	floatConnection = RunService.RenderStepped:Connect(function()
		local part = bobber
		if not part then
			stopFloating()
			return
		end
		local t = os.clock() * 1.8 + phase
		part.Position = Vector3.new(part.Position.X, restY + math.sin(t) * 0.03, part.Position.Z)
	end)
end

--[[ Szarpnięcie w momencie brania — poza paskiem UI to jedyna informacja
     „teraz!", a przy łowieniu wzrok jest na wodzie, nie na interfejsie. ]]
function Bobber.dip()
	local float = bobber
	if not float then
		return
	end

	stopFloating()

	local sunken = Vector3.new(float.Position.X, restY - 0.5, float.Position.Z)
	TweenService:Create(
		float,
		TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1, true),
		{ Position = sunken }
	):Play()

	ripple(float.Position, 5, 0.7)
	task.delay(0.35, function()
		if bobber == float then
			ripple(float.Position, 6, 0.8)
		end
	end)
end

--[[ Plusk przy wyciągnięciu ryby. Wołany zanim spławik zniknie. ]]
function Bobber.splash()
	local float = bobber
	if not float then
		return
	end

	local origin = float.Position
	ripple(origin, 12, 0.9)

	for index = 1, 8 do
		local drop = Instance.new("Part")
		drop.Name = "Droplet"
		drop.Shape = Enum.PartType.Ball
		drop.Size = Vector3.new(0.22, 0.22, 0.22)
		drop.Color = Color3.fromRGB(206, 236, 246)
		drop.Material = Enum.Material.Neon
		drop.Transparency = 0.15
		drop.Anchored = true
		drop.CanCollide = false
		drop.CanQuery = false
		drop.CanTouch = false
		drop.Position = origin
		drop.Parent = getContainer()

		local angle = (index / 8) * math.pi * 2
		local away = Vector3.new(math.cos(angle), 0, math.sin(angle)) * math.random(2, 4)

		local info = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(drop, info, {
			Position = origin + away + Vector3.new(0, 2.2, 0),
			Transparency = 1,
			Size = Vector3.new(0.05, 0.05, 0.05),
		}):Play()

		task.delay(0.55, function()
			drop:Destroy()
		end)
	end
end

return Bobber
