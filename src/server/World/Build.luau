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

function Build.sphere(parent: Instance, props: { [string]: any }): Part
	local part = Build.block(parent, props)
	part.Shape = Enum.PartType.Ball
	return part
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

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.fromScale(1, 0.62)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.Text = title
	titleLabel.TextColor3 = accent
	titleLabel.TextScaled = true
	titleLabel.Parent = gui

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Size = UDim2.fromScale(1, 0.34)
	subtitleLabel.Position = UDim2.fromScale(0, 0.64)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = Enum.Font.GothamMedium
	subtitleLabel.Text = subtitle
	subtitleLabel.TextColor3 = Color3.fromRGB(236, 240, 246)
	subtitleLabel.TextScaled = true
	subtitleLabel.Parent = gui
end

return table.freeze(Build)
