--!strict
--[[
	Bobber — spławik, żyłka, kręgi na wodzie i plusk.

	Efekt jest rysowany LOKALNIE, ale DLA KAŻDEGO łowiącego w zasięgu:
	własny spławik prowadzi `FishingController` (ze zdarzeń serwera),
	cudze — `AnglerController` (z atrybutów na postaciach). Instancje nie
	replikują się; każdy klient buduje je u siebie z tych samych danych,
	więc sieć niesie tylko fazę i punkt lądowania, a nie ruch spławika.

	Stąd fabryka: `Bobber.forCharacter(character)` daje osobny spławik
	przypięty do wędki tej postaci. Funkcje na poziomie modułu
	(`Bobber.launch` itd.) to spławik lokalnego gracza.

	Punkt lądowania PRZYCHODZI Z SERWERA. Klient go nie liczy: serwer
	wyznacza go z własnej pozycji postaci i mierzy tam głębokość, więc
	spławik staje dokładnie tam, skąd naprawdę bierze ryba.

	Spławik LECI, a nie pojawia się na miejscu. Teleportacja na kilkadziesiąt
	studów była największym pojedynczym powodem, dla którego zarzucanie
	wyglądało tanio — ruch po paraboli kosztuje kilkanaście linii i zmienia
	wszystko.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local LakeConfig = require(Shared.Config.Lake)

local Ripple = require(script.Parent.Ripple)
local Sfx = require(script.Parent.Sfx)

local Bobber = {}

export type Float = {
	clear: () -> (),
	launch: (landing: Vector3, flightTime: number) -> (),
	nibble: () -> (),
	dip: () -> (),
	beginFight: () -> (),
	setTension: (tension: number, surging: boolean) -> (),
	splash: () -> (),
	reelIn: () -> (),
}

local CONTAINER_NAME = "ClientEffects"
local REEL_TIME = 0.32
-- Skubnięcie: płytkie i krótkie. Branie zanurza spławik na 0,55 studa
-- i trzyma go pod wodą — te dwie liczby mają się różnić na pierwszy rzut oka.
local NIBBLE_DEPTH = 0.2
local NIBBLE_TIME = 0.3
-- Wysokość łuku jako ułamek dystansu. Przy 0 spławik leci płasko jak
-- pocisk, przy 0.4 wygląda jak rzut granatem.
local ARC_RATIO = 0.17

local container: Folder? = nil

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

--[[
	Tworzy spławik przypięty do wędki postaci zwracanej przez `getCharacter`.

	Funkcja, a nie sama postać: lokalny gracz odradza się z nowym modelem,
	a spławik ma wtedy trafić do nowej wędki bez przebudowywania czegokolwiek.
]]
local function create(getCharacter: () -> Model?): Float
	local bobber: BasePart? = nil
	local beam: Beam? = nil
	local motion: RBXScriptConnection? = nil
	local restY = LakeConfig.SURFACE_Y
	local nibbleAt = 0

	local self = {} :: Float

	--[[ Attachment na czubku wędki. Szukamy rekurencyjnie, bo model wędki
	     składa się z kilku części i czubek może się przenieść między nimi. ]]
	local function rodTip(): Attachment?
		local character = getCharacter()
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

	local function stopMotion()
		if motion then
			motion:Disconnect()
			motion = nil
		end
	end

	function self.clear()
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
			local now = os.clock()
			local t = now * 1.8 + phase

			-- Skubnięcie to jedno płytkie „mrugnięcie" nałożone na kołysanie:
			-- pół sinusoidy w dół i z powrotem, bez zatrzymywania pętli.
			local since = now - nibbleAt
			local dip = if since < NIBBLE_TIME
				then math.sin(since / NIBBLE_TIME * math.pi) * NIBBLE_DEPTH
				else 0

			part.Position =
				Vector3.new(part.Position.X, restY + math.sin(t) * 0.03 - dip, part.Position.Z)
		end)
	end

	--[[
		Wypuszcza spławik z czubka wędki i prowadzi go po paraboli na wodę.

		Woła się to w momencie puszczenia żyłki (patrz `CastPose.RELEASE_DELAY`), a nie
		na starcie zamachu — inaczej spławik wyprzedzałby ruch ręki.

		`landing` to punkt z serwera, `flightTime` rośnie z odległością rzutu
		(`Cast.flightTime`) — daleki rzut ma lecieć dłużej, a nie szybciej.

		Nic nie robi bez postaci; to normalny stan (respawn), nie błąd.
	]]
	function self.launch(landing: Vector3, flightTime: number)
		self.clear()

		local character = getCharacter()
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return
		end

		nibbleAt = 0
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

			local t = (os.clock() - startedAt) / flightTime

			if t >= 1 then
				part.Position = target

				-- Dopiero po wylądowaniu puszczamy żyłkę luźno. W locie jest
				-- napięta, bo spławik ciągnie ją za sobą.
				local line = beam
				if line then
					line.CurveSize1 = -(target - origin).Magnitude * 0.12
				end

				Ripple.spawn(target, 7, 1.1)
				Sfx.playAt("cast", target)
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

	--[[
		Fałszywe skubnięcie: płytkie drgnięcie i mały krąg.

		Celowo słabsze od brania pod każdym względem — spławik nie znika pod
		wodą, krąg jest jeden i mały, żyłka zostaje luźna. Gracz ma się nauczyć
		je odróżniać, bo zacięcie na skubnięciu płoszy rybę.
	]]
	function self.nibble()
		local float = bobber
		if not float then
			return
		end

		nibbleAt = os.clock()
		Sfx.playAt("nibble", float.Position)
		Ripple.spawn(Vector3.new(float.Position.X, restY, float.Position.Z), 2.6, 0.5)
	end

	--[[ Szarpnięcie w momencie brania. Poza paskiem UI to jedyna informacja
	     „teraz!", a przy łowieniu wzrok jest na wodzie, nie na interfejsie. ]]
	function self.dip()
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

		Ripple.spawn(float.Position, 5, 0.7)
		Sfx.playAt("bite", float.Position)
		task.delay(0.35, function()
			if bobber == float then
				Ripple.spawn(float.Position, 6, 0.8)
			end
		end)
	end

	--[[
		Przełącza spławik w tryb walki.

		Zatrzymuje kołysanie na fali: od tej chwili pozycję spławika wyznacza
		napięcie żyłki, a nie sinusoida. Bez tego obie pętle pisałyby po tym
		samym polu i spławik drgałby losowo.
	]]
	function self.beginFight()
		stopMotion()
	end

	--[[
		Odwzorowuje stan walki na spławiku i żyłce.

		Wzrok gracza jest na WODZIE, nie na pasku — pasek mówi dokładne liczby,
		ale to spławik mówi „teraz". Dlatego żyłka napina się wraz z napięciem
		(sag znika), czerwienieje przy wysokim i szarpie przy zrywie ryby.

		Wołane 20 razy na sekundę, więc nie tworzy tu żadnych instancji.
	]]
	function self.setTension(tension: number, surging: boolean)
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
			Color3.fromRGB(236, 240, 248)
				:Lerp(Color3.fromRGB(255, 96, 96), math.clamp(tension, 0, 1))
		)
		line.Width0 = if surging then 0.05 else 0.03
		line.Width1 = line.Width0
	end

	--[[ Plusk przy wyciągnięciu ryby. Wołany zanim spławik zniknie. ]]
	function self.splash()
		local float = bobber
		if not float then
			return
		end

		local origin = float.Position
		Ripple.spawn(origin, 12, 0.9)
		Sfx.playAt("splash", origin)

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
	function self.reelIn()
		local float = bobber
		if not float then
			self.clear()
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
				self.clear()
				return
			end

			-- Czubek wędki rusza się razem z postacią, więc cel liczymy
			-- w każdej klatce, a nie raz na starcie.
			part.Position = origin:Lerp(destination, t * t)
		end)
	end

	return self
end

--[[ Osobny spławik dla podanej postaci — do rysowania cudzych zarzuceń. ]]
function Bobber.forCharacter(character: Model): Float
	return create(function()
		return character
	end)
end

-- Spławik lokalnego gracza. Postać czytamy przy każdym użyciu, bo po
-- odrodzeniu to już inny model.
local own = create(function()
	return Players.LocalPlayer.Character
end)

Bobber.clear = own.clear
Bobber.launch = own.launch
Bobber.nibble = own.nibble
Bobber.dip = own.dip
Bobber.beginFight = own.beginFight
Bobber.setTension = own.setTension
Bobber.splash = own.splash
Bobber.reelIn = own.reelIn

return Bobber
