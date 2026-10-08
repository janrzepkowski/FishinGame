---
description: Przygotuj zmiany do PR-a — bramka jakości, przegląd diffa, propozycja opisu
---

Przygotuj bieżące zmiany do pull requesta.

1. **Bramka jakości** — wykonaj to, co opisuje `.claude/commands/sprawdz.md`.
   Jeśli nie przechodzi, napraw i nie idź dalej.

2. **Przegląd własnego diffa** (`git diff main...HEAD`). Sprawdź konkretnie:
   - czy nie ma pliku binarnego (`.rbxl`, `.rbxm`) poza `assets/`,
   - czy nie wszedł `sourcemap.json`, `globalTypes.d.luau`, `roblox.toml`, `build/`,
   - czy każdy nowy handler `OnServerEvent` waliduje argumenty (`typeof`) przed użyciem,
   - czy profil jest zmieniany tylko przez `DataService.mutate`,
   - czy nowe RemoteEventy są w `shared/Net.luau` z opisem payloadu,
   - czy nowe pliki mają `--!strict`,
   - czy nie zostały `print` debugowe ani zakomentowany kod.

3. **Raport.** Wypisz, co znalazłeś. Rzeczy, które sam poprawiłeś — osobno od tych,
   które wymagają decyzji autora.

4. **Propozycja opisu PR-a** w formacie z `.github/pull_request_template.md`,
   gotowa do skopiowania.

Nie rób `git commit` ani `git push` bez wyraźnej prośby.
