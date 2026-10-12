# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# FishinGame — instrukcje dla Claude Code

Gra wędkarska w Roblox. Luau + Rojo, bez plików binarnych w repo.
Zespół: 3 osoby, praca na feature branchach i PR-ach do `main`.

## Komendy

Narzędzia są przypięte w `rokit.toml`. Po `rokit install` wszystkie są na PATH.

```bash
rojo serve                                              # sync do Roblox Studio (port 34872)
rojo build default.project.json -o build/FishinGame.rbxl # zbuduj plik miejsca
rojo sourcemap default.project.json -o sourcemap.json    # mapa dla luau-lsp
luau tests/run.luau                                     # testy jednostkowe (bez Robloxa, <1 s)
stylua src tests                                        # sformatuj
stylua --check src tests                                # sprawdź formatowanie (to robi CI)
selene src tests                                        # lint
luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --platform=roblox src
```

**Przed każdym commitem uruchom pełną bramkę** — w tej kolejności, tak jak CI
(`.github/workflows/ci.yml`), które odrzuci PR, jeśli cokolwiek nie przejdzie:

```bash
luau tests/run.luau
stylua src tests && selene src tests
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --platform=roblox --base-luaurc=.luaurc --ignore="Packages/**" src
rojo build default.project.json -o build/FishinGame.rbxl
```

Skróty: `/sprawdz` (bramka + naprawa), `/przed-pr` (bramka, przegląd diffa, opis PR-a),
`/sync` (rojo serve + sourcemap w tle), `/nowa-ryba <nazwa> [rzadkość]`.

Testy to jeden plik bez filtra — nie da się odpalić pojedynczego testu, całość
trwa poniżej sekundy. Nowy test dopisujesz jako `t.equal/near/isTrue/isFalse`
w odpowiednim `t.suite` w `tests/run.luau`.

`globalTypes.d.luau` jest generowany (jest w `.gitignore`). Gdy go nie ma, pobierz
wersję z **tego samego taga co `luau-lsp` w `rokit.toml`** (nie z `main` — CI też
przypina tag, inaczej lokalnie widać inne błędy typów niż na PR-ze):

```bash
curl.exe -fsSL -o globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/1.70.1/scripts/globalTypes.d.luau
```

W PowerShellu koniecznie `curl.exe` — samo `curl` to alias `Invoke-WebRequest`
i nie zna tych flag.

## Struktura

```
src/shared/     -> ReplicatedStorage.Shared   (widzi klient i serwer)
src/server/     -> ServerScriptService.Server (tylko serwer)
src/client/     -> StarterPlayerScripts.Client (tylko klient)
```

| Gdzie | Co tam trafia |
|---|---|
| `shared/Types.luau` | każdy typ przechodzący granicę klient↔serwer lub do DataStore |
| `shared/Config/` | liczby do tunowania, katalog ryb, drabinka wędek, **geometria jeziora** |
| `shared/Net.luau` | **wszystkie** RemoteEventy — jedyne miejsce ich tworzenia |
| `shared/Util/` | funkcje bezstanowe, używane po obu stronach |
| `server/Services/` | logika gry; każdy serwis ma `start()` |
| `server/World/` | budowa mapy: `Build` (prymitywy), `Ground` (teren), `Dock`, `Market`, `Scenery` |
| `client/Controllers/` | wejście gracza i reakcja na eventy serwera |
| `client/UI/` | ekrany; każdy ma `mount(parent)`; `Theme` to system projektowy |
| `client/Effects/` | efekty czysto lokalne (nie replikują się) |

Kolejność startu jest w `src/server/init.server.luau` i `src/client/init.client.luau`.
Te pliki nie zawierają logiki gry — tylko kolejność. Nie dokładaj do nich mechanik.

## Przepływ, którego nie widać z jednego pliku

**Jedno zarzucenie** to automat stanów w `FishingService` (`Waiting → Biting →
Fighting`), sterowany Remote'ami z `Net`:

```
RequestCast    -> walidacja + LOSOWANIE RYBY -> CastStarted(depth)
  [task.delay] -> BiteStarted(reelWindow)
RequestReel    -> serwer mierzy czas reakcji -> FightStarted
  [Heartbeat 20 Hz, stały krok] -> FightUpdate (Unreliable)
RequestReeling(boolean)         -> tylko intencja „trzymam / puściłem"
                               -> CastResolved(wynik)
```

Gatunek jest znany serwerowi od zarzucenia, a klientowi dopiero w `CastResolved`
— nie wysyłaj go wcześniej, bo da się wtedy skryptować porzucanie tanich ryb.
Każdy opóźniony callback (`task.delay`) porównuje `castId` ze stanem bieżącym;
bez tego timeout starego zarzucenia ubija nowe.

**Profil:** DataStore → `DataService` (`sanitize` przy odczycie = walidacja
i jednocześnie ścieżka migracji) → `mutate` → pełny snapshot `Net.ProfileUpdated`
→ `ProfileCache` (klient, tylko kopia do odczytu) → `update(profile)` każdego
ekranu, spięte w `init.client.luau`.

**Balans walki jest pilnowany testami.** `tests/run.luau` celowo powtarza liczby
`FIGHT_*` z `Config/Game.luau` oraz siłę/wytrzymałość skrajnych ryb. Zmiana
strojenia ma te testy złamać — wtedy przelicz granice (czas do zerwania > 0,45 s,
walka < 10 s) i zaktualizuj liczby w teście świadomie, a nie mechanicznie.

## Zasady, których nie łamiemy

1. **Serwer nie ufa klientowi.** Klient wysyła intencję („chcę zarzucić”), nigdy
   wynik („złowiłem jesiotra za 20k”). Każdy handler `OnServerEvent` zaczyna się
   od walidacji: `typeof` na argumentach, potem stan (profil, cooldown, odległość),
   dopiero potem zmiana danych.

2. **Profil zmieniasz tylko przez `DataService.mutate`.** To jedyne miejsce, które
   replikuje snapshot do klienta i odświeża leaderstats. Zmiana `profile.coins`
   z boku rozjedzie UI z serwerem.

3. **Zero plików binarnych w repo.** Żadnych `.rbxl` ani `.rbxm` poza `assets/`.
   Mapa jest budowana kodem (`WorldBuilder`), bo git nie umie mergować binariów.

4. **Nowy RemoteEvent dodajesz w `shared/Net.luau`**, z komentarzem opisującym
   payload. Nigdy `Instance.new("RemoteEvent")` w serwisie.

5. **Wersje narzędzi podbijamy osobnym PR-em.** Nigdy razem z feature'em —
   inaczej diff formatowania zasłoni diff logiki.

6. **Matematyka licząca to samo po obu stronach ma JEDNĄ implementację
   w `shared/`.** Dotyczy to punktu zarzucenia (`Spatial.castTarget`),
   dociągnięcia go do wody (`Lake.clampToWater`) i głębokości
   (`Lake.depthAt`). Gdy klient liczy po swojemu, spławik ląduje gdzie
   indziej, niż serwer mierzy głębokość — i nikt nie wie, dlaczego ryby
   „nie biorą tam, gdzie widać".

7. **Mapa stawia się z `Build`, a nie z `Instance.new`.** Domyślnie części
   NIE kolidują. Podłogi, deski, barierki i lady deklarują
   `CanCollide = true` jawnie. Odwrotna domyślna wartość robi z koron drzew
   niewidzialne ściany.

8. **UI buduje się z `Theme`.** Kolory z `Theme.COLOR`, odstępy z `SPACE`,
   rozmiary tekstu z `TEXT`. Panele montujemy w korzeniu z `Theme.mountRoot`,
   nie wprost w ScreenGui — inaczej ominie je skalowanie. Wariant układu
   na telefon dodaje się przez `Theme.onLayout`.

   **Środek ekranu jest dla rozgrywki.** Komunikaty idą w lewy dolny róg,
   HUD w lewy górny, pasek walki na dół. Nic nowego nie ląduje w środku
   poza oknami, które gracz sam otworzył.

9. **Czysta matematyka w `shared/` ma mieć test.** `tests/run.luau` chodzi
   pod samym `luau`, bez Robloxa, w ułamku sekundy. Warunek: moduł nie może
   dotykać typów Robloxa **na poziomie modułu** (stąd `Lake.CENTER_X` jako
   liczba, a nie `Vector3`). Wewnątrz funkcji `Vector3` jest OK — test podaje
   zwykłą tabelę z polami X/Y/Z.

10. **Wymiary budynków liczymy w metrach przez `Build.m()`.** Postać R15 ma
    5,5 studa = 1,8 m. Budynek dobrany na oko w widoku z góry wygląda
    karłowato, gdy stanie obok niego gracz.

11. **`Tool.Grip` ustawiamy jednym CFrame'em.** Nigdy `GripForward`/`GripUp`
    osobno — są wyliczane z macierzy i pojedynczo zostawiają ją niespójną.
    `GripForward` to LookVector, czyli **−Z**; ustawienie go na `(0,0,1)`
    obraca narzędzie o 180°.

12. **Modele pokazywane w UI biorą geometrię z `shared/`, nie z obrazków.**
    `RodModel` opisuje wędkę jako dane; Tool, sklep i pasek czytają to samo.
    Obrazek wgrany na Roblox rozjedzie się z modelem przy pierwszej zmianie.

13. **Ciągły strumień stanu idzie `UnreliableRemoteEvent`em**, zdarzenie
    jednorazowe — zwykłym. Zgubiona klatka walki nic nie znaczy, zgubione
    „złowiłeś rybę" psuje grę.

## Konwencje Luau

- `--!strict` w każdym pliku. Bez wyjątków.
- Taby, 100 kolumn, podwójne cudzysłowy — wymusza StyLua, nie dyskutujemy o tym.
- Nazwy w kodzie po angielsku, komentarze i teksty dla gracza po polsku.
- `PascalCase` dla modułów i instancji, `camelCase` dla zmiennych i funkcji,
  `SCREAMING_SNAKE` dla stałych na poziomie modułu.
- Moduł zwraca `table.freeze(M)`, jeśli nie ma stanu wewnętrznego.
- Tablice w Luau są **niezmiennicze**: `{UICorner}` nie jest podtypem `{Instance}`.
  Dlatego `Theme.create` bierze dzieci jako varargs, nie tablicę. Nie zmieniaj
  tego na tablicę „bo czytelniej” — analiza typów przestanie przechodzić.
- Komentarze mówią **dlaczego**, nie **co**. `-- zwiększ licznik` jest bezwartościowy.

## Czego nie robić

- **Nie twórz wody przez `Terrain:FillBlock(..., Enum.Material.Water)`.**
  Woda w Robloxie nie jest materiałem, tylko osobnym kanałem
  `LiquidOccupancy`. FillBlock udaje, że jest, i robi to niespójnie —
  potrafi zbudować całe dno i nie postawić ani kropli wody. Misę jeziora
  pisze `Ground.writeLakeVoxels` przez `WriteVoxelChannels`. Kosztowało
  to trzy nieudane podejścia; nie wracaj do FillBlock.

- Nie dodawaj zależności Wally bez powodu opisanego w PR-ze. Każda paczka to
  kolejna rzecz do aktualizowania.
- Nie zapisuj do DataStore spoza `DataService`.
- Nie licz czasu reakcji gracza po stronie klienta. Serwer mierzy u siebie
  (`FishingService`), inaczej trafienia da się podrobić.
- Nie commituj `sourcemap.json`, `globalTypes.d.luau`, `roblox.toml`, `build/`.

## Testowanie w Studio

`rojo serve`, potem w Studio plugin Rojo → Connect. Szczegóły i pułapki:
`docs/ROBLOX_STUDIO.md`.

DataStore nie działa w Studio bez „Game Settings → Security → Enable Studio
Access to API Services”. Bez tego gra chodzi, ale postęp się nie zapisuje —
`DataService` mówi o tym jednym ostrzeżeniem na starcie.

## Praca przez Roblox Studio MCP

- Kod źródłowy to pliki w `src/` (Rojo). Skrypty zarządzane przez Rojo edytuj
  **na dysku**, nigdy przez `multi_edit` — Rojo je nadpisze przy następnym syncu.
  `multi_edit` tylko dla skryptów spoza Rojo.
- Po każdym etapie pracy nad światem lub UI: `screen_capture` z kilku kamer
  + `get_console_output` (tam ląduje diagnostyka `[Ground]` i `WorldBuilder`).
- Przed dużymi zmianami poproś o zapis place'a / commit.
- Assety z Creator Store: najpierw `inspect_instance`, usuń nieznane Scripty.
- **Nigdy nie publikuj gry.**

## Proces

Trunk-based: gałęzie `feat/`, `fix/`, `refac/`, `chore/`, `docs/`, jeden PR = jedna
rzecz, squash merge, rebase na `main` (nie merge). Zmianę zachowania gry opisz
w `docs/ARCHITECTURE.md` — jest to punkt checklisty w szablonie PR-a. Zmianę
w `shared/Net.luau` lub `shared/Types.luau` zgłoś zespołowi przed rozpoczęciem.

Branche, PR-y i podział odpowiedzialności: `docs/WORKFLOW.md`.
Jak działa gra i dlaczego tak: `docs/ARCHITECTURE.md`.
