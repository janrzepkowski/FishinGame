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

--[[ Kapelusz z dwóch brył, przyspawany do głowy. Bez niego dwie postacie
     w jednolitych kolorach wyglądają jak manekiny; z nim od razu widać,
     że to wędkarz i sklepowa, a nie gracze, którzy zamarli. ]]
local function addHat(model: Model, head: BasePart, color: Color3)
	local top = head.CFrame * CFrame.new(0, head.Size.Y / 2, 0)

	local pieces = {
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
	}

	for _, piece in pieces do
		-- `Build` kotwiczy części; kapelusz ma jechać z głową.
		piece.Anchored = false
		piece.Massless = true

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = piece
		weld.Parent = piece
	end
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
		addHat(model, head, definition.hat)

		model:SetAttribute(GameConfig.NPC_ATTRIBUTE, standKind)
		model:AddTag(GameConfig.NPC_TAG)
		model.Parent = parent
	end)
end

return table.freeze(Npc)
