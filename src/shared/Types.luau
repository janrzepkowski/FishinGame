--!strict
--[[
	Types — wspólne typy dla całego projektu.

	Zasada zespołowa: każdy kształt danych, który przechodzi przez granicę
	klient <-> serwer albo ląduje w DataStore, ma tutaj swój typ. Dzięki temu
	`luau-lsp analyze` wyłapie rozjechany payload na CI, a nie gracz w grze.

	Moduł nie ma zawartości w runtime — istnieje wyłącznie dla typów. Zwraca
	zamrożoną pustą tabelę, a nie `nil`: ModuleScript w Robloxie musi zwrócić
	dokładnie jedną wartość, a nie chcemy opierać startu CAŁEJ gry (ten plik
	requireuje niemal każdy inny) na tym, jak dokładnie liczone jest `return nil`.
	Typy i tak rozwiązują się statycznie, niezależnie od zwracanej wartości.
]]

-- Rzadkość steruje kolorem w UI i (pośrednio) ceną. Spawn rate siedzi
-- osobno w `spawnWeight`, bo chcemy móc je regulować niezależnie.
export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"

--[[
	Jak ryba walczy po zacięciu.

	`strength` — jak szybko napina żyłkę, gdy holujesz (1.0 = bazowo).
	`stamina`  — jak długo trwa walka; WYŻSZA wartość = DŁUŻSZA walka,
	             bo dzieli tempo przyrostu postępu.

	Dwie liczby zamiast jednej „trudności", bo to są różne odczucia:
	silna ryba grozi zerwaniem żyłki, wytrzymała po prostu męczy. Sum jest
	wytrzymały, ale nie szarpie; szczupak odwrotnie.
]]
export type FightProfile = {
	strength: number,
	stamina: number,
}

export type FishDefinition = {
	id: string,
	displayName: string,
	rarity: Rarity,
	-- Waga w losowaniu. Nie procent — sumy nie muszą dawać 100,
	-- więc dodanie nowej ryby nie wymusza przeliczania wszystkich pozostałych.
	spawnWeight: number,
	pricePerKg: number,
	minMass: number,
	maxMass: number,
	color: Color3,
	fight: FightProfile,
}

export type RodDefinition = {
	id: string,
	displayName: string,
	-- Kolejność w sklepie. Trzymamy jawnie, bo pary klucz-wartość w Luau
	-- nie mają gwarantowanej kolejności iteracji.
	order: number,
	price: number,
	-- Mnożnik przesuwający losowanie w stronę rzadkich ryb (1.0 = bez zmian).
	luck: number,
	-- Mnożnik czasu oczekiwania na branie (mniej = szybciej).
	biteSpeed: number,
	-- Ile sekund gracz ma na podcięcie. Lepsza wędka = większe okno.
	reelWindow: number,
	-- Dzielnik przyrostu napięcia w walce. Mocniejsza żyłka = można holować
	-- dłużej bez zerwania, czyli lepszy sprzęt realnie ułatwia walkę.
	lineStrength: number,
	color: Color3,
}

-- Konkretny złowiony egzemplarz. `price` liczy SERWER w momencie złowienia
-- i zapisuje w profilu, żeby zmiana cennika nie przewalutowała komuś
-- ekwipunku w połowie sesji.
export type CaughtFish = {
	fishId: string,
	mass: number,
	price: number,
}

-- ---------------------------------------------------------------------------
-- Profil
-- ---------------------------------------------------------------------------

export type Profile = {
	coins: number,
	totalCaught: number,
	ownedRods: { [string]: boolean },
	equippedRod: string,
	inventory: { CaughtFish },
	-- fishId -> największa złowiona masa. Zasila bestiariusz.
	records: { [string]: number },
	-- Suma monet zarobionych przez całe życie konta. Osobno od `coins`,
	-- bo wydawanie nie może cofać pozycji w rankingu.
	totalEarned: number,
}

export type CastOutcome =
	-- Wyholowana — ryba w ekwipunku.
	"Caught"
	-- Okno na podcięcie minęło bez reakcji.
	| "Escaped"
	-- Klik przed braniem.
	| "TooEarly"
	-- Napięcie sięgnęło maksimum w trakcie walki.
	| "LineSnapped"
	-- Brania nie było, bo nie ma gdzie wsadzić ryby.
	| "InventoryFull"

export type CastResult = {
	outcome: CastOutcome,
	fish: CaughtFish?,
	-- Podcięcie w pierwszych N% okna — bonus do ceny.
	perfect: boolean,
	-- Czy to nowy rekord wagi dla tego gatunku.
	record: boolean,
}

--[[
	Stan walki wysyłany na kliencki pasek. Celowo NIE zawiera gatunku ani
	trudności: gdyby zawierał, dałoby się porzucać walki z tanimi rybami
	i łowić wyłącznie opłacalne. Napięcie i postęp wystarczą, żeby walkę
	było czuć.
]]
export type FightState = {
	progress: number,
	tension: number,
	surging: boolean,
}

export type LeaderboardEntry = {
	name: string,
	value: number,
}

export type NotifyKind = "Info" | "Success" | "Warning"

return table.freeze({})
