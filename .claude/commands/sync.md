---
description: Wystartuj sync Rojo do Studio i sourcemapę w tle
---

Wystartuj środowisko pracy ze Studio:

1. `rojo serve` w tle (port 34872).
2. `rojo sourcemap default.project.json --output sourcemap.json --watch` w tle —
   bez tego luau-lsp nie rozumie ścieżek typu `script.Parent.Services` i zasypie
   edytor fałszywymi błędami.
3. Sprawdź, że serwer odpowiada: `curl -s http://localhost:34872/api/rojo`.

Potem przypomnij krótko, co zrobić w Studio:

- plugin Rojo → Connect (localhost:34872),
- F5 / Play, żeby odpalić serwer gry,
- zmiany w `src/` lecą do Studio na żywo, ale **w drugą stronę nie** —
  edycja w Studio nie zapisuje się do plików i zginie przy następnym sync.

Jeśli port 34872 jest zajęty, sprawdź, czy nie działa już inny `rojo serve`,
zanim uruchomisz go na innym porcie.
