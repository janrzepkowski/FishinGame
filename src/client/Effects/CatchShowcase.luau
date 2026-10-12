--!strict
--[[
	CatchShowcase — złowiona ryba NAPRAWDĘ wylatuje z wody. Efekt lokalny.

	Wcześniej złowienie kończyło się pluskiem i napisem na pasku: ryba
	istniała wyłącznie jako tekst. Dla dziecka to żadna nagroda — nagrodą
	jest zobaczyć rybę. Dlatego po `CastResolved` z wynikiem „Caught":

	  1. WYSKOK  (0,75 s)  ryba wyskakuje ze spławika po łuku i robi salto,
	  2. POKAZ   (1,6 s)   wisi nad graczem, macha ogonem, świeci kolorem
	                       rzadkości, sypie iskrami i konfetti,
	  3. DO TORBY (0,35 s) maleje i wpada do gracza.

	Model to ten sam `FishModel`, który jest w ekwipunku i w bestiariuszu.
	Gatunek bierzemy z wyniku od serwera — klient dowiaduje się, co złowił,
	dokładnie w tym samym momencie co wcześniej (patrz ARCHITECTURE.md,
	„Dlaczego gatunek NIE jest wysyłany razem z BiteStarted").

	Lokalnie, z tego samego powodu co spławik: wynik decyduje serwer, a pokaz
	niczego nie zmienia w rozgrywce, więc nie ma po co go replikować.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Fish = require(Shared.Config.Fish)
local FishModel = require(Shared.Util.FishModel)
local Spatial = require(Shared.Util.Spatial)
local Types = require(Shared.Types)

local CatchShowcase = {}

local LEAP_TIME = 0.75
local SHOW_TIME = 1.6
local STOW_TIME = 0.35
-- Ryba w świecie jest większa niż w skali 1 modelu: z odległości kilku
-- studów rybka długości 2 studów to plamka.
local WORLD_SCALE = 1.25
local CONFETTI = {
	Color3.fromRGB(255, 92, 120),
	Color3.fromRGB(255, 202, 40),
	Color3.fromRGB(76, 214, 98),
	Color3.fromRGB(66, 164, 255),
	Color3.fromRGB(156, 100, 255),
}

local player = Players.LocalPlayer

local current: Model? = nil
local connection: RBXScriptConnection? = nil

function CatchShowcase.clear()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if current then
		current:Destroy()
		current = nil
	end
end

local function effectsFolder(): Instance
	local existing = Workspace:FindFirstChild("ClientEffects")
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientEffects"
	folder.Parent = Workspace
	return folder
end

--[[ Konfetti z kolorowych kafelków. Bez tekstur: zwykłe Party,
     bo każda tekstura to asset do wgrania (zasada „zero binariów"). ]]
local function confetti(origin: Vector3, count: number)
	for _ = 1, count do
		local piece = Instance.new("Part")
		piece.Name = "Confetti"
		piece.Size = Vector3.new(0.35, 0.05, 0.22)
		piece.Color = CONFETTI[math.random(1, #CONFETTI)]
		piece.Material = Enum.Material.Neon
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.CastShadow = false
		piece.CFrame = CFrame.new(origin)
		piece.Parent = effectsFolder()

		local angle = math.random() * math.pi * 2
		local reach = 2 + math.random() * 4
		local burst = origin
			+ Vector3.new(math.cos(angle) * reach, 2 + math.random() * 3, math.sin(angle) * reach)
		local spin = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)

		local up = TweenService:Create(
			piece,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(burst) * spin }
		)
		up:Play()
		up.Completed:Connect(function()
			TweenService
				:Create(piece, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
					CFrame = CFrame.new(burst - Vector3.new(0, 5, 0))
						* spin
						* CFrame.Angles(3, 2, 1),
					Transparency = 1,
				})
				:Play()
		end)

		task.delay(1.7, function()
			piece:Destroy()
		end)
	end
end

--[[ Rozbłysk iskier wokół ryby. Domyślna tekstura ParticleEmittera
     to iskierka Robloxa — nie potrzeba żadnego wgranego obrazka. ]]
local function sparkleBurst(model: Model, color: Color3, amount: number)
	local body = model.PrimaryPart
	if not body then
		return
	end

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Rate = 0
	emitter.Parent = body
	emitter:Emit(amount)
end

--[[
	Podświetlenie konturem w kolorze rzadkości. `Highlight` rysuje się
	przez wszystko, więc ryby nie zgubi nawet za barierką pomostu.
]]
local function outline(model: Model, color: Color3)
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineColor = color
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
end

local function splashSound(position: Vector3)
	-- Dźwięk z zasobów klienta Robloxa (ten sam, którego używa Humanoid
	-- przy wpadnięciu do wody), więc nic nie trzeba wgrywać.
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position
	anchor.Parent = Workspace.Terrain

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/impact_water.mp3"
	sound.Volume = 0.8
	sound.PlaybackSpeed = 1.15
	sound.Parent = anchor
	sound:Play()

	task.delay(2, function()
		anchor:Destroy()
	end)
end

--[[
	Pokazuje wyciągnięcie ryby. `from` to miejsce spławika na wodzie.
	`onPeak` leci, gdy ryba dotrze nad głowę — wtedy pokazuje się baner
	nagrody, żeby oba efekty grały razem, a nie jeden po drugim.
]]
function CatchShowcase.play(caught: Types.CaughtFish, spot: Vector3?, onPeak: (() -> ())?)
	CatchShowcase.clear()

	local definition = Fish.find(caught.fishId)
	local root = Spatial.characterRoot(player)
	if not definition or not root then
		if onPeak then
			onPeak()
		end
		return
	end

	-- Bez spławika (np. zgubiony po lagu) ryba wyskakuje z wody przed graczem.
	local from = spot or (root.Position + root.CFrame.LookVector * 12 - Vector3.new(0, 3, 0))

	local scale = FishModel.scaleFor(definition, caught.mass) * WORLD_SCALE
	local model = FishModel.build(definition, { scale = scale, effects = true })
	model.Parent = effectsFolder()
	current = model

	local rarityColor = Fish.RARITY_COLOR[definition.rarity]
	local tier = Fish.RARITY_TIER[definition.rarity]
	outline(model, rarityColor)
	splashSound(from)

	local startedAt = os.clock()
	local peakFired = false
	local wagPhase = math.random() * math.pi

	connection = RunService.RenderStepped:Connect(function()
		local character = Spatial.characterRoot(player)
		if not character or not model.Parent then
			CatchShowcase.clear()
			return
		end

		-- Punkt pokazu liczony co klatkę: gracz może się ruszać w trakcie.
		local facing = character.CFrame.LookVector
		local show = character.Position + facing * 4.5 + Vector3.new(0, 4.5, 0)
		local toCamera = Workspace.CurrentCamera
		local look = if toCamera then toCamera.CFrame.Position else character.Position - facing * 10

		local elapsed = os.clock() - startedAt

		if elapsed < LEAP_TIME then
			local t = elapsed / LEAP_TIME
			local flat = from:Lerp(show, t)
			local height = 7 * 4 * t * (1 - t)
			local position = flat + Vector3.new(0, height, 0)
			local heading = (show - from) * Vector3.new(1, 0, 1)
			local base = if heading.Magnitude > 0.01
				then CFrame.lookAt(position, position + heading)
				else CFrame.new(position)
			-- Salto wokół osi poprzecznej: dokładnie jeden obrót w locie.
			model:PivotTo(base * CFrame.Angles(-t * math.pi * 2, 0, 0))
			return
		end

		if not peakFired then
			peakFired = true
			sparkleBurst(model, rarityColor, 20 + tier * 12)
			confetti(show, 14 + tier * 8)
			if onPeak then
				task.spawn(onPeak)
			end
		end

		if elapsed < LEAP_TIME + SHOW_TIME then
			local t = elapsed - LEAP_TIME
			-- Ryba bokiem do kamery, pyskiem w prawo kadru, macha ogonem
			-- i podryguje — „żywa trofeum", a nie wypchany eksponat.
			local side = CFrame.lookAt(show, look) * CFrame.Angles(0, math.rad(90), 0)
			local wag = math.sin(t * 14 + wagPhase) * 0.35 * math.exp(-t * 0.8)
			local bob = math.sin(t * 5) * 0.25
			-- Na wejściu lekkie „powiększenie" — pierwsze 0,2 s z przestrzeleniem.
			local grow = 1 + 0.25 * math.exp(-t * 9) * math.sin(t * 20)
			model:ScaleTo(math.max(grow, 0.5))
			model:PivotTo(side * CFrame.new(0, bob, 0) * CFrame.Angles(0, wag, wag * 0.3))
			return
		end

		local t = (elapsed - LEAP_TIME - SHOW_TIME) / STOW_TIME
		if t >= 1 then
			CatchShowcase.clear()
			return
		end

		-- Do torby: ryba maleje i wpada w gracza.
		local target = character.Position + Vector3.new(0, 1, 0)
		model:ScaleTo(math.max(1 - t, 0.05))
		model:PivotTo(CFrame.lookAt(show:Lerp(target, t * t), look) * CFrame.Angles(0, t * 8, 0))
	end)
end

return CatchShowcase
