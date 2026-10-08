---
description: Uruchom pełną bramkę jakości (format, lint, typy, build) i napraw, co się da
argument-hint: "[opcjonalnie: ścieżka, np. src/server]"
---

Uruchom pełną bramkę jakości na `$1` (domyślnie `src`), dokładnie w tej kolejności —
każdy krok może zmienić wynik następnego:

1. `stylua src` — sformatuj (nie `--check`, od razu popraw)
2. `selene src` — lint
3. Jeśli brakuje `globalTypes.d.luau`, pobierz go:
   `curl -L -o globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau`
4. `rojo sourcemap default.project.json --output sourcemap.json`
5. `luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --platform=roblox --base-luaurc=.luaurc --ignore="Packages/**" src`
6. `rojo build default.project.json --output build/FishinGame.rbxl`

Napraw znalezione błędy i uruchom ponownie, aż wszystko przechodzi.

Przy naprawianiu:

- Ostrzeżenia selene o `UDim2.new` → zamień na `UDim2.fromOffset` / `UDim2.fromScale`.
- Błąd `Expected '{Instance}', but got '{UICorner}'` → to niezmienniczość tablic
  w Luau. Przekazuj dzieci jako varargs (patrz `Theme.create`), nie jako tablicę.
- `Value of type 'Instance?' could be nil` po `if not x then x = ... end` →
  wydziel funkcję z wczesnym returnem i konkretnym typem zwrotu. Nie dodawaj `::`.
- `Function only returns 1 value, but 2 are required` przy `pcall` → funkcja nic
  nie zwraca, więc `pcall` ma typ `(boolean)`. Użyj `xpcall` z handlerem.

Na koniec podaj zwięzłe podsumowanie: co było zepsute i co z tym zrobiłeś.
Jeśli wszystko przeszło od pierwszego razu, napisz tylko tyle.
