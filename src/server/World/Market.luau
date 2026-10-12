--!strict
--[[
	Market — plac startowy, spawn i dwa stoiska: skup ryb i sklep wędkarski.

	=========================================================================
	SKALA
	=========================================================================
	Wszystkie wymiary są liczone w METRACH przez `Build.m()` i dopiero potem
	przeliczane na study. Punktem odniesienia jest postać gracza: R15 ma
	5,5 studa, co traktujemy jako 1,8 m człowieka.

	Dzięki temu proporcje są z definicji „ludzkie": blat na 1,05 m, prześwit
	pod okapem 2,3 m, kalenica na 3,3 m. Budynek dobrany na oko w widoku
	z góry wygląda karłowato w sekundzie, w której stanie obok niego gracz.

	=========================================================================
	UKŁAD LOKALNY
	=========================================================================
	Każde stoisko budujemy względem `CFrame.lookAt(pozycja, skądIdzieGracz)`.
	Lokalne -Z to zawsze przód i pokrywa się z `Enum.NormalId.Front`, więc
	szyld na pewno patrzy na gracza. Przy ręcznym obracaniu części prędzej
	czy później jeden wyląduje tyłem i nikt tego nie zauważy do premiery.

	Uwaga przy czytaniu offsetów: lokalne -Z mapuje się na świat +Z, więc
	`base * CFrame.new(0, 0, -4)` to cztery study W STRONĘ PLACU.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fish = require(ReplicatedStorage.Shared.Config.Fish)
local FishModel = require(ReplicatedStorage.Shared.Util.FishModel)
local GameConfig = require(ReplicatedStorage.Shared.Config.Game)

local Build = require(script.Parent.Build)

local Market = {}

local m = Build.m

-- ---------------------------------------------------------------------------
-- Wymiary (metry -> study)
-- ---------------------------------------------------------------------------

local WIDTH = m(5.2)
local DEPTH = m(3.4)
local DECK = m(0.12)
local COUNTER_TOP = m(1.05)
local COUNTER_DEPTH = m(0.62)
-- Okap na 3,3 m i kalenica na 4,9 m. Gracz ma 1,8 m, więc pod okapem jest
-- półtora metra zapasu, a szczyt dachu sięga prawie trzech wzrostów.
-- To już nie jest stragan, tylko budka targowa — i tak ma wyglądać.
--
-- Blat ZOSTAJE na 1,05 m: to wysokość lady, czyli funkcja człowieka,
-- a nie budynku. Podnoszenie go razem z dachem zrobiłoby ladę pod brodę.
local EAVES = m(3.3)
local RIDGE = m(4.9)
local OVERHANG = m(0.55)
local POST = m(0.16)
local PLANK = m(0.2)

local PLAZA_CENTER = Vector3.new(0, 0, 18)
local SPAWN_POSITION = Vector3.new(0, 0.55, 24)
local FISH_BUYER_POSITION = Vector3.new(-17, 0, -4)
local ROD_SHOP_POSITION = Vector3.new(17, 0, -4)

-- Paleta CUKIERKOWA: kremowy plac, ciepłe „drewno" jak z klocków, białe
-- wykończenia. Dachy biorą kolor ze stylu stoiska, więc z daleka widać,
-- które jest które, zanim da się przeczytać szyld.
local STONE = Color3.fromRGB(255, 238, 206)
local STONE_DARK = Color3.fromRGB(255, 214, 160)
local WOOD = Color3.fromRGB(255, 200, 140)
local WOOD_DARK = Color3.fromRGB(240, 166, 108)
local WOOD_BEAM = Color3.fromRGB(214, 128, 88)
local TRIM = Color3.fromRGB(255, 255, 255)
local PARTY = {
	Color3.fromRGB(255, 92, 120),
	Color3.fromRGB(255, 202, 40),
	Color3.fromRGB(76, 214, 98),
	Color3.fromRGB(66, 164, 255),
	Color3.fromRGB(156, 100, 255),
}

export type StallStyle = {
	accent: Color3,
	stripe: Color3,
	title: string,
	subtitle: string,
	promptAction: string,
	standKind: string,
}

-- ---------------------------------------------------------------------------
-- Plac i ścieżki
-- ---------------------------------------------------------------------------

local function buildPlaza(parent: Instance)
	local plaza = Build.model(parent, "Plaza")

	Build.block(plaza, {
		Name = "Floor",
		Size = Vector3.new(58, 0.4, 34),
		Position = PLAZA_CENTER + Vector3.new(0, 0.2, 0),
		Color = STONE,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
	})

	-- Ścieżka z placu na pomost. Prowadzi gracza bez tutoriala: widać,
	-- dokąd iść, zanim przeczyta jakikolwiek napis.
	Build.block(plaza, {
		Name = "Path",
		Size = Vector3.new(9, 0.3, 36),
		Position = Vector3.new(0, 0.15, -16),
		Color = STONE_DARK,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
	})

	-- Okrągły dywan pod spawnem. Koło zamiast kwadratu: w cukierkowym
	-- świecie nic nie ma ostrych rogów, a okrąg czyta się jako „start".
	Build.cylinder(plaza, {
		Name = "Rug",
		Size = Vector3.new(0.1, 22, 22),
		CFrame = CFrame.new(SPAWN_POSITION.X, 0.42, SPAWN_POSITION.Z)
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 176, 206),
	})
	Build.cylinder(plaza, {
		Name = "RugRing",
		Size = Vector3.new(0.12, 17, 17),
		CFrame = CFrame.new(SPAWN_POSITION.X, 0.43, SPAWN_POSITION.Z)
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 236, 140),
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Shape = Enum.PartType.Cylinder
	spawn.Size = Vector3.new(0.6, 12, 12)
	spawn.CFrame = CFrame.new(SPAWN_POSITION) * CFrame.Angles(0, 0, math.rad(90))
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Color = Color3.fromRGB(120, 226, 200)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	-- Zero sekund tarczy: gracz nie ma z kim walczyć, a świecąca kula wokół
	-- postaci zasłaniałaby mu spławik przy pierwszym rzucie.
	spawn.Duration = 0
	spawn.Parent = plaza
end

-- ---------------------------------------------------------------------------
-- Elementy konstrukcyjne stoiska
-- ---------------------------------------------------------------------------

--[[
	Ściana z PIONOWYCH desek zamiast jednej płyty.

	Jedna płyta w kolorze drewna czyta się jak pudełko. Deski dają pionowy
	rytm i cień między sobą, co jest najtańszym sposobem na „to jest
	zbudowane z czegoś", bez żadnych tekstur ani modeli.
]]
local function plankWall(
	model: Model,
	base: CFrame,
	localZ: number,
	width: number,
	bottom: number,
	top: number,
	color: Color3
)
	local height = top - bottom
	if height <= 0 then
		return
	end

	local count = math.max(1, math.floor(width / PLANK))
	local step = width / count

	for index = 1, count do
		local offsetX = -width / 2 + (index - 0.5) * step
		Build.block(model, {
			Name = "Plank",
			Size = Vector3.new(step - 0.04, height, m(0.05)),
			CFrame = base * CFrame.new(offsetX, bottom + height / 2, localZ),
			-- Lekka wariacja koloru co trzecią deskę. Idealnie równy ton
			-- wygląda jak plastik, nie jak drewno.
			Color = if index % 3 == 0 then WOOD_DARK else color,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = true,
		})
	end
end

local function buildFrame(model: Model, base: CFrame)
	Build.block(model, {
		Name = "Deck",
		Size = Vector3.new(WIDTH + m(0.3), DECK, DEPTH + m(0.3)),
		CFrame = base * CFrame.new(0, DECK / 2, 0),
		Color = WOOD_DARK,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
	})

	-- Cztery słupy nośne od podestu po okap.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Build.block(model, {
				Name = "Post",
				Size = Vector3.new(POST, EAVES, POST),
				CFrame = base * CFrame.new(
					sx * (WIDTH / 2 - POST / 2),
					EAVES / 2,
					sz * (DEPTH / 2 - POST / 2)
				),
				Color = WOOD_BEAM,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = true,
			})

			-- Kulka na szczycie słupa — zabawkowy detal, który zaokrągla
			-- sylwetkę budki na tle nieba.
			Build.sphere(model, {
				Name = "Finial",
				Size = Vector3.one * POST * 2.2,
				CFrame = base * CFrame.new(
					sx * (WIDTH / 2 - POST / 2),
					RIDGE + OVERHANG * 0.2,
					sz * (DEPTH / 2 - POST / 2)
				),
				Color = TRIM,
			})
		end
	end

	-- Oczepy spinające słupy. Bez nich słupy wyglądają jak wbite patyki.
	for _, sz in { -1, 1 } do
		Build.block(model, {
			Name = "Header",
			Size = Vector3.new(WIDTH, m(0.22), m(0.16)),
			CFrame = base * CFrame.new(0, EAVES - m(0.11), sz * (DEPTH / 2 - POST / 2)),
			Color = WOOD_BEAM,
			Material = Enum.Material.SmoothPlastic,
		})
	end
end

local function buildWalls(model: Model, base: CFrame, color: Color3)
	-- Tylna ściana na pełną wysokość.
	plankWall(model, base, DEPTH / 2 - m(0.08), WIDTH, DECK, EAVES, color)

	-- Boki tylko w tylnej części — przód musi zostać otwarty, inaczej
	-- stoisko zamienia się w budkę i nie widać, co jest w środku.
	local sideDepth = DEPTH * 0.55
	local sideZ = DEPTH / 2 - sideDepth / 2

	for _, sx in { -1, 1 } do
		Build.block(model, {
			Name = "SideWall",
			Size = Vector3.new(m(0.06), EAVES - DECK, sideDepth),
			CFrame = base
				* CFrame.new(sx * (WIDTH / 2 - m(0.05)), DECK + (EAVES - DECK) / 2, sideZ),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = true,
		})
	end
end

--[[
	Dach dwuspadowy: kalenica w poprzek szerokości, połacie opadające
	na przód i tył.

	Kąt liczymy z geometrii (`atan2(wzniesienie, wysięg)`), zamiast wpisywać
	stopnie na sztywno. Dzięki temu zmiana RIDGE albo DEPTH nie wymaga
	ponownego dobierania kąta — dach po prostu nadal się domyka.
]]
local function buildRoof(model: Model, base: CFrame, style: StallStyle)
	local run = DEPTH / 2 + OVERHANG
	local rise = RIDGE - EAVES
	local slope = math.sqrt(run * run + rise * rise)
	local angle = math.atan2(rise, run)
	local span = WIDTH + OVERHANG * 2

	for _, sz in { -1, 1 } do
		-- Obrót wokół lokalnego X: dodatni kąt opuszcza lokalne +Z.
		-- Mnożnik `sz` odbija połać na drugą stronę kalenicy.
		local slabCFrame = base
			* CFrame.new(0, (RIDGE + EAVES) / 2, sz * run / 2)
			* CFrame.Angles(sz * angle, 0, 0)

		Build.block(model, {
			Name = "RoofSlab",
			Size = Vector3.new(span, m(0.08), slope),
			CFrame = slabCFrame,
			Color = style.stripe,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = true,
		})

		-- Rytm „gontów": cienkie listwy w poprzek połaci. Buduje się je
		-- w układzie PŁYTY, nie świata — inaczej każdą trzeba by obracać.
		local rows = 5
		for row = 1, rows do
			local along = -slope / 2 + (row - 0.5) * (slope / rows)
			Build.block(model, {
				Name = "RoofBatten",
				Size = Vector3.new(span, m(0.05), m(0.14)),
				CFrame = slabCFrame * CFrame.new(0, m(0.06), along),
				-- Białe pasy na kolorowym dachu: dach jak z lukru.
				Color = TRIM,
				Material = Enum.Material.SmoothPlastic,
			})
		end

		-- Krokwie widoczne spod okapu.
		for _, sx in { -1, 0, 1 } do
			Build.block(model, {
				Name = "Rafter",
				Size = Vector3.new(m(0.1), m(0.12), slope),
				CFrame = slabCFrame * CFrame.new(sx * (WIDTH / 2 - m(0.4)), -m(0.1), 0),
				Color = WOOD_BEAM,
				Material = Enum.Material.SmoothPlastic,
			})
		end
	end

	Build.block(model, {
		Name = "Ridge",
		Size = Vector3.new(span, m(0.16), m(0.18)),
		CFrame = base * CFrame.new(0, RIDGE, 0),
		Color = TRIM,
		Material = Enum.Material.SmoothPlastic,
	})

	-- Szczyty: zamiast klina układamy poziome deski o malejącej długości.
	-- Klin wymagałby zgadywania orientacji, a deski czytają się jak
	-- prawdziwe szalowanie szczytu.
	local levels = 6
	for _, sx in { -1, 1 } do
		for level = 1, levels do
			local t = (level - 0.5) / levels
			local y = EAVES + rise * t
			local length = DEPTH * (1 - t)
			if length > m(0.2) then
				Build.block(model, {
					Name = "GableBoard",
					Size = Vector3.new(m(0.06), rise / levels, length),
					CFrame = base * CFrame.new(sx * (WIDTH / 2 - m(0.04)), y, 0),
					Color = WOOD,
					Material = Enum.Material.SmoothPlastic,
				})
			end
		end
	end
end

local function buildCounter(model: Model, base: CFrame, style: StallStyle): BasePart
	local frontZ = -DEPTH / 2 + COUNTER_DEPTH / 2

	-- Lada — to w nią gracz „wchodzi" i przy niej stoi ProximityPrompt,
	-- więc zwracamy ją jako punkt zaczepienia dla ShopService.
	local counter = Build.block(model, {
		Name = "Counter",
		Size = Vector3.new(WIDTH - POST * 2, COUNTER_TOP - DECK, COUNTER_DEPTH),
		CFrame = base * CFrame.new(0, DECK + (COUNTER_TOP - DECK) / 2, frontZ),
		Color = style.accent,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
	})

	-- Front lady z desek — ta ściana jest najbliżej oczu gracza,
	-- więc to na niej detal zwraca się najbardziej.
	plankWall(
		model,
		base,
		frontZ - COUNTER_DEPTH / 2 - m(0.03),
		WIDTH - POST * 2,
		DECK,
		COUNTER_TOP - m(0.06),
		style.accent
	)

	Build.block(model, {
		Name = "CounterTop",
		Size = Vector3.new(WIDTH - POST, m(0.08), COUNTER_DEPTH + m(0.18)),
		CFrame = base * CFrame.new(0, COUNTER_TOP, frontZ - m(0.04)),
		Color = Color3.fromRGB(216, 198, 168),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
	})

	-- Półka pod blatem: widać ją od strony gracza i wypełnia pustkę
	-- pod ladą, która inaczej wygląda jak dziura.
	Build.block(model, {
		Name = "Shelf",
		Size = Vector3.new(WIDTH - POST * 3, m(0.06), COUNTER_DEPTH * 0.8),
		CFrame = base * CFrame.new(0, COUNTER_TOP * 0.45, frontZ + m(0.1)),
		Color = WOOD_DARK,
		Material = Enum.Material.SmoothPlastic,
	})

	return counter
end

--[[ Szyld podwieszony na dwóch cięgnach pod przednim okapem. ]]
local function buildSign(model: Model, base: CFrame, style: StallStyle)
	local signY = EAVES - m(0.75)
	local signZ = -DEPTH / 2 - m(0.1)

	for _, sx in { -1, 1 } do
		Build.block(model, {
			Name = "SignChain",
			Size = Vector3.new(m(0.04), m(0.5), m(0.04)),
			CFrame = base * CFrame.new(sx * m(1.2), EAVES - m(0.25), signZ),
			Color = Color3.fromRGB(96, 100, 108),
			Material = Enum.Material.SmoothPlastic,
		})
	end

	local board = Build.block(model, {
		Name = "Sign",
		Size = Vector3.new(m(3.2), m(0.78), m(0.1)),
		CFrame = base * CFrame.new(0, signY, signZ),
		-- Biała tablica z kolorowym, obrysowanym napisem — jak przyciski w UI.
		Color = TRIM,
		Material = Enum.Material.SmoothPlastic,
	})

	Build.block(model, {
		Name = "SignTrim",
		Size = Vector3.new(m(3.3), m(0.06), m(0.12)),
		CFrame = base * CFrame.new(0, signY - m(0.4), signZ),
		Color = style.accent,
		Material = Enum.Material.SmoothPlastic,
	})

	Build.signFace(board, Enum.NormalId.Front, style.title, style.subtitle, style.accent)
end

--[[ Pasiasta markiza nad ladą. ]]
local function buildAwning(model: Model, base: CFrame, style: StallStyle)
	local awningCFrame = base
		* CFrame.new(0, EAVES - m(0.45), -DEPTH / 2 - m(0.5))
		* CFrame.Angles(math.rad(-18), 0, 0)

	local stripes = 11
	local stripeWidth = (WIDTH + m(0.3)) / stripes

	for index = 1, stripes do
		local offsetX = -(WIDTH + m(0.3)) / 2 + (index - 0.5) * stripeWidth
		Build.block(model, {
			Name = "AwningStripe",
			Size = Vector3.new(stripeWidth - 0.03, m(0.05), m(1.1)),
			CFrame = awningCFrame * CFrame.new(offsetX, 0, 0),
			Color = if index % 2 == 0 then style.stripe else Color3.fromRGB(240, 238, 232),
			Material = Enum.Material.SmoothPlastic,
		})

		-- Ząbkowana krawędź — detal, który odróżnia markizę od deski.
		Build.block(model, {
			Name = "AwningScallop",
			Size = Vector3.new(stripeWidth - 0.12, m(0.22), m(0.04)),
			CFrame = awningCFrame * CFrame.new(offsetX, -m(0.12), -m(0.55)),
			Color = if index % 2 == 0 then style.stripe else Color3.fromRGB(240, 238, 232),
			Material = Enum.Material.SmoothPlastic,
		})
	end
end

local function buildLighting(model: Model, base: CFrame)
	local lamp = Build.block(model, {
		Name = "Lamp",
		Size = Vector3.new(m(0.3), m(0.16), m(0.3)),
		CFrame = base * CFrame.new(0, EAVES - m(0.18), -m(0.4)),
		Color = Color3.fromRGB(255, 232, 178),
		Material = Enum.Material.Neon,
	})

	local light = Instance.new("PointLight")
	light.Brightness = 1.4
	light.Range = 24
	light.Color = Color3.fromRGB(255, 226, 176)
	-- Cienie z lampki stoiska nic nie wnoszą, a kosztują na mobile.
	light.Shadows = false
	light.Parent = lamp
end

-- ---------------------------------------------------------------------------
-- Rekwizyty
-- ---------------------------------------------------------------------------

local function buildCrate(model: Model, cframe: CFrame, size: number)
	Build.block(model, {
		Name = "Crate",
		Size = Vector3.new(size, size, size),
		CFrame = cframe,
		Color = Color3.fromRGB(158, 118, 76),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
	})

	-- Okucia na krawędziach — bez nich skrzynka jest po prostu sześcianem.
	for _, sy in { -1, 1 } do
		Build.block(model, {
			Name = "CrateBand",
			Size = Vector3.new(size + 0.04, size * 0.12, size + 0.04),
			CFrame = cframe * CFrame.new(0, sy * size * 0.32, 0),
			Color = WOOD_DARK,
			Material = Enum.Material.SmoothPlastic,
		})
	end
end

local function buildBarrel(model: Model, cframe: CFrame)
	-- Walec w Robloxie leży wzdłuż osi X, więc stawiamy go obrotem wokół Z.
	local upright = cframe * CFrame.Angles(0, 0, math.rad(90))

	Build.cylinder(model, {
		Name = "Barrel",
		Size = Vector3.new(m(0.9), m(0.62), m(0.62)),
		CFrame = upright,
		Color = Color3.fromRGB(122, 86, 56),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
	})

	for _, offset in { -0.25, 0.25 } do
		Build.cylinder(model, {
			Name = "BarrelHoop",
			Size = Vector3.new(m(0.06), m(0.66), m(0.66)),
			CFrame = upright * CFrame.new(offset * m(0.9), 0, 0),
			Color = Color3.fromRGB(94, 98, 106),
			Material = Enum.Material.SmoothPlastic,
		})
	end
end

local function buildFishBuyerProps(model: Model, base: CFrame)
	local frontZ = -DEPTH / 2 + COUNTER_DEPTH / 2

	-- Lód na ladzie i ryby na nim — od razu widać, co to za stoisko,
	-- bez czytania szyldu.
	Build.block(model, {
		Name = "Ice",
		Size = Vector3.new(WIDTH - m(1.2), m(0.1), COUNTER_DEPTH * 0.7),
		CFrame = base * CFrame.new(0, COUNTER_TOP + m(0.08), frontZ - m(0.04)),
		Color = Color3.fromRGB(198, 230, 240),
		Material = Enum.Material.Glass,
		Transparency = 0.2,
	})

	-- Na lodzie leżą PRAWDZIWE modele ryb z katalogu — te same, które gracz
	-- zobaczy w ekwipunku. Stoisko od razu pokazuje, co tu się sprzedaje,
	-- i zapowiada gatunki, których jeszcze nie złowił.
	local display = { "carp", "zander", "salmon", "pike", "roach" }

	for index, fishId in display do
		local definition = Fish.find(fishId)
		if not definition then
			continue
		end

		local fish = FishModel.build(definition, { scale = 0.42 })
		fish.Name = "DisplayFish"
		-- Ryba leży na boku (obrót o 90° wokół osi długości), głową do gracza
		-- pod lekkim kątem — jak na prawdziwej ladzie.
		fish:PivotTo(
			base
				* CFrame.new(m(-1.3 + (index - 1) * 0.65), COUNTER_TOP + m(0.2), frontZ - m(0.04))
				* CFrame.Angles(0, math.rad(80 + 14 * index), 0)
				* CFrame.Angles(0, 0, math.rad(90))
		)
		fish.Parent = model
	end

	-- Waga uchylna na końcu lady.
	Build.block(model, {
		Name = "ScalePost",
		Size = Vector3.new(m(0.07), m(0.8), m(0.07)),
		CFrame = base * CFrame.new(m(1.9), COUNTER_TOP + m(0.4), frontZ),
		Color = Color3.fromRGB(96, 100, 108),
		Material = Enum.Material.SmoothPlastic,
	})
	Build.cylinder(model, {
		Name = "ScalePan",
		Size = Vector3.new(m(0.05), m(0.42), m(0.42)),
		CFrame = base
			* CFrame.new(m(1.9), COUNTER_TOP + m(0.08), frontZ)
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(176, 180, 188),
		Material = Enum.Material.SmoothPlastic,
	})

	buildCrate(
		model,
		base * CFrame.new(-WIDTH / 2 + m(0.7), DECK + m(0.3), DEPTH / 2 - m(0.8)),
		m(0.6)
	)
	buildCrate(
		model,
		base * CFrame.new(-WIDTH / 2 + m(0.7), DECK + m(0.9), DEPTH / 2 - m(0.8)),
		m(0.5)
	)
	buildBarrel(model, base * CFrame.new(WIDTH / 2 - m(0.7), DECK + m(0.45), DEPTH / 2 - m(0.8)))
end

local function buildRodShopProps(model: Model, base: CFrame)
	-- Stojak z wędkami na tylnej ścianie.
	for _, y in { EAVES - m(0.5), m(0.6) } do
		Build.block(model, {
			Name = "RackBar",
			Size = Vector3.new(WIDTH - m(1.4), m(0.08), m(0.08)),
			CFrame = base * CFrame.new(0, y, DEPTH / 2 - m(0.25)),
			Color = WOOD_BEAM,
			Material = Enum.Material.SmoothPlastic,
		})
	end

	local rodColors = {
		Color3.fromRGB(141, 102, 60),
		Color3.fromRGB(72, 86, 102),
		Color3.fromRGB(38, 40, 46),
		Color3.fromRGB(196, 158, 72),
	}

	for index, color in rodColors do
		local x = m(-1.4 + (index - 1) * 0.95)

		Build.block(model, {
			Name = "DisplayRod",
			Size = Vector3.new(m(0.05), EAVES - m(0.9), m(0.05)),
			CFrame = base * CFrame.new(x, EAVES / 2 + m(0.1), DEPTH / 2 - m(0.3)),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
		})

		-- Kołowrotek przy każdej wystawionej wędce — ten detal odróżnia
		-- stojak z wędkami od stojaka z patykami.
		Build.cylinder(model, {
			Name = "DisplayReel",
			Size = Vector3.new(m(0.07), m(0.2), m(0.2)),
			CFrame = base * CFrame.new(x, m(1.1), DEPTH / 2 - m(0.38)),
			Color = Color3.fromRGB(196, 200, 208),
			Material = Enum.Material.SmoothPlastic,
		})
	end

	buildCrate(
		model,
		base * CFrame.new(WIDTH / 2 - m(0.7), DECK + m(0.3), DEPTH / 2 - m(0.8)),
		m(0.6)
	)
	buildBarrel(model, base * CFrame.new(-WIDTH / 2 + m(0.7), DECK + m(0.45), DEPTH / 2 - m(0.8)))
end

-- ---------------------------------------------------------------------------
-- Dekoracje placu
-- ---------------------------------------------------------------------------

--[[
	Girlanda chorągiewek między dwoma słupkami.

	Chorągiewki to romby (kwadrat obrócony o 45°) wiszące na zwisającej
	linie. Romb zamiast trójkąta, bo klin w Robloxie trzeba by obracać
	osobno dla każdej flagi, a obrócony kwadrat jest symetryczny i zawsze
	wygląda dobrze.
]]
local function buildBunting(parent: Instance, from: Vector3, to: Vector3, sag: number)
	for _, point in { from, to } do
		Build.post(parent, Vector3.new(point.X, 0, point.Z), point.Y + 0.6, 0.5, {
			Name = "BuntingPole",
			Color = TRIM,
			CanCollide = true,
		})
		Build.sphere(parent, {
			Name = "BuntingTop",
			Size = Vector3.one * 1.1,
			CFrame = CFrame.new(point + Vector3.new(0, 0.9, 0)),
			Color = PARTY[1],
		})
	end

	local flags = math.floor((to - from).Magnitude / 2.4)
	local direction = (to - from).Unit
	local facing = CFrame.lookAt(Vector3.zero, Vector3.new(direction.Z, 0, -direction.X))

	for index = 1, flags do
		local t = (index - 0.5) / flags
		-- Zwis paraboliczny: 4t(1-t) daje 0 przy słupkach i 1 pośrodku.
		local point = from:Lerp(to, t) - Vector3.new(0, sag * 4 * t * (1 - t), 0)
		Build.block(parent, {
			Name = "Flag",
			Size = Vector3.new(1.1, 1.1, 0.08),
			CFrame = CFrame.new(point - Vector3.new(0, 0.55, 0))
				* facing.Rotation
				* CFrame.Angles(0, 0, math.rad(45)),
			Color = PARTY[(index % #PARTY) + 1],
		})
	end
end

--[[ Pęk balonów na sznurkach. Lekko kołyszą się w różne strony,
     więc nie wyglądają jak sklejona kiść winogron. ]]
local function buildBalloons(parent: Instance, anchor: Vector3, seed: number)
	local generator = Random.new(seed)

	for index = 1, 5 do
		local top = anchor
			+ Vector3.new(
				generator:NextNumber(-1.4, 1.4),
				8 + generator:NextNumber(0, 2.5),
				generator:NextNumber(-1.4, 1.4)
			)
		local stringLength = (top - anchor).Magnitude

		Build.block(parent, {
			Name = "BalloonString",
			Size = Vector3.new(0.06, 0.06, stringLength),
			CFrame = CFrame.lookAt(anchor:Lerp(top, 0.5), top),
			Color = TRIM,
		})
		Build.ellipsoid(parent, {
			Name = "Balloon",
			Size = Vector3.new(2, 2.4, 2),
			CFrame = CFrame.new(top + Vector3.new(0, 1.1, 0)),
			Color = PARTY[(index + seed) % #PARTY + 1],
		})
	end

	Build.sphere(parent, {
		Name = "BalloonWeight",
		Size = Vector3.one * 0.8,
		CFrame = CFrame.new(anchor),
		Color = PARTY[2],
		CanCollide = true,
	})
end

local function buildFestive(parent: Instance)
	local festive = Build.model(parent, "Festive")

	-- Dwie girlandy w poprzek placu: z daleka „to jest centrum gry".
	buildBunting(festive, Vector3.new(-26, 11, 6), Vector3.new(26, 11, 6), 2.6)
	buildBunting(festive, Vector3.new(-26, 11, 30), Vector3.new(26, 11, 30), 2.6)

	buildBalloons(festive, Vector3.new(-10, 0.6, 30), 1)
	buildBalloons(festive, Vector3.new(10, 0.6, 30), 3)
end

-- ---------------------------------------------------------------------------

local function buildStall(
	parent: Instance,
	position: Vector3,
	style: StallStyle,
	props: (Model, CFrame) -> ()
): BasePart
	-- Gracz przychodzi od placu, czyli od +Z. `lookAt` ustawia lokalne -Z
	-- (czyli Enum.NormalId.Front) dokładnie w jego stronę.
	local base = CFrame.lookAt(position, position + Vector3.new(0, 0, 1))

	local model = Build.model(parent, style.title)

	buildFrame(model, base)
	buildWalls(model, base, style.accent)
	buildRoof(model, base, style)
	buildAwning(model, base, style)
	buildSign(model, base, style)
	buildLighting(model, base)

	local counter = buildCounter(model, base, style)
	props(model, base)

	counter:SetAttribute(GameConfig.STAND_ATTRIBUTE, style.standKind)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = style.promptAction
	prompt.ObjectText = style.title
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 12
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter

	return counter
end

export type Stands = {
	fishBuyer: BasePart,
	rodShop: BasePart,
}

function Market.build(parent: Instance): Stands
	local market = Build.model(parent, "Market")

	buildPlaza(market)
	buildFestive(market)

	local fishBuyer = buildStall(market, FISH_BUYER_POSITION, {
		accent = Color3.fromRGB(90, 200, 255),
		stripe = Color3.fromRGB(40, 150, 240),
		title = "Skup ryb",
		subtitle = "Sprzedaj cały połów",
		promptAction = "Sprzedaj ryby",
		standKind = GameConfig.STAND_FISH_BUYER,
	}, buildFishBuyerProps)

	local rodShop = buildStall(market, ROD_SHOP_POSITION, {
		accent = Color3.fromRGB(255, 176, 60),
		stripe = Color3.fromRGB(255, 92, 120),
		title = "Sklep wędkarski",
		subtitle = "Lepsza wędka = rzadsze ryby",
		promptAction = "Otwórz sklep",
		standKind = GameConfig.STAND_ROD_SHOP,
	}, buildRodShopProps)

	return { fishBuyer = fishBuyer, rodShop = rodShop }
end

return table.freeze(Market)
