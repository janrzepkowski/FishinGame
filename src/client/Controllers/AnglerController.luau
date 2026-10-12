--!strict
--[[
	AnglerController — animuje WSZYSTKIE łowiące postacie w zasięgu.

	Serwer ogłasza, co postać robi, atrybutami na jej modelu (`FishingPhase`,
	`CastPower`, `CastTarget`, `Tension`, `FishSurging`, `FishingNibbles`).
	Ten kontroler czyta je dla każdej postaci i rysuje z nich pozę
	(`AnglerRig`) oraz — dla cudzych postaci — spławik i żyłkę (`Bobber`).

	Sieć nie niesie więc animacji, tylko kilka bajtów przy zmianie fazy.
	Gracz, który podejdzie w trakcie cudzej walki, dostaje atrybuty razem
	z postacią i od razu widzi właściwą pozę.

	LOKALNY GRACZ MA DWA WYJĄTKI, oba dla responsywności:
	  * fazę bierzemy z `FishingController`, nie z atrybutu — zamach ma
	    zacząć się w klatce wciśnięcia przycisku, a nie po rundzie do serwera,
	  * spławik prowadzi `FishingController` ze zdarzeń serwera (ma dokładny
	    stan walki 20 razy na sekundę), więc tutaj go nie dublujemy.
	Poza tym własna postać idzie przez dokładnie ten sam `AnglerRig` co cudze.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cast = require(Shared.Util.Cast)
local CastPose = require(Shared.Util.CastPose)
local GameConfig = require(Shared.Config.Game)
local Rods = require(Shared.Config.Rods)

local AnglerRig = require(script.Parent.Parent.Effects.AnglerRig)
local Bobber = require(script.Parent.Parent.Effects.Bobber)
local FishingController = require(script.Parent.FishingController)

local AnglerController = {}

local ROD_ATTRIBUTE = "RodId"
-- Dalej niż tyle od kamery poza i tak nie jest czytelna, a każda animowana
-- postać to kilka zapisów do stawów na klatkę.
local ANIMATE_RADIUS = 180

type Entry = {
	character: Model,
	rig: AnglerRig.Rig,
	-- Spławik tylko dla cudzych postaci (patrz nagłówek).
	float: Bobber.Float?,
	connections: { RBXScriptConnection },
}

local localPlayer = Players.LocalPlayer
local entries: { [Player]: Entry } = {}
local bound = false

local function numberAttribute(character: Model, name: string): number
	local value = character:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function remotePhase(character: Model): AnglerRig.Phase
	local value = character:GetAttribute(GameConfig.ATTRIBUTE_PHASE)
	if value == "Charging" or value == "Waiting" or value == "Biting" or value == "Fighting" then
		return value
	end
	return "Idle"
end

--[[ Faza lokalnego gracza z kontrolera. `Casting` (rzut wysłany, serwer
     jeszcze nie potwierdził) to zastygły zamach. ]]
local function localPhase(): AnglerRig.Phase
	local phase = FishingController.getPhase()
	if phase == "Casting" then
		return "Windup"
	elseif phase == "Charging" then
		return "Charging"
	elseif phase == "Waiting" then
		return "Waiting"
	elseif phase == "Biting" then
		return "Biting"
	elseif phase == "Fighting" then
		return "Fighting"
	end
	return "Idle"
end

local function pushState(player: Player, entry: Entry)
	local character = entry.character
	local isLocal = player == localPlayer

	entry.rig.setState({
		phase = if isLocal then localPhase() else remotePhase(character),
		power = if isLocal
			then FishingController.getCastPower()
			else numberAttribute(character, GameConfig.ATTRIBUTE_POWER),
		tension = numberAttribute(character, GameConfig.ATTRIBUTE_TENSION),
		surging = character:GetAttribute(GameConfig.ATTRIBUTE_SURGING) == true,
	})
end

--[[ Czas lotu cudzego spławika — z tej samej funkcji co własnego. ]]
local function flightTimeFor(character: Model, landing: Vector3): number
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return Cast.flightTime(0, 1)
	end

	local distance = (Vector3.new(landing.X, root.Position.Y, landing.Z) - root.Position).Magnitude
	local tool = character:FindFirstChildOfClass("Tool")
	local rodId = if tool then tool:GetAttribute(ROD_ATTRIBUTE) else nil
	local rod = if typeof(rodId) == "string" then Rods.find(rodId) else nil
	return Cast.flightTime(distance, if rod then rod.castRange else distance)
end

--[[ Reakcja cudzego spławika na zmianę fazy. ]]
local function onRemotePhase(entry: Entry)
	local float = entry.float
	if not float then
		return
	end

	local character = entry.character
	local phase = remotePhase(character)

	if phase == "Waiting" then
		local landing = character:GetAttribute(GameConfig.ATTRIBUTE_TARGET)
		if typeof(landing) ~= "Vector3" then
			return
		end

		-- Spławik wylatuje w momencie puszczenia żyłki, nie na starcie wymachu.
		task.delay(CastPose.RELEASE_DELAY, function()
			if remotePhase(character) == "Waiting" and character.Parent then
				float.launch(landing, flightTimeFor(character, landing))
			end
		end)
	elseif phase == "Biting" then
		float.dip()
	elseif phase == "Fighting" then
		float.beginFight()
	elseif phase == "Idle" then
		float.reelIn()
	end
end

local function untrack(player: Player)
	local entry = entries[player]
	if not entry then
		return
	end
	entries[player] = nil

	for _, connection in entry.connections do
		connection:Disconnect()
	end
	entry.rig.destroy()
	if entry.float then
		entry.float.clear()
	end
end

local function track(player: Player, character: Model)
	untrack(player)

	local isLocal = player == localPlayer
	local entry: Entry = {
		character = character,
		rig = AnglerRig.new(character),
		float = if isLocal then nil else Bobber.forCharacter(character),
		connections = {},
	}
	entries[player] = entry

	local function watch(attribute: string, handler: () -> ())
		table.insert(
			entry.connections,
			character:GetAttributeChangedSignal(attribute):Connect(handler)
		)
	end

	local function refresh()
		pushState(player, entry)
	end

	watch(GameConfig.ATTRIBUTE_POWER, refresh)
	watch(GameConfig.ATTRIBUTE_SURGING, refresh)

	watch(GameConfig.ATTRIBUTE_TENSION, function()
		refresh()
		local float = entry.float
		if float and remotePhase(character) == "Fighting" then
			float.setTension(
				numberAttribute(character, GameConfig.ATTRIBUTE_TENSION),
				character:GetAttribute(GameConfig.ATTRIBUTE_SURGING) == true
			)
		end
	end)

	watch(GameConfig.ATTRIBUTE_PHASE, function()
		refresh()
		onRemotePhase(entry)
	end)

	watch(GameConfig.ATTRIBUTE_NIBBLES, function()
		local float = entry.float
		if float and remotePhase(character) == "Waiting" then
			float.nibble()
		end
	end)

	-- Postać mogła dojechać już w trakcie łowienia (dołączenie do gry,
	-- wejście w zasięg streamingu) — wtedy zmiany atrybutu nie będzie.
	refresh()
end

local function watchPlayer(player: Player)
	if player.Character then
		track(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		track(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		untrack(player)
	end)
end

local function update()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local now = os.clock()
	local origin = camera.CFrame.Position

	for player, entry in entries do
		local root = entry.character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			if player == localPlayer or (root.Position - origin).Magnitude <= ANIMATE_RADIUS then
				entry.rig.update(now)
			end
		end
	end
end

function AnglerController.start()
	if bound then
		return
	end
	bound = true

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(untrack)

	FishingController.onPhaseChanged(function()
		local entry = entries[localPlayer]
		if entry then
			pushState(localPlayer, entry)
		end
	end)

	--[[
		`PreSimulation`, a NIE `RenderStepped` — i to jest sedno całego modułu.

		Animator zapisuje pozę stawów w kroku animacji, tuż przed symulacją.
		Nowe stawy awatarów (`AnimationConstraint`) są rozwiązywane w samej
		symulacji, więc liczy się to, co stoi w `Transform` w TYM momencie.
		Zapis z `RenderStepped` jest widoczny w odczycie, ale Animator
		nadpisuje go, zanim cokolwiek trafi na ekran — zmierzone sondą:
		po naszym zapisie -1,35, w `PreSimulation` z powrotem 1,38.
		Zapis w `PreSimulation` trafia po Animatorze i przed solverem,
		i działa tak samo dla klasycznych `Motor6D`.
	]]
	RunService.PreSimulation:Connect(update)
end

return table.freeze(AnglerController)
