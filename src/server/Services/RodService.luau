--!strict
--[[
	RodService — wędka jako Tool w plecaku gracza.

	Wędka jest budowana z kodu (jedna część + Attachment na czubku), a nie
	wstawiana jako gotowy model. Powód jest ten sam, co przy mapie: model to
	plik binarny w repo. Gdy przyjdzie czas na porządne modele, podmieńcie
	`buildRod` na klonowanie z `ServerStorage.Rods[id]` i wczytujcie je
	z assets/*.rbxm — reszta serwisu zostaje bez zmian.

	Atrybut `RodId` na Toolu jest kontraktem z FishingService: serwer uznaje
	zarzucenie tylko wtedy, gdy gracz faktycznie trzyma w ręku Tool z tym
	atrybutem. Nie ufamy w tej sprawie klientowi.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Util.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local Rods = require(ReplicatedStorage.Shared.Config.Rods)
local Types = require(ReplicatedStorage.Shared.Types)

local DataService = require(script.Parent.DataService)

type RodDefinition = Types.RodDefinition

local ROD_ATTRIBUTE = "RodId"

local RodService = {}

--[[
	Część wędki przyspawana do uchwytu.

	Części w Toolu MUSZĄ być odkotwiczone i przyspawane do Handle — kotwiczone
	zostałyby w powietrzu, gdy gracz odejdzie. `WeldConstraint` zapamiętuje
	przesunięcie z momentu utworzenia, więc najpierw ustawiamy CFrame,
	dopiero potem spawamy. Handle stoi w punkcie zero, więc `offset` jest
	od razu przesunięciem lokalnym.
]]
local function weldedPart(
	handle: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = offset
	part.Color = color
	part.Material = material
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	-- Bez tego kilka części wędki zaczyna ciągnąć postać w dół.
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = handle.Parent

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = part

	return part
end

--[[
	Wędka z części zamiast jednego patyka: rączka, kij, szczytówka,
	kołowrotek i przelotki. Kij leży wzdłuż lokalnego -Z, a na samym czubku
	siedzi Attachment „Tip", od którego klient rysuje żyłkę do spławika.
]]
local function buildRod(definition: RodDefinition): Tool
	local tool = Instance.new("Tool")
	tool.Name = definition.displayName
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = `Szczęście x{definition.luck} · okno {Format.seconds(definition.reelWindow)}`
	tool:SetAttribute(ROD_ATTRIBUTE, definition.id)
	-- Dłoń trzyma przy końcu rączki, a nie w połowie kija.
	tool.GripPos = Vector3.new(0, 0, 0.25)
	tool.GripForward = Vector3.new(0, 0, 1)
	tool.GripUp = Vector3.new(0, 1, 0)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.34, 0.34, 1.3)
	handle.CFrame = CFrame.new()
	handle.Color = Color3.fromRGB(78, 56, 38)
	handle.Material = Enum.Material.Wood
	handle.Anchored = false
	handle.CanCollide = false
	handle.Massless = true
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool

	weldedPart(
		handle,
		"Shaft",
		Vector3.new(0.17, 0.17, 4.2),
		CFrame.new(0, 0, -2.75),
		definition.color,
		Enum.Material.Wood
	)

	local tip = weldedPart(
		handle,
		"TipSection",
		Vector3.new(0.09, 0.09, 1.7),
		CFrame.new(0, 0, -5.7),
		definition.color,
		Enum.Material.Wood
	)

	-- Kołowrotek: walec leży wzdłuż osi X, więc domyślna orientacja od razu
	-- daje bęben ustawiony w poprzek kija. Nic nie trzeba obracać.
	local reel = weldedPart(
		handle,
		"Reel",
		Vector3.new(0.5, 0.78, 0.78),
		CFrame.new(0, -0.36, -0.95),
		Color3.fromRGB(196, 200, 208),
		Enum.Material.Metal
	)
	reel.Shape = Enum.PartType.Cylinder

	weldedPart(
		handle,
		"ReelKnob",
		Vector3.new(0.14, 0.14, 0.34),
		CFrame.new(0.3, -0.36, -0.95),
		Color3.fromRGB(44, 48, 56),
		Enum.Material.SmoothPlastic
	)

	-- Przelotki — drobiazg, ale to one sprawiają, że kij czyta się jako
	-- wędka, a nie jako kij.
	for index = 1, 3 do
		weldedPart(
			handle,
			`Guide{index}`,
			Vector3.new(0.22, 0.22, 0.07),
			CFrame.new(0, -0.09, -1.5 - index * 1.45),
			Color3.fromRGB(212, 216, 222),
			Enum.Material.Metal
		)
	end

	local tipAttachment = Instance.new("Attachment")
	tipAttachment.Name = "Tip"
	-- Lokalnie względem szczytówki: jej połowa długości w stronę czubka.
	tipAttachment.Position = Vector3.new(0, 0, -0.85)
	tipAttachment.Parent = tip

	return tool
end

--[[ Czy dany Instance to nasza wędka (a nie dowolny inny Tool). ]]
function RodService.isRod(instance: Instance): boolean
	return instance:IsA("Tool") and instance:GetAttribute(ROD_ATTRIBUTE) ~= nil
end

--[[
	Wędka, którą gracz TRZYMA w tej chwili (Tool jest w postaci, nie w plecaku).
	Zwraca nil, gdy gracz jej nie wyjął — FishingService odrzuca wtedy zarzucenie.
]]
function RodService.getHeldRod(player: Player): Tool?
	local character = player.Character
	if not character then
		return nil
	end

	local tool = character:FindFirstChildOfClass("Tool")
	if tool and RodService.isRod(tool) then
		return tool
	end
	return nil
end

local function removeRods(player: Player)
	local containers: { Instance } = {}

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		table.insert(containers, backpack)
	end
	if player.Character then
		table.insert(containers, player.Character)
	end

	for _, container in containers do
		for _, child in container:GetChildren() do
			if RodService.isRod(child) then
				child:Destroy()
			end
		end
	end
end

--[[
	Daje graczowi wędkę zgodną z profilem. Idempotentne: najpierw usuwa
	wszystkie poprzednie, więc nie da się nazbierać czterech kijów w plecaku.

	YIELDUJE — czeka na wczytanie profilu. Wołaj z event handlera lub task.spawn.
]]
function RodService.refresh(player: Player)
	local profile = DataService.waitFor(player)
	if not profile then
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	-- Profil mógł przeżyć usunięcie tieru z configu. `sanitize` to łapie,
	-- ale lepiej mieć tu drugi bezpiecznik niż gracza bez narzędzia.
	local definition = Rods.find(profile.equippedRod) or Rods.expect(GameConfig.STARTING_ROD)

	removeRods(player)
	buildRod(definition).Parent = backpack
end

function RodService.start()
	local function onCharacterAdded(player: Player)
		-- Backpack powstaje razem z postacią, ale nie zawsze przed tym
		-- eventem. Bez tego czekania wędka trafiałaby w nicość.
		local backpack = player:WaitForChild("Backpack", 10)
		if not backpack then
			warn(`[RodService] brak Backpacka dla {player.Name}`)
			return
		end
		RodService.refresh(player)
	end

	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function()
			onCharacterAdded(player)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player)
		end
	end

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
end

return RodService
