# Adventurer's Kit (WoW: Forever)

Formerly **QuestFocus**. Since 0.6.0 the folders are `AdventurersKit*` too. The `QuestFocusDB` SavedVariables keep their old name, so settings and keybinds carry over. Since 0.8.0 the slash command is `/ak` (`/qf` still works) and the macro is called `AKit` (the old `QFocus` macro is renamed in place, so it stays on your action bar).

**Upgrading from QuestFocus (before 0.6.0):** remove the old `QuestFocus_Bags` and `QuestFocus_Buffs` folders and replace the old `QuestFocus` folder with the small one in the release (no code, it only loads your old settings). Restart the game, log in once, then that `QuestFocus` folder can be deleted. Safety net: `/ak export` before upgrading.

Requires **Questie**. TomTom is optional: if it is installed, its arrow is used. Bagnon is optional: if it is installed, the quest item features hook into its bag window.

## Addons (modules)
Adventurer's Kit ships as three folders (plus the `QuestFocus` settings bridge for upgrades). Copy them to `Interface\AddOns`; the two modules are optional and can be switched off in Options or disabled in the AddOns list.

| Folder | What it does |
|---|---|
| `AdventurersKit` | Core (required): AKit macro, marker, panel, tooltips, pace/ETA, suggestions, travel, city mode, dungeons |
| `AdventurersKit_Bags` | Quest item list, Bagnon highlight, use-item button and keybind |
| `AdventurersKit_Buffs` | Buff reminder: sleeping bag, XP food, weapon enchant, class buffs, tracking switch keybind |
| `QuestFocus` | Only for upgrades: loads the old settings once (no code), delete it afterwards |

Core layout: `Core\` (logic), `UI\` (panel, options, shared tooltip builder `UI\Tooltip.lua`), `Planner\` (pace, routes, popups, travel). All modules share the `QuestFocusDB` settings.

## First start
1. Start the game. On the character select screen click **AddOns** and enable Adventurer's Kit. If it shows "out of date", also tick **Load out of date AddOns**.
2. Open the quest log (L) and click a quest. This creates the **AKit** macro.
3. Type `/macro`, find AKit on the **General Macros** tab and drag it to an action bar. You only need to do this once.

## Usage
- **Click a quest in the quest log:** the AKit macro now targets that quest's mobs, and a marker is placed at the nearest spot (TomTom arrow or the built-in arrow).
- **Hover a quest in the log:** the tooltip shows the mobs and items, where an item comes from (dropped by, picked up from, sold by), the zone, coordinates and distance.
- **Panel:** a small window lists the quest's objectives.
  - Left click an objective: the marker and the macro apply to that objective only.
  - Right click: the macro applies to all remaining objectives again.
  - The bottom line shows live status: the mob the macro will target, "nearby mobs are taken", the turn-in NPC with distance, or the marker distance.
- **Completed quest:** the macro and the marker switch to the turn-in NPC automatically.
- WoW does not allow changing macros in combat, so the addon updates the macro after combat.

### How the macro picks a target
- With **enemy nameplates enabled** (V key), the addon picks a living quest mob **that nobody else has tapped** from the visible nameplates and writes it into the macro (`/target nameplateN`). It prefers mobs that are not in combat.
- If the only quest mobs nearby are tapped or dead, the macro targets nothing and shows "nearby quest mobs are taken".
- If no quest mob nameplate is visible (too far away, nameplates off) or you are in combat, the macro targets by name. It skips corpses, but it can't detect tapped mobs this way; a red warning appears if the target is tapped.

### Other quests nearby
While you focus a quest, the addon also looks at the other quests in your log. Unfinished mob objectives with a spawn within ~200 yards are added to the AKit macro, so it targets those mobs too (e.g. tigers and panthers in the same spot). The panel lists them under **ALSO NEARBY** with progress and time left; click one to focus that quest. This is off when you narrowed the macro to one objective. At turn-in, when the turn-in NPC is more than ~100 yards away, the macro targets these nearby quest mobs; closer than that, it targets the NPC again. Toggle it on the Panel tab.

### Panel
- Header with the quest name, then three stat boxes: **Progress** (all objective counters together), **Time left** and **Pace** (average time per kill, searching included), plus a progress bar.
- Each objective shows its own estimated time left. Hover it for the details.
- **Resize:** drag the grip in the bottom right corner to change the panel width and height. In "What next?" mode a taller panel shows more route and pickup rows. Right click the grip to reset. The font size is a separate setting on the Panel tab (8-20).
- **Progress popup:** for a few seconds after an objective counter goes up, a small popup above the panel shows the new count and the time left.

### Time left estimate
Every source measures the **time between** two events, so the searching is counted too, not just the fight. A gap of 15 minutes or more counts as a break and is left out.
1. **Your pace on that objective:** the time between two increases of its counter.
2. **The time between your kills of that objective's mobs**, read from the "X dies, you gain N experience" messages. For loot objectives this is combined with the Questie drop rate: 10 items at 5% is about 200 kills.
3. **Your general kill pace** (all mobs).
4. **A default of 45 s per kill.** A `?` after the time means there is no data yet and this default is used.

If you have been searching for longer than your average, that is counted too: the time left grows while you search. The **PACE** box shows the pace of the first open objective, e.g. `2m10s / kill`. Reset all of this on the Panel tab.

### What next? (no quest selected)
With no quest selected, the panel suggests what to do next:
- **Route:** quests from your log ordered as a route. It always goes to the nearest next stop, which is the remaining objectives or the turn-in NPC. Each row shows the extra distance and the time left. Click a row to select that quest.
- **Pick up nearby:** the 3 nearest quests you can pick up, from Questie's available quests, with completed quests filtered out. They are colored by difficulty. Click one to put a marker on the quest giver.

### Quests to pick up nearby
When a quest you can pick up is within ~300 yards, a popup appears at the top center of the screen. It shows the quest level, colored by difficulty, an estimated length and the distance, e.g. `[32] Some Quest ~5m est. 250 yd`. Click it to get a marker (TomTom arrow) on the quest giver. Each quest pops up only once per session, and hovering keeps it open.

Only quests between your level minus 2 and plus 10 are shown; this range also applies to the "Pick up nearby" list. Change the range or turn the popup off on the Panel tab. The length is a rough estimate, because Questie's data has no counts: about 8 kills per mob objective, 6 items per loot objective (with the drop rate), about 1 min for talk or delivery quests, all scaled by your kill pace.

### City mode
In a city or an inn (where you get rested XP), quests don't pop up one by one. When you arrive, a single list shows every quest you can pick up within ~600 yards, up to 12. Each row has the level, the name, the estimated length and the distance, and a click puts a TomTom marker on the quest giver. The list refreshes while you walk around, and quests you have picked up drop off it. It closes when you leave; X hides it until the next city. The town icon on the quest panel (or `/ak city`) opens and closes it anywhere. In city mode the panel hides the Progress / Time left / Pace boxes. Options > City list turns it off, or stops it opening by itself in towns ("Open automatically in towns").

### Travel: Hearthstone and flight
When a marker is placed, the addon compares walking with your Hearthstone and with flying. If one of them is clearly faster, it says so once in chat, e.g. "Faster: Hearthstone to Booty Bay (~2m instead of ~9m on foot)". The Hearthstone estimate includes the 10 s cast and any cooldown.
- **Hearthstone position:** the game only gives the name of your bind location, not its coordinates. The addon learns the position when you bind at an innkeeper, or right after you arrive by Hearthstone. The Debug tab shows whether it is known.
- **Turn-in mode:** the panel boxes show **Distance** (yards to the turn-in NPC), **Travel** (time at your current speed, like TomTom) and **Best way** (walk, Hearthstone or flight).
- **Hearth home:** if completed quests can be turned in where your Hearthstone takes you, the panel shows e.g. "Hearth home: 3 quests to turn in at Booty Bay", with the cooldown if there is one. Hover it to see which quests. It shows from 1 quest in turn-in mode, otherwise from 2, and only when you are far from your Hearthstone location.
- **Route in turn-in mode:** while you head to turn in a finished quest, the bottom of the panel lists your other quest-log quests in route order (max 5, nearest next stop first, with distance and ETA). Click one to focus it. The list refreshes as you move.
- **Flight:** uses the flight points you know, if the client provides them (`C_TaxiMap`). The flight time is estimated in a straight line.

### Tracking (Find Minerals / Find Herbs)
If you know a tracking spell and none is active, the buff reminder shows it; the arrow switches between them. In Classic only one tracking can be active at a time, and an addon cannot switch them on its own. Instead there is a keybinding: Options > Keybindings > AddOns > Adventurer's Kit - Buffs > **Switch tracking**. Each press switches between Find Minerals and Find Herbs (`/castsequence`), and it works in combat too.

### Buff reminders
Watched buffs (warning + reminder popup). An optional row of buttons under the panel is **off by default**, because the buff frame already shows the timers; turn it on on the Buffs tab:
- **Sleeping bag:** found in your bags by name. The buff is spell 429959 and needs **3 stacks**. The button shows the stacks (e.g. `54m 2/3`), and fewer than 3 counts as low, the same as an expiring buff.
- **XP food:** if none is set, a picker opens about 12 s after login. It lists the food in your bags, with items whose description mentions XP or experience first (marked "XP"). Click one to set it. "Don't ask again" stops the picker. You can open it any time with **Choose XP food from bags** on the Buffs tab, or drag an item onto the slot.
- **Weapon enchant:** sharpening stone, weightstone or oil, found by name. Clicking applies it to your main hand.

Each button shows the time left on its buff. When the buff is missing, or about to run out, the button pulses red. "About to run out" is set per buff on the Buffs tab: by default 10 min for the sleeping bag, and 1 min for the XP food and the weapon enchant (so those only warn when missing or almost gone). You also get one warning on screen and in chat. The buff an item gives is learned the first time you use it from the button.

**Class buffs.** Your class's own buffs are watched too, and clicking the icon casts the buff on you:
- **Paladin:** Blessing (any, Greater too) and Aura.
- **Mage:** Arcane Intellect and armor.
- **Priest:** Fortitude and Inner Fire.
- **Druid:** Mark of the Wild and Thorns.
- **Warlock:** Demon Skin / Armor.
- **Hunter:** Aspect and Trueshot Aura.
- **Shaman:** Lightning / Water Shield.

By default it casts the one you last had on (e.g. Blessing of Might). To choose, drag a spell from your spellbook onto its slot on the Buffs tab. Auras and aspects only count when they are missing. Timed buffs warn 1 min before they run out (you can change this).

**Reminder popup.** Out of combat, when a buff is missing or about to run out, a small popup appears above the panel with one row per buff: the item icon, the time left and the item name. Click the icon to apply it; weapon enchants go on the main hand. It sits as a band on top of the panel and moves with it. When there is more than one choice, a small arrow next to the icon opens a flyout (like the inventory slot flyouts). It holds the XP foods in your bags, the auras / blessings you know, or your sharpening stones / oils. Clicking one uses or casts it right away and makes it the default. The X hides it until your next fight; after that fight it comes back if still needed. It disappears when combat starts, because the game does not allow it to stay up (attached to the panel) in combat. It uses the same spot as the progress popup: if a progress popup is showing (e.g. right after combat), the reminder waits until it fades.

## Commands
| Command | What it does |
|---|---|
| `/ak` | toggle the panel (after closing it with X it also comes back when you click a quest) |
| `/ak options` | settings window (Options → AddOns → Adventurer's Kit), includes a Debug tab |
| `/ak zone` | toggle zone focus: only quests of the current zone stay in the Questie tracker |
| `/ak minimap` | toggle the minimap button |
| `/ak bags` | toggle the quest item list next to the bags |
| `/ak city` | open / close the city list (quests to pick up nearby, errands, Directions), also outside towns |
| `/ak chat` | turn chat messages on/off (off: only the login line and command replies) |
| `/ak notes` | release notes |
| `/ak junk` | destroy unsellable leftover quest items (asks for each one) |
| `/ak debug` | diagnostics to chat |
| `/ak copy` | diagnostics in a selectable text box (Ctrl+C to copy); also the **Copy** button on the Debug tab |
| `/ak spell <name>` | tag spell in the macro (e.g. `/ak spell Moonfire`); `/ak spell` = clear, `/ak spell off` = disable |
| `/ak next` | next objective (marker + macro); worth putting in a macro too |
| `/ak all` | macro for all remaining mobs |
| `/ak mark` | place the marker again at the nearest spot |
| `/ak arrow` | toggle the built-in arrow (not shown when TomTom is installed) |
| `/ak ping` | toggle pinging the target in the macro (on by default; party members see it). It only pings a new target: spamming the macro on the mob you already have targeted does not ping again |
| `/ak icon <iconname>` | custom macro icon (e.g. `/ak icon inv_misc_map_01`); `/ak icon` = back to automatic |
| `/ak unmark` | remove the marker (TomTom + map pin + arrow) |
| `/ak clear` | clear the selection and the marker |

**Where the marker goes:** if you are already in the spawn area (a spawn within ~150 yards), no marker is placed; the macro targets the visible mobs anyway. Otherwise it picks a spawn point that is close **and** has many other spawns around it, so it leads to the dense part, not to a lone spawn point. The spawn points come from the Questie database, not from live mobs.

**Automatic marker cleanup:** when an objective is done, the marker jumps to the next remaining target. When the quest is complete, it moves to the turn-in NPC. When you turn it in (or abandon it), the marker is removed. Right clicking the built-in arrow also removes it.

## Minimap button and zone focus
- **Minimap button:** left click opens the settings, right click toggles zone focus. Drag it to move it around the minimap.
- **Zone focus:** only quests of the current zone (plus the selected AKit quest) stay in the Questie tracker; the rest are untracked. It follows you when you change zones. Turning it off restores everything as it was. The zone is taken from the quest log headers, so quests under a collapsed header are not seen.
- **Zone question:** while zone focus is off, entering a zone where you have quests (and other quests elsewhere) opens a popup asking whether to focus on it. The choices are **Focus**, **Not now** and **Don't ask again**. It asks once per zone per session, and waits until combat ends. Toggle it with **Ask when entering a new zone** in the settings. Next to the zone focus button, the settings show whether zone focus is on and for which zone.

## Quest items
**List next to the bags.** While your bags are open (Bagnon or the default bags), a list of your quest items appears on their left. It is never taller than the bag window and scrolls if needed; the +/− button collapses it. Row colors:
- **yellow:** needed for an active quest, with your progress (e.g. 5/7). If you carry more than needed it shows "+2 surplus";
- **green:** you have enough. If the whole quest is complete, the row says "quest complete, turn in". If only this objective is done, it says "7/7 done (keep it, quest not finished)";
- **blue:** starts a quest (right click it in the bag);
- **grey:** no active quest needs it;
- **IN BANK:** an active quest needs it and it is in your bank (based on Bagnon/BagBrother's last bank snapshot). If you also have some in your bags, the name shows "+N bank".

Hover a row to see the item tooltip. Click it to highlight the item in the bag: its slot gets a pulsing gold frame and the other slots dim. Click the same row again, or close the bag, to clear it. The click also selects the quest (marker + AKit macro). Turn off with `/ak bags` or in the settings.

**Coloring in Bagnon.** Quest item slots get the same border colors (yellow, green, blue, grey). Can be turned off in the settings.

**Quest item button.** If the selected quest needs a usable item (e.g. to throw at a mob or use at a spot), a button with that item appears left of the Adventurer's Kit panel. You can bind a key to it: Options → Keybindings → AddOns → Adventurer's Kit. The button works in combat, but it can only switch to another item out of combat.

**Destroying leftover quest items.** A button appears at the bottom of the list (or use `/ak junk`) when you have quest items that no active quest needs **and that can't be sold**. It asks for each one (Destroy / Skip). Sellable quest items are never touched.

## Settings (optional)
Esc → Options → AddOns → **Adventurer's Kit**, or `/ak options`. New options are off by default.

The settings are grouped into tabs on the left, in this order: General (panel, font size, chat messages, minimap button), Macro & marker, Route & progress, Quest pickup (level range, nearby popup, city mode and ignored places), Zone focus, Bags and Buffs (only when that module is enabled), Release notes and Debug. Every option has a short description under it.

**Chat messages** (General tab, `/ak chat`): when off, Adventurer's Kit writes only one line at login, plus the replies to your own `/ak` commands and button clicks. **Release notes**: `/ak notes`, or the Release notes tab. After an update the login line also shows what's new.
- **Spell in the macro (tagging):** drag a spell from your spellbook (P) into the slot, or type its name. The AKit macro then also casts it on the mob after targeting (e.g. Moonfire, Arcane Shot, Shoot). It does not cast at turn-in.
- **Auto attack:** also starts auto attack after targeting.
- **Ping the target** and **own arrow** on/off (same as `/ak ping` and `/ak arrow`).
- **Zone focus** button and **minimap button** on/off.
- **Quest item list**, **Bagnon coloring** and **quest item button** on/off.
- **Panel tab:** quest suggestions, progress popup, reset kill pace.
- **Buffs tab:** buff buttons, warning and how many minutes before, item slots. Drag an item from your bags onto a slot. Right click cycles through set, automatic and off.
- **Lua errors:** Adventurer's Kit's own Lua errors are listed at the bottom of the Debug tab with time, count and stack. By default they don't open the error window (one chat line instead). The **Lua error popup** checkbox turns the window back on, and **Clear errors** empties the list. Other addons are not affected.
- **Debug tab:** live view of the selected quest, the wanted mobs, the picked nameplate, combat state, the visible quest mob nameplates and the current macro text.

The macro icon changes automatically: **crosshair** while you need to kill mobs or collect items, **letter** when the quest is complete and must be turned in, **map** when no quest is selected.

## Localization
All texts go through `Locales.lua`. The key is the English text; if a translation for the client language (`GetLocale()`, e.g. `deDE`) is missing, English is shown. Only English is included for now.
