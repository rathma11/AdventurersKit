# QuestFocus (WoW: Forever)

Kell hozzá: **Questie**. A TomTom nem kötelező: ha fent van, annak a nyilát használja.

## Első indítás
1. Indítsd a játékot. A karakterválasztóban az **AddOns** gombnál pipáld be a QuestFocust. Ha „out of date” jelzést látsz, pipáld be a **Load out of date AddOns** opciót is.
2. Nyisd meg a quest logot (L), és kattints egy questre. Ekkor létrejön a **QFocus** macro.
3. Írd be: `/macro`. A **General Macros** fülön keresd meg a QFocus-t, és húzd fel az actionbarra. Ezt csak egyszer kell megtenni.

## Használat
- **Kattintás egy questre a quest logban:** a QFocus macro ezután a quest mobjaira targetel, és a legközelebbi helyre marker kerül (TomTom nyíl vagy saját nyíl).
- **Egér a quest fölött a logban:** a tooltipben látod a mobokat és itemeket, a zónát, a koordinátát és a távolságot.
- **Panel:** egy kis ablakban látszanak a quest objective-jei.
  - Bal klikk egy objective-re: a marker és a macro csak arra az objective-re vonatkozik.
  - Jobb klikk: a macro újra az összes hátralévő objective-re vonatkozik.
- **Kész quest:** a macro és a marker automatikusan a leadó NPC-re vált.
- Harc közben a WoW nem engedi módosítani a macrót, ezért az addon harc után frissíti.
- **Csak élő, még senki által nem tapolt mobot targetel**, ha az ellenséges nameplate-ek be vannak kapcsolva (V gomb). A választás a látható nameplate-ek közül történik. Ha a nameplate-ek ki vannak kapcsolva, a macro név alapján targetel: a hullát átugorja, de a más által tapolt mobot nem tudja kiszűrni, erre piros figyelmeztetés jelenik meg.

## Parancsok
| Parancs | Mit csinál |
|---|---|
| `/qf` | panel ki/be (X-szel bezárva is visszajön, ha questre kattintasz a logban) |
| `/qf options` | beállítások ablak (Options → AddOns → QuestFocus), van Debug füle is |
| `/qf zone` | zóna fókusz ki/be: csak az aktuális zóna questjei maradnak a Questie trackerben |
| `/qf minimap` | minimap gomb ki/be |
| `/qf bags` | quest item lista a táska mellett ki/be |
| `/qf debug` | diagnosztika a chatbe |
| `/qf spell <név>` | tap spell a macroba (pl. `/qf spell Moonfire`); `/qf spell` = törlés, `/qf spell off` = kikapcsolás |
| `/qf next` | következő objective (marker + macro); érdemes erre is egy macrót csinálni |
| `/qf all` | macro az összes hátralévő mobra |
| `/qf mark` | marker újra a legközelebbi helyre |
| `/qf arrow` | saját nyíl ki/be (TomTom mellett nem jelenik meg) |
| `/qf ping` | ping a targetelt mobra/NPC-re a macroban ki/be (alapból be; partyban a többiek is látják) |
| `/qf icon <ikonnév>` | saját ikon a macronak (pl. `/qf icon inv_misc_map_01`); `/qf icon` = vissza automatikusra |
| `/qf unmark` | marker törlése (TomTom + térkép pin + nyíl) |
| `/qf clear` | kijelölés + marker törlése |

**Markerek automatikus törlése:** ha egy objective kész, a marker a következő hátralévő célra ugrik. Ha a quest kész, a leadó NPC-re kerül. Ha leadtad (vagy abandon), a marker törlődik. A saját nyílra jobb klikk szintén törli.

## Minimap gomb és zóna fókusz
- **Minimap gomb:** bal klikk megnyitja a beállításokat, jobb klikk a zóna fókuszt kapcsolja. Húzással áthelyezhető.
- **Zóna fókusz:** csak az aktuális zóna questjei (és a kijelölt QFocus quest) maradnak a Questie trackerben, a többit kiveszi. Zónaváltáskor automatikusan követ. Kikapcsoláskor minden visszakerül úgy, ahogy volt. A zónát a quest log fejléce alapján dönti el. Összecsukott fejléc alatti questeket nem lát.

## Quest item lista a táska mellett
Ha nyitva a táska (Bagnon vagy a sima Blizzard táska), a bal oldalán megjelenik egy lista a quest itemekről:
- **sárga:** melyik questhez kell, és hol tartasz (pl. 5/7), vagy „kész, leadni”;
- **zöld:** questet indít (jobb klikk rá a táskában);
- **szürke:** nincs hozzá aktív quest, valószínűleg eladható vagy eldobható.

Egérrel fölé állva látod az item tooltipjét, klikkre a quest kijelölődik (marker + QFocus macro). Kikapcsolás: `/qf bags` vagy a beállításokban.

## Beállítások (opcionális)
Esc → Options → AddOns → **QuestFocus**, vagy `/qf options`. Alapból minden új opció ki van kapcsolva.
- **Spell a macroban (tapelés):** húzz egy spellt a spellbookból (P) a négyzetbe, vagy írd be a nevét. Ezután a QFocus a target után el is süti a mobra (pl. Moonfire, Arcane Shot, Shoot). Leadásnál nem castol.
- **Autoattack:** a target után automatikus támadás is indul.
- **Ping** és **saját nyíl** ki/be (ugyanaz, mint a `/qf ping` és a `/qf arrow`).

A macro ikonja automatikusan vált: **célkereszt**, amíg mobokat kell ölni vagy itemet gyűjteni, **levél**, amikor kész a quest és le kell adni, **térkép**, ha nincs kijelölt quest.
