--!strict
--[[
	Npc — stawia sprzedawców za ladami stoisk.

	Postać powstaje z `HumanoidDescription` przez
	`Players:CreateHumanoidModelFromDescriptionAsync` — pełny awatar R15
	z kodu, bez żadnego pliku modelu w repo. Wygląd (kolory, kapelusz)
	jest w `shared/Config/Npc`.

	Sprzedawca jest DEKORACJĄ Z GŁOSEM, nie mechaniką. Transakcje dalej
	obsługuje `ShopService` przez ProximityPrompt na ladzie; gdyby postać
	się nie zbudowała (wywołanie jest sieciowe i potrafi zawieść), sklep
	działa normalnie, tylko bez sprzedawcy.

	Budowa leci w `task.spawn`: wywołanie yielduje, a mapa nie może czekać
	ze startem serwera na awatar.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local NpcConfig = require(ReplicatedStorage.Shared.Config.Npc)

local Build = require(script.Parent.Build)

local Npc = {}

--[[ Przyspawa bryły do części ciała. `Build` kotwiczy części, a dodatki
     mają jechać z postacią. ]]
local function attach(anchor: BasePart, pieces: { BasePart })
	for _, piece in pieces do
		piece.Anchored = false
		piece.Massless = true

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = anchor
		weld.Part1 = piece
		weld.Parent = piece
	end
end

--[[ Kapelusz z dwóch brył: rondo i główka. ]]
local function addHat(model: Model, head: BasePart, color: Color3)
	local top = head.CFrame * CFrame.new(0, head.Size.Y / 2, 0)

	attach(head, {
		Build.cylinder(model, {
			Name = "HatBrim",
			Size = Vector3.new(0.18, 2.6, 2.6),
			-- Walec leży wzdłuż osi X — obrót wokół Z kładzie rondo płasko.
			CFrame = top * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Material = Enum.Material.Fabric,
		}),
		Build.cylinder(model, {
			Name = "HatCrown",
			Size = Vector3.new(0.7, 1.5, 1.5),
			CFrame = top * CFrame.new(0, 0.42, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Material = Enum.Material.Fabric,
		}),
	})
end

--[[
	Długie włosy: czapa na czubku, kurtyna na plecy i dwa pasma po bokach
	twarzy.

	Z brył, a nie z akcesorium z katalogu: akcesorium to asset o numerze,
	którego nie da się sprawdzić z repozytorium i który może zniknąć.
	Przód postaci to -Z, więc „z tyłu głowy" znaczy +Z.
]]
local function addLongHair(model: Model, head: BasePart, color: Color3)
	local size = head.Size
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.18)

	attach(head, {
		Build.block(model, {
			Name = "HairTop",
			Size = Vector3.new(size.X * 1.08, size.Y * 0.42, size.Z * 1.1),
			CFrame = head.CFrame * CFrame.new(0, size.Y * 0.36, 0.04),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
		}),
		-- Kurtyna sięga do połowy pleców.
		Build.block(model, {
			Name = "HairBack",
			Size = Vector3.new(size.X * 1.04, size.Y * 2.1, 0.34),
			CFrame = head.CFrame * CFrame.new(0, -size.Y * 0.62, size.Z * 0.52),
			Color = dark,
			Material = Enum.Material.SmoothPlastic,
		}),
		Build.block(model, {
			Name = "HairLeft",
			Size = Vector3.new(0.26, size.Y * 1.7, size.Z * 0.78),
			CFrame = head.CFrame * CFrame.new(-size.X * 0.54, -size.Y * 0.42, 0.18),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
		}),
		Build.block(model, {
			Name = "HairRight",
			Size = Vector3.new(0.26, size.Y * 1.7, size.Z * 0.78),
			CFrame = head.CFrame * CFrame.new(size.X * 0.54, -size.Y * 0.42, 0.18),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
		}),
	})
end

--[[ Fartuch: płat materiału na przodzie tułowia, sięgający za pas. ]]
local function addApron(model: Model, color: Color3)
	local torso = model:FindFirstChild("UpperTorso")
	if not torso or not torso:IsA("BasePart") then
		return
	end

	attach(torso, {
		Build.block(model, {
			Name = "Apron",
			Size = Vector3.new(torso.Size.X * 0.92, torso.Size.Y * 1.7, 0.14),
			CFrame = torso.CFrame * CFrame.new(0, -torso.Size.Y * 0.38, -torso.Size.Z / 2 - 0.08),
			Color = color,
			Material = Enum.Material.Fabric,
		}),
	})
end

--[[
	Stawia sprzedawcę. `feet` to miejsce, w którym mają stać stopy, zwrócone
	przodem (-Z) do klienta.
]]
function Npc.spawn(parent: Instance, feet: CFrame, standKind: string)
	local definition = NpcConfig.find(standKind)
	if not definition then
		return
	end

	task.spawn(function()
		local description = Instance.new("HumanoidDescription")
		description.HeadColor = definition.skin
		description.LeftArmColor = definition.shirt
		description.RightArmColor = definition.shirt
		description.TorsoColor = definition.shirt
		description.LeftLegColor = definition.pants
		description.RightLegColor = definition.pants
		description.HeightScale = definition.height
		description.WidthScale = definition.width
		description.DepthScale = definition.width

		local ok, result = pcall(function()
			return Players:CreateHumanoidModelFromDescriptionAsync(
				description,
				Enum.HumanoidRigType.R15
			)
		end)

		if not ok or not result then
			warn(
				`[Npc] nie udało się zbudować sprzedawcy "{definition.displayName}": {tostring(
					result
				)}`
			)
			return
		end

		local model = result
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		local head = model:FindFirstChild("Head")
		if not (humanoid and root and root:IsA("BasePart") and head and head:IsA("BasePart")) then
			model:Destroy()
			return
		end

		-- Stoisko mogło zostać przebudowane, zanim awatar dojechał.
		if not parent:IsDescendantOf(game) then
			model:Destroy()
			return
		end

		model.Name = definition.displayName
		humanoid.DisplayName = definition.displayName
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		-- Zakotwiczony korzeń: sprzedawcy nie da się zepchnąć ani przewrócić.
		root.Anchored = true

		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CanTouch = false
				descendant.CanQuery = false
			end
		end

		model:PivotTo(feet * CFrame.new(0, humanoid.HipHeight + root.Size.Y / 2, 0))
		if definition.hat then
			addHat(model, head, definition.hat)
		end
		if definition.longHair then
			addLongHair(model, head, definition.longHair)
		end
		if definition.apron then
			addApron(model, definition.apron)
		end

		model:SetAttribute(GameConfig.NPC_ATTRIBUTE, standKind)
		model:AddTag(GameConfig.NPC_TAG)
		model.Parent = parent
	end)
end

return table.freeze(Npc)
