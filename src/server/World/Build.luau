--!strict
--[[
	Build — prymitywy do stawiania mapy z kodu.

	STYL: świat jest ZAOKRĄGLONY i pastelowy. Podstawowe bryły to walec,
	kula i elipsoida; prostopadłościan zostaje tam, gdzie gracz po czymś
	chodzi, i nawet wtedy dostaje okrągłe końce (`Build.pill`). Wszystko
	jest z gładkiego plastiku — jak zabawka, nie jak makieta.

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

-- Nunito, nie FredokaOne: ta druga nie ma polskich znaków (ę, ł, ś…)
-- i szyld wychodził w dwóch krojach naraz.
local SIGN_FONT = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Heavy)

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

--[[
	Paleta świata: pastelowe „cukierki". Każdy kolor na mapie pochodzi stąd
	(docs/art/ART_DIRECTION.md) — dzięki temu stoisko, pomost i drzewo
	wyglądają, jakby wyjęto je z jednego pudełka.
]]
Build.COLOR = table.freeze({
	cream = Color3.fromRGB(232, 204, 172),
	vanilla = Color3.fromRGB(244, 208, 132),
	peach = Color3.fromRGB(255, 196, 160),
	pink = Color3.fromRGB(255, 150, 190),
	rose = Color3.fromRGB(255, 108, 150),
	cherry = Color3.fromRGB(240, 70, 96),
	lilac = Color3.fromRGB(196, 164, 255),
	grape = Color3.fromRGB(150, 110, 230),
	sky = Color3.fromRGB(140, 206, 255),
	aqua = Color3.fromRGB(110, 226, 220),
	mint = Color3.fromRGB(150, 232, 180),
	leaf = Color3.fromRGB(112, 214, 120),
	lime = Color3.fromRGB(176, 232, 110),
	lemon = Color3.fromRGB(255, 226, 96),
	orange = Color3.fromRGB(255, 170, 84),
	cocoa = Color3.fromRGB(176, 122, 96),
	-- „Biel" jest lekko przygaszona: czysta biel w pełnym słońcu przepala
	-- się w białą plamę bez kształtu.
	white = Color3.fromRGB(226, 230, 242),
	ink = Color3.fromRGB(46, 50, 110),
})

--[[
	Elipsoida: część z siatką kuli. `Shape = Ball` wymusza równe wymiary,
	a kopuła dachu, korona drzewa i kamień-pianka kulami nie są.

	UWAGA: siatka zmienia tylko WYGLĄD. Kolizja zostaje prostopadłościanem,
	więc elipsoidy nie nadają się na nic, po czym gracz chodzi.
]]
function Build.ellipsoid(parent: Instance, props: { [string]: any }): Part
	local part = Instance.new("Part")
	applyDefaults(part)
	assign(part, props)

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part

	part.Parent = parent
	return part
end

--[[
	Walec STOJĄCY: słupek, krążek podłogi, pień. `center` to środek bryły.

	Walec w Robloxie leży wzdłuż osi X, więc każde „postaw go pionowo"
	wymaga obrotu wokół Z i zamiany wymiarów. Ta funkcja robi to raz —
	w wywołaniach zostaje średnica i wysokość, czyli to, co się ma na myśli.
]]
function Build.upright(
	parent: Instance,
	center: CFrame,
	diameter: number,
	height: number,
	props: { [string]: any }
): Part
	local part = Build.block(parent, props)
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, diameter, diameter)
	part.CFrame = center * CFrame.Angles(0, 0, math.rad(90))
	return part
end

--[[
	Laska cukrowa: słupek z naprzemiennych kolorowych pierścieni, z kulką
	na czubku. `base` to środek PODSTAWY. Zwraca CFrame czubka.
]]
function Build.candyCane(
	parent: Instance,
	base: CFrame,
	diameter: number,
	height: number,
	first: Color3,
	second: Color3,
	solid: boolean?
): CFrame
	local bands = math.max(2, math.floor(height / (diameter * 2.2) + 0.5))
	local step = height / bands

	for index = 1, bands do
		Build.upright(parent, base * CFrame.new(0, (index - 0.5) * step, 0), diameter, step, {
			Name = "CaneBand",
			Color = if index % 2 == 0 then second else first,
			CanCollide = solid == true,
		})
	end

	local top = base * CFrame.new(0, height, 0)
	Build.sphere(parent, {
		Name = "CaneCap",
		Size = Vector3.one * diameter * 1.5,
		CFrame = top,
		Color = first,
	})
	return top
end

--[[
	„Pigułka": prostopadłościan z zaokrąglonymi końcami — lada, szyld, deska.
	Długość biegnie wzdłuż lokalnego X, a końce zaokrągla walec o osi
	`axis` ("Y" = widok z góry jest owalny, "Z" = owalny jest przód).
	Zwraca środkowy blok (to on niesie kolizję i ewentualny napis).
]]
function Build.pill(
	parent: Instance,
	center: CFrame,
	size: Vector3,
	axis: "Y" | "Z",
	props: { [string]: any }
): Part
	local round = if axis == "Y" then size.Z else size.Y
	local body = Build.block(parent, props)
	body.Size = Vector3.new(math.max(size.X - round, 0.05), size.Y, size.Z)
	body.CFrame = center

	for _, side in { -1, 1 } do
		local cap = Build.block(parent, props)
		cap.Name = `{body.Name}Cap`
		cap.Shape = Enum.PartType.Cylinder
		local offset = center * CFrame.new(side * (size.X - round) / 2, 0, 0)
		if axis == "Y" then
			cap.Size = Vector3.new(size.Y, round, round)
			cap.CFrame = offset * CFrame.Angles(0, 0, math.rad(90))
		else
			cap.Size = Vector3.new(size.Z, round, round)
			cap.CFrame = offset * CFrame.Angles(0, math.rad(90), 0)
		end
	end

	return body
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
	gui.Brightness = 1.2
	gui.Parent = board

	-- Napis jak naklejka: kolor stoiska, gruby granatowy obrys.
	local function outlined(label: TextLabel, thickness: number)
		local stroke = Instance.new("UIStroke")
		stroke.Color = Build.COLOR.ink
		stroke.Thickness = thickness
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = label
	end

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.fromScale(0.94, 0.58)
	titleLabel.Position = UDim2.fromScale(0.03, 0.04)
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = SIGN_FONT
	titleLabel.Text = title
	titleLabel.TextColor3 = accent
	titleLabel.TextScaled = true
	titleLabel.Parent = gui
	outlined(titleLabel, 5)

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Size = UDim2.fromScale(0.94, 0.28)
	subtitleLabel.Position = UDim2.fromScale(0.03, 0.66)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.FontFace = SIGN_FONT
	subtitleLabel.Text = subtitle
	subtitleLabel.TextColor3 = Build.COLOR.ink
	subtitleLabel.TextScaled = true
	subtitleLabel.Parent = gui
end

return table.freeze(Build)
