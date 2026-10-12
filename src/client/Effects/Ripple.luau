--!strict
--[[
	Ripple — rozchodzący się krąg na wodzie.

	Wspólny dla spławika, skaczących ryb i deszczu. Był skopiowany w dwóch
	modułach; trzecia kopia przy deszczu przesądziła o wydzieleniu.
]]

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Ripple = {}

local CONTAINER_NAME = "ClientRipples"

local container: Folder? = nil

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

--[[ Krąg rośnie do `maxDiameter` studów i znika w `life` sekund.
     Sam się sprząta. ]]
function Ripple.spawn(position: Vector3, maxDiameter: number, life: number)
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
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(198, 232, 244)
	ring.Transparency = 0.45
	ring.Parent = getContainer()

	TweenService
		:Create(ring, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.05, maxDiameter, maxDiameter),
			Transparency = 1,
		})
		:Play()

	task.delay(life + 0.05, function()
		ring:Destroy()
	end)
end

return table.freeze(Ripple)
