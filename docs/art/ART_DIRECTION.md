# Kierunek artystyczny

Jedno zdanie: **cukierkowe jezioro dla dzieci** — wszystko zaokrąglone,
pastelowe, z gładkiego plastiku, a interfejs jak naklejki z grubym konturem.

Ten dokument rozstrzyga spory o wygląd. Gdy coś na mapie „nie pasuje", odpowiedź
ma być tutaj, a nie w guście osoby, która akurat patrzy.

> Wcześniejszy kierunek („bajkowe jezioro o złotej godzinie", drewno i łupek,
> paczka low-poly) został zastąpiony w październiku 2026. Stare wartości są
> w historii gita.

## Styl

- **Zaokrąglone, nie kanciaste.** Podstawowe bryły to walec, kula i elipsoida
  (`Build.upright`, `Build.sphere`, `Build.ellipsoid`). Prostopadłościan zostaje
  tam, gdzie gracz po czymś chodzi — i dostaje okrągłe końce (`Build.pill`).
- **Jeden materiał: `SmoothPlastic`.** Świat ma wyglądać jak zabawka. Bez
  tekstur drewna, kamienia i tkaniny, bez PBR.
- **Kolor z palety `Build.COLOR`** (świat) i `Theme.COLOR` (interfejs).
  Barwa spoza palety wymaga uzasadnienia w PR-ze.
- **Punkty orientacyjne zamiast napisów.** Ryba na dachu skupu, spławik na
  dachu sklepu, tęczowy pomost: dziecko trafia tam, zanim przeczyta szyld.
- **Środek kadru należy do rozgrywki** (zasada 8 z `CLAUDE.md`). Dekoracje nie
  stają między graczem a spławikiem.

## Świat

| Element | Jak wygląda | Gdzie |
|---|---|---|
| Plac | okrągły krążek z pastelowymi „guzikami", latarnie-lizaki | `World/Market` |
| Stoiska | „babeczki": podest, laski cukrowe, kopuła z lukrem i posypką | `World/Market` |
| Pomost | deski w sześciu pastelach, okrągłe czoła, okrągła platforma na końcu | `World/Dock` |
| Drzewa | pień-walec i korona z kul; zaokrąglone choinki; wielkie lizaki | `World/Scenery` |
| Kamienie | „pianki" — spłaszczone elipsoidy | `World/Scenery` |
| Horyzont | kopuły wzgórz: bliżej zielone, dalej pastelowe | `World/Scenery` |

`assets/NaturePack.rbxm` nie jest już używany przez `Scenery` — kanciaste,
ciemne siatki nie dawały się pogodzić ze stylem.

## Światło

Wartości w `default.project.json` (oświetlenie) i `World/Ground` (woda, niebo),
dobrane na zrzutach o 13:00 (`DevClockTime` na Workspace zamraża godzinę).

| Właściwość | Wartość |
|---|---|
| `Lighting.Brightness` | 1,6 |
| `Lighting.ExposureCompensation` | −0,45 |
| `Lighting.Ambient` / `OutdoorAmbient` | 0,30 0,30 0,40 / 0,44 0,46 0,54 |
| `Bloom` | Intensity 0,2, Threshold 2,2 |
| `ColorCorrection.Saturation` | 0,20 |
| `Atmosphere` | Density 0,14, Haze 0,3 |
| `Terrain.WaterColor` | 36, 150, 196; Reflectance 0,12; Transparency 0,3 |
| trawa / piasek terenu | 118, 206, 104 / 255, 226, 170 |

**Pastele przepalają się bardzo łatwo.** Przy jasności 2,6 i dodatniej
ekspozycji plac był białą plamą bez kształtu. Dlatego ekspozycja jest ujemna,
bloom prawie wyłączony, a „biel" palety to 226, 230, 242, nie 255.

Fale zostają drobne (`WaterWaveSize` 0,15) — to decyzja rozgrywki, nie
estetyki: przy większych spławik skacze i nie da się odczytać brania.

## Interfejs

- Panele nasycone (niebieskie), **gruby granatowy kontur** na wszystkim,
  biały tekst z obrysem. Żadnych szarości.
- Każde okno ma belkę tytułu we własnym kolorze (torba różowa, sklep
  pomarańczowy, dziennik fioletowy) i czerwony przycisk zamknięcia w rogu
  (`Theme.window`).
- **Czcionka: Nunito** (ExtraBold / Heavy). FredokaOne i LuckiestGuy nie mają
  w Robloxie polskich znaków ę, ą, ś, ć, ł, ż, ź, ń — silnik podmienia je
  inną czcionką i wyraz wychodzi w dwóch krojach.
- Ryby w ekwipunku i bestiariuszu to **siatka kafelków** w kolorze rzadkości,
  z modelem 3D gatunku (`UI/FishIcon` + `shared/Util/FishModel`).
- **Nagrody (`UI/Celebration`)**: baner z promieniami, konfetti, migające
  światła przy rekordzie, monety lecące do licznika po sprzedaży. To język
  nagrody z automatów, ale **bez hazardu**: nie ma losowania, zakładu ani
  niczego do kupienia. Pospolita ryba nie dostaje banera.
- `BillboardGui` z `AlwaysOnTop` nie pojawia się na zrzutach z `screen_capture`
  — podpowiedź przy stoisku (`UI/PromptBubble`) sprawdza się w grze albo
  odczytem pozycji, nie zrzutem.
- **Ekran ładowania (`UI/LoadingScreen`)** zasłania grę, dopóki mapa nie
  dojedzie strumieniowo, a pora dnia i światła się nie ustawią. Pasek rośnie
  płynnie (najwyżej 40% na sekundę) i kurtyna podnosi się dopiero przy 100%.
