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

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)

local Build = require(script.Parent.Build)

local Market = {}

local m = Build.m

-- ---------------------------------------------------------------------------
-- Wymiary (metry -> study)
-- ---------------------------------------------------------------------------

local WIDTH = m(4.6)
local DEPTH = m(3.0)
local DECK = m(0.12)
local COUNTER_TOP = m(1.05)
local COUNTER_DEPTH = m(0.62)
local EAVES = m(2.35)
local RIDGE = m(3.3)
local OVERHANG = m(0.45)
local POST = m(0.16)
local PLANK = m(0.2)

local PLAZA_CENTER = Vector3.new(0, 0, 18)
local SPAWN_POSITION = Vector3.new(0, 0.55, 24)
local FISH_BUYER_POSITION = Vector3.new(-17, 0, -4)
local ROD_SHOP_POSITION = Vector3.new(17, 0, -4)

local STONE = Color3.fromRGB(138, 141, 148)
local STONE_DARK = Color3.fromRGB(104, 108, 116)
local WOOD = Color3.fromRGB(154, 114, 74)
local WOOD_DARK = Color3.fromRGB(104, 76, 50)
local WOOD_BEAM = Color3.fromRGB(86, 63, 42)
local ROOF = Color3.fromRGB(78, 84, 96)
local ROOF_DARK = Color3.fromRGB(62, 67, 78)

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
		Material = Enum.Material.Cobblestone,
		CanCollide = true,
	})

	-- Ścieżka z placu na pomost. Prowadzi gracza bez tutoriala: widać,
	-- dokąd iść, zanim przeczyta jakikolwiek napis.
	Build.block(plaza, {
		Name = "Path",
		Size = Vector3.new(9, 0.3, 36),
		Position = Vector3.new(0, 0.15, -16),
		Color = STONE_DARK,
		Material = Enum.Material.Cobblestone,
		CanCollide = true,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(12, 0.6, 12)
	spawn.Position = SPAWN_POSITION
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Material = Enum.Material.Marble
	spawn.Color = Color3.fromRGB(196, 201, 209)
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
			Material = Enum.Material.WoodPlanks,
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
		Material = Enum.Material.WoodPlanks,
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
				Material = Enum.Material.Wood,
				CanCollide = true,
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
			Material = Enum.Material.Wood,
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
			Material = Enum.Material.WoodPlanks,
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
local function buildRoof(model: Model, base: CFrame)
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
			Color = ROOF,
			Material = Enum.Material.Slate,
			CanCollide = true,
		})

		-- Rytm „gontów": cienkie listwy w poprzek połaci. Buduje się je
		-- w układzie PŁYTY, nie świata — inaczej każdą trzeba by obracać.
		local rows = 5
		for row = 1, rows do
			local along = -slope / 2 + (row - 0.5) * (slope / rows)
			Build.block(model, {
				Name = "RoofBatten",
				Size = Vector3.new(span, m(0.04), m(0.06)),
				CFrame = slabCFrame * CFrame.new(0, m(0.06), along),
				Color = ROOF_DARK,
				Material = Enum.Material.Slate,
			})
		end

		-- Krokwie widoczne spod okapu.
		for _, sx in { -1, 0, 1 } do
			Build.block(model, {
				Name = "Rafter",
				Size = Vector3.new(m(0.1), m(0.12), slope),
				CFrame = slabCFrame * CFrame.new(sx * (WIDTH / 2 - m(0.4)), -m(0.1), 0),
				Color = WOOD_BEAM,
				Material = Enum.Material.Wood,
			})
		end
	end

	Build.block(model, {
		Name = "Ridge",
		Size = Vector3.new(span, m(0.16), m(0.18)),
		CFrame = base * CFrame.new(0, RIDGE, 0),
		Color = ROOF_DARK,
		Material = Enum.Material.Slate,
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
					Material = Enum.Material.WoodPlanks,
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
		Material = Enum.Material.WoodPlanks,
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
		Material = Enum.Material.Wood,
		CanCollide = true,
	})

	-- Półka pod blatem: widać ją od strony gracza i wypełnia pustkę
	-- pod ladą, która inaczej wygląda jak dziura.
	Build.block(model, {
		Name = "Shelf",
		Size = Vector3.new(WIDTH - POST * 3, m(0.06), COUNTER_DEPTH * 0.8),
		CFrame = base * CFrame.new(0, COUNTER_TOP * 0.45, frontZ + m(0.1)),
		Color = WOOD_DARK,
		Material = Enum.Material.Wood,
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
			Material = Enum.Material.Metal,
		})
	end

	local board = Build.block(model, {
		Name = "Sign",
		Size = Vector3.new(m(3.2), m(0.78), m(0.1)),
		CFrame = base * CFrame.new(0, signY, signZ),
		Color = Color3.fromRGB(38, 42, 52),
		Material = Enum.Material.Wood,
	})

	Build.block(model, {
		Name = "SignTrim",
		Size = Vector3.new(m(3.3), m(0.06), m(0.12)),
		CFrame = base * CFrame.new(0, signY - m(0.4), signZ),
		Color = style.accent,
		Material = Enum.Material.Wood,
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
			Material = Enum.Material.Fabric,
		})

		-- Ząbkowana krawędź — detal, który odróżnia markizę od deski.
		Build.block(model, {
			Name = "AwningScallop",
			Size = Vector3.new(stripeWidth - 0.12, m(0.22), m(0.04)),
			CFrame = awningCFrame * CFrame.new(offsetX, -m(0.12), -m(0.55)),
			Color = if index % 2 == 0 then style.stripe else Color3.fromRGB(240, 238, 232),
			Material = Enum.Material.Fabric,
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
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
	})

	-- Okucia na krawędziach — bez nich skrzynka jest po prostu sześcianem.
	for _, sy in { -1, 1 } do
		Build.block(model, {
			Name = "CrateBand",
			Size = Vector3.new(size + 0.04, size * 0.12, size + 0.04),
			CFrame = cframe * CFrame.new(0, sy * size * 0.32, 0),
			Color = WOOD_DARK,
			Material = Enum.Material.Wood,
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
		Material = Enum.Material.Wood,
		CanCollide = true,
	})

	for _, offset in { -0.25, 0.25 } do
		Build.cylinder(model, {
			Name = "BarrelHoop",
			Size = Vector3.new(m(0.06), m(0.66), m(0.66)),
			CFrame = upright * CFrame.new(offset * m(0.9), 0, 0),
			Color = Color3.fromRGB(94, 98, 106),
			Material = Enum.Material.Metal,
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
		Material = Enum.Material.Ice,
		Transparency = 0.25,
	})

	local display = {
		Color3.fromRGB(176, 128, 72),
		Color3.fromRGB(122, 136, 150),
		Color3.fromRGB(232, 132, 110),
		Color3.fromRGB(88, 124, 96),
		Color3.fromRGB(198, 203, 211),
	}

	for index, color in display do
		Build.sphere(model, {
			Name = "DisplayFish",
			Size = Vector3.new(m(0.52), m(0.19), m(0.15)),
			CFrame = base
				* CFrame.new(m(-1.3 + (index - 1) * 0.65), COUNTER_TOP + m(0.17), frontZ - m(0.04))
				* CFrame.Angles(0, math.rad(14 * index), 0),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
		})
	end

	-- Waga uchylna na końcu lady.
	Build.block(model, {
		Name = "ScalePost",
		Size = Vector3.new(m(0.07), m(0.8), m(0.07)),
		CFrame = base * CFrame.new(m(1.9), COUNTER_TOP + m(0.4), frontZ),
		Color = Color3.fromRGB(96, 100, 108),
		Material = Enum.Material.Metal,
	})
	Build.cylinder(model, {
		Name = "ScalePan",
		Size = Vector3.new(m(0.05), m(0.42), m(0.42)),
		CFrame = base
			* CFrame.new(m(1.9), COUNTER_TOP + m(0.08), frontZ)
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(176, 180, 188),
		Material = Enum.Material.Metal,
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
			Material = Enum.Material.Wood,
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
			Material = Enum.Material.Wood,
		})

		-- Kołowrotek przy każdej wystawionej wędce — ten detal odróżnia
		-- stojak z wędkami od stojaka z patykami.
		Build.cylinder(model, {
			Name = "DisplayReel",
			Size = Vector3.new(m(0.07), m(0.2), m(0.2)),
			CFrame = base * CFrame.new(x, m(1.1), DEPTH / 2 - m(0.38)),
			Color = Color3.fromRGB(196, 200, 208),
			Material = Enum.Material.Metal,
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
	buildRoof(model, base)
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

	local fishBuyer = buildStall(market, FISH_BUYER_POSITION, {
		accent = Color3.fromRGB(86, 164, 128),
		stripe = Color3.fromRGB(58, 132, 102),
		title = "Skup ryb",
		subtitle = "Sprzedaj cały połów",
		promptAction = "Sprzedaj ryby",
		standKind = GameConfig.STAND_FISH_BUYER,
	}, buildFishBuyerProps)

	local rodShop = buildStall(market, ROD_SHOP_POSITION, {
		accent = Color3.fromRGB(206, 152, 74),
		stripe = Color3.fromRGB(188, 124, 54),
		title = "Sklep wędkarski",
		subtitle = "Lepsza wędka = rzadsze ryby",
		promptAction = "Otwórz sklep",
		standKind = GameConfig.STAND_ROD_SHOP,
	}, buildRodShopProps)

	return { fishBuyer = fishBuyer, rodShop = rodShop }
end

return table.freeze(Market)
