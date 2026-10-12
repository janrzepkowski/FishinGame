--!strict
--[[
	Market — plac startowy, spawn i dwa stoiska: skup ryb i sklep wędkarski.

	=========================================================================
	STYL
	=========================================================================
	Plac jest okrągły, a stoiska to „babeczki": okrągły podest, słupki
	z lasek cukrowych, kopuła z falbanką lukru i wielka ozdoba na czubku
	(ryba nad skupem, spławik nad sklepem). Ozdoba jest punktem
	orientacyjnym — dziecko trafia do skupu po rybie na dachu, zanim nauczy
	się czytać szyld.

	Żadnych ostrych krawędzi: wszystko to walce, kule, elipsoidy i „pigułki"
	z `Build`. Kolory z `Build.COLOR`.

	=========================================================================
	SKALA
	=========================================================================
	Wszystkie wymiary są liczone w METRACH przez `Build.m()` i dopiero potem
	przeliczane na study. Punktem odniesienia jest postać gracza: R15 ma
	5,5 studa, co traktujemy jako 1,8 m człowieka. Blat na 1,05 m, prześwit
	pod daszkiem 3,3 m.

	=========================================================================
	UKŁAD LOKALNY
	=========================================================================
	Każde stoisko budujemy względem `CFrame.lookAt(pozycja, skądIdzieGracz)`.
	Lokalne -Z to zawsze przód i pokrywa się z `Enum.NormalId.Front`, więc
	szyld na pewno patrzy na gracza.

	Uwaga przy czytaniu offsetów: lokalne -Z mapuje się na świat +Z, więc
	`base * CFrame.new(0, 0, -4)` to cztery study W STRONĘ PLACU.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FishModel = require(ReplicatedStorage.Shared.Util.FishModel)
local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local Rods = require(ReplicatedStorage.Shared.Config.Rods)

local Build = require(script.Parent.Build)
local Npc = require(script.Parent.Npc)

local Market = {}

local m = Build.m
local C = Build.COLOR

-- ---------------------------------------------------------------------------
-- Wymiary (metry -> study)
-- ---------------------------------------------------------------------------

local WIDTH = m(5.2)
local DEPTH = m(3.4)
local DECK = m(0.14)
-- Podest jest kołem opisanym na prostokącie stoiska.
local DECK_RADIUS = m(3.3)
-- Blat na 1,05 m: to wysokość lady, czyli funkcja człowieka, nie budynku.
local COUNTER_TOP = m(1.05)
local COUNTER_DEPTH = m(0.7)
local EAVES = m(3.3)
local ROOF_RADIUS = DECK_RADIUS + m(0.4)
local DOME_RISE = m(1.5)
local POST = m(0.3)

--[[
	O ile płaski wzór (krążek na posadzce) wystaje ponad powierzchnię, na
	której leży — i zarazem jego grubość. Poniżej ok. 0,05 studa dwie
	powierzchnie z daleka migoczą (z-fighting): bufor głębi nie umie już
	rozstrzygnąć, która jest bliżej. Wzór leży NA powierzchni, nigdy w niej.
]]
local DECAL_LIFT = 0.08

local PLAZA_CENTER = Vector3.new(0, 0, 14)
local PLAZA_RADIUS = 31
local SPAWN_POSITION = Vector3.new(0, 0.55, 24)
local FISH_BUYER_POSITION = Vector3.new(-17, 0, -4)
local ROD_SHOP_POSITION = Vector3.new(17, 0, -4)

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

--[[ Latarnia-lizak: laska cukrowa ze świecącą kulą. ]]
local function buildLamp(parent: Instance, position: Vector3, color: Color3)
	local top = Build.candyCane(parent, CFrame.new(position), 0.7, 9, C.white, color, true)

	local globe = Build.sphere(parent, {
		Name = "LampGlobe",
		Size = Vector3.one * 2.4,
		CFrame = top * CFrame.new(0, 1, 0),
		Color = C.vanilla,
		Material = Enum.Material.Neon,
	})

	local light = Instance.new("PointLight")
	light.Brightness = 1.2
	light.Range = 26
	light.Color = Color3.fromRGB(255, 232, 190)
	-- Cienie z latarni nic nie wnoszą, a kosztują na telefonach.
	light.Shadows = false
	light.Parent = globe
end

local function buildPlaza(parent: Instance)
	local plaza = Build.model(parent, "Plaza")
	local floorTop = 0.4

	-- Okrągły plac: kremowy krążek z różową obwódką.
	Build.upright(
		plaza,
		CFrame.new(PLAZA_CENTER + Vector3.new(0, 0.1, 0)),
		PLAZA_RADIUS * 2 + 4,
		0.2,
		{
			Name = "Rim",
			Color = C.pink,
			CanCollide = true,
		}
	)
	Build.upright(
		plaza,
		CFrame.new(PLAZA_CENTER + Vector3.new(0, 0.2, 0)),
		PLAZA_RADIUS * 2,
		floorTop,
		{
			Name = "Floor",
			Color = C.cream,
			CanCollide = true,
		}
	)

	-- Pastelowe „guziki" na posadzce. Płaskie i bez kolizji: to wzór,
	-- a nie próg, o który można się potknąć.
	local dots = { C.peach, C.mint, C.lilac, C.sky, C.vanilla, C.pink }
	for index = 1, 12 do
		local angle = (index - 1) / 12 * math.pi * 2
		Build.upright(
			plaza,
			CFrame.new(
				PLAZA_CENTER
					+ Vector3.new(
						math.cos(angle) * (PLAZA_RADIUS - 5),
						floorTop + DECAL_LIFT / 2,
						math.sin(angle) * (PLAZA_RADIUS - 5)
					)
			),
			5,
			DECAL_LIFT,
			{ Name = "FloorDot", Color = dots[(index - 1) % #dots + 1], CastShadow = false }
		)
	end

	-- Ścieżka z placu na pomost: pas z okrągłymi „cukierkami" na przemian.
	--
	-- Ścieżka zaczyna się POD krawędzią placu i kończy pod pierwszym stopniem
	-- pomostu, a „cukierki" leżą tylko na odcinku, na którym ścieżkę widać.
	-- Wcześniej krążki wchodziły pod posadzkę placu i na stopnie pomostu:
	-- dwie powierzchnie na prawie tej samej wysokości migotały, walcząc
	-- o piksele (z-fighting).
	local pathTop = 0.3
	Build.block(plaza, {
		Name = "Path",
		Size = Vector3.new(10, pathTop, 14),
		Position = Vector3.new(0, pathTop / 2, -22),
		Color = C.vanilla,
		CanCollide = true,
	})
	for index, z in { -19.6, -24.4 } do
		Build.upright(plaza, CFrame.new(0, pathTop + DECAL_LIFT / 2, z), 4.4, DECAL_LIFT, {
			Name = "PathDot",
			Color = if index % 2 == 0 then C.peach else C.pink,
			CastShadow = false,
		})
	end

	-- Latarnie dookoła placu, z przerwą na ścieżkę do jeziora.
	local lampColors = { C.rose, C.sky, C.grape, C.orange, C.mint, C.rose, C.sky }
	for index, color in lampColors do
		local angle = math.rad(-20 + (index - 1) * (220 / (#lampColors - 1)))
		buildLamp(
			plaza,
			PLAZA_CENTER
				+ Vector3.new(
					math.cos(angle) * (PLAZA_RADIUS + 0.5),
					0.2,
					math.sin(angle) * (PLAZA_RADIUS + 0.5)
				),
			color
		)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(12, 0.6, 12)
	spawn.Position = SPAWN_POSITION
	spawn.Anchored = true
	spawn.CanCollide = true
	-- Sam spawn jest niewidzialną płytą; widać gwiazdę z krążków nad nim.
	-- Kwadratowa płyta gryzłaby się z okrągłym placem.
	spawn.Transparency = 1
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	-- Zero sekund tarczy: gracz nie ma z kim walczyć, a świecąca kula wokół
	-- postaci zasłaniałaby mu spławik przy pierwszym rzucie.
	spawn.Duration = 0
	spawn.Parent = plaza

	local ringColors = { C.sky, C.white, C.lemon }
	for index, diameter in { 13, 10, 7 } do
		-- Każdy krążek o pełne `DECAL_LIFT` wyżej od poprzedniego.
		Build.upright(
			plaza,
			CFrame.new(SPAWN_POSITION.X, floorTop + DECAL_LIFT * (index - 0.5), SPAWN_POSITION.Z),
			diameter,
			DECAL_LIFT,
			{ Name = "SpawnRing", Color = ringColors[index], CastShadow = false }
		)
	end
end

-- ---------------------------------------------------------------------------
-- Elementy konstrukcyjne stoiska
-- ---------------------------------------------------------------------------

local function buildFrame(model: Model, base: CFrame, style: StallStyle)
	Build.upright(model, base * CFrame.new(0, DECK / 2, 0), DECK_RADIUS * 2, DECK, {
		Name = "Deck",
		Color = C.cream,
		CanCollide = true,
	})
	-- Kolorowa obwódka podestu, odrobinę szersza i niższa.
	Build.upright(model, base * CFrame.new(0, DECK / 4, 0), DECK_RADIUS * 2 + m(0.3), DECK / 2, {
		Name = "DeckRim",
		Color = style.accent,
	})

	-- Cztery laski cukrowe niosące daszek.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Build.candyCane(
				model,
				base * CFrame.new(sx * (WIDTH / 2 - POST), DECK, sz * (DEPTH / 2 - POST / 2)),
				POST,
				EAVES - DECK,
				C.white,
				style.accent,
				true
			)
		end
	end
end

--[[
	Tylna ścianka w kształcie łuku: prostokąt z półkolem na górze.
	Zamyka stoisko od tyłu i jest tłem dla towaru, ale boki zostają otwarte —
	widać sprzedawcę z każdej strony placu.
]]
local function buildBackdrop(model: Model, base: CFrame, style: StallStyle)
	local width = WIDTH * 0.72
	local wallZ = DEPTH / 2 - m(0.1)
	local straight = EAVES - DECK - width / 2 - m(0.2)

	Build.block(model, {
		Name = "Backdrop",
		Size = Vector3.new(width, straight, m(0.14)),
		CFrame = base * CFrame.new(0, DECK + straight / 2, wallZ),
		Color = style.stripe,
		CanCollide = true,
	})
	Build.cylinder(model, {
		Name = "BackdropArch",
		Size = Vector3.new(m(0.14), width, width),
		CFrame = base * CFrame.new(0, DECK + straight, wallZ) * CFrame.Angles(0, math.rad(90), 0),
		Color = style.stripe,
	})
end

--[[
	Daszek-babeczka: płaski krążek, falbanka z kulek „lukru" na krawędzi,
	kopuła w kolorze stoiska i biała czapa śmietany.

	Zwraca CFrame czubka kopuły — tam staje ozdoba stoiska.
]]
local function buildRoof(model: Model, base: CFrame, style: StallStyle): CFrame
	Build.upright(model, base * CFrame.new(0, EAVES, 0), ROOF_RADIUS * 2, m(0.2), {
		Name = "RoofBrim",
		Color = C.white,
		CanCollide = true,
	})

	local drips = 18
	for index = 1, drips do
		local angle = (index - 1) / drips * math.pi * 2
		Build.sphere(model, {
			Name = "Frosting",
			-- Co druga kulka większa: falbanka, a nie sznur pereł.
			Size = Vector3.one * (if index % 2 == 0 then m(0.8) else m(0.6)),
			CFrame = base * CFrame.new(
				math.cos(angle) * ROOF_RADIUS,
				EAVES - m(0.08),
				math.sin(angle) * ROOF_RADIUS
			),
			Color = C.white,
			CastShadow = false,
		})
	end

	-- Środek kopuły jest NAD okapem: spód elipsoidy nie może zwisać
	-- sprzedawcy nad głową.
	local domeCenter = base * CFrame.new(0, EAVES + m(1.0), 0)
	Build.ellipsoid(model, {
		Name = "RoofDome",
		Size = Vector3.new(ROOF_RADIUS * 1.9, DOME_RISE * 2, ROOF_RADIUS * 1.9),
		CFrame = domeCenter,
		Color = style.accent,
	})
	Build.ellipsoid(model, {
		Name = "RoofCream",
		Size = Vector3.new(ROOF_RADIUS * 1.1, DOME_RISE * 1.2, ROOF_RADIUS * 1.1),
		CFrame = domeCenter * CFrame.new(0, DOME_RISE * 0.52, 0),
		Color = C.white,
	})

	-- Posypka: kolorowe kuleczki rozsiane po kopule.
	local sprinkles = { C.rose, C.lemon, C.sky, C.grape, C.mint, C.orange }
	for index = 1, 14 do
		local angle = index * 2.4
		local ring = if index % 2 == 0 then 0.78 else 0.6
		local height = DOME_RISE * math.sqrt(1 - ring * ring)
		Build.sphere(model, {
			Name = "Sprinkle",
			Size = Vector3.one * m(0.26),
			CFrame = domeCenter * CFrame.new(
				math.cos(angle) * ROOF_RADIUS * 0.95 * ring,
				height,
				math.sin(angle) * ROOF_RADIUS * 0.95 * ring
			),
			Color = sprinkles[(index - 1) % #sprinkles + 1],
			CastShadow = false,
		})
	end

	return domeCenter * CFrame.new(0, DOME_RISE * 1.1, 0)
end

local function buildCounter(model: Model, base: CFrame, style: StallStyle): BasePart
	local frontZ = -DEPTH / 2 + COUNTER_DEPTH / 2
	local length = WIDTH - m(0.9)
	local height = COUNTER_TOP - DECK

	-- Lada — to w nią gracz „wchodzi" i przy niej stoi ProximityPrompt,
	-- więc zwracamy ją jako punkt zaczepienia dla ShopService.
	local counter = Build.pill(
		model,
		base * CFrame.new(0, DECK + height / 2, frontZ),
		Vector3.new(length, height, COUNTER_DEPTH),
		"Y",
		{ Name = "Counter", Color = style.accent, CanCollide = true }
	)

	-- Biały pas w połowie wysokości — jak wstążka na pudełku.
	Build.pill(
		model,
		base * CFrame.new(0, DECK + height * 0.5, frontZ),
		Vector3.new(length + m(0.06), height * 0.22, COUNTER_DEPTH + m(0.06)),
		"Y",
		{ Name = "CounterBand", Color = C.white }
	)

	Build.pill(
		model,
		base * CFrame.new(0, COUNTER_TOP + m(0.05), frontZ),
		Vector3.new(length + m(0.3), m(0.12), COUNTER_DEPTH + m(0.3)),
		"Y",
		{ Name = "CounterTop", Color = C.cream, CanCollide = true }
	)

	return counter
end

--[[ Szyld-naklejka: biała pigułka z granatowym obrysem na przedniej
     krawędzi daszku. ]]
local function buildSign(model: Model, base: CFrame, style: StallStyle)
	local size = Vector3.new(m(3.5), m(0.9), m(0.14))
	-- Szyld stoi NA okapie, nie wisi pod nim: podwieszony zasłaniał
	-- sprzedawcę każdemu, kto podchodził od placu.
	local center = base * CFrame.new(0, EAVES + m(0.75), -(ROOF_RADIUS - m(0.2)))

	-- Obrys to ta sama pigułka, odrobinę większa i cofnięta.
	Build.pill(
		model,
		center * CFrame.new(0, 0, m(0.04)),
		size + Vector3.new(m(0.2), m(0.2), 0),
		"Z",
		{ Name = "SignOutline", Color = C.ink }
	)
	local board = Build.pill(model, center, size, "Z", { Name = "Sign", Color = C.white })

	for _, sx in { -1, 1 } do
		Build.upright(model, center * CFrame.new(sx * m(1.2), -m(0.55), 0), m(0.14), m(0.4), {
			Name = "SignLeg",
			Color = C.ink,
		})
	end

	Build.signFace(board, Enum.NormalId.Front, style.title, style.subtitle, style.accent)
end

local function buildLighting(model: Model, base: CFrame)
	for _, sx in { -1, 1 } do
		local lamp = Build.sphere(model, {
			Name = "Lamp",
			Size = Vector3.one * m(0.4),
			CFrame = base * CFrame.new(sx * m(1.9), EAVES - m(0.35), -m(0.9)),
			Color = C.vanilla,
			Material = Enum.Material.Neon,
		})

		local light = Instance.new("PointLight")
		light.Brightness = 1
		light.Range = 20
		light.Color = Color3.fromRGB(255, 232, 190)
		-- Cienie z lampki stoiska nic nie wnoszą, a kosztują na mobile.
		light.Shadows = false
		light.Parent = lamp
	end
end

--[[ Pęk balonów przywiązany przy stoisku. ]]
local function buildBalloons(model: Model, anchor: CFrame, colors: { Color3 })
	for index, color in colors do
		local lean = (index - (#colors + 1) / 2) * 0.22
		local length = m(2.6) + index * m(0.35)
		local string = anchor * CFrame.Angles(0, 0, -lean)

		Build.upright(model, string * CFrame.new(0, length / 2, 0), m(0.04), length, {
			Name = "BalloonString",
			Color = C.white,
			CastShadow = false,
		})
		Build.ellipsoid(model, {
			Name = "Balloon",
			Size = Vector3.new(m(0.85), m(1.05), m(0.85)),
			CFrame = string * CFrame.new(0, length + m(0.45), 0),
			Color = color,
		})
	end
end

-- ---------------------------------------------------------------------------
-- Rekwizyty
-- ---------------------------------------------------------------------------

local function buildBarrel(model: Model, cframe: CFrame, color: Color3)
	Build.upright(model, cframe, m(0.7), m(0.9), {
		Name = "Barrel",
		Color = color,
		CanCollide = true,
	})
	for _, offset in { -0.28, 0.28 } do
		Build.upright(model, cframe * CFrame.new(0, offset * m(0.9), 0), m(0.76), m(0.1), {
			Name = "BarrelHoop",
			Color = C.white,
		})
	end
end

local function buildFishBuyerProps(model: Model, base: CFrame, top: CFrame)
	local frontZ = -DEPTH / 2 + COUNTER_DEPTH / 2

	-- Tacka z lodem i ryby na niej — od razu widać, co to za stoisko.
	-- To TE SAME modele, które gracz wyciąga z jeziora.
	Build.pill(
		model,
		base * CFrame.new(0, COUNTER_TOP + m(0.14), frontZ),
		Vector3.new(WIDTH - m(1.8), m(0.1), COUNTER_DEPTH * 0.8),
		"Y",
		{ Name = "Ice", Color = Color3.fromRGB(214, 244, 255) }
	)

	local display = { "carp", "perch", "salmon", "roach", "pike" }
	for index, fishId in display do
		local fish = FishModel.build(fishId, 0.42)
		fish.Name = "DisplayFish"
		-- Ryba leży na boku, lekko skręcona — jak rzucona na lód.
		fish:PivotTo(
			base
				* CFrame.new(m(-1.5 + (index - 1) * 0.75), COUNTER_TOP + m(0.3), frontZ)
				* CFrame.Angles(0, math.rad(60 + index * 23), math.rad(90))
		)
		fish.Parent = model
	end

	-- Wielka ryba na dachu: znak rozpoznawczy skupu.
	local mascot = FishModel.build("carp", 2.3)
	mascot.Name = "RoofFish"
	mascot:PivotTo(top * CFrame.new(0, m(0.75), 0) * CFrame.Angles(0, math.rad(-70), 0))
	mascot.Parent = model

	buildBarrel(
		model,
		base * CFrame.new(WIDTH / 2 - m(0.4), DECK + m(0.45), DEPTH / 2 - m(0.3)),
		C.aqua
	)
	buildBarrel(
		model,
		base * CFrame.new(-WIDTH / 2 + m(0.4), DECK + m(0.45), DEPTH / 2 - m(0.3)),
		C.sky
	)
end

local function buildRodShopProps(model: Model, base: CFrame, top: CFrame)
	local wallZ = DEPTH / 2 - m(0.28)

	-- Wędki z katalogu wystawione na tylnej ściance, w swoich kolorach.
	for index, definition in Rods.all() do
		local x = m(-1.2 + (index - 1) * 0.8)
		local length = m(2.0)

		Build.upright(
			model,
			base * CFrame.new(x, DECK + m(0.3) + length / 2, wallZ),
			m(0.09),
			length,
			{
				Name = "DisplayRod",
				Color = definition.color,
			}
		)
		Build.sphere(model, {
			Name = "DisplayReel",
			Size = Vector3.one * m(0.24),
			CFrame = base * CFrame.new(x, DECK + m(0.75), wallZ - m(0.1)),
			Color = C.white,
		})
	end

	-- Wielki spławik na dachu: znak rozpoznawczy sklepu.
	local float = top * CFrame.new(0, m(0.7), 0)
	Build.sphere(model, {
		Name = "RoofFloatTop",
		Size = Vector3.one * m(1.5),
		CFrame = float,
		Color = C.cherry,
	})
	Build.upright(model, float * CFrame.new(0, -m(0.1), 0), m(1.54), m(0.36), {
		Name = "RoofFloatBand",
		Color = C.white,
	})
	Build.upright(model, float * CFrame.new(0, m(1.05), 0), m(0.12), m(0.9), {
		Name = "RoofFloatAntenna",
		Color = C.lemon,
	})

	buildBarrel(
		model,
		base * CFrame.new(WIDTH / 2 - m(0.4), DECK + m(0.45), DEPTH / 2 - m(0.3)),
		C.orange
	)
	buildBarrel(
		model,
		base * CFrame.new(-WIDTH / 2 + m(0.4), DECK + m(0.45), DEPTH / 2 - m(0.3)),
		C.lemon
	)
end

-- ---------------------------------------------------------------------------

local function buildStall(
	parent: Instance,
	position: Vector3,
	style: StallStyle,
	props: (Model, CFrame, CFrame) -> ()
): BasePart
	-- Gracz przychodzi od placu, czyli od +Z. `lookAt` ustawia lokalne -Z
	-- (czyli Enum.NormalId.Front) dokładnie w jego stronę.
	local base = CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
		-- Stoisko stoi NA placu, nie w nim.
		* CFrame.new(0, 0.4, 0)

	local model = Build.model(parent, style.title)

	buildFrame(model, base, style)
	buildBackdrop(model, base, style)
	local top = buildRoof(model, base, style)
	buildSign(model, base, style)
	buildLighting(model, base)

	local counter = buildCounter(model, base, style)
	props(model, base, top)

	for _, sx in { -1, 1 } do
		buildBalloons(
			model,
			base * CFrame.new(sx * (WIDTH / 2 + m(0.5)), DECK + m(0.9), -DEPTH / 2 + m(0.2)),
			if sx < 0 then { C.rose, C.lemon, C.sky } else { C.mint, C.grape, C.orange }
		)
	end

	-- Sprzedawca stoi na podłodze stoiska, tuż za ladą, przodem do klienta.
	Npc.spawn(
		model,
		base * CFrame.new(0, DECK, -DEPTH / 2 + COUNTER_DEPTH + m(0.75)),
		style.standKind
	)

	counter:SetAttribute(GameConfig.STAND_ATTRIBUTE, style.standKind)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = style.promptAction
	prompt.ObjectText = style.title
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 12
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	-- Własny wygląd podpowiedzi rysuje klient (`UI/PromptBubble`).
	prompt.Style = Enum.ProximityPromptStyle.Custom
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
		accent = C.aqua,
		stripe = C.sky,
		title = "Skup ryb",
		subtitle = "Sprzedaj cały połów",
		promptAction = "Sprzedaj ryby",
		standKind = GameConfig.STAND_FISH_BUYER,
	}, buildFishBuyerProps)

	local rodShop = buildStall(market, ROD_SHOP_POSITION, {
		accent = C.orange,
		stripe = C.vanilla,
		title = "Sklep wędkarski",
		subtitle = "Lepsza wędka = rzadsze ryby",
		promptAction = "Otwórz sklep",
		standKind = GameConfig.STAND_ROD_SHOP,
	}, buildRodShopProps)

	return { fishBuyer = fishBuyer, rodShop = rodShop }
end

return table.freeze(Market)
