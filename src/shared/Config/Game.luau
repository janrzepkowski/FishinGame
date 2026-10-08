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
	-- Jak blisko wody trzeba stać (studs od krawędzi strefy łowienia).
	MAX_CAST_DISTANCE = 28,
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
