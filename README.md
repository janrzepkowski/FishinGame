# FishinGame

Gra wędkarska w Roblox. Luau, Rojo, bez plików binarnych w repo.

Pętla rozgrywki: zarzuć → poczekaj na branie → podetnij w oknie czasowym →
ryba ląduje w ekwipunku → sprzedaj w skupie → kup lepszą wędkę → łów rzadsze ryby.

## Start w 5 minut

Wymagane raz na maszynę:

- [Roblox Studio](https://create.roblox.com/)
- [Git](https://git-scm.com/)
- Edytor — zalecany VS Code (lista rozszerzeń jest w `.vscode/extensions.json`,
  VS Code sam je zaproponuje przy otwarciu projektu)

```powershell
git clone https://github.com/janrzepkowski/FishinGame.git
cd FishinGame

# Rokit — menedżer narzędzi (Windows PowerShell)
Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
# zamknij i otwórz terminal, żeby PATH się odświeżył

# Narzędzia w wersjach przypiętych w rokit.toml
rokit install

# Sprawdzenie, że wszystko stoi
rojo --version; stylua --version; selene --version; luau-lsp --version
```

macOS / Linux — zamiast skryptu `.ps1`:

```bash
curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
rokit install
```

### Odpalenie gry

```powershell
rojo serve
```

W Roblox Studio: zainstaluj plugin Rojo (`rojo plugin install`), otwórz **dowolny
pusty baseplate**, w pluginie kliknij **Connect**. Drzewo z `src/` pojawi się
w Studio. Teraz F5 i grasz.

Szczegóły, pułapki i co zrobić, gdy sync nie działa: **[docs/ROBLOX_STUDIO.md](docs/ROBLOX_STUDIO.md)**.

## Sterowanie

| Klawisz | Akcja |
|---|---|
| LPM (z wędką w ręce) | zarzuć, a przy braniu — podetnij |
| `B` | ekwipunek |
| `E` przy stoisku | sprzedaż połowu / sklep z wędkami |

Podcięcie w pierwszych 30% okna daje bonus x1,5 do ceny.
Podcięcie przed braniem kosztuje zarzucenie i 1,2 s blokady.

## Codzienna praca

```powershell
rojo serve                    # sync do Studio (trzymaj włączone)
stylua src                    # sformatuj
selene src                    # lint
rojo build default.project.json --output build/FishinGame.rbxl
```

Pełna bramka jakości przed commitem — w Claude Code: `/sprawdz`.
Ręcznie: wszystkie komendy z sekcji „Komendy" w [CLAUDE.md](CLAUDE.md).

## Dokumentacja

| Plik | O czym |
|---|---|
| **[docs/WORKFLOW.md](docs/WORKFLOW.md)** | branche, PR-y, podział pracy na 3 osoby, konflikty |
| **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** | jak działa gra i dlaczego tak |
| **[docs/ROBLOX_STUDIO.md](docs/ROBLOX_STUDIO.md)** | Studio, plugin Rojo, publikacja, DataStore |
| **[CLAUDE.md](CLAUDE.md)** | instrukcje dla Claude Code — zasady projektu |

## Czego tu nie ma i dlaczego

**Team Create jest wyłączony.** Przy Rojo każdy pracuje na swojej lokalnej kopii
Studio, a źródłem prawdy są pliki w `src/`. Team Create robiłby drugie, równoległe
źródło prawdy — i wygrywałoby to, które ktoś akurat zapisał później.

**W repo nie ma pliku `.rbxl`.** Jest binarny, więc git go nie zmerguje. Mapa jest
budowana kodem (`src/server/World/WorldBuilder.luau`), a plik miejsca generuje
`rojo build`. CI pilnuje, żeby binarka nie weszła przez przypadek.

**Zero zależności Wally.** MVP stoi na czystym API Roblox. Kandydaci na później
są wypisane w `wally.toml`.
