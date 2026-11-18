# Adventurer's Kit: features

A questing kit for WoW: Forever built on Questie: it picks your next quest target, points the way, plans
the route and handles the errands around it (towns, dungeons, buffs, bags, farming, the auction house).
The same list is in game under Options > About. Changes per version: `AdventurersKit\UI\ReleaseNotes.lua`
(Options > Release notes, `/qf notes`).

## Quest focus and targeting

- **Quest panel:** the focused quest with its objectives, the quests also nearby and your route, in a fixed-size panel.
- **QFocus macro:** one key targets a living quest mob of your objectives (and of nearby quests), and keeps a living enemy you clicked.
- **Nameplate mode:** with enemy nameplates on, the macro picks a quest mob nobody has tapped from the visible nameplates; otherwise it targets by name.
- **Ping modes:** the macro pings its target always, never, or asks when you join a group (`/qf ping`).
- **Zone focus:** only the current zone's quests in the tracker, with a prompt when you enter another zone (`/qf zone`).

## Markers

- **Markers:** the addon's own arrow or a TomTom waypoint points to the nearest spot of the current objective; the map button opens the world map there.
- **Spawn hopping:** an empty spawn point counts as checked for 5 minutes and the marker moves on to the next one.

## Quest stepping

- **◀ ▶ arrows** (with key bindings) step to the next stop of the route, or back through the quests you focused before.
- **Skip rules:** a skipped quest waits at the end of the route (saved per character) and comes back when you pick it, it makes progress, you get near its target, or you turn in a quest.

## Route and travel

- **Route:** the quests in your log in nearest-next order, with the distance from you.
- **Next zone:** go where most of your quests are, or to the nearest zone with quests for your level; "Hearth back" when the Hearthstone is fastest.
- **Travel planning** counts boats, zeppelins, the tram and the Hearthstone, with WoW Forever's own transport routes.

## Pace and time left

- **Pace:** your kill pace is learned (per group size) and every quest gets a time-left estimate.

## Escort quests

- **Escorts:** the panel shows the escort's health and destination, the macro targets whatever attacks it, and a star marks the escort NPC.

## Dungeons

- **Dungeon list:** the dungeons for your level with their quests, WoW Forever's own dungeons included (`/qf dungeon`).
- **Dungeon prep:** a checklist of the dungeon's quests to pick up (chain steps too), then the entrance on the map.
- **Inside the dungeon:** every objective in boss order, the next step highlighted and its mobs in the macro.
- **Share popup:** in a group, entering the dungeon offers to share your dungeon quests with the party.

## City list

- **City list:** in towns and villages, the quests to pick up nearby with XP, chain step and dungeon tags (town icon or `/qf city`).
- **Errands:** repair, ammo, XP food and full bags, each with the nearest NPC to mark.
- **Directions:** like asking a guard, the nearest bank, auction house, flight master, inn, trainers or repairer.
- **Auto-open:** the list opens by itself in towns (can be turned off) and closes when you walk away.

## Quest pickup popup

- **Quest nearby:** out in the world a draggable popup shows a quest you can pick up nearby, with its estimated length; click marks the quest giver.

## Buff reminder (Buffs module)

- **Consumables:** sleeping bag, XP food and your own items or buffs, with how many you have left.
- **Weapon enchants:** stones, oils, poisons, scrolls and shaman imbues, picked to fit the weapon in your hand.
- **Class buffs and tracking:** your own class buffs, and gathering tracking first.
- **Outside warnings:** bags filling up, worn gear and "Vendor nearby", with a marker to the nearest vendor or repairer.

## Bags module

- **Quest items:** a list next to the bags (Bagnon coloring, click to highlight), use buttons on objective rows with a key binding, and `/qf junk` for leftovers.

## Farm session

- **Farm session:** time, XP per hour with an ETA to level, kills, looted gold and item value (auction price if available), and a summary when you stop (`/qf farm`).

## Auction house

- **Quest items tab:** the items your quests still need with the cheapest price; click to search, Buy / Buy all with one confirmation.

## Settings

- **Per-character settings:** buffs, skipped quests, dungeon prep and the farm session are kept per character.
- **Profile export / import:** your settings as text to share (`/qf export`, `/qf import`).
- **Self test:** `/qf selftest` checks your live data and prints one summary line.

## Main commands

| Command | What it does |
|---|---|
| `/qf` | show / hide the quest panel |
| `/qf options` | settings |
| `/qf next \| all \| mark \| unmark \| clear` | objectives, marker and focus |
| `/qf ping` | ping mode (ask / always / never) |
| `/qf zone` | zone focus on / off |
| `/qf city` | city list |
| `/qf dungeon [name \| off]` | dungeon list, dungeon prep |
| `/qf farm [stop \| pause \| resume \| reset]` | farm session |
| `/qf bags \| junk` | quest item list, destroy leftover quest items |
| `/qf export \| import` | share settings |
| `/qf notes` | release notes |
| `/qf selftest \| debug \| copy` | self test and diagnostics |
