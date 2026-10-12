--!strict
--[[
	AnglerRig — proceduralna poza wędkarza na jednej postaci.

	DLACZEGO PROCEDURALNIE, A NIE ANIMACJĄ
	Animacje w Robloxie są assetami: trzeba je zrobić w edytorze, wgrać na
	platformę i odwołać się po `rbxassetid`. Tego nie da się zrobić
	z repozytorium z kodem. Zamiast tego nakładamy kąty z `CastPose` na
	`Transform` stawów — dokładnie tę warstwę, którą Roblox wystawia do
	nadpisywania animacji — a drugą rękę doprowadza do kija `IKControl`.

	KLUCZOWY SZCZEGÓŁ: Animator nadpisuje `Transform` w KAŻDEJ klatce.
	`update` musi więc lecieć po nim, a przed symulacją — z
	`RunService.PreSimulation`. Robi to `AnglerController`, jedną pętlą dla
	wszystkich postaci (tam też jest opis, dlaczego nie `RenderStepped`).

	Rig nie wie, czyja to postać. Dostaje stan (`setState`) i rysuje pozę —
	tak samo dla lokalnego gracza i dla cudzych postaci, których stan
	przychodzi z atrybutów ustawianych przez serwer.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cast = require(Shared.Util.Cast)
local CastPose = require(Shared.Util.CastPose)
local GameConfig = require(Shared.Config.Game)

local AnglerRig = {}

--[[
	Fazy pozy. To samo co `Types.FishingPhase` plus `Windup`: zastygły zamach
	między puszczeniem przycisku a potwierdzeniem rzutu przez serwer. Bez
	niego ręka lokalnego gracza opadałaby na czas pingu i dopiero potem
	wykonywała wymach.
]]
export type Phase = "Idle" | "Charging" | "Windup" | "Waiting" | "Biting" | "Fighting"

export type State = {
	phase: Phase,
	-- Moc rzutu 0..1 (dla `Windup` i `Waiting`).
	power: number,
	tension: number,
	surging: boolean,
}

export type Rig = {
	setState: (state: State) -> (),
	update: (now: number) -> (),
	destroy: () -> (),
}

local ROD_ATTRIBUTE = "RodId"
local IK_NAME = "FishinGameOffHand"
local OFF_HAND_NAME = "OffHandGrip"

--[[
	Oś obrotu barku.

	X odpowiada za machnięcie przód-tył, czyli dokładnie to, co robi
	wędkarz. Niewielka składowa Z dokłada odchylenie na zewnątrz, dzięki
	czemu kij nie przechodzi postaci przez głowę w fazie zamachu —
	prawdziwy rzut też idzie lekko z boku, nad barkiem, a nie przez czubek.
]]
local SWING_AXIS = Vector3.new(1, 0, 0.22).Unit

-- Jak daleko od rękojeści (w stronę czubka) chwyta druga ręka.
local OFF_HAND_REACH = 1.3
-- Po wymachu druga ręka wraca na kij dopiero, gdy ruch się uspokoi.
-- Rzut jedną ręką czyta się naturalniej niż sztywne trzymanie oburącz.
local OFF_HAND_AFTER_CAST = 0.5

--[[
	Staw postaci: klasyczny `Motor6D` albo nowy `AnimationConstraint`.

	Roblox przenosi awatary na stawy oparte o więzy (`AnimationConstraint`
	+ `BallSocketConstraint`) i część postaci NIE MA już `Motor6D` w rękach
	ani w talii. Oba typy mają tę samą właściwość `Transform`, więc pozę
	nakładamy tak samo. Sprawdzanie wyłącznie `Motor6D` — jak robił to
	poprzedni kod zamachu — sprawiało, że na takich awatarach animacja po
	cichu nie robiła nic.
]]
local function pose(parent: Instance?, name: string, transform: CFrame): boolean
	local found = parent and parent:FindFirstChild(name)
	if not found then
		return false
	end

	-- Dwie gałęzie zamiast unii typów: analiza zawęża wtedy `found` do
	-- konkretnej klasy i pozwala pisać do `Transform` bez rzutowania.
	if found:IsA("Motor6D") then
		found.Transform = transform
		return true
	end

	local constraint = if found:IsA("AnimationConstraint") then found else nil
	if constraint then
		constraint.Transform = transform
	end
	return constraint ~= nil
end

--[[ Nakłada cztery kąty na stawy ręki z wędką i talię. ]]
local function applyPose(
	character: Model,
	shoulder: CFrame,
	elbow: CFrame,
	waist: CFrame,
	wrist: CFrame
)
	-- R6 trzyma bark w `Torso` pod nazwą ze spacją i nie ma pozostałych stawów.
	if not pose(character:FindFirstChild("RightUpperArm"), "RightShoulder", shoulder) then
		pose(character:FindFirstChild("Torso"), "Right Shoulder", shoulder)
	end
	pose(character:FindFirstChild("RightLowerArm"), "RightElbow", elbow)
	pose(character:FindFirstChild("UpperTorso"), "Waist", waist)
	pose(character:FindFirstChild("RightHand"), "RightWrist", wrist)
end

local function heldRod(character: Model): Tool?
	local tool = character:FindFirstChildOfClass("Tool")
	return if tool and tool:GetAttribute(ROD_ATTRIBUTE) ~= nil then tool else nil
end

function AnglerRig.new(character: Model): Rig
	local state: State = { phase = "Idle", power = 0, tension = 0, surging = false }
	local phaseStartedAt = os.clock()
	-- Czy w poprzedniej klatce nadpisywaliśmy stawy — żeby przy powrocie do
	-- `Idle` wyzerować je dokładnie raz, a potem zostawić postać w spokoju.
	local posed = false

	local ik: IKControl? = nil
	local offHand: Attachment? = nil
	local offHandTool: Tool? = nil

	local self = {} :: Rig

	--[[
		Punkt chwytu drugiej ręki na kiju.

		Liczymy go z geometrii wędki (od rękojeści w stronę czubka), a nie
		z ręcznie wpisanego przesunięcia: wędki różnych klas mają różne
		modele i sztywna liczba trafiałaby obok kija.
	]]
	local function ensureOffHand(tool: Tool): Attachment?
		local existing = offHand
		if existing and existing.Parent and offHandTool == tool then
			return existing
		end

		if existing then
			existing:Destroy()
			offHand = nil
		end

		local handle = tool:FindFirstChild("Handle")
		local tip = tool:FindFirstChild("Tip", true)
		if not (handle and handle:IsA("BasePart") and tip and tip:IsA("Attachment")) then
			return nil
		end

		local toTip = handle.CFrame:PointToObjectSpace(tip.WorldPosition)
		if toTip.Magnitude < 1e-3 then
			return nil
		end

		local attachment = Instance.new("Attachment")
		attachment.Name = OFF_HAND_NAME
		attachment.Position = toTip.Unit * OFF_HAND_REACH
		attachment.Parent = handle

		offHand = attachment
		offHandTool = tool
		return attachment
	end

	local function setOffHand(tool: Tool?, enabled: boolean)
		local control = ik

		if not enabled or not tool then
			if control then
				control.Enabled = false
			end
			return
		end

		-- R6 nie ma osobnej dłoni ani łokcia — tam zostaje sam ruch barku.
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local upperArm = character:FindFirstChild("LeftUpperArm")
		local hand = character:FindFirstChild("LeftHand")
		local target = ensureOffHand(tool)
		if not (humanoid and upperArm and hand and target) then
			return
		end

		local active: IKControl
		if control and control.Parent then
			active = control
		else
			active = Instance.new("IKControl")
			active.Name = IK_NAME
			active.Type = Enum.IKControlType.Position
			-- Miękkie dojście: ręka sięga do kija, zamiast się do niego
			-- teleportować przy zmianie fazy.
			active.SmoothTime = 0.12
			active.Parent = humanoid
			ik = active
		end

		active.ChainRoot = upperArm
		active.EndEffector = hand
		active.Target = target
		active.Enabled = true
	end

	local function resetJoints()
		applyPose(character, CFrame.identity, CFrame.identity, CFrame.identity, CFrame.identity)
	end

	function self.setState(next: State)
		if next.phase ~= state.phase then
			phaseStartedAt = os.clock()
		end
		state = next
	end

	function self.update(now: number)
		local tool = heldRod(character)
		local phase = state.phase

		if phase == "Idle" or not tool then
			if posed then
				posed = false
				resetJoints()
				setOffHand(nil, false)
			end
			return
		end

		local elapsed = now - phaseStartedAt
		local shoulderAngle, elbowAngle, waistAngle, wristAngle = 0, 0, 0, 0
		local twoHanded = true

		if phase == "Charging" then
			-- Bieżącą moc liczymy z tej samej funkcji co pasek. U obserwatora
			-- start fazy jest przesunięty o ping, więc wahanie nie jest co do
			-- klatki zgodne z paskiem rzucającego — ale głębokość zamachu
			-- przy puszczeniu bierzemy już z atrybutu mocy, nie stąd.
			local live = Cast.powerAt(elapsed, GameConfig.CAST_POWER_PERIOD)
			shoulderAngle, elbowAngle, waistAngle, wristAngle = CastPose.charging(elapsed, live)
		elseif phase == "Windup" then
			shoulderAngle, elbowAngle, waistAngle, wristAngle = CastPose.casting(0, state.power)
		elseif phase == "Waiting" then
			shoulderAngle, elbowAngle, waistAngle, wristAngle =
				CastPose.casting(elapsed, state.power)
			twoHanded = elapsed > OFF_HAND_AFTER_CAST
		elseif phase == "Biting" then
			shoulderAngle, elbowAngle, waistAngle, wristAngle = CastPose.biting(elapsed)
		else
			shoulderAngle, elbowAngle, waistAngle, wristAngle =
				CastPose.fighting(elapsed, state.tension, state.surging)
		end

		posed = true

		applyPose(
			character,
			CFrame.fromAxisAngle(SWING_AXIS, shoulderAngle),
			CFrame.Angles(elbowAngle, 0, 0),
			CFrame.Angles(waistAngle, 0, 0),
			CFrame.Angles(wristAngle, 0, 0)
		)

		setOffHand(tool, twoHanded)
	end

	function self.destroy()
		if posed and character.Parent then
			resetJoints()
		end
		posed = false

		if ik then
			ik:Destroy()
			ik = nil
		end
		if offHand then
			offHand:Destroy()
			offHand = nil
		end
		offHandTool = nil
	end

	return self
end

return table.freeze(AnglerRig)
