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

export type Profile = {
	coins: number,
	totalCaught: number,
	ownedRods: { [string]: boolean },
	equippedRod: string,
	inventory: { CaughtFish },
	-- fishId -> największa złowiona masa. Czysto dla dumy gracza.
	records: { [string]: number },
}

export type CastOutcome =
	-- Podcięte w oknie — ryba w ekwipunku.
	"Caught"
	-- Okno minęło bez reakcji.
	| "Escaped"
	-- Klik przed braniem.
	| "TooEarly"
	-- Brania nie było, bo nie ma gdzie wsadzić ryby.
	| "InventoryFull"

export type CastResult = {
	outcome: CastOutcome,
	fish: CaughtFish?,
	-- Podcięcie w pierwszych N% okna — bonus do ceny.
	perfect: boolean,
}

export type NotifyKind = "Info" | "Success" | "Warning"

return table.freeze({})
