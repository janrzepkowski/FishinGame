--!strict
--[[
	FishModel — wygląd każdego gatunku ryby jako dane i jeden budowniczy.

	Ten sam model widzi gracz w czterech miejscach: wyskakujący z wody po
	wyholowaniu, w ekwipunku, w bestiariuszu i na ladzie skupu. Jedno źródło
	oznacza, że ryba w torbie wygląda dokładnie jak ta, która przed chwilą
	wyleciała z jeziora — tak jak wędka w sklepie jest tą samą wędką co
	w ręce (`RodModel`). Obrazek wgrany na Roblox rozjechałby się z modelem
	przy pierwszej zmianie.

	STYL: gra jest dla dzieci, więc ryby są jak żelki — pękate, z wielkimi
	oczami, rumieńcami i czystymi, nasyconymi kolorami. NIE MA TU ANI JEDNEJ
	OSTREJ KRAWĘDZI: płetwy i ogony to spłaszczone elipsoidy, nie kliny.

	KAŻDY GATUNEK MA COŚ SWOJEGO, co widać w okienku 60x60 pikseli: szczupak
	ma kaczy pysk i żółte cętki, okoń kolczasty grzebień i pręgi, sum wąsy
	do połowy ciała, jesiotr złote płytki i ogon rekina, a Złota Rybka nosi
	koronę. Sylwetka i jeden wyróżnik mówią więcej niż detal, którego w tej
	skali i tak nie widać.

	Wszystko z prymitywów, bez żadnego assetu: elipsoidy to zwykłe `Part`
	z siatką `Sphere`.

	ORIENTACJA: przód ryby to lokalne -Z, grzbiet to +Y.
]]

local FishModel = {}

export type Dorsal = "fin" | "spikes" | "sail" | "back" | "plates" | "none"
export type Tail = "fork" | "round" | "veil" | "shark"

export type Shape = {
	-- Wymiary korpusu w studach: długość (Z), wysokość (Y), szerokość (X).
	length: number,
	height: number,
	width: number,
	body: Color3,
	belly: Color3,
	fin: Color3,
	-- Ciemniejsza „czapka" na grzbiecie; nil = grzbiet w kolorze korpusu.
	back: Color3?,
	dorsal: Dorsal?,
	tail: Tail?,
	-- Wąsy (sum, karp): długość w studach; nil = bez wąsów.
	whiskers: number?,
	-- Wydłużony pysk (szczupak, jesiotr): długość jako ułamek korpusu.
	snout: number?,
	-- Ciemne pręgi w poprzek grzbietu (okoń, sandacz).
	stripes: number?,
	-- Cętki albo łuski na bokach: liczba na stronę i kolor.
	spots: number?,
	spotColor: Color3?,
	spotSize: number?,
	-- Kolor płytek jesiotra (`dorsal = "plates"`).
	plateColor: Color3?,
	-- Białe ząbki drapieżnika.
	teeth: boolean?,
	-- Korona i poświata (Złota Rybka).
	crown: boolean?,
	glow: boolean?,
	eye: Color3?,
	cheeks: Color3?,
	lips: Color3?,
}

local WHITE = Color3.fromRGB(255, 255, 255)
local PUPIL = Color3.fromRGB(26, 28, 44)
local BLUSH = Color3.fromRGB(255, 138, 170)

-- Kształt awaryjny dla gatunku, którego ktoś jeszcze tu nie opisał.
-- Nowa ryba w katalogu ma się POJAWIĆ, a nie wywalić ekwipunku.
local DEFAULT: Shape = {
	length = 2.4,
	height = 1.2,
	width = 0.8,
	body = Color3.fromRGB(130, 196, 255),
	belly = Color3.fromRGB(236, 246, 255),
	fin = Color3.fromRGB(86, 150, 236),
}

local SHAPES: { [string]: Shape } = {
	roach = {
		-- Płoć: srebrnobłękitna, z czerwonymi płetwami. Pierwsza ryba gracza
		-- — ma być najprostsza i najsłodsza.
		length = 2.1,
		height = 1.15,
		width = 0.78,
		body = Color3.fromRGB(126, 200, 255),
		back = Color3.fromRGB(84, 152, 240),
		belly = Color3.fromRGB(240, 250, 255),
		fin = Color3.fromRGB(255, 96, 86),
	},
	perch = {
		-- Okoń: limonkowy, w pręgi, z kolczastym grzebieniem.
		length = 2.3,
		height = 1.3,
		width = 0.84,
		body = Color3.fromRGB(132, 218, 76),
		back = Color3.fromRGB(84, 170, 62),
		belly = Color3.fromRGB(255, 242, 150),
		fin = Color3.fromRGB(255, 132, 40),
		stripes = 5,
		dorsal = "spikes",
	},
	bream = {
		-- Leszcz jest wysoki i płaski — jedyna ryba o takiej sylwetce.
		length = 2.4,
		height = 1.95,
		width = 0.66,
		body = Color3.fromRGB(255, 196, 96),
		back = Color3.fromRGB(232, 150, 70),
		belly = Color3.fromRGB(255, 236, 190),
		fin = Color3.fromRGB(190, 110, 220),
		dorsal = "sail",
	},
	tench = {
		-- Lin: szmaragdowy, okrągły wszędzie, z pomarańczowym oczkiem.
		length = 2.4,
		height = 1.4,
		width = 0.96,
		body = Color3.fromRGB(64, 190, 130),
		back = Color3.fromRGB(40, 150, 110),
		belly = Color3.fromRGB(244, 230, 124),
		fin = Color3.fromRGB(30, 130, 110),
		eye = Color3.fromRGB(255, 176, 90),
		tail = "round",
		whiskers = 0.22,
	},
	carp = {
		-- Karp: pomarańczowy grubas z dużymi łuskami i wąsami.
		length = 2.9,
		height = 1.7,
		width = 1.12,
		body = Color3.fromRGB(255, 152, 56),
		back = Color3.fromRGB(240, 110, 46),
		belly = Color3.fromRGB(255, 230, 156),
		fin = Color3.fromRGB(240, 84, 64),
		whiskers = 0.45,
		spots = 5,
		spotColor = Color3.fromRGB(255, 204, 116),
		spotSize = 0.34,
		lips = Color3.fromRGB(255, 130, 150),
	},
	pike = {
		-- Szczupak: długi, z kaczym pyskiem, żółtymi cętkami i płetwą
		-- przesuniętą pod sam ogon.
		length = 3.9,
		height = 1.05,
		width = 0.84,
		body = Color3.fromRGB(72, 176, 100),
		back = Color3.fromRGB(46, 136, 84),
		belly = Color3.fromRGB(240, 246, 172),
		fin = Color3.fromRGB(255, 164, 50),
		snout = 0.3,
		spots = 6,
		spotColor = Color3.fromRGB(250, 238, 124),
		spotSize = 0.2,
		dorsal = "back",
		teeth = true,
	},
	zander = {
		-- Sandacz: stalowy, w pręgi, z dwoma ząbkami i szklistym okiem.
		length = 3.3,
		height = 1.15,
		width = 0.84,
		body = Color3.fromRGB(104, 168, 204),
		back = Color3.fromRGB(64, 116, 170),
		belly = Color3.fromRGB(234, 246, 244),
		fin = Color3.fromRGB(58, 104, 160),
		stripes = 6,
		dorsal = "spikes",
		teeth = true,
		eye = Color3.fromRGB(206, 255, 246),
	},
	catfish = {
		-- Sum: fioletowy, szeroki łeb, wąsy do połowy ciała, bez płetwy.
		length = 4.2,
		height = 1.4,
		width = 1.3,
		body = Color3.fromRGB(122, 108, 196),
		back = Color3.fromRGB(88, 76, 160),
		belly = Color3.fromRGB(230, 220, 246),
		fin = Color3.fromRGB(86, 74, 150),
		whiskers = 1.4,
		tail = "round",
		dorsal = "none",
	},
	salmon = {
		-- Łosoś: różowy z ciemnym grzbietem i drobnymi cętkami.
		length = 3.5,
		height = 1.3,
		width = 0.9,
		body = Color3.fromRGB(255, 132, 146),
		back = Color3.fromRGB(110, 150, 214),
		belly = Color3.fromRGB(255, 228, 220),
		fin = Color3.fromRGB(226, 84, 116),
		spots = 6,
		spotColor = Color3.fromRGB(196, 62, 96),
		spotSize = 0.13,
		snout = 0.1,
	},
	sturgeon = {
		-- Jesiotr: prehistoryczny — złote płytki na grzbiecie, długi nos
		-- i niesymetryczny ogon rekina.
		length = 4.6,
		height = 1.1,
		width = 1.0,
		body = Color3.fromRGB(112, 136, 176),
		back = Color3.fromRGB(78, 98, 142),
		belly = Color3.fromRGB(236, 240, 246),
		fin = Color3.fromRGB(78, 98, 142),
		snout = 0.3,
		dorsal = "plates",
		plateColor = Color3.fromRGB(255, 212, 110),
		tail = "shark",
		whiskers = 0.35,
	},
	albino_catfish = {
		-- Sum albinos: kremowy, z różowymi płetwami, oczami i rumieńcem.
		length = 4.4,
		height = 1.45,
		width = 1.34,
		body = Color3.fromRGB(255, 242, 228),
		belly = Color3.fromRGB(255, 252, 246),
		fin = Color3.fromRGB(255, 176, 196),
		whiskers = 1.5,
		tail = "round",
		dorsal = "none",
		eye = Color3.fromRGB(255, 150, 170),
		cheeks = Color3.fromRGB(255, 120, 150),
		lips = Color3.fromRGB(255, 150, 170),
	},
	golden_fish = {
		-- Złota Rybka: świeci, ma welon zamiast ogona i koronę.
		length = 1.9,
		height = 1.5,
		width = 1.1,
		body = Color3.fromRGB(255, 200, 50),
		belly = Color3.fromRGB(255, 236, 150),
		fin = Color3.fromRGB(255, 140, 40),
		tail = "veil",
		dorsal = "sail",
		crown = true,
		glow = true,
		lips = Color3.fromRGB(255, 110, 120),
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

--[[ Ułamek pełnego przekroju korpusu w odległości `z` od środka (0..1).
     Korpus to elipsoida, więc przekrój maleje ku pyskowi i ogonowi. ]]
local function taper(shape: Shape, z: number): number
	return math.sqrt(math.max(1 - (z / (shape.length / 2)) ^ 2, 0.04))
end

--[[ Odległość powierzchni korpusu od osi w punkcie (y, z) — tam kładziemy
     wszystko, co ma leżeć NA boku ryby: oczy, rumieńce, cętki. ]]
local function sideAt(shape: Shape, y: number, z: number): number
	local inner = 1 - (y / (shape.height / 2)) ^ 2 - (z / (shape.length / 2)) ^ 2
	return shape.width / 2 * math.sqrt(math.max(inner, 0.02))
end

local function buildEyes(model: Model, shape: Shape)
	-- Wielkie oczy to połowa „uroku" modelu: skala od wysokości, nie długości,
	-- więc szczupak nie dostaje spodków, a leszcz ma je jak talerze.
	local size = math.clamp(shape.height * 0.46, 0.36, 0.7)
	local z = -shape.length * 0.27
	local y = shape.height * 0.12
	local half = sideAt(shape, y, z)

	for _, side in { -1, 1 } do
		ellipsoid(
			model,
			"Eye",
			Vector3.new(size * 0.55, size, size),
			CFrame.new(side * half * 0.9, y, z),
			shape.eye or WHITE
		)
		ellipsoid(
			model,
			"Pupil",
			Vector3.new(size * 0.34, size * 0.66, size * 0.66),
			CFrame.new(side * (half * 0.9 + size * 0.17), y - size * 0.03, z - size * 0.05),
			PUPIL
		)
		-- Dwa błyski: duży u góry i mały na dole. Jeden robi z kropki oko,
		-- drugi robi z oka oko z kreskówki.
		ellipsoid(
			model,
			"Glint",
			Vector3.new(size * 0.16, size * 0.26, size * 0.26),
			CFrame.new(side * (half * 0.9 + size * 0.31), y + size * 0.15, z - size * 0.17),
			WHITE,
			Enum.Material.Neon
		)
		ellipsoid(
			model,
			"GlintSmall",
			Vector3.new(size * 0.12, size * 0.13, size * 0.13),
			CFrame.new(side * (half * 0.9 + size * 0.32), y - size * 0.17, z + size * 0.1),
			WHITE,
			Enum.Material.Neon
		)

		-- Rumieniec pod okiem.
		local cheekY = y - size * 0.62
		local cheekZ = z + size * 0.1
		ellipsoid(
			model,
			"Cheek",
			Vector3.new(0.08, size * 0.34, size * 0.5),
			CFrame.new(side * sideAt(shape, cheekY, cheekZ) * 0.99, cheekY, cheekZ),
			shape.cheeks or BLUSH
		)
	end
end

--[[ Płat ogona: spłaszczona elipsoida odchylona o `angle` od osi ryby
     (dodatni kąt = w górę), zaczepiona bliższym końcem przy korpusie. ]]
local function tailLobe(
	model: Model,
	shape: Shape,
	name: string,
	angle: number,
	span: number,
	reach: number
)
	local root = shape.length / 2 - shape.length * 0.06
	-- Obrót wokół X o dodatni kąt opuszcza +Z, więc „w górę" to kąt ujemny.
	local pivot = CFrame.new(0, 0, root) * CFrame.Angles(-angle, 0, 0)
	ellipsoid(
		model,
		name,
		Vector3.new(0.14, span, reach),
		pivot * CFrame.new(0, 0, reach * 0.42),
		shape.fin
	)
end

local function buildTail(model: Model, shape: Shape)
	local style: Tail = shape.tail or "fork"
	local height = shape.height
	local length = shape.length

	if style == "round" then
		-- Wachlarz: jeden krągły płat (lin, sum).
		tailLobe(model, shape, "Tail", 0, height * 0.95, length * 0.26)
	elseif style == "veil" then
		-- Welon: trzy długie, opadające płaty.
		tailLobe(model, shape, "TailUpper", 0.75, height * 0.6, length * 0.7)
		tailLobe(model, shape, "TailMiddle", 0, height * 0.5, length * 0.62)
		tailLobe(model, shape, "TailLower", -0.75, height * 0.6, length * 0.7)
	elseif style == "shark" then
		-- Niesymetryczny: długi płat górny, krótki dolny (jesiotr).
		tailLobe(model, shape, "TailUpper", 0.7, height * 0.5, length * 0.3)
		tailLobe(model, shape, "TailLower", -0.6, height * 0.42, length * 0.15)
	else
		tailLobe(model, shape, "TailUpper", 0.62, height * 0.5, length * 0.3)
		tailLobe(model, shape, "TailLower", -0.62, height * 0.5, length * 0.3)
	end
end

local function buildDorsal(model: Model, shape: Shape)
	local style: Dorsal = shape.dorsal or "fin"
	local top = shape.height / 2
	local length = shape.length

	if style == "none" then
		return
	end

	if style == "plates" then
		-- Jesiotr: rząd okrągłych, złotych płytek wzdłuż grzbietu.
		for index = 1, 6 do
			local z = -length * 0.26 + (index - 1) * length * 0.11
			local size = 0.3 - math.abs(index - 3) * 0.025
			ellipsoid(
				model,
				"Plate",
				Vector3.new(size * 0.8, size, size * 1.1),
				CFrame.new(0, top * taper(shape, z) + size * 0.08, z),
				shape.plateColor or shape.fin
			)
		end
		return
	end

	if style == "spikes" then
		-- Kolczasty grzebień: coraz niższe „płomyki" pochylone ku ogonowi.
		for index = 1, 5 do
			local z = -length * 0.16 + (index - 1) * length * 0.1
			local spike = shape.height * (0.62 - index * 0.07)
			ellipsoid(
				model,
				"Spike",
				Vector3.new(0.12, spike, length * 0.1),
				CFrame.new(0, top * taper(shape, z) + spike * 0.2, z) * CFrame.Angles(0.45, 0, 0),
				shape.fin
			)
		end
		return
	end

	local finHeight = shape.height * (if style == "sail" then 0.95 else 0.62)
	local finLength = length * (if style == "sail" then 0.44 else 0.3)
	-- Szczupak ma płetwę grzbietową tuż przed ogonem.
	local z = if style == "back" then length * 0.27 else length * 0.03

	-- Pół elipsoidy siedzi w korpusie, więc widać zaokrąglony „żagiel".
	ellipsoid(
		model,
		"Dorsal",
		Vector3.new(0.12, finHeight, finLength),
		CFrame.new(0, top * taper(shape, z) * 0.94 + finHeight * 0.16, z)
			* CFrame.Angles(0.42, 0, 0),
		shape.fin
	)
end

local function buildFins(model: Model, shape: Shape)
	buildDorsal(model, shape)

	-- Płetwy piersiowe: spłaszczone elipsoidy odstające na boki.
	for _, side in { -1, 1 } do
		ellipsoid(
			model,
			"Pectoral",
			Vector3.new(0.1, shape.height * 0.4, shape.length * 0.2),
			CFrame.new(side * shape.width * 0.47, -shape.height * 0.2, -shape.length * 0.06)
				* CFrame.Angles(0.35, 0, side * 0.8),
			shape.fin
		)
	end

	-- Płetwa odbytowa pod brzuchem — domyka sylwetkę od spodu.
	local z = shape.length * 0.22
	ellipsoid(
		model,
		"Anal",
		Vector3.new(0.1, shape.height * 0.36, shape.length * 0.16),
		CFrame.new(0, -shape.height / 2 * taper(shape, z) * 0.9, z) * CFrame.Angles(-0.5, 0, 0),
		shape.fin
	)
end

local function buildDetails(model: Model, shape: Shape)
	local half = shape.length / 2
	-- Punkt, w którym kończy się pysk: czubek korpusu albo czubek ryja.
	local mouthZ = -half

	if shape.snout then
		-- Pysk: spłaszczona elipsoida wysunięta przed korpus (kaczy dziób).
		local reach = shape.length * shape.snout
		ellipsoid(
			model,
			"Snout",
			Vector3.new(shape.width * 0.68, shape.height * 0.42, reach * 1.7),
			CFrame.new(0, -shape.height * 0.07, -half - reach * 0.18),
			shape.body
		)
		mouthZ = -half - reach * 0.95
	end

	-- Buzia: mały „dzióbek" na czubku. Bez niej ryba nie ma miny.
	ellipsoid(
		model,
		"Mouth",
		Vector3.new(shape.width * 0.3, shape.height * 0.13, 0.2),
		CFrame.new(0, -shape.height * 0.1, mouthZ + 0.07),
		shape.lips or shape.body:Lerp(Color3.new(0, 0, 0), 0.3)
	)

	if shape.teeth then
		for _, side in { -1, 1 } do
			ellipsoid(
				model,
				"Tooth",
				Vector3.new(0.1, 0.2, 0.1),
				CFrame.new(side * shape.width * 0.1, -shape.height * 0.2, mouthZ + 0.12),
				WHITE
			)
		end
	end

	if shape.stripes then
		local dark = (shape.back or shape.body):Lerp(Color3.new(0, 0, 0), 0.22)
		for index = 1, shape.stripes do
			local z = -shape.length * 0.14 + (index - 1) * (shape.length * 0.5 / shape.stripes)
			local scale = taper(shape, z)
			-- Krążek minimalnie większy od przekroju korpusu, przesunięty
			-- w górę: widać go jako pręgę na grzbiecie, nie na brzuchu.
			ellipsoid(
				model,
				"Stripe",
				Vector3.new(shape.width * scale * 1.05, shape.height * scale * 0.82, 0.16),
				CFrame.new(0, shape.height * scale * 0.14, z),
				dark
			)
		end
	end

	if shape.spots then
		local size = shape.spotSize or 0.2
		local color = shape.spotColor or shape.fin
		for index = 1, shape.spots do
			local z = -shape.length * 0.08 + (index - 1) * (shape.length * 0.44 / shape.spots)
			-- Zygzak: co druga cętka wyżej, żeby nie stały w szeregu.
			local y = shape.height * (if index % 2 == 0 then 0.2 else -0.02)
			for _, side in { -1, 1 } do
				ellipsoid(
					model,
					"Spot",
					Vector3.new(0.1, size, size),
					CFrame.new(side * sideAt(shape, y, z) * 0.98, y, z),
					color
				)
			end
		end
	end

	if shape.whiskers then
		for _, side in { -1, 1 } do
			local whisker = Instance.new("Part")
			whisker.Name = "Whisker"
			whisker.Shape = Enum.PartType.Cylinder
			-- Walec leży wzdłuż osi X.
			whisker.Size = Vector3.new(shape.whiskers, 0.09, 0.09)
			local root = CFrame.new(side * shape.width * 0.26, -shape.height * 0.2, mouthZ + 0.3)
				* CFrame.Angles(0, side * 0.55, side * -0.4)
			whisker.CFrame = root * CFrame.new(side * shape.whiskers / 2, 0, 0)
			decorate(whisker, shape.fin)
			whisker.Parent = model

			-- Kulka na końcu wąsa: zaokrąglony koniec zamiast uciętego.
			ellipsoid(
				model,
				"WhiskerTip",
				Vector3.new(0.17, 0.17, 0.17),
				root * CFrame.new(side * shape.whiskers, 0, 0),
				shape.fin
			)
		end
	end

	if shape.crown then
		local z = -shape.length * 0.12
		local base = CFrame.new(0, shape.height / 2 * taper(shape, z) + 0.1, z)
		local gold = Color3.fromRGB(255, 226, 90)
		local jewels = {
			Color3.fromRGB(255, 86, 120),
			Color3.fromRGB(90, 200, 255),
			Color3.fromRGB(150, 110, 255),
		}

		local band = Instance.new("Part")
		band.Name = "CrownBand"
		band.Shape = Enum.PartType.Cylinder
		band.Size = Vector3.new(0.2, 0.62, 0.62)
		-- Walec leży wzdłuż osi X — obrót wokół Z stawia obręcz poziomo.
		band.CFrame = base * CFrame.Angles(0, 0, math.rad(90))
		decorate(band, gold, Enum.Material.Neon)
		band.Parent = model

		for index, jewel in jewels do
			local angle = (index - 1) * (math.pi * 2 / #jewels)
			local offset = CFrame.new(math.cos(angle) * 0.24, 0.2, math.sin(angle) * 0.24)
			ellipsoid(
				model,
				"CrownPoint",
				Vector3.new(0.16, 0.34, 0.16),
				base * offset,
				gold,
				Enum.Material.Neon
			)
			ellipsoid(
				model,
				"CrownJewel",
				Vector3.new(0.16, 0.16, 0.16),
				base * offset * CFrame.new(0, 0.2, 0),
				jewel,
				Enum.Material.Neon
			)
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

	local material = if shape.glow then Enum.Material.Neon else nil
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
		Vector3.new(shape.width * 0.95, shape.height * 0.62, shape.length * 0.9),
		CFrame.new(0, -shape.height * 0.2, 0),
		shape.belly
	)

	if shape.back then
		-- Ciemniejszy grzbiet: ta sama sztuczka co z brzuchem, lustrzanie.
		ellipsoid(
			model,
			"Back",
			Vector3.new(shape.width * 0.9, shape.height * 0.5, shape.length * 0.9),
			CFrame.new(0, shape.height * 0.27, 0),
			shape.back
		)
	end

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
