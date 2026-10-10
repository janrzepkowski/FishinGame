# Roblox Studio + Rojo

## Jak to w ogóle działa

Rojo to serwer HTTP na twojej maszynie i plugin w Studio. Plugin pyta serwer
o drzewo instancji i odtwarza je w otwartym miejscu.

**Sync jest jednostronny: pliki → Studio.** Zmiana w `src/` ląduje w Studio
w sekundę. Zmiana zrobiona ręcznie w Studio **nie wraca do plików** i zginie
przy następnym sync. To nie jest ograniczenie do obejścia — to jest cała idea:
jedno źródło prawdy, w gicie.

## Plugin — instalacja

```powershell
rojo plugin install
```

Wrzuca plugin do `%LOCALAPPDATA%\Roblox\Plugins`. Studio musi być zamknięte
albo trzeba je zrestartować.

Alternatywnie: [Rojo w Creator Store](https://create.roblox.com/store/asset/13916111004/Rojo)
→ Install → plugin dociąga się automatycznie.

## Codzienna praca

```powershell
rojo serve
```

W Studio: otwórz **pusty baseplate** (File → New), w pluginie Rojo → **Connect**
(`localhost:34872`). Drzewo z `src/` pojawia się w Explorerze. F5 i grasz.

Dwie rzeczy warto trzymać włączone równolegle:

```powershell
rojo sourcemap default.project.json --output sourcemap.json --watch
```

Bez sourcemapy `luau-lsp` nie wie, że `script.Services.DataService` istnieje,
i zasypie edytor fałszywymi błędami. W VS Code jest to zadanie
**„Rojo: sourcemap (watch)"** (Ctrl+Shift+P → Run Task).

## Co ustawić w Studio raz

### Ustawienia miejsca

**File → Experience Settings → zakładka Security** → zmień → **Save**.
(W starszych wersjach Studio to samo okno nazywa się **Game Settings**.
Po polsku: Plik → Ustawienia doświadczenia → Bezpieczeństwo.)

> **Nie widzisz tego menu?** Na ekranie startowym Studio menu ma tylko
> Plik / Dodatki plug-in / Pomoc. `Experience Settings` pojawia się dopiero,
> gdy **masz otwarte jakieś miejsce** w edytorze. Otwórz cokolwiek
> (Nowy projekt → Baseplate albo `build/FishinGame.rbxl`) i wróć do menu.

| Ustawienie | Wartość | Dlaczego |
|---|---|---|
| **Allow HTTP Requests** | ON | bez tego plugin Rojo nie dogada się z `rojo serve` |
| **Enable Studio Access to API Services** | ON | bez tego DataStore rzuca błędem i postęp się nie zapisuje |

### Ustawienia samego Studio

**File → Studio Settings**:

| Ustawienie | Wartość | Dlaczego |
|---|---|---|
| Script Editor → Auto Indent | OFF | formatuje StyLua, Studio tylko przeszkadza |
| Luau Language Server (jeśli jest) | OFF | kolizja z luau-lsp w VS Code |

### Trzy warunki, o które się potykają wszyscy

**1. Musisz mieć otwarte miejsce**, inaczej menu nie istnieje (patrz ramka wyżej).

**2. Miejsce musi być opublikowane.** Na lokalnym, nigdy niezapisanym pliku
„Enable Studio Access to API Services" nic nie da — DataStore nie zadziała
w ogóle. Pełna kolejność:

```powershell
rojo build default.project.json --output build/FishinGame.rbxl
```

1. Plik → **Otwórz z pliku** (Open from File) → `build/FishinGame.rbxl`
2. Plik → **Opublikuj w Roblox jako…** (Publish to Roblox As…) → nowe
   doświadczenie, nazwane z dopiskiem `DEV`
3. Dopiero teraz Experience Settings → Security → oba przełączniki → Save

**3. Ustawienie jest per-experience, nie globalne.** Każde miejsce, w którym
testujecie, trzeba włączyć osobno.

### Zanim zaczniecie publikować: szybka ścieżka do zagrania

Do sprawdzenia samej rozgrywki **nie trzeba nic publikować**:

```powershell
rojo serve
```

Studio → Nowy projekt → Baseplate → plugin Rojo → Connect → F5. Gra działa,
tylko postęp się nie zapisuje. Publikacja jest potrzebna wyłącznie wtedy,
gdy testujecie zapis danych.

### Nie testujcie na produkcyjnym DataStore

Studio z włączonym API uderza w **te same** DataStore'y co opublikowana gra.
Przy trzech osobach testujących jednocześnie oznacza to nadpisywanie prawdziwych
danych graczy — i swoich wzajemnie.

Zróbcie osobne miejsce testowe. W tym projekcie wystarczy zmienić
`DATASTORE_NAME` w `src/shared/Config/Game.luau` — nazwa ma już wersję w sobie
(`PlayerProfiles_v1`), więc `PlayerProfiles_dev` daje piaskownicę odciętą
od produkcji.

### Jak sprawdzić, że zapis działa

Odpal grę (F5) i zerknij w **Output**. `DataService` wypisuje ostrzeżenie
**tylko** wtedy, gdy zapis nie działa:

```
[DataService] POSTĘP NIE JEST ZAPISYWANY. Gra działa na danych w pamięci.
```

Cisza = DataStore odpowiada i profile się zapisują.

To ostrzeżenie jest celowe: gra ma się dać testować nawet bez włączonego API,
a zgadywanie „dlaczego nic się nie zapisuje" to strata czasu całego zespołu.

## Testowanie wieloosobowe

Test → Clients and Servers → Players: **2** → Start.

Studio odpala jeden serwer i dwóch klientów w osobnych okienkach. To jedyny
sensowny sposób sprawdzenia, czy:

- dwóch graczy naraz łowi bez wzajemnego psucia stanu,
- spławik jednego nie jest widoczny u drugiego (powinien nie być — efekt jest lokalny),
- leaderstats pokazują poprawne wartości dla każdego osobno.

Pamiętajcie, że w `FishingService` stan zarzucenia jest trzymany per `Player`.
Test jednoosobowy nie wyłapie błędu, w którym stan jest globalny.

## Publikacja

Repo i opublikowana gra to **dwie osobne rzeczy**. `git push` nie publikuje
niczego, a `git revert` nie cofa publikacji.

### Dwa doświadczenia: DEV i PROD

| | DEV | PROD |
|---|---|---|
| Prywatność | Private | **Public** |
| Kto wchodzi | tylko twórcy | cały zespół i gracze |
| Po co | testy, eksperymenty | wersja, którą się pokazuje |

**DataStore'y są przypisane do doświadczenia (universe), nie do pliku miejsca.**
To znaczy, że osobne DEV i PROD mają z automatu osobne dane graczy i NIE trzeba
zmieniać `DATASTORE_NAME`. Zmiana nazwy jest potrzebna tylko wtedy, gdy ktoś
testuje bezpośrednio na doświadczeniu produkcyjnym — czego nie robimy.

### Wypuszczenie nowej wersji

```powershell
rojo build default.project.json --output build/FishinGame.rbxl
```

1. Otwórz `build/FishinGame.rbxl` w Studio (Plik → Otwórz z pliku)
2. **Plik → Opublikuj w Roblox jako…** (Publish to Roblox As…)
3. Wybierz **istniejące** doświadczenie z listy, nie „Create new" —
   nowe utworzyłoby trzecią grę z osobnym linkiem i osobnymi danymi
4. Potwierdź nadpisanie

### Udostępnienie osobom spoza zespołu

**To jest krok, bez którego nic nie zadziała.** Samo „Publish" NIE udostępnia
gry nikomu — tworzy tylko wersję na serwerach Robloxa. Dopóki doświadczenie
jest **Private**, wejdą do niego wyłącznie osoby z uprawnieniami do edycji;
każdy inny zobaczy „this experience is not available".

Creator Dashboard → twoja Experience → **Settings → Permissions**
→ Playability: **Public** → Save.

Potem wystarczy link:

```
https://www.roblox.com/games/<PLACE_ID>
```

`PLACE_ID` jest w adresie strony doświadczenia w Creator Dashboard. Odbiorca
klika, wchodzi, gra w kliencie Robloxa — bez Studio, bez gita, bez niczego.

#### Experience Guidelines (kwestionariusz wieku)

Roblox pyta o rodzaj treści w grze. **Nie blokuje to udostępnienia linkiem** —
doświadczenie bez wypełnionego kwestionariusza jest traktowane jak **13+**
i dorosły odbiorca z kontem wejdzie bez problemu.

Kwestionariusz ma znaczenie dla ZASIĘGU: żeby gra była widoczna dla młodszych
graczy i wyświetlała się szerzej w wyszukiwarce, Roblox wymaga wypełnienia
guidelines, a dla kategorii „all ages" dodatkowo progu zaangażowania
(ok. 250 kwalifikowanych wejść w 60 dni) albo jednorazowej opłaty.

Do pokazania gry zespołowi albo rekruterowi nie trzeba nic z tego —
wystarczy Playability: Public.

#### Alternatywa: bez upubliczniania

Jeśli gra ma zostać prywatna, dodaj odbiorców imiennie:
Creator Dashboard → Experience → **Permissions → Collaborators** → wpisz ich
nazwy użytkownika Robloxa → rola **Play**.

Wymaga znajomości ich nazw i tego, żeby mieli konta. Przy jednorazowym pokazie
Public jest prostszy; przy wewnętrznym buildzie — odwrotnie.

### Które doświadczenie: DEV czy osobne

Trzymaj dwa:

- **FishinGame DEV** — Private, do testów ze Studio z włączonym API
- **FishinGame** — Public, to co dostaje odbiorca

Powód jest praktyczny: DataStore należy do doświadczenia, więc gdy testujesz
w Studio podpiętym pod to samo doświadczenie, twoje testowe konto ląduje
w tym samym rankingu, co prawdziwi gracze. Rekruter otwierający ranking
zobaczyłby „janrzepkowski — 9 999 999 monet" z testu balansu.

### Gracze nie widzą zmian po publikacji

To nie jest błąd. Serwery, które już działają, mieszczą starą wersję
i migrują na nową stopniowo przez kilka–kilkanaście minut. Żeby wymusić
natychmiast: Creator Dashboard → Experience → **Shut Down All Servers**.

### Kto publikuje

**Jedna osoba**, po merge'u do `main`. Dwie osoby publikujące z własnych
gałęzi to gwarantowany bałagan w tym, co właściwie jest na produkcji.

Roblox trzyma historię wersji: Creator Dashboard → Experience → **Versions**.
Da się wrócić do poprzedniej, gdy coś wyjdzie krzywo.

Alternatywa na później, gdy publikacja zacznie się zdarzać często: Open Cloud
API key i `rbxcloud` w CI. Nie na tym etapie — ręczne publikowanie raz na kilka
dni jest tańsze niż utrzymywanie pipeline'u.

## Gdy coś nie działa

**Plugin nie widzi serwera**

- czy `rojo serve` faktycznie chodzi? `curl http://localhost:34872/api/rojo`
  powinno zwrócić JSON
- Allow HTTP Requests w Studio — włączone?
- antywirus / firewall blokuje `localhost:34872`?
- inny `rojo serve` już zajmuje port — sprawdź, zanim odpalisz na innym

**„Place ID mismatch"**

Projekt ma przypięte `servePlaceIds`, a otwarte miejsce ma inne ID. W tym repo
nie przypinamy ID, więc jeśli to widzicie, ktoś dopisał je do
`default.project.json` — usuńcie albo dopiszcie swoje.

**Otworzyłem `build/FishinGame.rbxl` i zmiany nie działają**

Studio **nie przeładowuje** otwartego pliku, gdy `rojo build` nadpisze go na
dysku. Trzymasz w pamięci kopię sprzed zmian i możesz klikać Play dowolną
liczbę razy — zobaczysz starą wersję.

Plik `.rbxl` jest do publikacji, nie do codziennej pracy. Do pracy używaj
`rojo serve` + pusty Baseplate + Connect: wtedy każda zmiana trafia do Studio
od razu, a Shift+F5 → F5 przebudowuje świat.

Gdy już musisz testować z pliku: zamknij go **bez zapisywania**, zbuduj
od nowa, otwórz ponownie. W tej kolejności.

**Zmiany w plikach nie docierają do Studio**

- plugin pokazuje „Connected"? Po restarcie Studio trzeba połączyć ponownie
- zmiana jest w pliku, który Rojo w ogóle widzi? Rojo czyta `.luau`, `.lua`,
  `.json`, `.model.json`, `.rbxm`, `.rbxmx`, `.txt`, `.csv` — inne rozszerzenia ignoruje
- czy plik jest pod ścieżką z `default.project.json`? Plik poza `src/` nie trafi nigdzie

**Skrypt działa w Studio, nie działa po publikacji**

Prawie zawsze DataStore albo `RunService:IsStudio()`. Sprawdźcie Output
opublikowanej gry przez Developer Console (F9) w uruchomionej grze.

**Po Rojo sync gra zachowuje się dziwnie, ale restart pomaga**

Sync podmienia skrypty w działającym miejscu, ale nie czyści stanu, który już
powstał. `WorldBuilder.build()` jest idempotentne (kasuje stary świat), ale
połączenia eventów z poprzedniej wersji skryptu nadal wiszą. Przy zmianach
w `init.server.luau` albo w `start()` któregokolwiek serwisu — zatrzymaj test
(Shift+F5) i odpal od nowa.

## Czego nie używamy

**Team Create — wyłączony.** Przy Rojo każdy pracuje na własnej lokalnej kopii
Studio, a prawda jest w `src/`. Team Create robiłby drugie, równoległe źródło
prawdy i wygrywałoby to, które ktoś zapisał później. Jeśli ktoś je włączy,
dwie osoby zaczną nadpisywać sobie drzewo instancji w czasie rzeczywistym,
a `rojo serve` będzie z tym walczył.

**Edycja skryptów w Studio.** Pisz w edytorze, nie w Studio. To, co napiszesz
w Studio, nie trafi do gita i zginie przy najbliższym sync.
