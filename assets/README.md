# assets/

Jedyne miejsce w repo, gdzie wolno trzymać pliki `.rbxm` / `.rbxmx`.

`.gitignore` blokuje binaria Roblox w całym repo i robi wyjątek tylko dla tego
katalogu. CI pilnuje tego osobnym jobem (`Pliki zabronione`).

## Co tu trafia

Gotowe modele zrobione w Studio: mapa, budynki, modele wędek, animacje.
Rzeczy, które mają **jednego właściciela** i zmieniają się **rzadko**.

## Co tu NIE trafia

Plik miejsca (`.rbxl`). Nigdy. Generuje go `rojo build` do `build/`.

Nic, co da się opisać kodem. Mapa greybox jest w
`src/server/World/WorldBuilder.luau` właśnie dlatego, że kod się merguje,
a binarka nie.

## Jak dodać model

1. Zbuduj go w Studio.
2. Zaznacz → prawy przycisk → **Save to File** (albo File → Export Selection)
   → zapisz tutaj jako `.rbxm`.
3. Wystaw go w `default.project.json`, np. pod `"Workspace"`:
   ```json
   "Map": { "$path": "assets/Map.rbxm" }
   ```
4. W PR-ze napisz, **kto** jest właścicielem tego pliku.

Przy edycji: git nie zmerguje dwóch zmian w tym samym `.rbxm`. Umowa jest taka,
że jeden plik = jedna osoba naraz. Zgłoś na czacie, że bierzesz się za dany
model, zanim zaczniesz.

## Co tu jest

| Plik | Skąd | Właściciel |
|---|---|---|
| `NaturePack.rbxm` | Creator Store, darmowa paczka „Low Poly Nature Pack (Trees, Rocks & Foliage)" autorstwa Veedubmike1, asset `127731233099210` | @janrzepkowski |

`NaturePack.rbxm`: 29 modeli, 44 siatki. Audyt przed dodaniem: zero skryptów,
zdarzeń zdalnych, dźwięków, dekali i tekstur PBR. W grze trafia do
`ServerStorage.NaturePack`; modele stawia i przemalowuje na paletę
`src/server/World/Scenery.luau`.

Wtyczka Rojo nie przenosi `MeshId` przy synchronizacji na żywo. Jeśli po
`rojo serve` modele są pustymi klockami, `Scenery` zbuduje scenerię awaryjną
z prostych brył i powie o tym w Output — wtedy otwórz plik z `rojo build`.
