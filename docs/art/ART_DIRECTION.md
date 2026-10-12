# Kierunek artystyczny

Jedno zdanie: **bajkowe jezioro o złotej godzinie** — proste bryły, soczyste
kolory, ciepłe światło. Punktem odniesienia są stoiska na placu: wszystko inne
ma wyglądać, jakby stało w tym samym świecie co one.

Ten dokument rozstrzyga spory o wygląd. Gdy coś na mapie „nie pasuje", odpowiedź
ma być tutaj, a nie w guście osoby, która akurat patrzy.

## Styl

- **Stylizowany, nie realistyczny.** Kształty czytelne z daleka, bez drobnego
  detalu. Drzewo to pień i dwie–trzy bryły korony, nie tysiąc liści.
- **Kolor niesie nastrój, materiał tylko fakturę.** Najpierw dobieramy barwę
  z palety, dopiero potem materiał.
- **Woda jest turkusowa i zaprasza**, ale ma wyglądać jak jezioro, nie basen:
  mało odbić, widoczna głębia, ciemniejsza nad głębokimi półkami.
- **Środek kadru należy do rozgrywki** (zasada 8 z `CLAUDE.md`). Dekoracje nie
  stają między graczem a spławikiem.

## Paleta

Sześć kolorów bazowych. Cztery pochodzą wprost ze stoisk (`Market.luau`),
woda to `Theme.COLOR.water` — UI i świat mówią o wodzie tym samym kolorem.

| Rola | Hex | RGB | Gdzie |
|---|---|---|---|
| Trawa | `#62B04A` | 98, 176, 74 | teren, korony drzew (± odcień) |
| Woda | `#2FA8C8` | 47, 168, 200 | jezioro, akcenty wody w UI |
| Zieleń morska | `#56A480` | 86, 164, 128 | skup ryb, markizy, trzciny |
| Bursztyn | `#CE984A` | 206, 152, 74 | sklep wędkarski, światło latarni, monety |
| Drewno | `#9A724A` | 154, 114, 74 | pomost, belki, pnie |
| Łupek | `#4E5460` | 78, 84, 96 | dachy, kamienie, cienie |

Neutralne pochodne, poza limitem sześciu: piasek `#D9C79A` i kremowa biel
markiz `#F0EEE8`.

Zasady użycia:

- Nowy obiekt bierze kolor z tabeli albo jego odcień (jaśniej/ciemniej do
  ok. 20%). Barwa spoza palety wymaga uzasadnienia w PR-ze.
- Odcienie zieleni w roślinności: najwyżej trzy naraz, wszystkie cieplejsze
  od zieleni morskiej — ta jest zarezerwowana dla rzeczy zbudowanych ręką
  człowieka.
- Czerwień i jaskrawy pomarańcz zostają dla spławika i sygnałów rozgrywki.
  Nic w krajobrazie nie konkuruje z nimi o uwagę.

## Nastrój i światło

**Stała złota godzina.** Słońce nisko, długie miękkie cienie, ciepły tint.
Cykl dnia i nocy to osobna funkcja na później — do tego czasu pora się nie
zmienia.

Wartości startowe dla fazy F2 (do sprawdzenia kamerami z `cameras.json`,
nie do przyjęcia na wiarę):

| Właściwość | Teraz | Cel |
|---|---|---|
| `Lighting.ClockTime` | 15,5 | 17,3 |
| `Lighting.Brightness` | 2,8 | 2,4 |
| `Lighting.ShadowSoftness` | 0,35 | 0,2 |
| `ColorCorrection.TintColor` | 255, 252, 246 | 255, 242, 224 |
| `ColorCorrection.Saturation` | 0,14 | 0,20 |
| `Atmosphere.Haze` | 1,1 | 0,6 |
| `Atmosphere.Density` | 0,32 | 0,25 |
| `Clouds` | brak | Cover 0,55, Density 0,6 |
| `SunRaysEffect` | brak | Intensity 0,08, Spread 0,6 |
| `Terrain.WaterColor` | 16, 94, 134 | 36, 156, 178 |
| `Terrain.WaterReflectance` | 0,65 | 0,25 |
| `Terrain.WaterTransparency` | 0,3 | 0,35 |
| kolor materiału `Grass` w terenie | domyślny (oliwkowy) | `#62B04A` |

Fale zostają drobne (`WaterWaveSize` 0,15) — to decyzja rozgrywki, nie
estetyki: przy większych spławik skacze i nie da się odczytać brania.

## Materiały

- **Konstrukcje stawiane kodem:** `WoodPlanks` na deski i ściany, `Wood` na
  belki i pnie, `Slate` na dachy i kamień, `Fabric` na markizy, `Cobblestone`
  na bruk. `SmoothPlastic` tylko jako domyślny dla brył bez faktury.
- **Roślinność:** `LeafyGrass` albo `Grass`. Bez `Neon` i bez połysku.
- **`Neon` wyłącznie dla źródeł światła** (klosze latarni) i sygnałów
  rozgrywki (spławik). Świecący element, który nic nie znaczy, uczy gracza
  ignorować te, które znaczą.
- **Bez tekstur fotograficznych i bez PBR** (`SurfaceAppearance`). Gryzą się
  ze stylem i kosztują pamięć na telefonach.
- **Cienie:** duże bryły rzucają cień, drobnica (trzciny, kamyki, detale lad)
  ma `CastShadow = false`.

## Budulec

Mieszany. **Konstrukcje** (stoiska, pomost, plac) dalej z kodu przez `Build`.
**Natura i rekwizyty** (drzewa, trzciny, kamienie) z **jednej** stylizowanej
paczki low-poly z Creator Store — jednej, żeby wszystko miało tę samą rękę.

Zanim asset trafi do gry:

1. `inspect_instance` na całej paczce; każdy `Script`, `LocalScript`
   i `ModuleScript` zostaje usunięty, o ile nie wiemy dokładnie, co robi.
2. Kolory przemalowane na paletę z tego dokumentu.
3. Model trafia do `assets/` jako `.rbxm` i jest stawiany kodem — nie
   wklejamy niczego ręcznie do Workspace, bo Rojo tego nie widzi.
