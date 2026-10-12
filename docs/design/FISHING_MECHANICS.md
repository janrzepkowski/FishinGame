# Mechaniki łowienia — przegląd i propozycja

Status: **zaakceptowany** — specyfikacja fazy F4 (rzut, animacje, feedback
łowienia). Dokument nie zawiera kodu.

Zasada nadrzędna: bierzemy z innych gier **mechaniki**, nie nazwy, grafiki,
interfejs, gatunki ryb ani teksty. Wszystko, co gracz widzi i czyta, zostaje
nasze.

## Gdzie jesteśmy

```
klik -> spławik ląduje 22 study przed graczem -> czekanie 1,4–5 s
     -> branie (okno 1,5–2,2 s) -> klik -> walka: postęp kontra napięcie
```

Walka jest dobra i zostaje: dwie liczby na gatunek (siła, wytrzymałość),
szarpnięcia wymuszające puszczenie, wędka zmieniająca wytrzymałość żyłki.
Słabe są dwa pierwsze etapy. Rzut to jedno kliknięcie bez żadnej decyzji —
spławik zawsze ląduje w tym samym miejscu. Czekanie jest bierne: gracz patrzy
w pasek i nic nie robi.

## Przegląd czterech gier

### Fisch (Roblox)

Pętla w trzech etapach: rzut, „shake", hol.

- **Rzut:** przytrzymanie przycisku pokazuje pionowy pasek mocy; puszczenie
  bliżej szczytu rzuca dalej.
- **Shake:** branie przychodzi samo, ale klikanie pojawiających się
  przycisków je przyspiesza.
- **Hol:** utrzymujesz znacznik w ruchomej strefie, aż wypełni się pasek
  postępu; kilka pomyłek jest wybaczanych.

Co działa: rzut ma decyzję (gdzie celuję), a każdy etap ma własny rytm.
Co nie działa: „shake" to klikanie dla klikania — najłatwiejszy do
zautomatyzowania etap w całej grze.

### Stardew Valley

Po braniu zaczyna się minigra: zielony prostokąt trzeba utrzymać na ikonie
ryby, aż wypełni się pasek postępu. Przytrzymanie przycisku podnosi prostokąt
z rosnącą prędkością, puszczenie go opuszcza — ma bezwładność, więc łatwo
przestrzelić.

Co działa: **bezwładność**. Gracz nie steruje pozycją, tylko przyspieszeniem,
więc każda ryba to nauka wyczucia. Postęp spada, gdy ryba ucieka ze strefy,
ale nie do zera od razu — pomyłka kosztuje, lecz nie kończy próby.

### Sea of Thieves

- **Rzut:** im dłuższe przytrzymanie, tym dalej.
- **Walka:** ryba ciągnie w lewo, w prawo albo od gracza; wędkę trzeba
  ciągnąć w stronę przeciwną. Zwijać wolno dopiero, gdy ryba się zmęczy
  i żyłka zwiotczeje. Zwijanie w trakcie szarpania zrywa żyłkę.
- **Sygnały:** trzeszczenie wędki i wibracja pada ostrzegają przed zerwaniem.

Co działa: **stan ryby czyta się ze świata, nie z paska** — z plusku, z kąta
wędki, z dźwięku. To ten sam rytm „hol / puść", który mamy, tylko pokazany
w scenie 3D zamiast w interfejsie.

### Animal Crossing: New Horizons

Spławik dostaje od zera do kilku **fałszywych skubnięć**, zanim ryba weźmie
naprawdę. Przycisk trzeba wcisnąć dokładnie wtedy, gdy spławik znika pod wodą;
za wcześnie albo za późno i ryba ucieka. Prawdziwe branie ma własny dźwięk —
część graczy łowi „na słuch", z zamkniętymi oczami.

Co działa: **czekanie staje się napięciem** bez dokładania żadnej akcji.
Gracz nic nie klika, a mimo to jest skupiony, bo każde drgnięcie może być tym
właściwym.

## Co się sprawdza i dlaczego

| Wzorzec | Dlaczego działa | Czy bierzemy |
|---|---|---|
| Rzut z siłą (Fisch, Sea of Thieves) | zamienia kliknięcie w decyzję: gdzie i jak daleko | **tak** |
| Fałszywe skubnięcia (Animal Crossing) | wypełnia czekanie napięciem bez nowej akcji | **tak** |
| Stan ryby widoczny w świecie (Sea of Thieves) | gracz patrzy na wodę, nie w róg ekranu | **tak**, jako feedback |
| Rytm hol / puść z ryzykiem zerwania | mamy to już i jest sednem gry | zostaje |
| Strefa ze znacznikiem i bezwładnością (Stardew) | dobra, ale to druga, konkurencyjna minigra holu | nie |
| „Shake" — klikanie przyspieszające branie (Fisch) | nagradza autoklikery, nie umiejętność | nie |
| Kierunek ciągnięcia wędki (Sea of Thieves) | wymaga trzech klawiszy; na telefonie niewygodne | nie teraz |

Wspólny mianownik gier, które się bronią: **każdy etap ma jedną czytelną
decyzję i natychmiastową informację zwrotną**, a pomyłka kosztuje bez
kończenia zabawy.

## Nasza propozycja

```
PRZYTRZYMAJ (moc rośnie) -> PUŚĆ -> spławik leci łukiem i ląduje z pluskiem
  -> skubnięcia... -> BRANIE -> KLIK -> walka: hol / puść -> wynik
```

### 1. Rzut z siłą

- **Przytrzymanie ładuje moc, puszczenie rzuca.** Pasek jest **wahadłowy**:
  moc idzie od 0 do 100% i z powrotem, z pełnym okresem ok. 1,3 s (stała
  w konfiguracji). Trafienie w szczyt wymaga wyczucia, a przetrzymanie nie
  jest darmowe.
- **Moc to odległość**, od 8 studów do zasięgu wędki (dziś stałe 22). Zasięg
  to pole `castRange` w konfiguracji wędki — na start **30 dla każdej**, ale
  jako osobne pole, żeby lepsze wędki mogły później rzucać dalej. Szybkie
  kliknięcie daje rzut minimalny, więc stare przyzwyczajenie dalej działa.
- **Odległość ma znaczenie przez głębokość.** Głębsza woda już dziś podbija
  szansę na rzadkie ryby, a półki dna zaczynają się 12, 32 i 56 studów od
  brzegu. Słaby rzut z brzegu ląduje na najpłytszej (8 m), mocny sięga
  drugiej (16 m); trzecia i czwarta zostają nagrodą za wyjście na pomost.
  Rzut przestaje być formalnością.
- **Bez premii za „idealną moc".** Nagrodą jest miejsce lądowania. Dodatkowy
  mnożnik szczęścia dublowałby premię za głębokość i komplikował ekonomię.
- **Pasek mocy przy lewej krawędzi**, w miejscu paska zarzutu — środek
  ekranu zostaje dla wody (zasada 8 z `CLAUDE.md`).

Granica zaufania: klient wysyła **wyłącznie moc** (liczba 0–1). Serwer ją
sprawdza i przycina, a punkt lądowania liczy sam, tą samą wspólną funkcją co
klient. Podanie mocy 1,0 skryptem daje dokładnie tyle, co dobry rzut ręką.
Serwer odsyła punkt lądowania, żeby spławik stanął dokładnie tam, gdzie
mierzona jest głębokość.

### 2. Trajektoria spławika

- Spławik **wylatuje z czubka wędki** w momencie puszczenia żyłki i leci po
  łuku; czas lotu rośnie z odległością (ok. 0,5–0,9 s).
- **Żyłka to `Beam`** od czubka do spławika: luźna w locie, opadająca na
  wodę po lądowaniu, napinająca się w walce.
- Lądowanie: **plusk cząstkami i rozchodzące się kręgi** na wodzie.
- Po lądowaniu spławik **pływa fizycznie** na wodzie terenu — niezakotwiczona
  część unoszona przez wyporność, lekko kołysana falami.

Lot jest czysto wizualny. O miejscu lądowania decyduje serwer; klient tylko
doprowadza tam spławik.

### 3. Branie

- W trakcie czekania spławik dostaje **od zera do trzech skubnięć**, losowo.
- **Skubnięcie i branie muszą być odróżnialne wzrokiem i słuchem:**

  | | Skubnięcie | Branie |
  |---|---|---|
  | Zanurzenie spławika | płytkie, spławik nie znika | głębokie, spławik idzie pod wodę |
  | Krąg na wodzie | mały, jeden | duży, podwójny |
  | Dźwięk | cichy, krótki | głośniejszy, wyraźnie inny |
  | Żyłka | zostaje luźna | napina się |

- Okno na podcięcie zostaje takie jak dziś (1,5–2,2 s zależnie od wędki),
  podobnie premia za podcięcie w pierwszych 30% okna.
- **Zacięcie na skubnięciu płoszy rybę.** Zarzucenie przepada i trzeba rzucić
  od nowa; komunikat mówi wprost „spłoszona", żeby gracz wiedział, co zrobił
  źle. Krótka blokada zarzucenia (1,2 s) zostaje.

O skubnięciach decyduje **serwer** — losuje ich liczbę i momenty przy
zarzuceniu. Dzięki temu widzą je także inni gracze, a rozstrzygnięcie
„spłoszona" nie zależy od tego, co klient twierdzi, że widział.

### 4. Walka z napięciem żyłki

Model zostaje bez zmian: postęp kontra napięcie, szarpnięcia, siła
i wytrzymałość gatunku, wytrzymałość żyłki z wędki. Zmienia się to, **gdzie
gracz patrzy**:

- **Wędka ugina się** proporcjonalnie do napięcia.
- **Żyłka zmienia kolor**: od jasnej, przez bursztyn, do czerwieni tuż przed
  zerwaniem.
- **Spławik i plusk pokazują szarpnięcie**: ryba rwie w bok, woda się burzy.
  Gracz ma zobaczyć zryw w wodzie o ułamek sekundy wcześniej niż na pasku.
- **Kamera lekko dosuwa się** w stronę spławika na czas walki.
- Pasek przy lewej krawędzi zostaje jako dokładny odczyt, nie jako jedyne
  źródło informacji.

## Animacje

Bez publikowanych assetów animacji — wszystko proceduralnie, z kodu.

- **Chwyt oburącz przez `IKControl`:** prawa ręka trzyma rękojeść, lewa
  sięga do uchwytu wyżej na kiju.
- **Zamach, rzut i hol przez `Motor6D`:** bark, łokieć i talia. Zamach
  odchyla tułów i kij w tył tym mocniej, im większa moc; rzut to szybki
  wymach z doskokiem; w walce postać odchyla się przy holu i pochyla przy
  puszczeniu.
- **Kij się ugina** — złożony z segmentów, wyginanych zależnie od napięcia.

### Animacje widzą wszyscy

Zamach, hol i ugięcie kija **nie są lokalne**. Mechanizm:

- **Klient wysyła tylko intencję:** „zaczynam ładować", moc rzutu,
  „trzymam / puściłem" w walce.
- **Serwer waliduje i ustawia atrybuty na postaci:** `FishingPhase` (faza
  łowienia), `CastPower` (moc ostatniego rzutu), `Tension` (napięcie żyłki
  w walce) oraz punkt lądowania spławika.
- **Każdy klient animuje wszystkie postacie w zasięgu** na podstawie tych
  atrybutów — własną i cudze tym samym kodem. Spławik i żyłka też są
  rysowane dla każdego łowiącego, nie tylko dla siebie.

Dlaczego atrybuty, a nie wysyłanie pozy: atrybut to kilka bajtów przy
zmianie fazy, a samą animację każdy klient liczy u siebie, płynnie i bez
ruchu w sieci. Serwer nie symuluje kości — mówi tylko, **co** postać robi.

Koszt, który akceptujemy: napięcie zmienia się 20 razy na sekundę, więc
atrybut `Tension` jest kwantowany (co 5%) i ustawiany tylko przy zmianie.
Cudza animacja jest też opóźniona o ping — przy łowieniu to niezauważalne.

## Woda i światło

Tylko to, co Roblox faktycznie umożliwia:

- właściwości wody w terenie (kolor, odbicie, przezroczystość, fale),
- oświetlenie i efekty obrazu (pora dnia, atmosfera, bloom, promienie słońca),
- cząstki: plusk przy lądowaniu, braniu i wyholowaniu,
- kręgi na wodzie jako rozszerzające się, zanikające pierścienie,
- wyporność części na wodzie terenu.

Nie robimy i nie obiecujemy: własnych shaderów, kaustyk na dnie, załamania
światła innego niż wbudowane, fal reagujących na spławik.

## Co się zmienia poza wyglądem

- **Sterowanie:** kliknięcie zamienia się w przytrzymanie i puszczenie —
  na myszy, dotyku i padzie. Przycisk dotykowy dostaje ten sam mechanizm.
- **Protokół klient–serwer:** dochodzi sygnał „zaczynam ładować", żądanie
  zarzucenia niesie moc, a odpowiedź niesie punkt lądowania. To zmiana
  w `Net.luau`, czyli do zgłoszenia zespołowi przed rozpoczęciem.
- **Atrybuty na postaci** (`FishingPhase`, `CastPower`, `Tension`, punkt
  lądowania) stają się częścią kontraktu: czyta je każdy klient.
- **Nowy wynik zarzucenia „spłoszona"** obok dotychczasowych.
- **Balans:** zasięg 8–30 zamiast stałych 22 zmienia, jak często gracze
  trafiają w głęboką wodę. Wymaga przeliczenia progresji i nowych testów
  matematyki rzutu.
- **Testowanie:** dev-flaga na szybkie branie, działająca **tylko w Studio**,
  żeby dało się sprawdzać walkę bez czekania po kilka sekund na każde
  zarzucenie.

## Podjęte decyzje

1. **Pasek mocy wahadłowy**, okres ok. 1,3 s, stała w konfiguracji.
2. **Zasięg wspólny 8–30 studów**, ale jako pole `castRange` w konfiguracji
   wędki, żeby mógł później rosnąć z lepszymi wędkami.
3. **Do trzech skubnięć, losowo**, odróżnialnych od brania wzrokiem
   i słuchem; zacięcie na skubnięciu płoszy rybę.
4. **Animacje, spławik i żyłka widoczne dla wszystkich**, sterowane
   atrybutami ustawianymi przez serwer.

## Źródła

- Fisch: <https://videogameschronicle.com/guide/fisch-fishing-tips>
- Stardew Valley: <https://stardewvalleywiki.com/Fishing>
- Sea of Thieves: <https://www.pcgamer.com/sea-of-thieves-fishing-guide>,
  <https://seaofthieves.wiki.gg/wiki/Fishing>
- Animal Crossing: New Horizons:
  <https://play.nintendo.com/news-tips/tips-tricks/fishing-new-horizons-tips-and-tricks/>,
  <https://pixelpoppers.com/2020/04/why-is-fishing-so-hard/>
