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

local function buildRod(definition: RodDefinition): Tool
	local tool = Instance.new("Tool")
	tool.Name = definition.displayName
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = `Szczęście x{definition.luck} · okno {Format.seconds(definition.reelWindow)}`
	tool:SetAttribute(ROD_ATTRIBUTE, definition.id)
	-- Chwyt bliżej końca kija, żeby wędka wyglądała jak trzymana, a nie
	-- wyważona w połowie.
	tool.GripPos = Vector3.new(0, 0, 1.8)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.22, 0.22, 4.6)
	handle.Color = definition.color
	handle.Material = Enum.Material.Wood
	handle.Massless = true
	handle.CanCollide = false
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool

	-- Attachment zamiast drugiej części: nie wymaga spawania, nie dodaje
	-- fizyki, a klient ma z czego poprowadzić linkę do spławika.
	local tip = Instance.new("Attachment")
	tip.Name = "Tip"
	tip.Position = Vector3.new(0, 0, -2.3)
	tip.Parent = handle

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
