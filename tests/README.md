# Tesztek

Két réteg: **offline** (ezen a gépen, játék nélkül) és **játékon belüli** (`/ak selftest`).

## Offline: lint + smoke tesztek

Egy parancs a repó gyökeréből (PowerShell):

```powershell
powershell -ExecutionPolicy Bypass -File tests\run.ps1
```

- `-NoLint`: csak a smoke tesztek
- `-Verbose`: a tesztelő a chat kimenetet és az automatikusan stubolt globálisokat is kiírja

Kilépési kód: 0 = minden rendben, 1 = hiba, 2 = nincs Lua.

### Lua kell hozzá (5.1 / LuaJIT)

A `run.ps1` ebben a sorrendben keres:

1. `$env:LUA` (egy lua.exe útvonala)
2. `tests\bin\lua5.1.exe` vagy `tests\bin\lua.exe`
3. `lua5.1`, `lua51`, `luajit`, `lua` a PATH-on
4. `$env:LUA_DLL`: egy meglévő 64 bites `lua51.dll` (LuaJIT). Ezt a `tests\luahost.ps1` futtatja a PowerShellen belül, így nem kell semmit telepíteni. Ezen a gépen ilyen DLL van az OBS / PRISM Live Studio mellett:

  ```powershell
  $env:LUA_DLL = "$env:LOCALAPPDATA\PRISMLiveStudio\bin\64bit\lua51.dll"
  powershell -ExecutionPolicy Bypass -File tests\run.ps1
  ```

  Tartósan: Gépház > Rendszer > Speciális > Környezeti változók, ott vedd fel a `LUA_DLL` változót.

A tisztább megoldás egy hordozható Lua 5.1: a LuaBinaries `lua-5.1.5_Win64_bin.zip` csomagja (sourceforge.net/projects/luabinaries). A benne lévő `lua5.1.exe` és `lua5.1.dll` menjen a `tests\bin\` mappába.

### Mit csinál

- **`tests\lint.ps1`** (Lua nélkül is fut):
  - lezáratlan string;
  - blokk- és zárójel-egyensúly;
  - egy backslash-es textúra útvonal (`"Interface\Icons"`);
  - `local a, b = x and f()` csonkolás;
  - véletlen globálisok (heurisztika);
  - a .toc fájlokban felsorolt fájlok léteznek-e.
- **`tests\run.lua`**:
  - A 3 addont .toc sorrendben tölti be `(ADDON_NAME, NS)` paraméterekkel egy hamis WoW API-n (`wowstub.lua`) és egy hamis Questie-n (`fake_questie.lua`).
  - Elküldi az ADDON_LOADED / PLAYER_LOGIN / PLAYER_ENTERING_WORLD eseményeket.
  - Utána ellenőrzi:
    - a betöltés hibamentes, nincs véletlen globális;
    - a .toc verzió egyezik a release notes tetejével;
    - a makró első sora megtartja az élő ellenséges célpontot, a nameplate mód és a leadás is helyes, a makró 255 karakter alatt marad, harcban késleltetve íródik;
    - a SelectQuest / ◀ ▶ átugrás szabályai;
    - a táska lépcsők (10 / 5 / 2 szabad hely);
    - a városban vagy-e (fogadó, pihenés, hálózsák, taxi);
    - a ping módok;
    - a dungeon prep indítása, megszakítása és a visszaállítás;
    - az utazási útvonal (Dijkstra);
    - a TomTom opcionális;
    - egy sor eseményre és a slash parancsokra nincs Lua hiba;
    - a tooltipek;
    - minden `L["..."]` kulcsnak van értéke.

### Mit nem tud

- Megjelenítés, elrendezés, betűk, textúrák: a keretek csak csonkok.
- Valódi secure frame-ek és taint, védett hívások, combat lockdown (csak az `InCombatLockdown()` jelzőt utánozza).
- Valódi Questie adat, valódi térkép- és világkoordináták, más addonok (Bagnon, Journal).
- A hamis világban csak néhány uiMap van, ezért a selftest „Dungeon entrances” pontja itt elbukik. Ez várható, a teszt ezt nem számítja hibának.

## Játékban: `/ak selftest`

Az élő adatokon ellenőrzi:

- a Questie be van-e töltve;
- a CollectTargets hiba nélkül fut-e a log minden questjére;
- a makró minden questre 255 karakter alatt marad-e;
- megvan-e a CharDB;
- a TomTom (opcionális) rendben van-e;
- a dungeon bejáratok érvényes uiMap-re mutatnak-e;
- a hajó / zeppelin tábla pontjai érvényesek-e.

Egy sor összegzést ír, részleteket csak hiba esetén.
