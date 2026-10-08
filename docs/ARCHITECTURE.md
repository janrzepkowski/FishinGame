# Architektura

## Mapowanie plików na drzewo Roblox

Robi to `default.project.json`:

| Katalog | Instancja w grze | Kto widzi |
|---|---|---|
| `src/shared/` | `ReplicatedStorage.Shared` | klient i serwer |
| `src/server/` | `ServerScriptService.Server` | tylko serwer |
| `src/client/` | `StarterPlayerScripts.Client` | tylko klient |

Katalog z plikiem `init.luau` / `init.server.luau` / `init.client.luau` staje się
tym skryptem, a pozostała zawartość katalogu — jego dziećmi. Dlatego
`src/server/init.server.luau` to `Script` o nazwie `Server`, a `src/server/Services/`
to jego dziecko `Services`.

Baseplate, oświetlenie i `StarterGui` też są w `default.project.json` — deklaratywnie,
jako dane. Reszta świata jest budowana kodem (patrz niżej).

## Kolejność startu

Serwer (`src/server/init.server.luau`):

```
1. require(Shared.Net)   -- tworzy RemoteEventy; klient na nie czeka
2. WorldBuilder.build()  -- stawia mapę; serwisy pytają go o wodę i stoiska
3. DataService.start()   -- wczytuje profile; wszystko inne z nich czyta
4. RodService / FishingService / ShopService.start()
```

Klient (`src/client/init.client.luau`):

```
1. ScreenGui
2. *.mount(screen)             -- ekrany budują instancje, jeszcze bez danych
3. ProfileCache.onChanged(...)  -- rozdzielanie snapshotów do ekranów
4. kontrolery .start()          -- wejście gracza
5. Net.RequestProfile:FireServer() -- dopiero teraz prosimy o dane
```

Punkt 5 musi być ostatni. Serwer robi pierwszy `push` w `PlayerAdded`, co może
się zdarzyć przed podłączeniem handlera przez klienta — jawne żądanie usuwa
ten wyścig, zamiast liczyć na kolejkowanie Remote'ów przez Roblox.

## Pętla łowienia

```
KLIENT                        SERWER
──────                        ──────
Tool.Activated
  stan Idle?
    │ RequestCast ──────────> walidacja:
    │                           - Tool z atrybutem RodId W RĘCE
    │                           - cooldown (0,6 s)
    │                           - miejsce w ekwipunku (max 24)
    │                           - odległość od wody (≤ 28 studs,
    │                             liczona do ściany bryły, nie do środka)
    │                         LOSUJE RYBĘ TERAZ
    │ <────────── CastStarted
  spławik + "Zarzucono..."
                              task.delay(1,4-5,0 s × biteSpeed wędki)
    │ <────────── BiteStarted(reelWindow)
  pasek opada, spławik dryga
                              zapisuje biteAt = os.clock()
Tool.Activated
  stan Biting?
    │ RequestReel ──────────> elapsed = os.clock() - biteAt
    │                         perfect = elapsed ≤ reelWindow × 0,3
    │                         masa, cena, DataService.mutate
    │ <────────── CastResolved(wynik)
  nazwa ryby, masa, cena
```

### Dlaczego gatunek jest losowany przy zarzuceniu, a nie przy podcięciu

Bo wynik musi być niezależny od tego, jak gracz podciął. Gdyby losowanie
następowało po podcięciu, trzeba by było przekazać do niego dane o trafieniu,
a wtedy pojawia się pokusa „im lepsze podcięcie, tym rzadsza ryba" — i gra
zamienia się w test refleksu, nie w łowienie. Trafność wpływa wyłącznie na cenę.

### Dlaczego gatunek NIE jest wysyłany razem z `BiteStarted`

Klient dowiaduje się, co złowił, dopiero w `CastResolved`. Gdyby wiedział
wcześniej, dałoby się napisać skrypt podcinający tylko legendarne i ignorujący
resztę brań. Koszt: klient nie może pokazać „coś dużego bierze!" przed podcięciem.
Świadomy kompromis.

### Dlaczego czas reakcji mierzy serwer

`FishingService` liczy `os.clock() - biteAt` u siebie. Klient wysyła tylko
„podcinam teraz", bez swojego wyniku. Gdyby podawał trafność, byłaby to liczba
pochodząca od klienta — czyli liczba do podrobienia.

Koszt: ping wchodzi w pomiar, więc gracz z 200 ms ma realnie krótsze okno.
Przy oknie 1,5-2,2 s to kilka procent i akceptujemy to. **Nie „naprawiajcie" tego
wysyłając czas z klienta** — to otwiera dokładnie tę dziurę, którą zamykamy.

### Walidacja odległości od wody

`Spatial.distanceToPart` liczy odległość do najbliższego punktu **bryły**, nie do
jej środka. Woda to prostopadłościan 180×180 studów — liczone od środka gracz
stojący na końcu pomostu byłby „90 studów od wody".

Ta sama funkcja jest w `shared/`, więc klient używa dokładnie tej samej matematyki.
Jedna implementacja = nie ma sytuacji, w której UI mówi „możesz łowić",
a serwer odrzuca.

## Przepływ danych

```
            DataStore
                │  GetAsync / UpdateAsync (z retry)
                ▼
         ┌─────────────┐
         │ DataService │  ◄── JEDYNE miejsce zmiany profilu
         └──────┬──────┘
                │ mutate(player, fn)
       ┌────────┼────────────┐
       ▼        ▼            ▼
  leaderstats  Net.ProfileUpdated (pełny snapshot)
                       │
                       ▼
                 ProfileCache (klient)
                       │ onChanged
            ┌──────────┼──────────┐
            ▼          ▼          ▼
           Hud   InventoryPanel  ShopPanel
```

**`DataService.mutate` jest jedynym wejściem do zmiany profilu.** Nie jest to
preferencja stylistyczna: to jedno miejsce odpowiada za replikację snapshotu
i odświeżenie leaderstats. Zmiana `profile.coins` z boku da stan, w którym serwer
wie o 500 monetach, a gracz widzi 300 — i nikt nie będzie wiedział, dlaczego.

Wysyłamy **pełny snapshot**, nie diff. Profil ma kilka kilobajtów. Diffowanie
to własny protokół, własne bugi i własne testy — nieopłacalne na tym etapie.

### Walidacja danych z DataStore

`DataService.sanitize` przepisuje surowe dane na poprawny `Profile`, wyrzucając
wszystko, czego nie rozpoznaje. To jednocześnie:

- ochrona przed uszkodzonym wpisem (`NaN` w jednym polu zatruwa całą arytmetykę),
- ochrona przed starym kształtem danych,
- **ścieżka migracji**: nowe pole dostaje wartość domyślną dla starych profili
  i nie trzeba pisać osobnego kodu migracyjnego.

### Czego tu nie ma: session locking

Jeśli ten sam gracz trafi na dwa serwery naraz (teleport, szybki rejoin), ostatni
zapis wygrywa i da się zduplikować przedmioty. Dla MVP z jednym miejscem to
akceptowalne. **Przed publicznym wydaniem** przejdźcie na ProfileStore
(`wally add grilme99/profilestore`) — robi lock, retry i migracje. Nie piszcie
tego sami, to trudniejsze, niż wygląda.

## Woda, głębokość i fizyka zbiornika

Jezioro to **Terrain Robloxa**, nie przezroczysty Part. Tylko wodę w Terrain
silnik traktuje jak wodę: daje pływanie, wyporność, opór, animowane fale,
załamanie światła i zmianę kamery pod powierzchnią. Part z `Transparency = 0.4`
był obrazkiem wody, po którym gracz chodził.

### Dno jest schodkowe i ma znaczenie dla rozgrywki

`shared/Config/Lake.luau` opisuje cztery półki: **8 m** przy brzegu, potem
**16**, **24** i **32 m** w środku. `server/World/Ground.luau` buduje z tych
liczb teren:

```
1. trawa na całym lądzie
2. piasek — cała misa jeziora plus pas plaży, od dna po grunt
3. woda — kolejne półki od NAJPŁYTSZEJ do NAJGŁĘBSZEJ
```

**Wodę się WYCINA w gotowym dnie — nie odwrotnie.** `FillBlock` zastępuje
materiał w swojej bryle, więc piaskiem nie da się pogłębić już istniejącego
dna: zasypanie do −4 na całym jeziorze zostawia 4 study wody wszędzie,
a kolejne, mniejsze zasypania nie mają czego usunąć powyżej.

Ta pułapka raz już zadziałała. Efekt był taki: jezioro miało 4 study wody na
całej powierzchni, gracz chodził po dnie z głową nad wodą (czyli bagno),
a HUD pokazywał przy tym 16 m, bo konfiguracja i teren się rozjechały.
Krok 3 działa, bo każda kolejna półka ma **mniejszy obrys i sięga głębiej** —
zamienia piasek na wodę tylko w środku.

### Diagnostyka, bo mapy nie widać w edytorze

Świat powstaje w runtime, więc w trybie edycji Workspace jest pusty i nie ma
jak „zobaczyć", co się zbudowało. Dlatego przy **każdym** starcie serwera
Output dostaje:

```
[Ground] profil jeziora (oczekiwane / zmierzone w terenie):
  brzeg: 8 / 8 studow
  blisko brzegu: 16 / 16 studow
  srodek pomostu: 24 / 24 studow
  srodek jeziora: 32 / 32 studow
```

Lewa liczba to `LakeConfig.depthAt`, prawa to realny odczyt wokseli
(`Terrain:ReadVoxels`). Rozjazd tych dwóch kolumn **był** przyczyną bagna
i teraz jest widoczny od razu, zamiast po tygodniu.

`WorldBuilder` sprawdza przy okazji, czy nad taflą nie leży coś kolidującego
(`GetPartBoundsInBox`), i wypisuje pełną ścieżkę takiej części. Objaw „woda
jest, ale chodzę po niej" prawie zawsze oznacza Baseplate z szablonu albo
ręcznie wklejoną platformę, której Rojo nie widzi i nie usunie.

Głębokości są dobrane **pod pływanie**, nie pod estetykę: HumanoidRootPart
siedzi ~3 study nad stopami, więc przy 4 studach gracz stoi na dnie
z korpusem na granicy powierzchni — i to właśnie czytało się jako bagno.
Najpłytsza półka ma 8 studów; brodzenia nie ma nigdzie.

Wszystkie wymiary są wielokrotnościami **4** — tyle ma woksel terenu. Przy 2,5
czy 11 silnik i tak zaokrągliłby wypełnienie, a `depthAt` pokazywałby
głębokość, której w terenie nie ma.

### Głębokość podbija szansę na rzadkie ryby

```
szczęście = luck_wędki × (1 + udział_głębokości × DEPTH_LUCK_BONUS)
waga_ryby = spawnWeight × szczęście ^ rarityTier
```

Głębokość wchodzi w to samo szczęście, co wędka, więc też jest podnoszona
do potęgi rzadkości. Dwa niezależne mnożniki rozdzieliłyby progresję „kup
lepszy sprzęt" od „znajdź lepsze miejsce" — a chcemy, żeby jedno wzmacniało
drugie. Stąd pomost: to jedyna droga pieszo nad 28 m wody.

Długość pomostu nie jest dobrana na oko — jego koniec **musi** sięgać
najgłębszej półki, inaczej bonus jest nieosiągalny i nikt nie ma powodu tam
wchodzić. `Dock.build()` sprawdza to przy starcie i ostrzega, gdy ktoś skróci
pomost albo przesunie półki w konfiguracji.

Dla legendarnych (tier 4): wędka startowa z brzegu ≈ 0,28%, wędka turniejowa
nad głębią ≈ 2,2%.

### Jedna matematyka dla obu stron

Punkt zarzucenia liczy `Spatial.castTarget`, a dociąga go do wody
`Lake.clampToWater` — **te same funkcje wołają klient i serwer**. Klient stawia
tam spławik, serwer mierzy tam głębokość.

Dociąganie jest konieczne, bo `MAX_CAST_DISTANCE` (28) jest większe niż
`CAST_DISTANCE` (22): gracz może legalnie stać dalej od brzegu, niż sięga jego
rzut. Bez wspólnego dociągnięcia spławik lądowałby na trawie, a serwer liczyłby
głębokość w zupełnie innym punkcie.

## Dlaczego mapa jest budowana kodem

`src/server/World/` stawia cały świat. Podział plików:

| Plik | Odpowiada za |
|---|---|
| `Build` | prymitywy: bloki, kliny, walce, szyldy |
| `Ground` | teren — ląd, plaża, misa jeziora z wodą |
| `Dock` | pomost nad głęboką wodę, z barierkami i latarnią |
| `Market` | plac, spawn, skup ryb, sklep wędkarski |
| `Scenery` | drzewa, kamienie, trzciny |
| `WorldBuilder` | kolejność i punkty zaczepienia dla serwisów |

Plik `.rbxl` jest binarny — git go nie zmerguje. Gdy dwie osoby edytują mapę
w Studio i obie zacommitują plik, jedna odtwarza swoją pracę ręcznie. Dopóki
mapa jest proceduralna, kod jest po prostu tańszy: merguje się jak tekst
i widać go na PR-ze.

### Dwie konwencje, które warto znać przed dopisywaniem budynków

**Części domyślnie NIE kolidują.** `Build` wyłącza `CanCollide`, `CanQuery`
i `CanTouch`. Podłogi, deski pomostu, barierki, ściany i lady włączają
kolizję jawnie. Odwrotna wartość domyślna zamieniała korony drzew
w niewidzialne ściany w powietrzu.

**Budynki stawiamy w lokalnym układzie** względem
`CFrame.lookAt(pozycja, skądPrzychodziGracz)`. Lokalne -Z to zawsze przód
i pokrywa się z `Enum.NormalId.Front`, więc szyld na pewno patrzy na gracza.
Przy ręcznym obracaniu części prędzej czy później jeden wyląduje tyłem.

**Sceneria jest losowa, ale deterministyczna** — `Random.new(SEED)`, nie
globalne `math.random`. Przy losowym ziarnie każdy serwer miałby inny las,
a zgłoszenie „stoję przy drzewie i nie mogę zarzucić" przestałoby cokolwiek
znaczyć.

**Gdy dojdzie do prawdziwego level designu:**

1. zbuduj mapę w Studio,
2. File → Export Selection → `assets/Map.rbxm`,
3. w `default.project.json`, pod `"Workspace"`:
   ```json
   "Map": { "$path": "assets/Map.rbxm" }
   ```
4. `WorldBuilder` zostaw tylko do wystawiania punktów zaczepienia
   (`getWater`, `getFishBuyer`, `getRodShop`) — znajdowanych po nazwie
   w zaimportowanym modelu.

Plik `.rbxm` ma jednego właściciela i zmienia się rzadko, więc jest OK w repo
(`.gitignore` ma już wyjątek na `assets/`).

## Rozpoznawanie stoisk: atrybuty, nie nazwy

Klient rozpoznaje stoiska po atrybucie `StandKind` (`GameConfig.STAND_ATTRIBUTE`),
nie po `Instance.Name`. Nazwa jest widoczna w ProximityPrompt, więc wcześniej czy
później ktoś zmieni ją na ładniejszą — i cicho zepsuje `ShopController`.

Stała musi siedzieć w `shared/Config/Game.luau`, bo klient nie może requireować
modułu z `ServerScriptService`.

## Efekty lokalne

`client/Effects/Bobber.luau` tworzy spławik, żyłkę, kręgi na wodzie i plusk.
`client/Effects/Underwater.luau` sinieje i rozmywa obraz, gdy kamera schodzi
pod lustro wody.

Instancje tworzone przez klienta nie replikują się — i o to chodzi: spławik
nie wpływa na rozgrywkę (decyduje `FishingService`), więc nie ma powodu
obciążać nim sieci. Podobnie filtr podwodny: gdyby robił go serwer, wejście
jednego gracza do wody zasiniłoby ekran całej serwerowni.

Konsekwencja: **inni gracze nie widzą twojej żyłki.** Gdy to zacznie
przeszkadzać, efekt trzeba przenieść na serwer, płacąc replikacją za każdy
rzut każdego gracza.

## Interfejs: system projektowy i responsywność

`client/UI/Theme.luau` jest fundamentem każdego ekranu i wymusza trzy rzeczy:

**Jedna paleta, kolor niesie znaczenie.** Złoty to zawsze pieniądze, zielony
to sukces, kolor rzadkości jest ten sam w ekwipunku, w pasku łowienia
i w toaście. Gracz uczy się tego raz.

**Skale zamiast dowolnych liczb** — `SPACE`, `RADIUS`, `TEXT`. Gdy każdy ekran
dobiera własne 13, 14 i 15 pikseli, interfejs wygląda na poskładany z kawałków,
choć nikt nie umie wskazać dlaczego.

**Jeden `UIScale` na wszystko.** `Theme.mountRoot` tworzy ramkę na cały ekran
z jednym mnożnikiem liczonym z viewportu. Panele pozycjonujemy skalą (0..1),
a wymiary podajemy w pikselach — wtedy skalowanie łapie rozmiary, a kotwice
trzymają się krawędzi ekranu. Montowanie panelu wprost w `ScreenGui` omija
ten mechanizm.

Dolne ograniczenie skali (0,82) jest ważniejsze niż wierność projektowi:
na telefonie proporcjonalne pomniejszenie dałoby przyciski poniżej progu
trafialności palcem.

### Warianty układu

`Theme.onLayout` woła callback od razu i przy każdej zmianie rozmiaru okna.
Klasy urządzeń: `Phone` (<700 px), `Tablet` (<1150 px), `Desktop`.

| Ekran | Desktop / tablet | Telefon |
|---|---|---|
| HUD | karta 230 px, lewy górny róg | węższa, bliżej krawędzi |
| Pasek łowienia | 120 px nad dołem | 190 px — nad sterowaniem dotykowym |
| Ekwipunek | kolumna z prawej | arkusz przyklejony do dołu |
| Sklep | okno 460 px | prawie pełny ekran |

`ScreenGui.ScreenInsets = CoreUISafeInsets` odsuwa interfejs od górnego paska
Robloxa i od wycięć w ekranach telefonów.

### Dotyk

`MobileControls` pokazuje się tylko przy dotyku **bez klawiatury** — na
tablecie z klawiaturą gracz i tak użyje klawiszy. Główny przycisk zmienia
podpis razem ze stanem: „ZARZUĆ" → „czekaj…" → „PODETNIJ!", więc nie trzeba
niczego kojarzyć.

Przycisk dotykowy i `Tool.Activated` wołają **tę samą** funkcję
(`FishingController.primaryAction`), więc obie ścieżki wejścia nie mogą się
rozjechać. Wędka wyjmuje się automatycznie: w grze z jednym narzędziem
wymaganie, żeby gracz najpierw znalazł je na pasku, to bariera bez wartości.

## Ekonomia

```
cena = masa × pricePerKg × (perfect ? 1,5 : 1)
```

Cena jest liczona **w momencie złowienia** i zapisywana w `CaughtFish`. Sprzedaż
sumuje zapisane ceny, nie przelicza po aktualnym cenniku — zmiana `pricePerKg`
w configu nie przewalutuje nikomu ekwipunku w połowie sesji.

Masa jest losowana z krzywą (`Rng.skewedNumber`, `MASS_SKEW = 2.2`): większość
sztuk jest drobna, okazy rzadkie. Rozkład równomierny dawałby rekordy co trzeci
rzut i nic by nie znaczyły.

### Jak `luck` wędki wpływa na rozkład

```
waga_efektywna = spawnWeight × luck ^ rarityTier
```

`rarityTier`: Common 0, Uncommon 1, Rare 2, Epic 3, Legendary 4.

Przy `luck = 1.0` rozkład jest dokładnie taki, jak `spawnWeight` w configu.
Wędka turniejowa (`luck = 1.42`) daje legendarnym wagę ×1,42⁴ ≈ 4,07, a pospolitym
×1 — czyli lepsza wędka nie „daje więcej wszystkiego", a realnie przesuwa rozkład
w stronę rzadkości.

## Gdzie co dopisywać

| Chcesz dodać | Idź do |
|---|---|
| nowy gatunek ryby | `shared/Config/Fish.luau` — i nic poza tym |
| nowy tier wędki | `shared/Config/Rods.luau` |
| zmienić balans | `shared/Config/Game.luau` |
| zmienić kształt lub głębokość jeziora | `shared/Config/Lake.luau` — teren przebuduje się sam |
| nowy budynek | nowy builder w `server/World/`, wywołaj go z `WorldBuilder.build()` |
| nową mechanikę serwerową | nowy plik w `server/Services/` z `start()`, dopisz go do `init.server.luau` |
| nowy ekran | nowy plik w `client/UI/` z `mount(parent)`, zamontuj w `init.client.luau` |
| wariant układu na telefon | `Theme.onLayout` w danym ekranie |
| nowy kolor lub rozmiar tekstu | `Theme.COLOR` / `Theme.TEXT` — nigdy liczba w miejscu użycia |
| nowy RemoteEvent | `shared/Net.luau` — z komentarzem opisującym payload |
| nowy typ przez granicę klient↔serwer | `shared/Types.luau` |
