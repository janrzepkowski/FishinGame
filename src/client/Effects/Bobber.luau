--!strict
--[[
	Bobber — spławik, żyłka, kręgi na wodzie i plusk. Efekt CZYSTO LOKALNY.

	Instancje tworzone przez klienta nie replikują się na serwer ani do innych
	graczy — i o to chodzi. Spławik nie wpływa na rozgrywkę (o złowieniu
	decyduje FishingService), więc nie ma powodu obciążać nim sieci.
	Konsekwencja: inni gracze nie widzą twojej żyłki. Gdy to zacznie
	przeszkadzać, efekt trzeba przenieść na serwer — ale wtedy płacimy
	replikacją za każdy rzut każdego gracza.

	Punkt zarzucenia liczymy `Spatial.castTarget` + `Lake.clampToWater` —
	DOKŁADNIE tymi samymi funkcjami, których serwer używa do sprawdzenia
	głębokości. Gdyby klient liczył po swojemu, spławik lądowałby gdzie
	indziej niż miejsce, z którego naprawdę bierze ryba.

	Spławik LECI, a nie pojawia się na miejscu. Teleportacja na 22 study
	była największym pojedynczym powodem, dla którego zarzucanie wyglądało
	tanio — ruch po paraboli kosztuje kilkanaście linii i zmienia wszystko.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.Game)
local LakeConfig = require(Shared.Config.Lake)
local Spatial = require(Shared.Util.Spatial)

local Bobber = {}

local CONTAINER_NAME = "ClientEffects"
local FLIGHT_TIME = 0.55
local REEL_TIME = 0.32
-- Wysokość łuku jako ułamek dystansu. Przy 0 spławik leci płasko jak
-- pocisk, przy 0.4 wygląda jak rzut granatem.
local ARC_RATIO = 0.17

local player = Players.LocalPlayer

local container: Folder? = nil
local bobber: BasePart? = nil
local beam: Beam? = nil
local motion: RBXScriptConnection? = nil
local restY = LakeConfig.SURFACE_Y

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

--[[ Attachment na czubku wędki. Szukamy rekurencyjnie, bo model wędki
     składa się z kilku części i czubek może się przenieść między nimi. ]]
local function rodTip(): Attachment?
	local character = player.Character
	if not character then
		return nil
	end

	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then
		return nil
	end

	local tip = tool:FindFirstChild("Tip", true)
	return if tip and tip:IsA("Attachment") then tip else nil
end

--[[ Rozchodzący się krąg na wodzie. Sam się sprząta. ]]
local function ripple(position: Vector3, maxDiameter: number, life: number)
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

local function stopMotion()
	if motion then
		motion:Disconnect()
		motion = nil
	end
end

function Bobber.clear()
	stopMotion()

	if beam then
		beam:Destroy()
		beam = nil
	end
	if bobber then
		bobber:Destroy()
		bobber = nil
	end
end

local function createBobber(origin: Vector3): BasePart
	local float = Instance.new("Part")
	float.Name = "Bobber"
	float.Shape = Enum.PartType.Ball
	float.Size = Vector3.new(0.6, 0.6, 0.6)
	float.Color = Color3.fromRGB(230, 72, 72)
	float.Material = Enum.Material.SmoothPlastic
	float.Anchored = true
	float.CanCollide = false
	float.CanQuery = false
	float.CanTouch = false
	float.Position = origin
	float.Parent = getContainer()

	local attachment = Instance.new("Attachment")
	attachment.Name = "Line"
	-- Oś attachmentu wyznacza kierunek, w którym `CurveSize` odciąga punkt
	-- kontrolny Béziera. Ustawiona w górę + ujemny CurveSize = punkt pod
	-- spławikiem, czyli żyłka zwisa, zamiast być napiętą kreską.
	attachment.Axis = Vector3.new(0, 1, 0)
	attachment.Parent = float

	local tip = rodTip()
	if tip then
		local line = Instance.new("Beam")
		line.Name = "Line"
		line.Attachment0 = tip
		line.Attachment1 = attachment
		line.Width0 = 0.03
		line.Width1 = 0.03
		line.Segments = 12
		line.Color = ColorSequence.new(Color3.fromRGB(236, 240, 248))
		line.Transparency = NumberSequence.new(0.25)
		line.FaceCamera = true
		line.Parent = float
		beam = line
	end

	return float
end

--[[ Delikatne kołysanie na fali po wylądowaniu. Amplituda celowo mała
     (3 cm): spławik ma „żyć", ale gracz musi odróżnić kołysanie
     od szarpnięcia przy braniu. ]]
local function startFloating()
	stopMotion()

	local phase = math.random() * math.pi * 2
	motion = RunService.RenderStepped:Connect(function()
		local part = bobber
		if not part then
			stopMotion()
			return
		end
		local t = os.clock() * 1.8 + phase
		part.Position = Vector3.new(part.Position.X, restY + math.sin(t) * 0.03, part.Position.Z)
	end)
end

--[[
	Wypuszcza spławik z czubka wędki i prowadzi go po paraboli na wodę.

	Woła się to w momencie puszczenia żyłki przez `CastAnimation`, a nie
	na starcie zamachu — inaczej spławik wyprzedzałby ruch ręki.

	Nic nie robi bez postaci; to normalny stan (respawn), nie błąd.
]]
function Bobber.launch()
	Bobber.clear()

	local root = Spatial.characterRoot(player)
	if not root then
		return
	end

	local landing = LakeConfig.clampToWater(
		Spatial.castTarget(root.CFrame, GameConfig.CAST_DISTANCE),
		GameConfig.CAST_SHORE_MARGIN
	)
	restY = landing.Y + 0.2
	local target = Vector3.new(landing.X, restY, landing.Z)

	local tip = rodTip()
	local origin = if tip then tip.WorldPosition else root.Position + Vector3.new(0, 3, 0)

	local float = createBobber(origin)
	bobber = float

	local arc = (target - origin).Magnitude * ARC_RATIO
	local startedAt = os.clock()

	motion = RunService.RenderStepped:Connect(function()
		local part = bobber
		if not part then
			stopMotion()
			return
		end

		local t = (os.clock() - startedAt) / FLIGHT_TIME

		if t >= 1 then
			part.Position = target

			-- Dopiero po wylądowaniu puszczamy żyłkę luźno. W locie jest
			-- napięta, bo spławik ciągnie ją za sobą.
			local line = beam
			if line then
				line.CurveSize1 = -(target - origin).Magnitude * 0.12
			end

			ripple(target, 7, 1.1)
			startFloating()
			return
		end

		local flat = origin:Lerp(target, t)
		-- Parabola o wierzchołku w połowie lotu: 4t(1-t) daje 0 na końcach
		-- i 1 w środku, bez żadnej trygonometrii.
		local height = arc * 4 * t * (1 - t)
		part.Position = Vector3.new(flat.X, flat.Y + height, flat.Z)
	end)
end

--[[ Gdzie teraz jest spławik — stąd wyskakuje złowiona ryba. ]]
function Bobber.position(): Vector3?
	local float = bobber
	return if float then float.Position else nil
end

--[[ Szarpnięcie w momencie brania. Poza paskiem UI to jedyna informacja
     „teraz!", a przy łowieniu wzrok jest na wodzie, nie na interfejsie. ]]
function Bobber.dip()
	local float = bobber
	if not float then
		return
	end

	stopMotion()

	local sunken = Vector3.new(float.Position.X, restY - 0.55, float.Position.Z)
	TweenService:Create(
		float,
		TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1, true),
		{ Position = sunken }
	):Play()

	-- Żyłka napina się przy braniu — sag znika.
	if beam then
		beam.CurveSize1 = 0
	end

	ripple(float.Position, 5, 0.7)
	task.delay(0.35, function()
		if bobber == float then
			ripple(float.Position, 6, 0.8)
		end
	end)
end

--[[
	Przełącza spławik w tryb walki.

	Zatrzymuje kołysanie na fali: od tej chwili pozycję spławika wyznacza
	napięcie żyłki, a nie sinusoida. Bez tego obie pętle pisałyby po tym
	samym polu i spławik drgałby losowo.
]]
function Bobber.beginFight()
	stopMotion()
end

--[[
	Odwzorowuje stan walki na spławiku i żyłce.

	Wzrok gracza jest na WODZIE, nie na pasku — pasek mówi dokładne liczby,
	ale to spławik mówi „teraz". Dlatego żyłka napina się wraz z napięciem
	(sag znika), czerwienieje przy wysokim i szarpie przy zrywie ryby.

	Wołane 20 razy na sekundę, więc nie tworzy tu żadnych instancji.
]]
function Bobber.setTension(tension: number, surging: boolean)
	local float = bobber
	local line = beam
	if not float then
		return
	end

	-- Zanurzenie rośnie z napięciem: im mocniej holujesz, tym głębiej
	-- spławik siedzi w wodzie.
	local sink = math.clamp(tension, 0, 1) * 0.42
	float.Position = Vector3.new(float.Position.X, restY - sink, float.Position.Z)

	if not line then
		return
	end

	-- Napięta żyłka to prosta linia; luźna zwisa. `CurveSize` to odległość
	-- punktu kontrolnego Béziera, więc zerowanie go prostuje żyłkę.
	line.CurveSize1 = -(1 - math.clamp(tension, 0, 1)) * 2.4
	line.Color = ColorSequence.new(
		Color3.fromRGB(236, 240, 248):Lerp(Color3.fromRGB(255, 96, 96), math.clamp(tension, 0, 1))
	)
	line.Width0 = if surging then 0.05 else 0.03
	line.Width1 = line.Width0
end

--[[ Plusk przy wyciągnięciu ryby. Wołany zanim spławik zniknie. ]]
function Bobber.splash()
	local float = bobber
	if not float then
		return
	end

	local origin = float.Position
	ripple(origin, 12, 0.9)

	for index = 1, 8 do
		local drop = Instance.new("Part")
		drop.Name = "Droplet"
		drop.Shape = Enum.PartType.Ball
		drop.Size = Vector3.new(0.22, 0.22, 0.22)
		drop.Color = Color3.fromRGB(206, 236, 246)
		drop.Material = Enum.Material.Neon
		drop.Transparency = 0.15
		drop.Anchored = true
		drop.CanCollide = false
		drop.CanQuery = false
		drop.CanTouch = false
		drop.Position = origin
		drop.Parent = getContainer()

		local angle = (index / 8) * math.pi * 2
		local away = Vector3.new(math.cos(angle), 0, math.sin(angle)) * math.random(2, 4)

		TweenService
			:Create(drop, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = origin + away + Vector3.new(0, 2.2, 0),
				Transparency = 1,
				Size = Vector3.new(0.05, 0.05, 0.05),
			})
			:Play()

		task.delay(0.55, function()
			drop:Destroy()
		end)
	end
end

--[[
	Zwija spławik z powrotem do czubka wędki i sprząta.

	Bez tego spławik po prostu znikał — a zniknięcie czyta się jak błąd,
	nie jak koniec akcji.
]]
function Bobber.reelIn()
	local float = bobber
	if not float then
		Bobber.clear()
		return
	end

	stopMotion()

	local origin = float.Position
	local startedAt = os.clock()

	motion = RunService.RenderStepped:Connect(function()
		local part = bobber
		if not part then
			stopMotion()
			return
		end

		local tip = rodTip()
		local destination = if tip then tip.WorldPosition else origin + Vector3.new(0, 4, 0)
		local t = (os.clock() - startedAt) / REEL_TIME

		if t >= 1 then
			Bobber.clear()
			return
		end

		-- Czubek wędki rusza się razem z postacią, więc cel liczymy
		-- w każdej klatce, a nie raz na starcie.
		part.Position = origin:Lerp(destination, t * t)
	end)
end

return Bobber
