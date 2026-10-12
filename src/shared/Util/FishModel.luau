--!strict
--[[
	FishModel — wygląd każdego gatunku ryby jako dane i jeden budowniczy.

	Ten sam model widzi gracz w trzech miejscach: wyskakujący z wody po
	wyholowaniu, w ekwipunku i w bestiariuszu. Jedno źródło oznacza, że
	ryba w torbie wygląda dokładnie jak ta, która przed chwilą wyleciała
	z jeziora — tak jak wędka w sklepie jest tą samą wędką co w ręce
	(`RodModel`). Obrazek wgrany na Roblox rozjechałby się z modelem przy
	pierwszej zmianie.

	STYL: gra jest dla dzieci, więc ryby są pękate, mają duże oczy i czyste
	kolory. Gatunek ma się dać rozpoznać po SYLWETCE (szczupak jest długi,
	leszcz wysoki, sum ma wąsy), a nie po detalu, którego w okienku 40x40
	pikseli i tak nie widać.

	Wszystko z prymitywów, bez żadnego assetu: elipsoidy to zwykłe `Part`
	z siatką `Sphere`, płetwy to kliny.

	ORIENTACJA: przód ryby to lokalne -Z, grzbiet to +Y.
]]

local FishModel = {}

export type Shape = {
	-- Wymiary korpusu w studach: długość (Z), wysokość (Y), szerokość (X).
	length: number,
	height: number,
	width: number,
	body: Color3,
	belly: Color3,
	fin: Color3,
	-- Wąsy (sum, karp): długość w studach; nil = bez wąsów.
	whiskers: number?,
	-- Wydłużony pysk (szczupak, jesiotr): długość jako ułamek korpusu.
	snout: number?,
	-- Ciemne pręgi w poprzek grzbietu (okoń, sandacz).
	stripes: number?,
	-- Rząd płytek na grzbiecie zamiast płetwy (jesiotr).
	plates: boolean?,
	-- Welon zamiast zwykłego ogona i świecenie (Złota Rybka).
	fancy: boolean?,
	eye: Color3?,
}

local WHITE = Color3.fromRGB(250, 250, 246)
local PUPIL = Color3.fromRGB(26, 28, 34)

-- Kształt awaryjny dla gatunku, którego ktoś jeszcze tu nie opisał.
-- Nowa ryba w katalogu ma się POJAWIĆ, a nie wywalić ekwipunku.
local DEFAULT: Shape = {
	length = 2.6,
	height = 1.1,
	width = 0.7,
	body = Color3.fromRGB(150, 170, 186),
	belly = Color3.fromRGB(226, 232, 236),
	fin = Color3.fromRGB(110, 130, 150),
}

local SHAPES: { [string]: Shape } = {
	roach = {
		length = 2.2,
		height = 1.0,
		width = 0.62,
		body = Color3.fromRGB(176, 192, 204),
		belly = Color3.fromRGB(236, 240, 244),
		fin = Color3.fromRGB(232, 146, 78),
	},
	perch = {
		length = 2.4,
		height = 1.15,
		width = 0.68,
		body = Color3.fromRGB(128, 164, 86),
		belly = Color3.fromRGB(236, 226, 170),
		fin = Color3.fromRGB(236, 142, 64),
		stripes = 5,
	},
	bream = {
		-- Leszcz jest wysoki i płaski — jedyna ryba o takiej sylwetce.
		length = 2.5,
		height = 1.75,
		width = 0.5,
		body = Color3.fromRGB(176, 150, 104),
		belly = Color3.fromRGB(232, 218, 184),
		fin = Color3.fromRGB(112, 104, 96),
	},
	tench = {
		length = 2.5,
		height = 1.25,
		width = 0.8,
		body = Color3.fromRGB(96, 124, 76),
		belly = Color3.fromRGB(214, 200, 120),
		fin = Color3.fromRGB(70, 92, 62),
		eye = Color3.fromRGB(244, 150, 90),
	},
	carp = {
		length = 3.0,
		height = 1.55,
		width = 0.95,
		body = Color3.fromRGB(196, 150, 74),
		belly = Color3.fromRGB(244, 222, 160),
		fin = Color3.fromRGB(214, 122, 58),
		whiskers = 0.45,
	},
	pike = {
		-- Długi, niski, z pyskiem jak dziób.
		length = 4.0,
		height = 0.95,
		width = 0.72,
		body = Color3.fromRGB(92, 136, 84),
		belly = Color3.fromRGB(226, 232, 190),
		fin = Color3.fromRGB(206, 140, 70),
		snout = 0.34,
		stripes = 4,
	},
	zander = {
		length = 3.4,
		height = 1.05,
		width = 0.72,
		body = Color3.fromRGB(128, 146, 124),
		belly = Color3.fromRGB(232, 236, 224),
		fin = Color3.fromRGB(96, 110, 102),
		stripes = 6,
	},
	catfish = {
		length = 4.4,
		height = 1.3,
		width = 1.15,
		body = Color3.fromRGB(84, 90, 100),
		belly = Color3.fromRGB(206, 204, 196),
		fin = Color3.fromRGB(62, 66, 76),
		whiskers = 1.3,
	},
	salmon = {
		length = 3.6,
		height = 1.15,
		width = 0.78,
		body = Color3.fromRGB(168, 184, 200),
		belly = Color3.fromRGB(244, 196, 186),
		fin = Color3.fromRGB(120, 136, 156),
	},
	sturgeon = {
		length = 4.8,
		height = 1.0,
		width = 0.9,
		body = Color3.fromRGB(110, 118, 130),
		belly = Color3.fromRGB(222, 224, 226),
		fin = Color3.fromRGB(84, 92, 104),
		snout = 0.3,
		plates = true,
		whiskers = 0.35,
	},
	albino_catfish = {
		length = 4.6,
		height = 1.35,
		width = 1.2,
		body = Color3.fromRGB(250, 236, 214),
		belly = Color3.fromRGB(255, 246, 236),
		fin = Color3.fromRGB(246, 196, 178),
		whiskers = 1.4,
		eye = Color3.fromRGB(246, 150, 160),
	},
	golden_fish = {
		length = 1.9,
		height = 1.4,
		width = 1.0,
		body = Color3.fromRGB(255, 196, 62),
		belly = Color3.fromRGB(255, 232, 150),
		fin = Color3.fromRGB(255, 150, 54),
		fancy = true,
	},
}

function FishModel.shape(fishId: string): Shape
	return SHAPES[fishId] or DEFAULT
end

local function decorate(part: BasePart, color: Color3, material: Enum.Material?)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

--[[ Elipsoida: zwykła część z siatką kuli. `Shape = Ball` wymusza równe
     wymiary, a ryba kulą nie jest. ]]
local function ellipsoid(
	model: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	decorate(part, color, material)

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part

	part.Parent = model
	return part
end

--[[ Klin. W Robloxie jest niski z przodu (-Z) i pełnej wysokości z tyłu
     (+Z), z płaskim spodem — obroty w wywołaniach wynikają z tego. ]]
local function wedge(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3)
	local part = Instance.new("WedgePart")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	decorate(part, color)
	part.Parent = model
end

local function buildEyes(model: Model, shape: Shape)
	-- Duże oczy to połowa „uroku" modelu: skala od wysokości, nie długości,
	-- więc szczupak nie dostaje spodków, a leszcz ma je jak talerze.
	local size = math.clamp(shape.height * 0.34, 0.26, 0.5)
	local z = -shape.length * 0.3
	local y = shape.height * 0.12
	-- Szerokość korpusu w miejscu oka (przekrój elipsoidy).
	local half = shape.width / 2 * math.sqrt(math.max(1 - (z / (shape.length / 2)) ^ 2, 0.05))

	for _, side in { -1, 1 } do
		ellipsoid(
			model,
			"Eye",
			Vector3.new(size * 0.5, size, size),
			CFrame.new(side * half * 0.92, y, z),
			shape.eye or WHITE
		)
		ellipsoid(
			model,
			"Pupil",
			Vector3.new(size * 0.3, size * 0.56, size * 0.56),
			CFrame.new(side * (half * 0.92 + size * 0.16), y, z - size * 0.06),
			PUPIL
		)
		-- Błysk w oku: jedna biała kropka i ryba „patrzy".
		ellipsoid(
			model,
			"Glint",
			Vector3.new(size * 0.14, size * 0.2, size * 0.2),
			CFrame.new(side * (half * 0.92 + size * 0.3), y + size * 0.14, z - size * 0.16),
			WHITE,
			Enum.Material.Neon
		)
	end
end

local function buildTail(model: Model, shape: Shape)
	local back = shape.length / 2
	local span = if shape.fancy then shape.height * 1.15 else shape.height * 0.62
	local reach = if shape.fancy then shape.length * 0.55 else shape.length * 0.26
	local size = Vector3.new(0.08, span, reach)

	-- Górny płat: klin wprost — wąski przy korpusie, rozchyla się ku tyłowi.
	wedge(model, "TailUpper", size, CFrame.new(0, span / 2, back + reach / 2 - 0.12), shape.fin)
	-- Dolny płat: ten sam klin odbity w pionie.
	wedge(
		model,
		"TailLower",
		size,
		CFrame.new(0, -span / 2, back + reach / 2 - 0.12) * CFrame.Angles(0, 0, math.pi),
		shape.fin
	)
end

local function buildFins(model: Model, shape: Shape)
	local top = shape.height / 2

	if shape.plates then
		-- Jesiotr: rząd kostnych płytek zamiast płetwy grzbietowej.
		for index = 1, 5 do
			local z = -shape.length * 0.28 + (index - 1) * shape.length * 0.14
			local scale = math.sqrt(math.max(1 - (z / (shape.length / 2)) ^ 2, 0.05))
			wedge(
				model,
				"Plate",
				Vector3.new(0.14, 0.24, 0.34),
				CFrame.new(0, top * scale + 0.06, z) * CFrame.Angles(0, math.pi, 0),
				shape.fin
			)
		end
	else
		-- Płetwa grzbietowa: klin obrócony tak, żeby był wysoki z przodu
		-- i opadał ku ogonowi.
		local finHeight = if shape.fancy then shape.height * 0.6 else shape.height * 0.42
		local finLength = shape.length * 0.32
		wedge(
			model,
			"Dorsal",
			Vector3.new(0.08, finHeight, finLength),
			CFrame.new(0, top * 0.92 + finHeight / 2, shape.length * 0.02)
				* CFrame.Angles(0, math.pi, 0),
			shape.fin
		)
	end

	-- Płetwy piersiowe: spłaszczone elipsoidy odstające na boki.
	for _, side in { -1, 1 } do
		ellipsoid(
			model,
			"Pectoral",
			Vector3.new(0.08, shape.height * 0.34, shape.length * 0.2),
			CFrame.new(side * shape.width * 0.46, -shape.height * 0.18, -shape.length * 0.08)
				* CFrame.Angles(0.35, 0, side * 0.75),
			shape.fin
		)
	end
end

local function buildDetails(model: Model, shape: Shape)
	local half = shape.length / 2

	if shape.snout then
		-- Pysk: wydłużona elipsoida wysunięta przed korpus.
		local reach = shape.length * shape.snout
		ellipsoid(
			model,
			"Snout",
			Vector3.new(shape.width * 0.6, shape.height * 0.46, reach * 1.6),
			CFrame.new(0, -shape.height * 0.06, -half - reach * 0.2),
			shape.body
		)
	end

	if shape.stripes then
		local dark = shape.body:Lerp(Color3.new(0, 0, 0), 0.38)
		for index = 1, shape.stripes do
			local z = -shape.length * 0.22 + (index - 1) * (shape.length * 0.56 / shape.stripes)
			local scale = math.sqrt(math.max(1 - (z / half) ^ 2, 0.05))
			-- Krążek minimalnie większy od przekroju korpusu, przesunięty
			-- w górę: widać go jako pręgę na grzbiecie, nie na brzuchu.
			ellipsoid(
				model,
				"Stripe",
				Vector3.new(shape.width * scale * 1.04, shape.height * scale * 0.8, 0.14),
				CFrame.new(0, shape.height * scale * 0.14, z),
				dark
			)
		end
	end

	if shape.whiskers then
		for _, side in { -1, 1 } do
			local whisker = Instance.new("Part")
			whisker.Name = "Whisker"
			whisker.Shape = Enum.PartType.Cylinder
			-- Walec leży wzdłuż osi X.
			whisker.Size = Vector3.new(shape.whiskers, 0.06, 0.06)
			whisker.CFrame = CFrame.new(
				side * (shape.width * 0.3 + shape.whiskers * 0.4),
				-shape.height * 0.24,
				-half * 0.86
			) * CFrame.Angles(0, side * 0.5, side * -0.35)
			decorate(whisker, shape.fin)
			whisker.Parent = model
		end
	end
end

--[[
	Buduje model gatunku `fishId`. `scale` mnoży wszystkie wymiary —
	wyskakujący okaz jest większy od przeciętnej sztuki.

	Pivot modelu leży w środku korpusu, przodem (-Z) do pyska; wszystkie
	części są zakotwiczone, więc całość przesuwa się jednym `PivotTo`.
]]
function FishModel.build(fishId: string, scale: number?): Model
	local shape = FishModel.shape(fishId)

	local model = Instance.new("Model")
	model.Name = `Fish_{fishId}`

	local material = if shape.fancy then Enum.Material.Neon else nil
	local body = ellipsoid(
		model,
		"Body",
		Vector3.new(shape.width, shape.height, shape.length),
		CFrame.identity,
		shape.body,
		material
	)
	model.PrimaryPart = body

	-- Jaśniejszy brzuch: druga elipsoida, niżej i odrobinę mniejsza.
	ellipsoid(
		model,
		"Belly",
		Vector3.new(shape.width * 0.94, shape.height * 0.62, shape.length * 0.9),
		CFrame.new(0, -shape.height * 0.2, 0),
		shape.belly
	)

	buildTail(model, shape)
	buildFins(model, shape)
	buildDetails(model, shape)
	buildEyes(model, shape)

	if scale and scale ~= 1 then
		model:ScaleTo(scale)
	end

	return model
end

return table.freeze(FishModel)
