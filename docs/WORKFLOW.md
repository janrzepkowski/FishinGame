# Jak pracujemy w trójkę

Dokument opisuje proces, nie kod. Kod jest w [ARCHITECTURE.md](ARCHITECTURE.md).

## Model gałęzi

Trunk-based: jedna żywa gałąź `main`, wszystko inne krótkie i jednorazowe.

```
main ─────●──────●──────●──────●────>
           \    /        \    /
            ●──●          ●──●
       feat/sklep    fix/spławik
```

**Dlaczego nie GitFlow** (`develop` + `release/*` + `hotfix/*`): GitFlow płaci
za siebie przy wydaniach wersjonowanych i wielu wspieranych gałęziach. W Robloxie
publikujecie jedno miejsce jednym przyciskiem. Dodatkowa gałąź `develop` dałaby
wam drugie miejsce do mergowania i zero korzyści.

### Nazwy gałęzi

```
feat/   nowa funkcjonalność      feat/dzienne-zadania
fix/    naprawa buga             fix/splawik-zostaje-po-smierci
refac/  przebudowa bez zmiany zachowania
chore/  narzędzia, CI, wersje    chore/rojo-7.7.2
docs/   dokumentacja
```

### Rozmiar gałęzi

**Jeden PR = jedna rzecz, maksymalnie 2-3 dni pracy.**

To nie jest estetyka, to arytmetyka. Przy trzech osobach i gałęziach żyjących
po dwa tygodnie każdy merge to konflikt na kilkuset liniach. Przy gałęziach
dwudniowych konfliktów praktycznie nie ma, bo nikt nie zdąży odejść daleko.

Gdy zadanie jest większe, podziel je na PR-y, które da się złożyć osobno —
np. najpierw konfiguracja i typy, potem logika serwera, potem UI.

## Cykl pracy

```powershell
# 1. Zacznij od świeżego main
git switch main
git pull

# 2. Nowa gałąź
git switch -c feat/dzienne-zadania

# 3. Pracuj. rojo serve trzymaj włączone.
rojo serve

# 4. Przed commitem — bramka jakości
stylua src
selene src
#   + analiza typów; w Claude Code wystarczy /sprawdz

# 5. Commit
git add -A
git commit -m "Dodaj dzienne zadania za złowienie 5 ryb"

# 6. Push i PR
git push -u origin feat/dzienne-zadania
gh pr create --fill
```

### Codziennie: rebase na main

```powershell
git switch main; git pull
git switch feat/dzienne-zadania
git rebase main
```

Rebase, nie merge — historia `main` zostaje liniowa, a `git log` czytelny.
Jeśli gałąź jest już wypushowana, po rebase potrzebny jest
`git push --force-with-lease` (nie `--force`: `--force-with-lease` odmówi,
gdy ktoś w międzyczasie dopisał coś do twojej gałęzi).

## Recenzje

**Każdy PR potrzebuje jednej akceptacji. Nikt nie merguje własnego PR-a bez niej.**
Przy trzech osobach to zasada praktyczna, nie biurokracja: zawsze są dwie osoby,
które mogą spojrzeć, i zawsze ktoś drugi wie, co się zmieniło.

Czego szukać w recenzji (po kolei, od najdroższych błędów):

1. **Czy serwer waliduje wejście z klienta?** Każdy `OnServerEvent` musi sprawdzić
   `typeof` argumentów, a potem stan (profil, cooldown, odległość). To jedyna
   klasa błędów, która kończy się zepsutą ekonomią u wszystkich graczy.
2. **Czy profil zmieniany jest przez `DataService.mutate`?** Zmiana z boku rozjedzie
   UI z serwerem.
3. **Czy da się to zepsuć wychodząc z gry w połowie operacji?** `task.delay`
   i `task.wait` to miejsca, gdzie gracz może zniknąć.
4. Czy nie ma plików binarnych i generowanych.
5. Czy komentarze mówią *dlaczego*, a nie *co*.

Czego **nie** komentować: formatowania (robi to StyLua), nazw zmiennych bez
realnego powodu, stylu, który jest już ustalony w `CLAUDE.md`. Spór o styl
rozwiązujemy zmieniając konfigurację, nie komentarzem na PR-ze.

## Podział odpowiedzialności

Nie chodzi o własność („nie dotykaj mojego folderu") — każdy może pracować wszędzie.
Chodzi o to, żeby trzy osoby rzadko pisały w tych samych plikach jednocześnie.

| Obszar | Główna osoba | Pliki |
|---|---|---|
| Serwer, dane, ekonomia | **janrzepkowski** | `src/server/` |
| Klient, UI, odczucia z gry | **dev2** | `src/client/` |
| Balans, treść, świat | **dev3** | `src/shared/Config/`, `src/server/World/` |

Routing recenzji jest w `.github/CODEOWNERS` — **podmieńcie tam `@dev2` i `@dev3`
na prawdziwe nicki z GitHuba**, inaczej wpisy są ignorowane.

### Pliki, w których konflikty bolą najbardziej

`src/shared/Net.luau` i `src/shared/Types.luau` to kontrakt klient-serwer. Gdy dwie
osoby dodają tam naraz, konflikt jest pewny, a sklejenie go bywa podstępne
(oba Remote'y wyglądają poprawnie, ale jeden serwis nasłuchuje nie tego, co trzeba).

Umowa: **zmianę w tych dwóch plikach zgłaszasz zespołowi przed rozpoczęciem pracy**.
Jedno zdanie na czacie wystarczy. To pięć sekund zamiast pół godziny rozplątywania.

## Co ustawić na GitHubie (jednorazowo)

Settings → Branches → Add branch protection rule dla `main`:

- [x] **Require a pull request before merging**
  - [x] Require approvals: **1**
  - [x] Dismiss stale pull request approvals when new commits are pushed
  - [x] Require review from Code Owners
- [x] **Require status checks to pass before merging**
  - [x] Require branches to be up to date before merging
  - Wybierz checki: `Lint, typy, build` oraz `Pliki zabronione`
    (pojawią się na liście po pierwszym przebiegu CI — najpierw zmergujcie
    cokolwiek, potem wróćcie i je zaznaczcie)
- [x] **Require linear history** — wymusza squash/rebase merge
- [ ] Allow force pushes — **zostaw wyłączone**
- [ ] Allow deletions — **zostaw wyłączone**

Settings → General → Pull Requests:

- [x] Allow squash merging — **zostaw tylko to**
- [ ] Allow merge commits — wyłącz
- [ ] Allow rebase merging — wyłącz
- [x] Automatically delete head branches

Squash merge oznacza: jeden PR = jeden commit na `main`. Historia czyta się jak
lista zmian w grze, a nie jak dziennik czyjejś pracy („wip", „fix", „no teraz").

Settings → Collaborators → dodaj pozostałe dwie osoby z rolą **Write**
(nie Admin — Admin pozwala obejść branch protection).

## Dodawanie osoby do zespołu

1. GitHub: Collaborators → rola Write.
2. Roblox: przy Rojo **nie trzeba** dawać dostępu do miejsca, żeby pisać kod.
   Dostęp do miejsca (Configure Experience → Permissions) potrzebny jest tylko
   do publikacji i podglądu danych na produkcji.
3. Niech przejdzie sekcję „Start w 5 minut" z [README](../README.md).
4. Niech przeczyta `CLAUDE.md` — tam są zasady, których nie łamiemy.
5. Pierwsze zadanie: coś małego w swoim obszarze, przeprowadzone przez cały
   cykl (gałąź → PR → recenzja → merge). Chodzi o przejście procesu, nie o kod.

## Gdy coś się zepsuje

**Konflikt w `src/`** — rozwiązujesz ty, autor gałęzi. Po `git rebase main`
i rozwiązaniu konfliktu **uruchom bramkę jakości ponownie**. Sklejony ręcznie
kod Luau potrafi się kompilować i jednocześnie nie mieć sensu.

**CI pada na `main`** — ma pierwszeństwo nad wszystkim innym. Zepsuty `main`
blokuje całą trójkę.

**Zepsuta publikacja** — Roblox trzyma historię wersji miejsca
(Creator Dashboard → Experience → Versions). Da się wrócić do poprzedniej.
Repo i opublikowana wersja to dwie osobne rzeczy: `git revert` nie cofa publikacji.
