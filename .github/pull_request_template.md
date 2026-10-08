## Co to zmienia

<!-- Jedno-dwa zdania. Nie lista plików — to recenzent widzi w diffie. -->

## Dlaczego tak

<!-- Jeśli były inne opcje, napisz, którą odrzuciłeś i dlaczego.
     To najcenniejsza część opisu — diff pokazuje "co", nie "dlaczego". -->

## Jak to przetestowałem

<!-- Konkretnie. "Zarzuciłem 20 razy wędką startową, wypadły 3 niepospolite,
     sprzedałem połów, kasa zgadza się z sumą z ekwipunku."
     Nie: "przetestowane". -->

## Checklista

- [ ] `stylua src` i `selene src` przechodzą lokalnie
- [ ] Analiza typów przechodzi (`luau-lsp analyze ...`)
- [ ] Odpaliłem to w Studio, nie tylko zbudowałem
- [ ] Brak plików binarnych (`.rbxl`, `.rbxm`) poza `assets/`
- [ ] Brak plików generowanych (`sourcemap.json`, `globalTypes.d.luau`, `build/`)
- [ ] Nowe handlery `OnServerEvent` walidują argumenty przed użyciem
- [ ] Profil zmieniany wyłącznie przez `DataService.mutate`
- [ ] Nowe RemoteEventy są w `shared/Net.luau` z opisem payloadu
- [ ] Brak debugowych `print` i zakomentowanego kodu
- [ ] Zmiany w zachowaniu gry opisane w `docs/ARCHITECTURE.md` (jeśli dotyczy)

## Dla recenzenta

<!-- Na co patrzeć szczególnie? Czego nie jesteś pewien?
     Jeśli coś zostawiasz na później, napisz to tutaj, a nie w TODO w kodzie. -->
