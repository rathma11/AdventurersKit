# Changelog

All notable changes to Adventurer's Kit (formerly QuestFocus). The same notes are in game:
Options > Release notes, or `/ak notes`. Generated from `AdventurersKit/UI/ReleaseNotes.lua`.

## 0.11.1 (2026-11-21)

- Options > Debug: an Enable all button before Copy all turns on the log of every section (when all are on, it reads Disable all and turns them off). Same as /ak debug all on | off.
- The Bags and Buffs modules have their own icons in the addon list: the compass with a bag or a glowing up arrow in the corner.
- AKit macro: a quest mob that is already your target (alive, not tapped) is always pinged, even when it is behind you or off screen and its nameplate is not visible.

## 0.11.0 (2026-11-19)

- Options > Debug: a section for each feature with a snapshot of what it sees, an optional log of its decisions, and Copy debug / Copy all for bug reports (/ak debug, /ak copy).
- AKit macro pings are simpler: pressing the button pings your target, turn-in and other friendly or neutral NPCs too. No ping when every nearby quest mob is tapped; attack pings stay out of combat only.

## 0.10.0 (2026-11-19)

- First public beta of Adventurer's Kit for WoW: Forever. Please report bugs with /ak copy all (paste the text into a CurseForge comment or a GitHub issue).
- Quest focus and targeting: a quest panel with objectives, progress, time left and kill pace; the AKit macro targets a living, untapped quest mob with one key, also for quests nearby.
- Markers and route: an arrow (built-in or TomTom) to the nearest spot; your quests in nearest-next order, the next zone and travel time with boats, zeppelins, the tram and the Hearthstone.
- Towns: a city list with quests to pick up, errands (repair, ammo, XP food, full bags) and directions to the bank, auction house, flight master, inn and trainers.
- Dungeons: the dungeons for your level, WoW: Forever's own included, with a quest checklist, the entrance on the map and objectives in boss order inside.
- Modules: a buff reminder, a quest item list next to your bags, a farm session (XP and gold per hour, time to level) and a Quest items tab at the auction house.
- Earlier 0.x versions were development builds and are not listed here.
