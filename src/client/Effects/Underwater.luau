--!strict
--[[
	Underwater — zmiana obrazu, gdy kamera schodzi pod lustro wody.

	Roblox sam przyciemnia widok pod wodą Terrain, ale robi to subtelnie.
	Dokładamy wyraźny niebieski filtr i rozmycie, bo to jedyny sygnał,
	że gracz PŁYWA, a nie chodzi — a pływając nie można łowić.

	Efekty tworzy KLIENT, więc nie replikują się: każdy widzi własne
	zanurzenie. Gdyby robił to serwer, wejście jednego gracza do wody
	zasiniłoby ekran całej serwerowni.
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local LakeConfig = require(Shared.Config.Lake)

local Underwater = {}

local TRANSITION = 0.35

local tint: ColorCorrectionEffect? = nil
local blur: BlurEffect? = nil
local submerged = false

local function apply(active: boolean)
	local color, haze = tint, blur
	if not (color and haze) then
		return
	end

	local info = TweenInfo.new(TRANSITION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	TweenService:Create(color, info, {
		TintColor = if active then Color3.fromRGB(92, 168, 208) else Color3.fromRGB(255, 255, 255),
		Brightness = if active then -0.08 else 0,
		Saturation = if active then -0.15 else 0,
	}):Play()

	TweenService:Create(haze, info, { Size = if active then 16 else 0 }):Play()
end

function Underwater.start()
	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "UnderwaterTint"
	color.Parent = Lighting
	tint = color

	local haze = Instance.new("BlurEffect")
	haze.Name = "UnderwaterBlur"
	haze.Size = 0
	haze.Parent = Lighting
	blur = haze

	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end

		local position = camera.CFrame.Position
		-- Sprawdzamy OBA warunki: poniżej lustra wody I w obrysie zbiornika.
		-- Sama wysokość dałaby niebieski ekran każdemu, kto zejdzie do piwnicy
		-- po drugiej stronie mapy.
		local isUnder = position.Y < LakeConfig.SURFACE_Y - 0.4 and LakeConfig.isOverWater(position)

		if isUnder ~= submerged then
			submerged = isUnder
			apply(isUnder)
		end
	end)
end

function Underwater.isSubmerged(): boolean
	return submerged
end

return Underwater
