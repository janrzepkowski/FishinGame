--!strict
--[[
	FishModel — geometria ryby jako DANE, nie jako kod budujący.

	=========================================================================
	DLACZEGO DANE (i dlaczego w shared/)
	=========================================================================
	Ten sam model jest potrzebny w kilku miejscach:

	  1. w ekwipunku       — karta z podglądem 3D (ViewportFrame)
	  2. w bestiariuszu    — karta albo ciemna sylwetka niezłowionej ryby
	  3. na pasku wyniku   — podgląd po złowieniu
	  4. w świecie         — ryba wyskakująca z wody (efekt klienta)

	Gdyby każde miejsce składało rybę po swojemu, płoć w ekwipunku przestałaby
	wyglądać jak ta, która właśnie wyskoczyła z wody. Tu jest jedna lista brył,
	a konsumenci decydują tylko, gdzie ją postawić i w jakiej skali.

	=========================================================================
	STYL
	=========================================================================
	Cukierkowy, dla dzieci: elipsoidy zamiast klocków, wielkie oczy
	z odblaskiem, rumieńce, płetwy w kontrastowym kolorze. Wymiary są
	przesadzone (krótkie, pękate ciała), bo w małym podglądzie 64 px
	realistyczne proporcje dają nieczytelną kreskę.

	Elipsoida to Part ze `SpecialMesh` typu Sphere. `Shape = Ball` się do tego
	nie nadaje — Roblox wymusza w nim jednakowe wymiary i każda „elipsa"
	wychodzi kulą.

	ORIENTACJA: głowa w stronę lokalnego -Z (LookVector), jak kij w `RodModel`.
	Środek ciała w początku układu, więc `PivotTo` obraca rybę wokół brzucha.

	Moduł nie dotyka typów Robloxa na poziomie modułu — wszystko powstaje
	wewnątrz funkcji (patrz zasada 9 w CLAUDE.md).
]]

local Types = require(script.Parent.Parent.Types)

local FishModel = {}

export type Shape = "Ellipsoid" | "Ball" | "Cylinder" | "Block"

export type Piece = {
	name: string,
	shape: Shape,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	-- Neon tylko dla legend: świecące płetwy to jedyny sygnał rzadkości,
	-- który działa także na ciemnej sylwetce wody.
	neon: boolean?,
	-- Elementy twarzy (oczy, rumieńce) nie są zaciemniane w sylwetce,
	-- więc konsument musi wiedzieć, które to.
	face: boolean?,
	transparency: number?,
}

export type BuildOptions = {
	-- Ciemna sylwetka bez twarzy — niezłowiony gatunek w bestiariuszu.
	silhouette: boolean?,
	-- Mnożnik rozmiaru. 1 = rybka ok. 2 studów długości.
	scale: number?,
	-- Iskry i światło dla legend. Wyłączone w podglądach: ViewportFrame
	-- i tak nie renderuje cząsteczek, a światło tylko by kosztowało.
	effects: boolean?,
}

type Proportions = { length: number, height: number, width: number }

local BODY: { [Types.FishBody]: Proportions } = {
	Round = { length = 2.0, height = 1.4, width = 0.9 },
	Tall = { length = 2.0, height = 1.75, width = 0.75 },
	Long = { length = 3.0, height = 1.05, width = 0.85 },
	Torpedo = { length = 2.8, height = 1.15, width = 0.9 },
}

local SILHOUETTE = { r = 46, g = 52, b = 86 }

--[[ Wygląd gatunku. Ryba bez `look` w configu dostaje okrągłą sylwetkę
     i płetwy w ciemniejszym odcieniu własnego koloru — nowy wpis w katalogu
     działa od razu, zanim ktoś dobierze mu styl. ]]
local function lookOf(definition: Types.FishDefinition): Types.FishLook
	local look = definition.look
	if look then
		return look
	end

	return {
		body = "Round",
		pattern = "None",
		accent = definition.color:Lerp(Color3.new(0, 0, 0), 0.25),
		belly = definition.color:Lerp(Color3.new(1, 1, 1), 0.6),
	}
end

--[[
	Punkt na powierzchni elipsoidy ciała, po stronie `side` (-1 lewa, 1 prawa).

	Wzory (kropki, łuski) muszą leżeć NA boku ryby. Stała odległość od osi
	wbijałaby je w ciało przy ogonie i zostawiała w powietrzu przy brzuchu.
]]
local function surfaceX(body: Proportions, y: number, z: number, side: number): number
	local ny = y / (body.height / 2)
	local nz = z / (body.length / 2)
	local inside = math.max(0, 1 - ny * ny - nz * nz)
	return side * (body.width / 2) * math.sqrt(inside) * 0.97
end

--[[ Wszystkie bryły ryby w jej układzie lokalnym, w skali 1. ]]
function FishModel.pieces(definition: Types.FishDefinition): { Piece }
	local look = lookOf(definition)
	local body = BODY[look.body]
	local L, H, W = body.length, body.height, body.width

	local main = definition.color
	local accent = look.accent
	local dark = main:Lerp(Color3.new(0, 0, 0), 0.35)
	local neon = look.sparkle == true

	local pieces: { Piece } = {
		{
			name = "Body",
			shape = "Ellipsoid",
			size = Vector3.new(W, H, L),
			cframe = CFrame.identity,
			color = main,
		},
		{
			-- Jasny brzuch wystaje spod ciała. Dwa tony zamiast jednego to
			-- najtańszy sposób, żeby bryła przestała wyglądać jak jajko.
			name = "Belly",
			shape = "Ellipsoid",
			size = Vector3.new(W * 0.86, H * 0.6, L * 0.8),
			cframe = CFrame.new(0, -H * 0.2, -L * 0.03),
			color = look.belly,
		},
		{
			name = "DorsalFin",
			shape = "Ellipsoid",
			size = Vector3.new(0.12, H * 0.55, L * 0.42),
			cframe = CFrame.new(0, H * 0.42, L * 0.06) * CFrame.Angles(math.rad(-12), 0, 0),
			color = accent,
			neon = neon,
		},
		{
			name = "Lips",
			shape = "Ellipsoid",
			size = Vector3.new(W * 0.34, H * 0.16, 0.22),
			cframe = CFrame.new(0, -H * 0.06, -L * 0.49),
			color = Color3.fromRGB(255, 120, 150),
			face = true,
		},
	}

	-- Ogon: dwie płetwy w literę V. Kąt ±38° czyta się jako ogon z każdej
	-- strony, także z boku, gdzie pojedyncza płetwa znikałaby jako kreska.
	for _, side in { -1, 1 } do
		table.insert(pieces, {
			name = "Tail",
			shape = "Ellipsoid",
			size = Vector3.new(0.14, H * 0.62, L * 0.34),
			cframe = CFrame.new(0, side * H * 0.17, L * 0.56)
				* CFrame.Angles(math.rad(side * 38), 0, 0),
			color = accent,
			neon = neon,
		})

		table.insert(pieces, {
			name = "PectoralFin",
			shape = "Ellipsoid",
			size = Vector3.new(0.1, H * 0.28, L * 0.2),
			cframe = CFrame.new(side * W * 0.46, -H * 0.16, -L * 0.08)
				* CFrame.Angles(0, math.rad(side * 30), math.rad(side * -25)),
			color = accent,
			neon = neon,
		})

		-- Oczy są celowo za duże — to one robią z bryły postać.
		local eyeSize = H * 0.38
		local eyeY = H * 0.12
		local eyeZ = -L * 0.3
		local eyeX = surfaceX(body, eyeY, eyeZ, side)

		table.insert(pieces, {
			name = "Eye",
			shape = "Ball",
			size = Vector3.one * eyeSize,
			cframe = CFrame.new(eyeX, eyeY, eyeZ),
			color = Color3.fromRGB(255, 255, 255),
			face = true,
		})
		table.insert(pieces, {
			name = "Pupil",
			shape = "Ball",
			size = Vector3.one * eyeSize * 0.58,
			cframe = CFrame.new(eyeX + side * eyeSize * 0.24, eyeY, eyeZ - eyeSize * 0.12),
			color = Color3.fromRGB(30, 30, 46),
			face = true,
		})
		table.insert(pieces, {
			-- Odblask w oku. Bez niego oczy są martwe; z nim ryba „patrzy".
			name = "EyeShine",
			shape = "Ball",
			size = Vector3.one * eyeSize * 0.2,
			cframe = CFrame.new(
				eyeX + side * eyeSize * 0.44,
				eyeY + eyeSize * 0.14,
				eyeZ - eyeSize * 0.2
			),
			color = Color3.fromRGB(255, 255, 255),
			face = true,
		})

		local cheekY = -H * 0.12
		local cheekZ = -L * 0.32
		table.insert(pieces, {
			name = "Cheek",
			shape = "Ellipsoid",
			size = Vector3.new(0.05, H * 0.14, L * 0.1),
			cframe = CFrame.new(surfaceX(body, cheekY, cheekZ, side), cheekY, cheekZ),
			color = Color3.fromRGB(255, 140, 170),
			face = true,
			transparency = 0.25,
		})

		if look.whiskers then
			-- Wąsy zwisają od kącików pyska w dół i do przodu.
			table.insert(pieces, {
				name = "Whisker",
				shape = "Cylinder",
				size = Vector3.new(L * 0.32, 0.07, 0.07),
				cframe = CFrame.new(side * W * 0.18, -H * 0.2, -L * 0.52)
					* CFrame.Angles(0, math.rad(90 + side * 30), math.rad(-35)),
				color = dark,
			})
		end
	end

	if look.pattern == "Stripes" then
		for index = 1, 3 do
			local z = -L * 0.12 + (index - 1) * L * 0.16
			table.insert(pieces, {
				name = "Stripe",
				shape = "Ellipsoid",
				-- Odrobinę szersza od ciała, żeby wyszła na powierzchnię,
				-- i niższa, żeby nie zachodziła na brzuch.
				size = Vector3.new(W * 1.03, H * 0.72, L * 0.07),
				cframe = CFrame.new(0, H * 0.08, z),
				color = dark,
			})
		end
	elseif look.pattern == "Spots" then
		local spots = {
			{ y = 0.22, z = -0.05 },
			{ y = -0.02, z = 0.12 },
			{ y = 0.26, z = 0.22 },
			{ y = 0.06, z = 0.32 },
		}
		for _, spot in spots do
			for _, side in { -1, 1 } do
				local y = H * spot.y
				local z = L * spot.z
				table.insert(pieces, {
					name = "Spot",
					shape = "Ellipsoid",
					size = Vector3.new(0.06, H * 0.16, L * 0.08),
					cframe = CFrame.new(surfaceX(body, y, z, side), y, z),
					color = accent,
				})
			end
		end
	elseif look.pattern == "Scutes" then
		-- Rząd tarczek wzdłuż grzbietu — jedyna rzecz, po której jesiotra
		-- rozpoznaje każde dziecko z atlasu.
		for index = 1, 5 do
			local z = -L * 0.28 + (index - 1) * L * 0.13
			table.insert(pieces, {
				name = "Scute",
				shape = "Ball",
				size = Vector3.one * H * 0.16,
				cframe = CFrame.new(0, H * 0.47 * math.sqrt(math.max(0, 1 - (2 * z / L) ^ 2)), z),
				color = accent,
			})
		end
	end

	if look.body == "Torpedo" then
		-- Szpiczasty pysk. Bez niego łosoś i jesiotr to tylko dłuższe płocie.
		table.insert(pieces, {
			name = "Snout",
			shape = "Ellipsoid",
			size = Vector3.new(W * 0.5, H * 0.45, L * 0.3),
			cframe = CFrame.new(0, -H * 0.02, -L * 0.42),
			color = main,
		})
	end

	return pieces
end

--[[ Długość modelu w skali 1 — do dobrania kamery podglądu. ]]
function FishModel.length(definition: Types.FishDefinition): number
	return BODY[lookOf(definition).body].length
end

--[[
	Skala modelu w świecie dla konkretnej masy.

	Rośnie z PIERWIASTKIEM masy w obrębie gatunku: okaz musi wyglądać na
	większy, ale sum 85 kg nie może zasłonić pół ekranu. Granice 0,8-1,7
	trzymają każdą rybę w kadrze nad głową gracza.
]]
function FishModel.scaleFor(definition: Types.FishDefinition, mass: number): number
	local span = math.max(definition.maxMass - definition.minMass, 0.001)
	local t = math.clamp((mass - definition.minMass) / span, 0, 1)
	return 0.8 + 0.9 * math.sqrt(t)
end

local function makePart(piece: Piece, scale: number, silhouette: boolean): BasePart
	local part = Instance.new("Part")
	part.Name = piece.name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = piece.size * scale
	part.CFrame = CFrame.new(piece.cframe.Position * scale) * piece.cframe.Rotation
	part.Material = if piece.neon and not silhouette
		then Enum.Material.Neon
		else Enum.Material.SmoothPlastic
	part.Color = if silhouette
		then Color3.fromRGB(SILHOUETTE.r, SILHOUETTE.g, SILHOUETTE.b)
		else piece.color
	part.Transparency = piece.transparency or 0

	if piece.shape == "Ball" then
		part.Shape = Enum.PartType.Ball
	elseif piece.shape == "Cylinder" then
		part.Shape = Enum.PartType.Cylinder
	elseif piece.shape == "Ellipsoid" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end

	return part
end

--[[
	Składa model z brył. Wszystko zakotwiczone i bez kolizji: model jest
	dekoracją — w podglądzie nie ma fizyki, a w świecie rybę prowadzi
	animacja, nie silnik.

	PrimaryPart to `Body`, więc `PivotTo` ustawia środek brzucha.
]]
function FishModel.build(definition: Types.FishDefinition, options: BuildOptions?): Model
	local silhouette = options ~= nil and options.silhouette == true
	local scale = if options and options.scale then options.scale else 1
	local effects = options ~= nil and options.effects == true

	local model = Instance.new("Model")
	model.Name = definition.id

	for _, piece in FishModel.pieces(definition) do
		-- Sylwetka nie ma twarzy: ciemna plama z oczami wygląda strasznie,
		-- a ma wyglądać jak zagadka.
		if silhouette and piece.face then
			continue
		end

		local part = makePart(piece, scale, silhouette)
		part.Parent = model
		if piece.name == "Body" then
			model.PrimaryPart = part
		end
	end

	local look = lookOf(definition)
	if effects and look.sparkle and not silhouette and model.PrimaryPart then
		local glow = Instance.new("PointLight")
		glow.Color = look.accent
		glow.Brightness = 2
		glow.Range = 10 * scale
		glow.Shadows = false
		glow.Parent = model.PrimaryPart

		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = look.accent
		sparkles.Parent = model.PrimaryPart
	end

	return model
end

return table.freeze(FishModel)
