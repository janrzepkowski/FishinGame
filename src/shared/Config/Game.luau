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
	-- Najkrótszy rzut (moc 0). Najdłuższy to `castRange` wędki — patrz
	-- Config/Rods. Odległość z mocy liczy `Cast.distanceFor`, wspólnie dla
	-- klienta i serwera, żeby obraz nie rozjechał się z mechaniką.
	CAST_MIN_DISTANCE = 8,
	-- Pełny okres wahadłowego paska mocy: 0 -> 100% -> 0 (sekundy).
	CAST_POWER_PERIOD = 1.3,
	-- Po tylu sekundach serwer sam kończy zamach, którego klient nie
	-- zamienił w rzut ani nie anulował (rozłączenie, zawieszony klient).
	-- Bez tego postać stałaby z wędką nad głową do końca sesji.
	CHARGE_TIMEOUT = 8,
	-- Ile najwyżej fałszywych skubnięć przed braniem.
	MAX_NIBBLES = 3,
	-- Zacięcie w tym czasie po skubnięciu płoszy rybę („Spooked"),
	-- a nie liczy się jako zwykłe „za wcześnie".
	NIBBLE_WINDOW = 0.7,
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
	-- Walka z rybą
	-- ---------------------------------------------------------------------
	-- Po udanym podcięciu zaczyna się hol. Dwa paski idą w przeciwne strony:
	--
	--   postęp   rośnie, gdy holujesz        -> 1.0 = ryba wyholowana
	--   napięcie rośnie, gdy holujesz        -> 1.0 = zerwana żyłka
	--
	-- Puszczenie opuszcza oba. Ryba co jakiś czas szarpie i wtedy napięcie
	-- rośnie trzykrotnie szybciej — wtedy TRZEBA puścić. Cała gra polega
	-- na rytmie: hol, puść przy szarpnięciu, hol dalej.
	--
	-- Symulacja chodzi na SERWERZE w stałym kroku. Klient wysyła wyłącznie
	-- intencję („holuję" / „nie holuję"), nigdy postępu.

	-- 20 Hz. Niżej widać skokowe paski, wyżej to marnowanie pasma na
	-- różnicę, której nie da się zobaczyć.
	FIGHT_TICK = 0.05,
	-- Bazowy przyrost postępu na sekundę, dzielony przez `stamina` ryby.
	-- Obniżone z 0,42: walka trwała ok. 3 s niezależnie od ryby i gracz nie
	-- zdążał poczuć różnicy między gatunkami. Przy 0,3 płoć to ~1,7 s
	-- czystego holu, a najwytrwalsza ryba ~7 s (testy pilnują granicy 10 s).
	FIGHT_PROGRESS_GAIN = 0.3,
	-- Bazowy przyrost napięcia, mnożony przez `strength` ryby i dzielony
	-- przez `lineStrength` wędki.
	FIGHT_TENSION_GAIN = 0.22,
	-- Mnożnik napięcia w trakcie szarpnięcia.
	FIGHT_SURGE_TENSION = 3.0,
	-- W trakcie szarpnięcia hol prawie nic nie daje — stąd opłaca się puścić.
	FIGHT_SURGE_PROGRESS = 0.35,
	-- Ubytki przy puszczonej żyłce.
	FIGHT_SLACK_LOSS = 0.12,
	FIGHT_TENSION_RECOVERY = 0.5,
	-- Odstępy i długość szarpnięć (sekundy).
	FIGHT_SURGE_GAP_MIN = 0.9,
	FIGHT_SURGE_GAP_MAX = 2.2,
	FIGHT_SURGE_MIN = 0.5,
	FIGHT_SURGE_MAX = 1.1,
	-- Bezpiecznik: gracz, który odłoży klawiaturę w trakcie walki, ma
	-- zwolnić swój stan, a nie trzymać go w nieskończoność.
	FIGHT_TIMEOUT = 30,

	-- ---------------------------------------------------------------------
	-- Ranking
	-- ---------------------------------------------------------------------
	LEADERBOARD_STORE = "TotalEarned_v1",
	LEADERBOARD_SIZE = 8,
	-- Jak często serwer CZYTA czołówkę.
	LEADERBOARD_REFRESH = 60,
	-- Jak często ZAPISUJE wyniki graczy. Rzadziej niż odczyt, bo i tak
	-- pokazujemy dane sprzed minuty — częstszy zapis nic by nie przyspieszył,
	-- a zjadałby limit zapytań.
	LEADERBOARD_SUBMIT_INTERVAL = 120,

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

	-- Sprzedawcy przy stoiskach: tag na modelu i atrybut mówiący, przy
	-- którym stoisku stoi. Klient znajduje ich po tagu, nie po nazwie.
	NPC_TAG = "ShopNpc",
	NPC_ATTRIBUTE = "NpcKind",

	-- ---------------------------------------------------------------------
	-- Atrybuty łowienia na postaci
	-- ---------------------------------------------------------------------
	-- Ustawia je WYŁĄCZNIE serwer; każdy klient animuje na ich podstawie
	-- wszystkie postacie w zasięgu. Nazwy są tutaj, bo czytają je obie strony.
	ATTRIBUTE_PHASE = "FishingPhase",
	ATTRIBUTE_POWER = "CastPower",
	ATTRIBUTE_TENSION = "Tension",
	ATTRIBUTE_SURGING = "FishSurging",
	ATTRIBUTE_TARGET = "CastTarget",
	-- Licznik skubnięć. Liczy się ZMIANA wartości, nie sama wartość.
	ATTRIBUTE_NIBBLES = "FishingNibbles",
	-- Krok kwantowania napięcia w atrybucie. Napięcie zmienia się 20 razy
	-- na sekundę; co 5% to najwyżej kilka replikacji na sekundę na walkę.
	TENSION_ATTRIBUTE_STEP = 0.05,

	-- ---------------------------------------------------------------------
	-- Pora dnia i pogoda
	-- ---------------------------------------------------------------------
	-- Ile sekund trwa doba w grze. 12 minut: gracz, który zostanie na
	-- kwadrans, zobaczy i zachód, i noc, a żadna pora nie zdąży znudzić.
	DAY_LENGTH_SECONDS = 720,
	-- Atrybut na Workspace z bieżącą pogodą ("Clear" / "Rain").
	WEATHER_ATTRIBUTE = "Weather",
	-- Co ile sekund serwer losuje pogodę na nowo i z jaką szansą na deszcz.
	WEATHER_INTERVAL_MIN = 150,
	WEATHER_INTERVAL_MAX = 330,
	RAIN_CHANCE = 0.35,

	-- ---------------------------------------------------------------------
	-- Narzędzia deweloperskie
	-- ---------------------------------------------------------------------
	-- Atrybut na Workspace. Działa TYLKO w Studio: branie po chwili i bez
	-- skubnięć, żeby dało się testować walkę bez czekania na każdy rzut.
	DEV_FAST_BITE_ATTRIBUTE = "DevFastBite",
	DEV_FAST_BITE_DELAY = 0.6,
	-- Atrybut na Workspace (liczba 0..24). Działa TYLKO w Studio: zamraża
	-- godzinę w grze — do zrzutów ekranu i testów nocy bez czekania.
	DEV_CLOCK_ATTRIBUTE = "DevClockTime",
	STAND_FISH_BUYER = "FishBuyer",
	STAND_ROD_SHOP = "RodShop",
}

-- Uwaga: geometria mapy (gdzie jest woda, jak długi jest pomost) NIE jest tutaj.
-- Siedzi w Server/World/WorldBuilder, bo to układ poziomu, nie parametr balansu.

-- Zamrożone, żeby nikt nie "tymczasowo" nadpisał configa w runtime.
-- Taki hack zawsze zostaje w kodzie i zawsze gryzie kogoś innego.
return table.freeze(Game)
