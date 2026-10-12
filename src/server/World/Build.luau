--!strict
--[[
	Build — prymitywy do stawiania mapy z kodu.

	Bez tego każdy element mapy to osiem linijek przypisań do właściwości,
	a plik świata rozrasta się do tysiąca linii, w których nie widać kształtu
	budynku. Z tym jedna linijka = jedna bryła.

	Wszystko jest domyślnie `Anchored` i CAŁKOWICIE przezroczyste dla fizyki:
	`CanCollide`, `CanQuery` i `CanTouch` są wyłączone.

	Domyślne wyłączenie kolizji jest celowe i wynika z konkretnego błędu:
	korona drzewa to trzy kule zawieszone kilka metrów nad ziemią. Z domyślnym
	`CanCollide = true` każde drzewo w lesie staje się niewidzialną ścianą,
	w którą gracz wchodzi, nie rozumiejąc dlaczego. To samo dotyczy trzcin
	na brzegu i ryb leżących na ladzie.

	Rzeczy, po których gracz chodzi albo o które się opiera — podłogi, deski
	pomostu, barierki, lady, ściany — deklarują `CanCollide = true` jawnie.
	Lepiej napisać to w dwudziestu miejscach niż szukać przez tydzień,
	o co gracz zahacza w lesie.
]]

local Build = {}

--[[
	Skala świata, wyprowadzona z postaci gracza.

	Domyślna postać R15 ma 5,5 studa wysokości (blokowy rig R6 — 5,1).
	Przyjmujemy, że to człowiek o wzroście 1,8 m, co daje ~3,06 studa na metr.

	Wszystkie wymiary budynków liczymy z `METER`, a nie dobieramy na oko.
	Budynek dobrany „żeby ładnie wyglądał" w widoku z góry okazuje się
	karłowaty w sekundzie, w której stanie obok niego gracz — a to jedyny
	widok, który kogokolwiek obchodzi.
]]
Build.HUMAN_HEIGHT = 5.5
Build.METER = Build.HUMAN_HEIGHT / 1.8

--[[ Wymiar w metrach, przeliczony na study. ]]
function Build.m(meters: number): number
	return meters * Build.METER
end

local function applyDefaults(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
end

local function assign(instance: Instance, props: { [string]: any }?): Instance
	if not props then
		return instance
	end

	local target: any = instance
	for key, value in props do
		-- Parent ustawiamy osobno, na końcu — patrz niżej.
		if key ~= "Parent" then
			target[key] = value
		end
	end
	return instance
end

--[[
	Prostopadłościan. `props` to zwykłe właściwości Part, więc nie trzeba
	uczyć się osobnego słownika.

	Parent przypisujemy NA KOŃCU, już po wszystkich właściwościach: instancja
	trafia do świata gotowa, zamiast przechodzić przez stan pośredni, który
	silnik i tak musiałby przeliczyć.
]]
function Build.block(parent: Instance, props: { [string]: any }): Part
	local part = Instance.new("Part")
	applyDefaults(part)
	assign(part, props)
	part.Parent = parent
	return part
end

--[[ Klin — dachy, pochylnie, wszystko co ma skos. ]]
function Build.wedge(parent: Instance, props: { [string]: any }): WedgePart
	local part = Instance.new("WedgePart")
	applyDefaults(part)
	assign(part, props)
	part.Parent = parent
	return part
end

--[[ Walec — słupki, beczki, pnie. ]]
function Build.cylinder(parent: Instance, props: { [string]: any }): Part
	local part = Build.block(parent, props)
	part.Shape = Enum.PartType.Cylinder
	return part
end

--[[ Kula. UWAGA: `Shape = Ball` wymusza RÓWNE wymiary — przy rozmiarze
     (4, 3, 4) silnik i tak zrobi kulę 3×3×3. Do spłaszczonych brył
     (korony drzew, kamienie, balony) jest `Build.ellipsoid`. ]]
function Build.sphere(parent: Instance, props: { [string]: any }): Part
	local part = Build.block(parent, props)
	part.Shape = Enum.PartType.Ball
	return part
end

--[[
	Elipsoida: Part z `SpecialMesh` typu Sphere, rozciągniętą do `Size`.

	To podstawowa bryła cukierkowej mapy. Zaokrąglone korony, kamienie,
	balony i kopułki — wszystko, co w poprzedniej wersji było kulą
	(bo Ball nie umie być spłaszczony) albo klockiem.

	Kolizja liczy się po prostopadłościanie Partu, nie po elipsoidzie.
	Dlatego elipsoidy domyślnie nie kolidują (jak wszystko w Build),
	a tam, gdzie gracz ma się zatrzymać, stawiamy niewidzialny walec.
]]
function Build.ellipsoid(parent: Instance, props: { [string]: any }): Part
	local part = Build.block(parent, props)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

--[[
	Pigułka: walec z kulami na końcach, leżący wzdłuż lokalnego X.

	Zaokrąglone belki, słupki i poręcze — bez ostrych krawędzi, które
	odróżniały mapę od cukierkowego interfejsu. `length` to długość
	całości razem z zaokrągleniami.
]]
function Build.pill(
	parent: Instance,
	cframe: CFrame,
	length: number,
	thickness: number,
	props: { [string]: any }
): Part
	local core = math.max(length - thickness, 0.05)
	local body = Build.cylinder(parent, props)
	body.Size = Vector3.new(core, thickness, thickness)
	body.CFrame = cframe

	for _, side in { -1, 1 } do
		local cap = Build.sphere(parent, props)
		cap.Name = "PillCap"
		cap.Size = Vector3.new(thickness, thickness, thickness)
		cap.CFrame = cframe * CFrame.new(side * core / 2, 0, 0)
		-- Czapki nigdy nie kolidują: kula na końcu barierki to miejsce,
		-- o które gracz zahacza, a nie po którym chodzi.
		cap.CanCollide = false
	end

	return body
end

--[[ Pionowa pigułka (słupek) stojąca na punkcie `base`. ]]
function Build.post(
	parent: Instance,
	base: Vector3,
	height: number,
	thickness: number,
	props: { [string]: any }
): Part
	return Build.pill(
		parent,
		CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		height,
		thickness,
		props
	)
end

--[[ Pusty Model — grupuje elementy jednej budowli, żeby dało się ją ruszyć całą. ]]
function Build.model(parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

function Build.folder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

--[[
	Dwuspadowy dach z dwóch klinów.

	`width` biegnie wzdłuż kalenicy, `depth` to głębokość jednej połaci,
	`rise` to wysokość w kalenicy. Kliny są obrócone lustrzanie względem
	siebie, więc stykają się na szczycie.
]]
function Build.gableRoof(
	parent: Instance,
	center: Vector3,
	width: number,
	depth: number,
	rise: number,
	props: { [string]: any }
)
	for _, side in { -1, 1 } do
		local wedge = Build.wedge(parent, props)
		wedge.Size = Vector3.new(depth / 2, rise, width)
		-- WedgePart rośnie skosem w +Y/-Z; obrót o 90° wokół Y ustawia skos
		-- w poprzek kalenicy, a `side` odbija jedną połać na drugą stronę.
		wedge.CFrame = CFrame.new(center + Vector3.new(side * depth / 4, 0, 0))
			* CFrame.Angles(0, side * math.rad(90), 0)
	end
end

--[[
	Tabliczka z napisem. SurfaceGui, nie BillboardGui — szyld ma wisieć
	na budynku i być czytelny pod kątem, a nie obracać się za kamerą.
]]
function Build.signFace(
	board: BasePart,
	face: Enum.NormalId,
	title: string,
	subtitle: string,
	accent: Color3
)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face
	gui.CanvasSize = Vector2.new(400, 130)
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.Parent = board

	-- Ta sama czcionka i ten sam obrys liter co w interfejsie: szyld na
	-- budynku i okno sklepu mają wyglądać jak z jednej gry.
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.fromScale(0.94, 0.6)
	titleLabel.Position = UDim2.fromScale(0.03, 0.02)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.Text = title
	titleLabel.TextColor3 = accent
	titleLabel.TextScaled = true
	titleLabel.Parent = gui

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(40, 46, 84)
	titleStroke.Thickness = 4
	titleStroke.Parent = titleLabel

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Size = UDim2.fromScale(0.94, 0.3)
	subtitleLabel.Position = UDim2.fromScale(0.03, 0.64)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = Enum.Font.FredokaOne
	subtitleLabel.Text = subtitle
	subtitleLabel.TextColor3 = Color3.fromRGB(40, 46, 84)
	subtitleLabel.TextScaled = true
	subtitleLabel.Parent = gui
end

return table.freeze(Build)
