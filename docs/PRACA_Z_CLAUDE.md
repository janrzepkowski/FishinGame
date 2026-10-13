# Praca z Claude nad grą — poradnik i szablony

Jak zlecać pracę tak, żeby wynik był trafiony za pierwszym razem. Poradnik jest
ogólny: sekcje 1–6 pasują do każdego projektu w Roblox Studio, a to, co dotyczy
tylko FishinGame, jest w `CLAUDE.md` i `docs/`.

Zasada nadrzędna: **Claude widzi tylko to, co mu pokażesz albo co jest w repo.**
Lista w Twojej głowie, gra, którą masz przed oczami, i „ten styl co zawsze"
dla niego nie istnieją, dopóki nie trafią do wiadomości albo do pliku.

## 1. Zanim zaczniesz sesję

- [ ] Czyste drzewo gita i właściwa gałąź (`feat/…`), świeżo po `git pull` z `main`.
- [ ] **Jedna sesja Claude na jedno zadanie.** Dwie sesje robiące to samo
      na różnych gałęziach kończą się dwiema wersjami nie do połączenia.
- [ ] `rojo serve` działa, a w Studio plugin Rojo pokazuje **Connected**.
- [ ] W Studio otwarte jest **to miejsce, na którym chcesz pracować** (plik
      lokalny i opublikowane „DEV" to dwa różne miejsca — Claude pracuje na tym,
      które jest otwarte).
- [ ] Do oceny światła i cieni: Studio Settings → Rendering → Quality Level
      ustawione ręcznie, nie „Automatic".

## 2. Szablon zlecenia

Skopiuj, wypełnij, wyślij jako jedną wiadomość. Puste pola usuń.

```markdown
## Cel
Jedno zdanie: co ma się zmienić dla gracza.

## Zakres
- Co zmieniamy: (ekrany, pliki, fragment mapy)
- Czego NIE ruszamy: (mechanika, balans, zapis danych…)

## Referencje stylu
1. [obraz] — biorę: … / nie biorę: …
2. [obraz] — biorę: … / nie biorę: …

## Referencje funkcji
- Gra + mechanika: … (link albo nagranie)
- Co w niej działa: wyzwalacz → reakcja → nagroda
- Co zmieniamy u nas: …

## Po czym poznam, że gotowe
- [ ] …
- [ ] …

## Decyzje, które zostawiam sobie
- (np. dźwięki, publikacja, merge do main)
```

## 3. Referencje stylu

**Obraz bez podpisu to zagadka.** Na jednym zrzucie jest paleta, kształty,
układ, czcionka i światło — Claude nie wie, o które Ci chodzi.

- Do każdego obrazu dopisz **co bierzesz** i **czego nie**:
  „biorę zaokrąglone bryły i pastele, nie biorę ciemnego nieba".
- Rozdziel referencje na kategorie i nie mieszaj ich w jednej wiadomości bez
  podpisu: **interfejs** (panele, przyciski), **świat** (mapa, modele),
  **światło i kolor**, **ruch** (animacje, efekty).
- 3–5 dobrych obrazów na kategorię wystarcza. Dwadzieścia się uśrednia.
- Wyślij **wszystkie naraz, na początku**. Referencja mapy dosłana po godzinie
  pracy oznacza przebudowę tego, co już stoi.
- Powiedz, dla kogo jest gra („dzieci 7–12") — to rozstrzyga setki drobnych
  decyzji bez pytania.
- Trwałe ustalenia zapisuj w `docs/art/ART_DIRECTION.md`. To ten plik
  rozstrzyga spory o wygląd w kolejnych sesjach, nie pamięć rozmowy.

Gdzie trzymać: `docs/art/refs/` z krótkim `README.md` (obraz → co z niego
bierzemy). Obrazy zmniejsz przed dodaniem; duże pliki trzymaj poza repo
i wklejaj link.

## 4. Referencje funkcji z innych gier

Claude nie zagra w tamtą grę. Opisz mechanikę jako **zachowanie**, nie jako
nazwę („zrób jak w Fisch" nic nie znaczy).

| Pole | Przykład |
|---|---|
| Gra i mechanika | Fisch — pasek holowania |
| Wyzwalacz | ryba bierze, gracz klika |
| Co robi gracz | trzyma przycisk, puszcza przy szarpnięciu |
| Co widzi i słyszy | pasek, ugięty kij, plusk |
| Nagroda | ryba, licznik, baner |
| Dlaczego to działa | napięcie rośnie, decyzja co pół sekundy |
| Co zmieniamy u nas | bez mikropłatności, prostsze dla dzieci |

- Najlepszym źródłem jest **krótkie nagranie albo 3–4 zrzuty po kolei**.
- Dopisz liczby, jeśli je znasz (czas trwania, szansa, zasięg).
- Zaznacz, co jest **konieczne**, a co „miło by było".
- Dłuższe analizy zapisuj w `docs/design/` (wzór: `FISHING_MECHANICS.md`).
- Kopiujemy **mechanikę**, nigdy grafikę, dźwięki ani nazwy z cudzej gry.

## 5. Skille, pluginy i MCP

**Skille** to gotowe instrukcje do typowych zadań. Większość Claude ładuje sam
po temacie rozmowy; możesz też wymusić: „użyj skilla `roblox-lighting`".

| Chcę… | Napisz |
|---|---|
| sprawdzić jakość przed commitem | `/sprawdz` |
| przygotować PR | `/przed-pr` |
| odpalić sync do Studio | `/sync` |
| dodać gatunek ryby | `/nowa-ryba <nazwa> [rzadkość]` |
| przegląd kodu | `/code-review` |
| znaleźć skill do czegoś | „czy jest skill do …?" |

Skille Roblox przydatne przy tej grze: `roblox-building` (mapa),
`roblox-lighting` (światło), `roblox-gui` (interfejs), `roblox-animation-vfx`
(efekty), `roblox-audio` (dźwięk), `roblox-performance`, `roblox-security`,
`roblox-publish-checklist` (przed publikacją).

**Roblox Studio MCP** pozwala Claude'owi uruchomić grę, zrobić zrzut, odczytać
konsolę i wykonać kod w Studio. Ograniczenia, o których warto wiedzieć:

- Zrzuty przychodzą z opóźnieniem 1–3 s — krótkich animacji nie złapią.
- Elementy „zawsze na wierzchu" (`AlwaysOnTop`) nie pojawiają się na zrzutach.
- Przy jakości „Automatic" na zrzutach może nie być cieni.
- Kod zarządzany przez Rojo Claude zmienia **na dysku**, nie w Studio.
- Jeśli sam grasz w trakcie testu, powiedz to — testowe zdarzenia Claude'a
  i Twoja rozgrywka nachodzą na siebie.

**Twoje własne powtarzalne zadania** zamieniaj w komendy: plik
`.claude/commands/<nazwa>.md` z opisem kroków staje się `/nazwa`.

## 6. W trakcie pracy

- **Jedna uwaga = jedna rzecz + zrzut.** Najlepiej z kursorem na problemie.
- Pisz, **co widzisz** i **co chcesz zobaczyć**, a nie tylko „popraw".
  „Spawn jest biały, nie widać koloru posadzki" jest lepsze niż „złe światło".
- Uwagi możesz dosyłać w trakcie — Claude uwzględni je bez przerywania.
- Gdy coś „zniknęło po poprawce", powiedz, jak było wcześniej. Naprawa jednej
  rzeczy (np. prześwietlenia) potrafi zepsuć inną (cienie).
- Listę rzeczy do zrobienia trzymaj w pliku, np. `docs/BACKLOG.md`:

```markdown
## Do zrobienia
- [ ] (P1) krótki opis — po czym poznam, że gotowe
- [ ] (P2) …
## W toku
## Zrobione
```

## 7. Na koniec sesji

1. `/sprawdz` — testy, formatowanie, lint, typy, build.
2. Commit na gałęzi, potem `/przed-pr` i PR do `main`. Bez pushowania wprost
   na `main`.
3. Zmiana wyglądu → `docs/art/ART_DIRECTION.md`. Zmiana zachowania gry →
   `docs/ARCHITECTURE.md`.
4. Jeśli Claude czegoś nie mógł sprawdzić (pisze to w podsumowaniu), obejrzyj
   to sam w grze.
5. **Publikacja należy do Ciebie.** Claude jej nie wykonuje; kroki są
   w `docs/ROBLOX_STUDIO.md`.

## 8. O czym łatwo zapomnieć

- [ ] **Dźwięk** — każdy klip ma mieć znane źródło i licencję. Dźwięki z cudzych
      gier odpadają.
- [ ] **Telefon** — większość graczy Robloxa gra na dotyku. Sprawdź układ
      w emulatorze urządzeń w Studio.
- [ ] **Noc i deszcz** — światło strojone w południe wygląda inaczej o północy.
- [ ] **Słabsze urządzenia** — cienie, bloom i cząstki znikają przy niskiej
      jakości; gra ma być czytelna bez nich.
- [ ] **Polskie znaki** — każdą nową czcionkę sprawdź na „ąćęłńóśźż".
- [ ] **Gra dla dzieci** — efekty nagrody tak, hazard nie: żadnych losowań
      za walutę ani zakładów. Wypełnij kwestionariusz treści przed publikacją.
- [ ] **Zapis danych** — zmiana w profilu gracza wymaga migracji; testuj na
      osobnym miejscu DEV, nie na danych graczy.
- [ ] **Bezpieczeństwo** — serwer nie ufa klientowi; nowy Remote przechodzi
      przez `shared/Net.luau`.
- [ ] **Pierwsze 30 sekund** — ekran ładowania, pierwsza podpowiedź, pierwsza
      ryba. Nowy gracz ocenia grę właśnie wtedy.
- [ ] **Zasady na stałe** — jeśli powtarzasz Claude'owi tę samą uwagę drugi
      raz, dopisz ją do `CLAUDE.md`.
