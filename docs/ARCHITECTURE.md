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

## Dlaczego mapa jest budowana kodem

`src/server/World/WorldBuilder.luau` stawia wodę, pomost, dwa stoiska i spawn.

Plik `.rbxl` jest binarny — git go nie zmerguje. Gdy dwie osoby edytują mapę
w Studio i obie zacommitują plik, jedna odtwarza swoją pracę ręcznie. Dopóki
mapa to greybox, kod jest po prostu tańszy: merguje się jak tekst i widać go
na PR-ze.

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

`client/Effects/Bobber.luau` tworzy spławik i linkę. Instancje tworzone przez
klienta nie replikują się — i o to chodzi: spławik nie wpływa na rozgrywkę
(decyduje `FishingService`), więc nie ma powodu obciążać nim sieci.

Konsekwencja: **inni gracze nie widzą twojej linki.** Gdy to zacznie przeszkadzać,
efekt trzeba przenieść na serwer, płacąc replikacją za każdy rzut każdego gracza.

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
| nową mechanikę serwerową | nowy plik w `server/Services/` z `start()`, dopisz go do `init.server.luau` |
| nowy ekran | nowy plik w `client/UI/` z `mount(parent)`, zamontuj w `init.client.luau` |
| nowy RemoteEvent | `shared/Net.luau` — z komentarzem opisującym payload |
| nowy typ przez granicę klient↔serwer | `shared/Types.luau` |
