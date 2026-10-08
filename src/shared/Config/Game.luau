--!strict
--[[
	Game — wszystkie liczby, które da się tunować, w jednym miejscu.

	Zasada: jeśli zmiana wartości nie wymaga zmiany logiki, jej miejsce jest
	tutaj. Dzięki temu PR typu "podkręcamy ekonomię" dotyka jednego pliku
	i recenzuje się w 30 sekund — a nie przeszukuje się trzech serwisów
	w poszukiwaniu zahardkodowanej dwójki.
]]

local Game = {
	-- ---------------------------------------------------------------------
	-- Zapis danych
	-- ---------------------------------------------------------------------
	-- Wersja w nazwie, nie w polu. Gdy kiedyś zmienimy kształt profilu
	-- w sposób niekompatybilny, bijemy _v2 i stary store zostaje nietknięty
	-- (czyli jest z czego odzyskać dane, jak migracja wyjdzie krzywo).
	DATASTORE_NAME = "PlayerProfiles_v1",
	AUTOSAVE_INTERVAL = 120,
	-- Ile razy ponawiamy nieudaną operację na DataStore zanim się poddamy.
	DATASTORE_RETRIES = 4,
	DATASTORE_RETRY_DELAY = 2,

	-- ---------------------------------------------------------------------
	-- Start gracza
	-- ---------------------------------------------------------------------
	STARTING_COINS = 0,
	STARTING_ROD = "wooden",
	MAX_INVENTORY = 24,

	-- ---------------------------------------------------------------------
	-- Łowienie
	-- ---------------------------------------------------------------------
	-- Bazowe widełki czasu oczekiwania na branie (sekundy).
	-- Wędka skaluje je przez `biteSpeed`.
	MIN_BITE_DELAY = 1.4,
	MAX_BITE_DELAY = 5.0,
	-- Minimalna przerwa między zarzuceniami. Chroni przed spamem Remote'ów.
	CAST_COOLDOWN = 0.6,
	-- Jak blisko wody trzeba stać (studs od krawędzi lustra wody).
	MAX_CAST_DISTANCE = 28,
	-- Jak daleko przed gracza leci spławik. Klient rysuje go dokładnie tam,
	-- a serwer w tym samym punkcie mierzy głębokość — jedna liczba, żeby
	-- obraz nie rozjechał się z mechaniką.
	CAST_DISTANCE = 22,
	-- Zapas od krawędzi lustra wody przy dociąganiu punktu zarzucenia.
	--
	-- Punkt wyliczony „22 study przed graczem" potrafi wypaść na lądzie:
	-- gracz może stać 28 studów od brzegu (dozwolone) albo patrzeć wzdłuż
	-- brzegu. Zamiast odrzucać takie zarzucenie, OBIE strony dociągają punkt
	-- do wody tą samą funkcją (`Lake.clampToWater`). Gdyby robiła to tylko
	-- jedna, spławik lądowałby gdzie indziej, niż serwer mierzy głębokość.
	CAST_SHORE_MARGIN = 4,
	-- Ile szczęścia dokłada najgłębsza woda. 0.3 oznacza mnożnik 1.3 nad
	-- dnem na 16 m, a ponieważ szczęście wchodzi w potęgę rzadkości
	-- (patrz FishingService.pickFish), legendarne zyskują 1.3^4 ≈ 2.9x.
	-- To ma być powód, żeby dojść na koniec pomostu, a nie łowić z brzegu.
	DEPTH_LUCK_BONUS = 0.3,
	-- Podcięcie w pierwszych N okna liczy się jako perfekcyjne.
	PERFECT_REEL_FRACTION = 0.3,
	PERFECT_PRICE_BONUS = 1.5,
	-- Kara za klikanie przed braniem: ile sekund blokady zarzucenia.
	TOO_EARLY_PENALTY = 1.2,
	-- Krzywa masy ryby (patrz Rng.skewedNumber). Powyżej 1 = większość
	-- egzemplarzy drobna, okazy rzadkie.
	MASS_SKEW = 2.2,

	-- ---------------------------------------------------------------------
	-- Sklep / skup
	-- ---------------------------------------------------------------------
	-- Jak blisko stoiska trzeba stać, żeby transakcja przeszła. Klient i tak
	-- ma ProximityPrompt, ale serwer sprawdza to po swojemu — prompt da się
	-- wywołać bez podchodzenia.
	SHOP_INTERACT_DISTANCE = 14,

	-- Po tym atrybucie klient rozpoznaje, co to za stoisko. Celowo nie po
	-- nazwie instancji: nazwa jest widoczna w promptach, więc ktoś ją kiedyś
	-- zmieni na ładniejszą i cicho zepsuje ShopController.
	-- Stała musi być w `shared`, bo klient nie może requireować WorldBuildera.
	STAND_ATTRIBUTE = "StandKind",
	STAND_FISH_BUYER = "FishBuyer",
	STAND_ROD_SHOP = "RodShop",
}

-- Uwaga: geometria mapy (gdzie jest woda, jak długi jest pomost) NIE jest tutaj.
-- Siedzi w Server/World/WorldBuilder, bo to układ poziomu, nie parametr balansu.

-- Zamrożone, żeby nikt nie "tymczasowo" nadpisał configa w runtime.
-- Taki hack zawsze zostaje w kodzie i zawsze gryzie kogoś innego.
return table.freeze(Game)
