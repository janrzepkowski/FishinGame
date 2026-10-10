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

## Pętla rozgrywki

```
zarzuć → czekaj na branie → PODETNIJ → WALKA → sprzedaj → lepsza wędka
```

**Walka jest sednem gry.** Po zacięciu dwa paski idą w przeciwne strony:

| | rośnie, gdy | przy 100% |
|---|---|---|
| **postęp** | holujesz | ryba wyholowana |
| **żyłka** | holujesz | zerwana linka |

Puszczenie obniża oba. Ryba co jakiś czas **szarpie** — wtedy napięcie rośnie
trzy razy szybciej i trzeba puścić. Cała rzecz polega na rytmie: hol, puść
przy szarpnięciu, hol dalej.

Każdy gatunek walczy inaczej. Szczupak szarpie gwałtownie i krótko, sum męczy
długo bez zrywów, a Złota Rybka waży ćwierć kilo i zrywa żyłkę w sekundę.

## Sterowanie

| Klawiatura | Dotyk | Akcja |
|---|---|---|
| LPM | duży okrągły przycisk | zarzuć, a przy braniu — podetnij |
| **LPM (trzymaj)** | **przycisk (trzymaj)** | **holuj w trakcie walki** |
| `1` | kliknięcie w slot wędki | wyjmij / schowaj wędkę |
| `B` | przycisk ▦ | ekwipunek |
| `J` | przycisk ✦ | dziennik: bestiariusz i ranking |
| `Esc` | przycisk ✕ | zamknij otwarte okno |
| `E` przy stoisku | `E` przy stoisku | sprzedaż połowu / sklep z wędkami |

Wędka wyjmuje się sama przy pierwszym zarzuceniu — nie trzeba jej szukać.
Klawiszem `1` można ją schować i wyjąć ręcznie.

Podcięcie w pierwszych 30% okna daje bonus x1,5 do ceny.
Podcięcie przed braniem kosztuje zarzucenie i 1,2 s blokady.

## Progresja

**Bestiariusz** — 12 gatunków, przy każdym zapisany rekord wagi. Klawisz `J`.

**Ranking** — globalna lista najlepszych zarobków w dzienniku. Liczy się suma
zarobiona przez całe życie konta, więc zakup wędki nie cofa pozycji.

**Wędki** — cztery tiery. Każdy poprawia szczęście, tempo brań, okno
na podcięcie i **wytrzymałość żyłki**. To ostatnie jest w praktyce
najważniejsze: na startowej wędce szczupaka trzeba holować ostrożnie,
na turniejowej da się go przeciągnąć siłą.

**Idź na koniec pomostu.** Jezioro ma schodkowe dno: 8 m przy brzegu,
potem 16, 24 i 32 m w środku. Głębokość realnie podbija szansę na rzadkie
ryby, a HUD pokazuje ją pod spławikiem przy każdym zarzuceniu. Nigdzie nie
da się brodzić — od pierwszego kroku w wodę się pływa.

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
