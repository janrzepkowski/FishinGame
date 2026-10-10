--!strict
--[[
	CastAnimation — zamach wędką: ramię i obrót kija.

	DLACZEGO PROCEDURALNIE, A NIE ANIMACJĄ
	Animacje w Robloxie są assetami: trzeba je zrobić w edytorze animacji,
	wgrać na platformę i odwołać się po `rbxassetid`. Tego nie da się zrobić
	z repozytorium z kodem — a cała zasada tego projektu brzmi „zero binariów
	w gicie". Zamiast tego nakładamy pozę na `Motor6D.Transform`, czyli
	dokładnie tę warstwę, którą Roblox wystawia do nadpisywania animacji.

	KLUCZOWY SZCZEGÓŁ: `Transform` jest kasowany przez Animatora w KAŻDEJ
	klatce. Dlatego piszemy do niego z `BindToRenderStep` o priorytecie
	WYŻSZYM (liczbowo większym) niż `RenderPriority.Character` — czyli już
	po tym, jak animacje się policzyły. Przy zwykłym `RenderStepped`
	albo niższym priorytecie poza znika i nic się nie dzieje.

	EFEKT JEST LOKALNY. Inni gracze nie zobaczą zamachu — tak samo jak
	nie widzą spławika. Gdyby miał być widoczny dla wszystkich, pozę
	musiałby wysyłać serwer, płacąc replikacją za każdy rzut każdego gracza.
	Przy jednym kliencie oglądającym własny rzut to się nie opłaca.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CastAnimation = {}

export type Phase = "Idle" | "Cast" | "Hold" | "Bite"

--[[
	Oś obrotu barku.

	X odpowiada za machnięcie przód-tył, czyli dokładnie to, co robi
	wędkarz. Niewielka składowa Z dokłada odchylenie na zewnątrz, dzięki
	czemu kij nie przechodzi graczowi przez głowę w fazie zamachu —
	prawdziwy rzut też idzie lekko z boku, nad barkiem, a nie przez czubek.

	Jeśli ramię macha w złą stronę, zmienia się TYLKO ta oś albo znaki
	kątów niżej. Reszta animacji jest od tego niezależna.
]]
local SWING_AXIS = Vector3.new(1, 0, 0.22).Unit

-- Czasy faz zamachu (sekundy od startu).
local WINDUP_END = 0.30
local WHIP_END = 0.44
-- Moment puszczenia żyłki. Celowo tuż PRZED końcem wymachu: spławik ma
-- wylecieć w trakcie ruchu, a nie po jego zakończeniu.
local RELEASE_AT = 0.37
local SETTLE_END = 0.78

--[[
	Kąty w radianach. Ujemny = ramię w tył, nad bark.

	-72° to pozycja „na drugą godzinę" — tak wygląda zamach w prawdziwym
	rzucie przez głowę. +49° to wyprost w przód, mniej więcej na dziesiątą.
	Po wymachu ramię wraca do +13°, czyli trzyma wędkę lekko uniesioną.
]]
local WINDUP_ANGLE = -1.25
local WHIP_ANGLE = 0.85
local HOLD_ANGLE = 0.22

local BIND_NAME = "FishinGameCast"

local player = Players.LocalPlayer

local phase: Phase = "Idle"
local phaseStartedAt = 0
local bound = false

local shoulder: Motor6D? = nil
local tool: Tool? = nil
-- Chwyt ustawiony przez serwer, zanim zaczęliśmy go modyfikować.
-- `capturedTool` pilnuje, żeby odczytać go DOKŁADNIE RAZ na narzędzie:
-- ponowny odczyt w trakcie zamachu zapisałby pozę pośrednią jako bazę
-- i wędka zostałaby przekrzywiona na stałe.
local baseGrip = CFrame.identity
local capturedTool: Tool? = nil
local releaseCallback: (() -> ())? = nil
local releaseFired = false

--[[
	Bark prawej ręki. R15 trzyma Motor6D w `RightUpperArm`, R6 w `Torso`
	pod nazwą ze spacją. Obsługujemy oba, bo gracz wybiera typ awatara
	w ustawieniach konta i gra nie ma na to wpływu.
]]
local function findShoulder(character: Model): Motor6D?
	local upperArm = character:FindFirstChild("RightUpperArm")
	if upperArm then
		local motor = upperArm:FindFirstChild("RightShoulder")
		if motor and motor:IsA("Motor6D") then
			return motor
		end
	end

	local torso = character:FindFirstChild("Torso")
	if torso then
		local motor = torso:FindFirstChild("Right Shoulder")
		if motor and motor:IsA("Motor6D") then
			return motor
		end
	end

	return nil
end

local function heldRodTool(): Tool?
	local character = player.Character
	if not character then
		return nil
	end

	local found = character:FindFirstChildOfClass("Tool")
	if found and found:GetAttribute("RodId") ~= nil then
		return found
	end
	return nil
end

--[[ Wygładzenie 0..1: szybki start, miękkie dojście. ]]
local function easeOut(t: number): number
	local clamped = math.clamp(t, 0, 1)
	return 1 - (1 - clamped) * (1 - clamped)
end

local function easeIn(t: number): number
	local clamped = math.clamp(t, 0, 1)
	return clamped * clamped
end

--[[
	Kąt ramienia dla danego momentu zamachu.

	Trzy odcinki: zamach w tył (wolno), wymach w przód (szybko), powrót
	do pozycji trzymania. Różnica tempa jest tym, co odróżnia „zamach"
	od „machnięcia ręką" — bez niej ruch wygląda jak wycieraczka.
]]
local function castAngle(elapsed: number): number
	if elapsed < WINDUP_END then
		return WINDUP_ANGLE * easeOut(elapsed / WINDUP_END)
	end

	if elapsed < WHIP_END then
		local t = (elapsed - WINDUP_END) / (WHIP_END - WINDUP_END)
		return WINDUP_ANGLE + (WHIP_ANGLE - WINDUP_ANGLE) * easeIn(t)
	end

	local t = (elapsed - WHIP_END) / (SETTLE_END - WHIP_END)
	return WHIP_ANGLE + (HOLD_ANGLE - WHIP_ANGLE) * easeOut(t)
end

--[[ Dodatkowy obrót samego kija w dłoni. Kij wyprzedza ramię, przez co
     wymach czyta się jako bat, a nie jako sztywny drąg. ]]
local function rodPitch(elapsed: number): number
	if elapsed < WINDUP_END then
		return -0.5 * easeOut(elapsed / WINDUP_END)
	end
	if elapsed < WHIP_END then
		local t = (elapsed - WINDUP_END) / (WHIP_END - WINDUP_END)
		return -0.5 + 1.3 * easeIn(t)
	end
	local t = (elapsed - WHIP_END) / (SETTLE_END - WHIP_END)
	return 0.8 - 0.8 * easeOut(t)
end

local function apply(angle: number, pitch: number)
	local motor = shoulder
	if motor and motor.Parent then
		motor.Transform = CFrame.fromAxisAngle(SWING_AXIS, angle)
	end

	local rod = tool
	if rod and rod.Parent then
		rod.Grip = baseGrip * CFrame.Angles(pitch, 0, 0)
	end
end

local function update()
	if phase == "Idle" then
		return
	end

	local elapsed = os.clock() - phaseStartedAt

	if phase == "Cast" then
		if not releaseFired and elapsed >= RELEASE_AT then
			releaseFired = true
			local callback = releaseCallback
			releaseCallback = nil
			if callback then
				-- Odpalamy poza pętlą renderowania: callback stawia spławik
				-- i tworzy instancje, a to nie jest praca na render step.
				task.spawn(callback)
			end
		end

		apply(castAngle(elapsed), rodPitch(elapsed))

		if elapsed >= SETTLE_END then
			phase = "Hold"
			phaseStartedAt = os.clock()
		end
		return
	end

	if phase == "Hold" then
		apply(HOLD_ANGLE, 0)
		return
	end

	-- Bite: dwa szybkie szarpnięcia czubkiem w dół, potem drganie.
	-- To samo, co robi spławik, tylko po stronie wędki — gracz patrzy
	-- raz na jedno, raz na drugie.
	local wobble = math.sin(elapsed * 22) * 0.12 * math.exp(-elapsed * 1.5)
	apply(HOLD_ANGLE + wobble, 0.25 + wobble)
end

local function beginPhase(next: Phase)
	phase = next
	phaseStartedAt = os.clock()
end

--[[
	Zaczyna zamach. `onRelease` leci w momencie puszczenia żyłki — to wtedy
	spławik ma opuścić czubek wędki, a nie na początku ani na końcu ruchu.
]]
function CastAnimation.playCast(onRelease: () -> ())
	shoulder = if player.Character then findShoulder(player.Character) else nil
	tool = heldRodTool()

	local rod = tool
	if rod and rod ~= capturedTool then
		capturedTool = rod
		baseGrip = rod.Grip
	end

	releaseCallback = onRelease
	releaseFired = false
	beginPhase("Cast")
end

function CastAnimation.playBite()
	beginPhase("Bite")
end

--[[ Wraca do pozycji neutralnej i oddaje kontrolę animacjom Robloxa. ]]
function CastAnimation.reset()
	phase = "Idle"
	releaseCallback = nil

	local motor = shoulder
	if motor and motor.Parent then
		motor.Transform = CFrame.identity
	end

	local rod = tool
	if rod and rod.Parent then
		rod.Grip = baseGrip
	end
end

function CastAnimation.start()
	if bound then
		return
	end
	bound = true

	-- Priorytet WYŻSZY niż Character: inaczej Animator nadpisze nam pozę
	-- w tej samej klatce i nie zobaczymy nic.
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Character.Value + 1, update)

	player.CharacterRemoving:Connect(function()
		-- Stare referencje wskazują na niszczone instancje.
		shoulder = nil
		tool = nil
		capturedTool = nil
		phase = "Idle"
	end)
end

return CastAnimation
