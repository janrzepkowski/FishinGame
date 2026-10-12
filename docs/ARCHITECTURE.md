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

## Walka z rybą

Po udanym zacięciu zaczyna się hol — i to jest właściwa gra. Wcześniej cała
pętla miała **jedno kliknięcie na osiem sekund**, a wędki i głębokość
zmieniały wyłącznie prawdopodobieństwa. Sufit umiejętności wynosił „kliknij
w okno 1,5 s" i po pięciu rzutach nie było już czego opanowywać.

### Model

Dwa stany, 0..1, idące w przeciwne strony:

```
holuje + spokój    postęp szybko,      napięcie wolno       (idealnie)
holuje + szarpie   postęp prawie zero, napięcie szybko      (zerwiesz)
puścił + spokój    postęp powoli -,    napięcie -           (marnujesz czas)
puścił + szarpie   postęp powoli -,    napięcie -           (prawidłowo)
```

`postęp ≥ 1` → złowiona. `napięcie ≥ 1` → zerwana żyłka.

```
tempo postępu  = FIGHT_PROGRESS_GAIN / stamina_ryby
tempo napięcia = FIGHT_TENSION_GAIN * strength_ryby / lineStrength_wędki
```

Podczas szarpnięcia napięcie ×3, a postęp ×0,35 — czyli trzymanie przestaje
się opłacać i jednocześnie zaczyna być groźne. To jedyny moment decyzyjny
i cała gra kręci się wokół niego.

### Dlaczego dwie liczby na gatunek, a nie jedna „trudność"

`strength` i `stamina` to różne odczucia. Silna ryba grozi zerwaniem, wytrzymała
po prostu męczy. Jedna liczba zrobiłaby z każdej walki to samo, tylko dłuższe.
Stąd sum (wytrzymały, spokojny) gra inaczej niż szczupak (gwałtowny, krótki).

### Symulacja jest na serwerze

Klient wysyła **wyłącznie boolean** — „trzymam" / „puściłem" — i to tylko przy
zmianie. Nie ma czego podrobić: wysłanie `true` w kółko to dokładnie to samo,
co trzymanie przycisku, czyli najszybsza droga do zerwania żyłki.

Serwer liczy w stałym kroku 20 Hz, jedną wspólną pętlą `Heartbeat` dla
wszystkich walczących graczy. Akumulator odkleja symulację od zmiennego czasu
klatki — przy spadku FPS serwera walka zwalnia, zamiast przeskakiwać, co przy
progu zerwania żyłki miałoby znaczenie.

Stan leci do klienta przez **`UnreliableRemoteEvent`**: zgubiona klatka nic nie
znaczy, bo za 50 ms przyjdzie następna. Wynik walki idzie osobno, zwykłym
niezawodnym Remote'em — zgubione „złowiłeś jesiotra" to zepsuta gra.

Klient interpoluje paski w stronę ostatniego znanego stanu. **Nie symuluje
walki lokalnie** dla gładkości: własna symulacja rozjechałaby się z serwerem
i pokazywała zerwaną żyłkę tam, gdzie serwer widzi złowioną rybę.

### Balans jest testowany, nie wyczuwany

`shared/Util/Fight.luau` to czysta matematyka bez typów Robloxa, więc
`tests/run.luau` sprawdza granice, których w Studio nie da się zmierzyć:

- **czas do zerwania przy szarpnięciu > 0,45 s** — poniżej ludzkiego czasu
  reakcji walka jest nie do wygrania i żadna umiejętność tego nie zmieni
- **najdłuższa walka < 10 s czystego holu** — powyżej gracz się nudzi
- **mocniejsza żyłka realnie wydłuża czas do zerwania** — inaczej zakup
  wędki niczego nie zmienia

Zmiana strojenia w `GameConfig` ma **złamać** te testy i zmusić do świadomego
przeliczenia. To jest ich jedyny cel.

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

Odległość od brzegu liczy `Lake.edgeDistance` — dodatnia nad wodą, ujemna
na lądzie. Jezioro nie jest prostokątem, tylko zaokrągloną, trójpłatową
zatoką opisaną promieniem zależnym od kierunku (`Lake.radiusAt`), a odległość
mierzymy wzdłuż promienia od środka.

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

`shared/Config/Lake.luau` opisuje obrys jeziora (`radiusAt`) i cztery półki:
**8 m** przy brzegu, potem **16**, **24** i **32 m** w środku. Półki są
pomniejszonymi kopiami brzegu, zaczynającymi się 12, 32 i 56 studów od niego. `server/World/Ground.luau` buduje z tych
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

Rzut ma siłę: gracz przytrzymuje przycisk, wahadłowy pasek mocy chodzi
0 → 100% → 0, a puszczenie rzuca. Moc na odległość przelicza
`Cast.distanceFor` (od `CAST_MIN_DISTANCE` do `castRange` wędki), a pasek
i kontroler czytają moc z tej samej funkcji `Cast.powerAt` — gracz dostaje
dokładnie ten rzut, który widział na pasku.

Klient wysyła **wyłącznie moc**. Punkt lądowania liczy serwer
(`Spatial.castTarget` + `Lake.clampToWater`), mierzy tam głębokość i odsyła
punkt w `CastStarted`; klient stawia spławik tam, gdzie mu kazano, zamiast
liczyć drugi raz.

Dociąganie do wody jest konieczne, bo `MAX_CAST_DISTANCE` (28) jest większe
niż najkrótszy rzut (8): gracz może legalnie stać dalej od brzegu, niż sięga
jego rzut. Bez dociągnięcia spławik lądowałby na trawie.

### Stan łowienia widoczny dla wszystkich

Serwer ogłasza, co postać robi, atrybutami na jej modelu: `FishingPhase`,
`CastPower`, `CastTarget`, `Tension`, `FishSurging` i licznik skubnięć
`FishingNibbles`. Nazwy są w `GameConfig`. Każdy klient animuje z nich
wszystkie postacie w zasięgu. Atrybut, a nie Remote do wszystkich, bo gracz,
który podejdzie w trakcie cudzej walki, dostaje aktualny stan razem
z postacią. Pełna specyfikacja: `docs/design/FISHING_MECHANICS.md`.

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

`client/Effects/Bobber.luau` tworzy spławik, żyłkę, kręgi na wodzie i plusk —
dla każdego łowiącego w zasięgu, nie tylko dla siebie. `client/Effects/AnglerRig.luau`
nakłada na postać pozę zamachu, rzutu i holu z kątów liczonych w
`shared/Util/CastPose.luau`; steruje tym `AnglerController` na podstawie
atrybutów postaci.

Dwie pułapki, które kosztowały najwięcej czasu:

- **Stawy awatarów to nie zawsze `Motor6D`.** Nowe postacie mają
  `AnimationConstraint` o tej samej właściwości `Transform`. Kod szukający
  wyłącznie `Motor6D` po cichu nie animuje nic.
- **Pozę nakładamy w `RunService.PreSimulation`, nie w `RenderStepped`.**
  Zapis z `RenderStepped` widać w odczycie, ale Animator nadpisuje go, zanim
  trafi na ekran.

Poniższe uwagi o replikacji dalej obowiązują: instancje tworzy każdy klient
u siebie, sieć niesie tylko atrybuty.
`client/Effects/Underwater.luau` sinieje i rozmywa obraz, gdy kamera schodzi
pod lustro wody.

Instancje tworzone przez klienta nie replikują się — i o to chodzi: spławik
nie wpływa na rozgrywkę (decyduje `FishingService`), więc nie ma powodu
obciążać nim sieci. Podobnie filtr podwodny: gdyby robił go serwer, wejście
jednego gracza do wody zasiniłoby ekran całej serwerowni.

Inni gracze widzą twoją żyłkę i spławik, bo ich klienci rysują je sami
z atrybutów twojej postaci — bez replikowania samych instancji.

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

**Cały trwały interfejs trzyma się LEWEJ KRAWĘDZI.** Środek i prawa strona
ekranu należą do rozgrywki — tam jest woda, spławik i ryba. Pasek łowienia
stał kiedyś na dole pośrodku i zasłaniał dokładnie to, na co gracz patrzy
w kluczowym momencie.

Lewa krawędź, od góry do dołu:

```
HUD_BAND      monety, torba, wędka, głębokość
...
komunikaty    rosną w górę, najświeższy najniżej
CAST_BAND     pasek zarzucania i walki
BOTTOM_SAFE   drążek ruchu Robloxa (tylko telefon)
```

Wymiary tego stosu siedzą w `Theme` (`HUD_BAND`, `CAST_BAND`, `BOTTOM_SAFE`)
i są liczone przez `Theme.castBottom` / `Theme.toastBottom`. **Żaden panel nie
trzyma własnej liczby.** Gdyby trzymał, pierwsza zmiana rozmiaru paska walki
nasunęłaby na niego komunikaty i nikt nie wiedziałby, który plik poprawić.

| Ekran | Desktop / tablet | Telefon |
|---|---|---|
| HUD | karta 230 px, lewy górny róg | węższa, bliżej krawędzi |
| Komunikaty | lewa krawędź, nad paskiem łowienia | to samo, podniesione nad drążek |
| Pasek łowienia | **lewy dolny róg** | to samo, nad drążkiem ruchu |
| Slot wędki | dół, wyśrodkowany | dół, wyśrodkowany |
| Ekwipunek | kolumna z prawej | arkusz przyklejony do dołu |
| Sklep / dziennik | okno wyśrodkowane | prawie pełny ekran |

Mapa zajętości ekranu (Roblox nie dokumentuje pozycji CoreGui, trzeba ją
znać z praktyki):

```
góra-lewo    czat Robloxa           + nasz HUD
góra-prawo   lista graczy
dół-środek   pasek narzędzi         + nasz slot wędki
dół-prawo    skok (mobile)          + nasze przyciski dotykowe
dół-lewo     drążek ruchu (mobile)  -> reszta: komunikaty + pasek łowienia
```

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

## Progresja i retencja

### Bestiariusz

`profile.records` (fishId → największa masa) był zapisywany od początku
i **nigdy nie pokazywany**. Dane były, brakowało okna. Teraz jest w dzienniku.

Niezłowione gatunki pokazujemy po nazwie, nie jako „???" — lista celów działa
tylko wtedy, gdy wiadomo, co się na niej znajduje.

### Ranking

`OrderedDataStore`, bo zwykły DataStore nie umie sortować: żeby zrobić z niego
ranking, trzeba by trzymać listę wszystkich graczy i czytać tysiąc kluczy.

Rankingujemy **`totalEarned`** (suma zarobiona przez całe życie konta), nie
`coins`. Gdyby liczyły się monety w kieszeni, zakup wędki cofałby gracza
w rankingu — czyli gra karałaby za granie w nią zgodnie z zamysłem.

### Zapis: cyklicznie plus przy wyjściu

Sam zapis na wyjściu wygląda poprawnie, dopóki serwer kończy się normalnie.
W praktyce serwery padają, a Roblox nie gwarantuje, że `PlayerRemoving` zdąży
dokończyć zapis — gracz traciłby wtedy cały dorobek sesji w rankingu.

Drugą skrajnością byłby zapis po każdej sprzedaży: przy 50 graczach na serwerze
to ~100 zapisów na minutę na dane, które i tak odświeżamy raz na minutę.

Stoimy pośrodku: cykl co 2 minuty, z pominięciem graczy, których wynik się nie
zmienił. W praktyce kilka zapisów na minutę na serwer.

### `UpdateAsync` z `max`, nie `SetAsync`

Przy jednym serwerze różnicy nie widać. Przy kilkudziesięciu wygląda to tak:
gracz gra, wychodzi, wchodzi na inny serwer i gra dalej. Jeśli spóźniony zapis
ze starego serwera dotrze **po** zapisie z nowego, `SetAsync` cofnąłby mu wynik.

`totalEarned` rośnie monotonicznie, więc maksimum jest zawsze poprawne,
a zapis, który przyszedł nie w kolejności, po prostu nic nie robi.

Ranking jest w dzienniku (`J`). Była też fizyczna tablica na placu — została
usunięta, bo zagracała drogę między spawnem a pomostem, czyli jedyną ścieżkę,
którą gracz przechodzi w pierwszych dziesięciu sekundach.

### Analityka

`AnalyticsService` owinięty w `xpcall`, bo **rzuca błędem w Studio bez dostępu
do API**. Bez tego telemetria wywalałaby handler przy każdym złowieniu —
czyli psułaby grę zamiast ją mierzyć.

Logujemy zdarzenia **kończące etap pętli**, nie każde zarzucenie: lejek
`cast → hooked → landed → sold` odpowiada na pytanie „gdzie gracze odpadają".
Jeśli walka zabija 60% sesji, widać to w danych, a nie w domysłach.

## Interfejs: podglądy 3D zamiast obrazków

Wędka w sklepie i na pasku to **`ViewportFrame` z tym samym modelem**, który
gracz trzyma w ręce — nie obrazek.

Obrazek trzeba wyrenderować, wgrać na Roblox i trzymać jego ID w kodzie. Przy
czterech wędkach to cztery assety, które rozjadą się z modelem przy pierwszej
zmianie kształtu. Geometria siedzi raz, w `shared/Util/RodModel`, jako **dane**;
`RodService` skleja z nich Tool, a UI renderuje podgląd. Nie da się ich
rozjechać, bo to jeden opis.

Z tego samego powodu wbudowany pasek Robloxa jest wyłączony: rysuje slot jako
`Tool.TextureId`, więc bez obrazka pokazuje samą nazwę.

### Chwyt narzędzia

`Tool.GripForward` jest z definicji **LookVectorem** chwytu, a LookVector
w Robloxie to **−Z**. Ustawienie go na `(0, 0, 1)` obraca wędkę o 180°
i wychodzi zza pleców gracza — dokładnie ten błąd tu był.

Dlatego nie ustawiamy `GripForward`/`GripUp`/`GripRight` osobno. Te pola są
wyliczane z macierzy `Grip` i ustawiane pojedynczo potrafią zostawić ją
niespójną. Podajemy jeden kompletny `CFrame`.

## Gdzie co dopisywać

| Chcesz dodać | Idź do |
|---|---|
| nowy gatunek ryby | `shared/Config/Fish.luau` — i nic poza tym |
| zmienić balans walki | `shared/Config/Game.luau` (sekcja walki) — i przelicz testy |
| zmienić kształt wędki | `shared/Util/RodModel.luau` — model, sklep i pasek same się zaktualizują |
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
