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
local RodModel = require(ReplicatedStorage.Shared.Util.RodModel)
local Rods = require(ReplicatedStorage.Shared.Config.Rods)
local Types = require(ReplicatedStorage.Shared.Types)

local DataService = require(script.Parent.DataService)

type RodDefinition = Types.RodDefinition

local ROD_ATTRIBUTE = "RodId"

local RodService = {}

--[[
	Buduje wędkę jako Tool z brył opisanych w `shared/Util/RodModel`.

	Ta sama lista brył zasila podgląd w sklepie i ikonę na pasku, więc
	wędka w ręce i wędka na obrazku NIE MOGĄ się rozjechać — bo to jest
	dosłownie ten sam opis.

	=========================================================================
	CHWYT (Tool.Grip) — dlaczego wędka wychodziła zza pleców
	=========================================================================
	Roblox spawa Handle z ręką weldem, w którym `C1 = Tool.Grip`, czyli:

	    Handle.CFrame = Ręka.CFrame * C0 * Grip:Inverse()

	Dla domyślnego `C0` ręki obrót o -90° wokół X odwzorowuje lokalne -Z
	rączki na kierunek WYCHODZĄCY Z DŁONI. Kij zbudowany wzdłuż -Z
	(patrz `RodModel`) celuje więc przed gracza i wszystko się zgadza.

	Błąd polegał na `GripForward = (0, 0, 1)`. `GripForward` jest
	z definicji LookVectorem chwytu, a LookVector w Robloxie to **-Z** —
	podanie (0,0,1) obracało chwyt o 180° wokół Y, przez co -Z rączki
	mapowało się w stronę barku. Stąd wędka za plecami.

	Dlatego NIE ustawiamy `GripForward`/`GripUp`/`GripRight` osobno: są
	wyliczane z macierzy `Grip` i pojedynczo potrafią zostawić ją niespójną.
	Jeden kompletny CFrame i tyle.

	Chwyt jest CZYSTYM PRZESUNIĘCIEM, bez obrotu. Pochylenie wędki w spoczynku
	robi ramię (`CastAnimation.HOLD_ANGLE`), bo prawdziwy wędkarz też unosi
	kij ramieniem, nie nadgarstkiem. Mniej stałych tutaj = mniej rzeczy,
	które mogą być źle ustawione.
]]
local GRIP_OFFSET = Vector3.new(0, 0, 0.45)

local function buildRod(definition: RodDefinition): Tool
	local tool = Instance.new("Tool")
	tool.Name = definition.displayName
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = `Szczęście x{definition.luck} · okno {Format.seconds(definition.reelWindow)}`
	tool:SetAttribute(ROD_ATTRIBUTE, definition.id)
	tool.Grip = CFrame.new(GRIP_OFFSET)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = RodModel.handleSize()
	handle.CFrame = CFrame.identity
	handle.Color = RodModel.handleColor()
	handle.Material = Enum.Material.SmoothPlastic
	handle.Anchored = false
	handle.CanCollide = false
	-- Bez tego kilka części wędki zaczyna ciągnąć postać w dół.
	handle.Massless = true
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool

	local tipSection: BasePart? = nil

	for _, piece in RodModel.pieces(definition) do
		local part = Instance.new("Part")
		part.Name = piece.name
		part.Size = piece.size
		-- CFrame USTAWIAMY PRZED spawaniem: WeldConstraint zapamiętuje
		-- przesunięcie z momentu utworzenia, więc kolejność ma znaczenie.
		part.CFrame = piece.cframe
		part.Color = piece.color
		part.Material = piece.material
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		if piece.shape then
			part.Shape = piece.shape
		end
		part.Parent = tool

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = part

		if piece.name == "TipSection" then
			tipSection = part
		end
	end

	-- Attachment „Tip" na czubku — stąd klient ciągnie żyłkę do spławika.
	local tipAttachment = Instance.new("Attachment")
	tipAttachment.Name = "Tip"
	if tipSection then
		-- Lokalnie względem szczytówki.
		tipAttachment.Position = Vector3.new(0, 0, -tipSection.Size.Z / 2)
		tipAttachment.Parent = tipSection
	else
		tipAttachment.Position = RodModel.tipOffset()
		tipAttachment.Parent = handle
	end

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
