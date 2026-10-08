---
description: Dodaj nowy gatunek ryby do katalogu
argument-hint: "<nazwa po polsku> [rzadkość: Common|Uncommon|Rare|Epic|Legendary]"
---

Dodaj gatunek ryby: **$ARGUMENTS**

Zmiany wyłącznie w `src/shared/Config/Fish.luau` — nic poza tym plikiem nie powinno
wymagać dotknięcia. Jeśli okazuje się, że wymaga, zatrzymaj się i powiedz dlaczego,
bo to znaczy, że katalog przestał być samowystarczalny.

Przy ustalaniu liczb trzymaj się tego, co już jest w pliku:

- `id` — `snake_case`, po angielsku, bez diakrytyków
- `spawnWeight` — porównaj z istniejącymi wpisami tej samej rzadkości.
  Wagi nie sumują się do 100, to skala względna.
- `pricePerKg` — trzymaj drabinkę: Common ~12-22, Uncommon ~34-58,
  Rare ~95-120, Epic ~260-340, Legendary 900+
- `minMass` / `maxMass` — realistyczne dla gatunku. Pamiętaj, że masa jest
  losowana z krzywą (`MASS_SKEW`), więc większość złowionych sztuk będzie
  blisko `minMass`.
- `color` — `Color3.fromRGB`, kolor zbliżony do prawdziwej ryby

Po dodaniu:

1. Sprawdź, czy `id` się nie powtarza (jest na to `assert`, ale lepiej wiedzieć od razu).
2. Uruchom bramkę z `.claude/commands/sprawdz.md`.
3. Napisz jedną linijkę: jaka jest szansa na tę rybę przy wędce startowej
   (`luck = 1.0`) — czyli `spawnWeight` podzielone przez sumę wszystkich wag.
