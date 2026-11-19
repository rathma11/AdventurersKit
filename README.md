# Adventurer's Kit

**A questing kit for WoW: Forever, built on Questie.** One key targets the mobs your quests need, a
marker points the way, and a route plans the next quests, zones and boat rides for you. Around the
questing it handles the errands: what to do in town, which dungeon to prepare for, which buff ran out,
which quest item is in your bags, and how well a farming spot pays.

> Game flavor: **WoW: Forever** (client 1.60.1, Interface 16001). Requires **Questie**.

<!-- Screenshots: add them on CurseForge under Images (quest panel, AKit macro target, city list,
     dungeon prep, buff reminder, farm session). -->

## Features

### Quest focus and targeting
- **Quest panel:** the focused quest with its objectives, time left and pace, the other quests nearby and your route.
- **AKit macro:** one key targets a living quest mob of your objectives (and of quests nearby), and keeps a living enemy you clicked.
- **Nameplate mode:** with enemy nameplates on, the macro picks a quest mob nobody has tapped.
- **Zone focus:** only the current zone's quests in the tracker (`/ak zone`).

### Markers, route and travel
- **Markers:** the built-in arrow or a TomTom waypoint to the nearest spot of the current objective; empty spawn points are skipped for 5 minutes.
- **◀ ▶ stepping** through the route, with skip rules for quests you want to leave for later.
- **Route and next zone:** your quests in nearest-next order, and where to go next ("Hearth back" when that is fastest).
- **Travel planning** with boats, zeppelins, the tram and the Hearthstone, including WoW: Forever's own routes.

### Pace, escorts and pickups
- **Pace:** your kill pace is learned (per group size) and every quest gets a time-left estimate.
- **Escort quests:** the escort's health and destination, and the macro targets whatever attacks it.
- **Quest nearby popup:** a quest you can pick up close by, with its estimated length.

### Towns and dungeons
- **City list:** quests to pick up in town (XP, chain step, dungeon tags), errands (repair, ammo, XP food, full bags) and directions to the bank, auction house, flight master, inn, trainers.
- **Dungeon list and prep:** the dungeons for your level (WoW: Forever's own dungeons included), a checklist of their quests, the entrance on the map, and every objective in boss order inside.
- **Share popup:** offers to share your dungeon quests with the party.

### Modules
- **Buffs:** reminder for sleeping bag, XP food, weapon enchants (stones, oils, poisons, imbues), class buffs and tracking; bag space, repair and "vendor nearby" warnings.
- **Bags:** quest item list next to the bags (Bagnon highlight), use buttons with a key binding, `/ak junk` for leftovers.
- **Farm session:** time, XP per hour and ETA to level (rested XP counted), kills, gold and item value (AH price when available), and a summary at the end.
- **Auction house:** a Quest items tab with the items your quests still need and their cheapest price.

### Settings
- Per-character settings, profile export / import as text, and `/ak selftest`.

## Commands

| Command | What it does |
|---|---|
| `/ak` | show / hide the quest panel |
| `/ak options` | settings |
| `/ak next \| all \| mark \| unmark \| clear` | objectives, marker and focus |
| `/ak ping` | ping mode (ask / always / never) |
| `/ak zone` | zone focus on / off |
| `/ak city` | city list |
| `/ak dungeon [name \| off]` | dungeon list, dungeon prep |
| `/ak farm [stop \| pause \| resume \| reset]` | farm session |
| `/ak bags \| junk` | quest item list, destroy leftover quest items |
| `/ak export \| import` | share settings |
| `/ak notes` | release notes |
| `/ak selftest \| debug \| copy` | self test and diagnostics |

`/qf` works as an alias of `/ak`.

## Getting started
1. Install **Questie** and Adventurer's Kit (three folders: `AdventurersKit`, `AdventurersKit_Bags`, `AdventurersKit_Buffs`). The Bags and Buffs modules are optional.
2. In game, open the quest log and click a quest. This creates the **AKit** macro.
3. Type `/macro`, find **AKit** under General Macros and drag it to an action bar. Press it to target your quest mobs.

## Requirements
- **Required:** [Questie](https://www.curseforge.com/wow/addons/questie) (the quest database).
- **Optional:** TomTom (arrow), Bagnon (bag highlight), Auctionator / TradeSkillMaster / Auctioneer (AH prices), DungeonJournal (opens a dungeon there on Shift+click).

## Credits and license
Adventurer's Kit is free software under the **GNU GPL v3** (or later), see `LICENSE.md`.
It carries small copies of data from **Questie** (GPL-3.0, the Questie team), **DungeonJournal** by
**Exehn** (dungeon bosses, quests and entrances) and **OpenMap** (MIT, OpenMap contributors: boat,
zeppelin and tram ports). Details are in `AdventurersKit/CREDITS.txt`.
World of Warcraft is a trademark of Blizzard Entertainment, Inc.

Changes per version: [CHANGELOG.md](CHANGELOG.md).
