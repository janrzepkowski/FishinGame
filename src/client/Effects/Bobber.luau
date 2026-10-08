--!strict
--[[
	Bobber — spławik i linka. Efekt CZYSTO LOKALNY.

	Instancje tworzone przez klienta nie replikują się na serwer ani do innych
	graczy — i o to chodzi. Spławik nie wpływa na rozgrywkę (o złowieniu
	decyduje FishingService), więc nie ma powodu obciążać nim sieci.
	Konsekwencja: inni gracze nie widzą twojej linki. Gdy to zacznie
	przeszkadzać, efekt trzeba przenieść na serwer — ale wtedy płacimy
	replikacją za każdy rzut każdego gracza.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Bobber = {}

local CONTAINER_NAME = "ClientEffects"
local CAST_DISTANCE = 22

local player = Players.LocalPlayer

local container: Folder? = nil
local bobber: BasePart? = nil
local beam: Beam? = nil

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

--[[ Górna powierzchnia strefy wody, albo nil gdy mapy jeszcze nie ma. ]]
local function waterSurfaceY(): number?
	local world = Workspace:FindFirstChild("World")
	if not world then
		return nil
	end

	local water = world:FindFirstChild("Water")
	if not water or not water:IsA("BasePart") then
		return nil
	end

	return water.Position.Y + water.Size.Y / 2
end

local function rodTip(): Attachment?
	local character = player.Character
	if not character then
		return nil
	end

	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then
		return nil
	end

	local handle = tool:FindFirstChild("Handle")
	if not handle then
		return nil
	end

	local tip = handle:FindFirstChild("Tip")
	if tip and tip:IsA("Attachment") then
		return tip
	end
	return nil
end

function Bobber.clear()
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
	Rzuca spławik przed gracza, na powierzchnię wody.

	Nic nie robi, gdy nie ma postaci, wędki w ręce albo strefy wody — to nie
	są błędy, tylko normalne stany (respawn, pierwsza klatka po wejściu).
]]
function Bobber.cast()
	Bobber.clear()

	local character = player.Character
	local root = character and character.PrimaryPart
	if not root then
		return
	end

	local surfaceY = waterSurfaceY()
	if not surfaceY then
		return
	end

	-- Rzutujemy kierunek patrzenia na płaszczyznę poziomą. Przy patrzeniu
	-- prosto w górę/dół zostaje wektor zerowy, a `.Unit` dałoby wtedy NaN
	-- i spławik wylądowałby "nigdzie" — stąd ten bezpiecznik.
	local forward = root.CFrame.LookVector
	local flat = Vector3.new(forward.X, 0, forward.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end

	local target = root.Position + flat.Unit * CAST_DISTANCE
	local landing = Vector3.new(target.X, surfaceY + 0.15, target.Z)

	local float = Instance.new("Part")
	float.Name = "Bobber"
	float.Shape = Enum.PartType.Ball
	float.Size = Vector3.new(0.6, 0.6, 0.6)
	float.Color = Color3.fromRGB(226, 72, 72)
	float.Material = Enum.Material.SmoothPlastic
	float.Anchored = true
	float.CanCollide = false
	float.CanQuery = false
	float.CanTouch = false
	float.Position = landing
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
		line.Width0 = 0.04
		line.Width1 = 0.04
		line.Color = ColorSequence.new(Color3.fromRGB(228, 232, 238))
		line.Transparency = NumberSequence.new(0.25)
		line.FaceCamera = true
		line.Parent = float
		beam = line
	end

	bobber = float
end

--[[ Szarpnięcie w momencie brania — jedyna czytelna informacja "teraz!" poza UI. ]]
function Bobber.dip()
	local float = bobber
	if not float then
		return
	end

	local down = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1, true)
	TweenService:Create(float, down, { Position = float.Position - Vector3.new(0, 0.45, 0) }):Play()
end

return Bobber
