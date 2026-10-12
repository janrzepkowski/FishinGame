--!strict
--[[
	Fish — katalog ryb.

	Dodanie gatunku = jeden wpis w `DEFINITIONS`. Nic poza tym plikiem nie
	trzeba ruszać: UI bierze kolor z rzadkości, ekonomia z `pricePerKg`,
	losowanie ze `spawnWeight`, walka z `fight`, a model 3D (ekwipunek,
	bestiariusz, animacja wyciągania) z `color` i `look`.

	KOLORY SĄ CUKIERKOWE, NIE REALISTYCZNE. Gra jest dla dzieci: szary
	sandacz na tle szarej wody to ryba, której nikt nie zapamięta. Każdy
	gatunek ma własny, jaskrawy kolor, żeby dało się go rozpoznać w ułamku
	sekundy, zanim przeczyta się nazwę.

	PROFILE WALKI są dobierane pod CHARAKTER gatunku, nie pod jego wartość.
	Szczupak szarpie gwałtownie i krótko, sum męczy długo bez gwałtownych
	zrywów, a Złota Rybka jest malutka i wściekła. Gdyby trudność szła
	wprost za rzadkością, każda walka byłaby tym samym, tylko dłuższym.
]]

local Types = require(script.Parent.Parent.Types)

type FishDefinition = Types.FishDefinition
type Rarity = Types.Rarity

-- Im wyższy tier, tym mocniej `luck` wędki podbija szansę na dany gatunek.
-- Przy luck = 1.0 rozkład jest dokładnie taki, jak `spawnWeight`.
local RARITY_TIER: { [Rarity]: number } = table.freeze({
	Common = 0,
	Uncommon = 1,
	Rare = 2,
	Epic = 3,
	Legendary = 4,
})

local RARITY_COLOR: { [Rarity]: Color3 } = table.freeze({
	Common = Color3.fromRGB(198, 203, 211),
	Uncommon = Color3.fromRGB(110, 215, 120),
	Rare = Color3.fromRGB(90, 160, 255),
	Epic = Color3.fromRGB(190, 110, 255),
	Legendary = Color3.fromRGB(255, 190, 70),
})

local RARITY_LABEL: { [Rarity]: string } = table.freeze({
	Common = "Pospolita",
	Uncommon = "Niepospolita",
	Rare = "Rzadka",
	Epic = "Epicka",
	Legendary = "Legendarna",
})

-- Kolejność rzadkości od pospolitej do legendarnej — do sortowania
-- bestiariusza i generowania zadań.
-- Rzutowanie na pierwszym elemencie nadaje typ całej tablicy. Bez niego
-- literał dostaje `{string}`, a to nie jest podtyp `{Rarity}` — tablice
-- w Luau są niezmiennicze.
local RARITY_ORDER: { Rarity } = table.freeze({
	"Common" :: Rarity,
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
})

local Fish = {}

Fish.RARITY_TIER = RARITY_TIER
Fish.RARITY_COLOR = RARITY_COLOR
Fish.RARITY_LABEL = RARITY_LABEL
Fish.RARITY_ORDER = RARITY_ORDER

local DEFINITIONS: { FishDefinition } = {
	{
		id = "roach",
		displayName = "Płoć",
		rarity = "Common",
		spawnWeight = 100,
		pricePerKg = 12,
		minMass = 0.1,
		maxMass = 0.6,
		color = Color3.fromRGB(150, 190, 235),
		look = {
			body = "Round",
			pattern = "None",
			accent = Color3.fromRGB(255, 96, 96),
			belly = Color3.fromRGB(236, 246, 255),
		},
		-- Pierwsza ryba, jaką zobaczy nowy gracz. Walka ma nauczyć rytmu,
		-- a nie ukarać — słaba i szybka.
		fight = { strength = 0.55, stamina = 0.5 },
	},
	{
		id = "perch",
		displayName = "Okoń",
		rarity = "Common",
		spawnWeight = 85,
		pricePerKg = 18,
		minMass = 0.2,
		maxMass = 1.4,
		color = Color3.fromRGB(150, 214, 74),
		look = {
			body = "Round",
			pattern = "Stripes",
			accent = Color3.fromRGB(255, 120, 60),
			belly = Color3.fromRGB(250, 248, 200),
		},
		fight = { strength = 0.7, stamina = 0.6 },
	},
	{
		id = "bream",
		displayName = "Leszcz",
		rarity = "Common",
		spawnWeight = 70,
		pricePerKg = 22,
		minMass = 0.5,
		maxMass = 3.2,
		color = Color3.fromRGB(240, 196, 92),
		look = {
			body = "Tall",
			pattern = "None",
			accent = Color3.fromRGB(196, 132, 74),
			belly = Color3.fromRGB(255, 244, 210),
		},
		-- Ospały, ale ciężki: nie szarpie, tylko wisi.
		fight = { strength = 0.6, stamina = 0.85 },
	},
	{
		id = "tench",
		displayName = "Lin",
		rarity = "Uncommon",
		spawnWeight = 42,
		pricePerKg = 34,
		minMass = 0.8,
		maxMass = 4.0,
		color = Color3.fromRGB(96, 196, 120),
		look = {
			body = "Round",
			pattern = "Spots",
			accent = Color3.fromRGB(255, 196, 64),
			belly = Color3.fromRGB(220, 250, 200),
		},
		fight = { strength = 0.8, stamina = 0.95 },
	},
	{
		id = "carp",
		displayName = "Karp",
		rarity = "Uncommon",
		spawnWeight = 34,
		pricePerKg = 46,
		minMass = 1.5,
		maxMass = 14.0,
		color = Color3.fromRGB(255, 150, 60),
		look = {
			body = "Tall",
			pattern = "Spots",
			accent = Color3.fromRGB(255, 226, 120),
			belly = Color3.fromRGB(255, 236, 200),
			whiskers = true,
		},
		-- Klasyczny długi hol.
		fight = { strength = 0.95, stamina = 1.3 },
	},
	{
		id = "pike",
		displayName = "Szczupak",
		rarity = "Uncommon",
		spawnWeight = 28,
		pricePerKg = 58,
		minMass = 1.0,
		maxMass = 11.0,
		color = Color3.fromRGB(72, 186, 140),
		look = {
			body = "Long",
			pattern = "Spots",
			accent = Color3.fromRGB(255, 214, 82),
			belly = Color3.fromRGB(226, 255, 230),
		},
		-- Drapieżnik: gwałtowny i krótki. Pierwsza ryba, która realnie
		-- zrywa żyłkę startowej wędki.
		fight = { strength = 1.35, stamina = 0.85 },
	},
	{
		id = "zander",
		displayName = "Sandacz",
		rarity = "Rare",
		spawnWeight = 14,
		pricePerKg = 95,
		minMass = 1.2,
		maxMass = 9.5,
		color = Color3.fromRGB(120, 150, 230),
		look = {
			body = "Long",
			pattern = "Stripes",
			accent = Color3.fromRGB(80, 230, 255),
			belly = Color3.fromRGB(232, 238, 255),
		},
		fight = { strength = 1.15, stamina = 1.05 },
	},
	{
		id = "catfish",
		displayName = "Sum",
		rarity = "Rare",
		spawnWeight = 10,
		pricePerKg = 120,
		minMass = 4.0,
		maxMass = 48.0,
		color = Color3.fromRGB(126, 104, 200),
		look = {
			body = "Long",
			pattern = "None",
			accent = Color3.fromRGB(255, 150, 200),
			belly = Color3.fromRGB(236, 224, 255),
			whiskers = true,
		},
		-- Maraton: nie szarpie mocno, ale nie chce odpuścić.
		fight = { strength = 1.05, stamina = 1.75 },
	},
	{
		id = "salmon",
		displayName = "Łosoś atlantycki",
		rarity = "Epic",
		spawnWeight = 4.5,
		pricePerKg = 260,
		minMass = 3.0,
		maxMass = 18.0,
		color = Color3.fromRGB(255, 120, 150),
		look = {
			body = "Torpedo",
			pattern = "Spots",
			accent = Color3.fromRGB(255, 220, 90),
			belly = Color3.fromRGB(255, 234, 240),
		},
		fight = { strength = 1.5, stamina = 1.2 },
	},
	{
		id = "sturgeon",
		displayName = "Jesiotr",
		rarity = "Epic",
		spawnWeight = 3,
		pricePerKg = 340,
		minMass = 6.0,
		maxMass = 62.0,
		color = Color3.fromRGB(70, 140, 220),
		look = {
			body = "Torpedo",
			pattern = "Scutes",
			accent = Color3.fromRGB(255, 240, 160),
			belly = Color3.fromRGB(214, 236, 255),
			whiskers = true,
		},
		fight = { strength = 1.25, stamina = 1.85 },
	},
	{
		id = "albino_catfish",
		displayName = "Sum albinos",
		rarity = "Legendary",
		spawnWeight = 0.8,
		pricePerKg = 900,
		minMass = 20.0,
		maxMass = 85.0,
		color = Color3.fromRGB(255, 244, 252),
		look = {
			body = "Long",
			pattern = "None",
			accent = Color3.fromRGB(255, 130, 200),
			belly = Color3.fromRGB(255, 255, 255),
			whiskers = true,
			sparkle = true,
		},
		fight = { strength = 1.4, stamina = 2.1 },
	},
	{
		id = "golden_fish",
		displayName = "Złota Rybka",
		rarity = "Legendary",
		spawnWeight = 0.3,
		pricePerKg = 4200,
		minMass = 0.2,
		maxMass = 1.1,
		color = Color3.fromRGB(255, 200, 30),
		look = {
			body = "Round",
			pattern = "None",
			accent = Color3.fromRGB(255, 120, 40),
			belly = Color3.fromRGB(255, 246, 170),
			sparkle = true,
		},
		-- Dwadzieścia deko czystej furii. Walka trwa chwilę, ale jedna
		-- sekunda nieuwagi przy szarpnięciu zrywa żyłkę.
		fight = { strength = 1.9, stamina = 0.55 },
	},
}

local byId: { [string]: FishDefinition } = {}
for _, definition in DEFINITIONS do
	assert(byId[definition.id] == nil, `zduplikowane id ryby: {definition.id}`)
	table.freeze(definition.fight)
	if definition.look then
		table.freeze(definition.look)
	end
	byId[definition.id] = table.freeze(definition)
end

table.freeze(DEFINITIONS)
table.freeze(byId)

--[[
	Wszystkie gatunki w kolejności z pliku (od pospolitych do legendarnych).
	Zwracana tablica jest zamrożona — nie sortuj jej w miejscu.
]]
function Fish.all(): { FishDefinition }
	return DEFINITIONS
end

function Fish.find(id: string): FishDefinition?
	return byId[id]
end

--[[
	Jak `find`, ale wywala się przy nieznanym id. Używaj tam, gdzie id pochodzi
	z naszego kodu — niech literówka w configu wybuchnie od razu, a nie zamieni
	się w ciche `nil` trzy warstwy dalej.
]]
function Fish.expect(id: string): FishDefinition
	local definition = byId[id]
	if definition == nil then
		error(`nieznane id ryby: {id}`, 2)
	end
	return definition
end

return table.freeze(Fish)
