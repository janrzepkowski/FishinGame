# FishinGame — instrukcje dla Claude Code

Gra wędkarska w Roblox. Luau + Rojo, bez plików binarnych w repo.
Zespół: 3 osoby, praca na feature branchach i PR-ach do `main`.

## Komendy

Narzędzia są przypięte w `rokit.toml`. Po `rokit install` wszystkie są na PATH.

```bash
rojo serve                                              # sync do Roblox Studio (port 34872)
rojo build default.project.json -o build/FishinGame.rbxl # zbuduj plik miejsca
rojo sourcemap default.project.json -o sourcemap.json    # mapa dla luau-lsp
stylua src                                              # sformatuj
stylua --check src                                      # sprawdź formatowanie (to robi CI)
selene src                                              # lint
luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --platform=roblox src
```

**Przed każdym commitem uruchom pełną bramkę:** `stylua src && selene src` + analiza typów.
CI robi dokładnie to samo i odrzuci PR, który tego nie przechodzi.
Skrót: `/sprawdz`.

`globalTypes.d.luau` jest generowany (jest w `.gitignore`). Gdy go nie ma:

```bash
curl -L -o globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
```

## Struktura

```
src/shared/     -> ReplicatedStorage.Shared   (widzi klient i serwer)
src/server/     -> ServerScriptService.Server (tylko serwer)
src/client/     -> StarterPlayerScripts.Client (tylko klient)
```

| Gdzie | Co tam trafia |
|---|---|
| `shared/Types.luau` | każdy typ przechodzący granicę klient↔serwer lub do DataStore |
| `shared/Config/` | liczby do tunowania, katalog ryb, drabinka wędek |
| `shared/Net.luau` | **wszystkie** RemoteEventy — jedyne miejsce ich tworzenia |
| `shared/Util/` | funkcje bezstanowe, używane po obu stronach |
| `server/Services/` | logika gry; każdy serwis ma `start()` |
| `server/World/` | budowa mapy |
| `client/Controllers/` | wejście gracza i reakcja na eventy serwera |
| `client/UI/` | ekrany; każdy ma `mount(parent)` |
| `client/Effects/` | efekty czysto lokalne (nie replikują się) |

Kolejność startu jest w `src/server/init.server.luau` i `src/client/init.client.luau`.
Te pliki nie zawierają logiki gry — tylko kolejność. Nie dokładaj do nich mechanik.

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

## Proces

Branche, PR-y i podział odpowiedzialności: `docs/WORKFLOW.md`.
Jak działa gra i dlaczego tak: `docs/ARCHITECTURE.md`.
