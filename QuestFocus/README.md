# QuestFocus (WoW: Forever)

Requires **Questie**. TomTom is optional: if it is installed, its arrow is used. Bagnon is optional: if it is installed, the quest item features hook into its bag window.

## First start
1. Start the game. On the character select screen click **AddOns** and enable QuestFocus. If it shows "out of date", also tick **Load out of date AddOns**.
2. Open the quest log (L) and click a quest. This creates the **QFocus** macro.
3. Type `/macro`, find QFocus on the **General Macros** tab and drag it to an action bar. You only need to do this once.

## Usage
- **Click a quest in the quest log:** the QFocus macro now targets that quest's mobs, and a marker is placed at the nearest spot (TomTom arrow or the built-in arrow).
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

### Panel
- Header with the quest name, then three stat boxes: **Progress** (all objective counters together), **Time left** and **Pace** (your average time per kill), plus a progress bar.
- Each objective shows its own estimated time left. Hover it for the details.
- **Progress popup:** for a few seconds after an objective counter goes up, a small popup above the panel shows the new count and the time left.

### Time left estimate
- The best source is your own pace on that objective, i.e. how fast its counter has been growing.
- Without that, it uses your kill pace (time between your kills, taken from the "X dies, you gain N experience" messages; breaks over 5 min ignored) times the kills still needed. For loot objectives this uses the Questie drop rate: 10 items at 5% is about 200 kills.
- A `?` means there is no kill data yet, so a default of 45 s per kill is used. Reset the pace on the Panel tab.

### What next? (no quest selected)
With no quest selected, the panel suggests what to do next:
- **Route:** quests from your log ordered as a route. It always goes to the nearest next stop, which is the remaining objectives or the turn-in NPC. Each row shows the extra distance and the time left. Click a row to select that quest.
- **Pick up nearby:** the 3 nearest quests you can pick up, from Questie's available quests, with completed quests filtered out. They are colored by difficulty. Click one to put a marker on the quest giver.

### Buff reminders
A small row of buttons under the panel:
- **Sleeping bag:** found in your bags by name. The buff is spell 429959 and needs **3 stacks**. The button shows the stacks (e.g. `54m 2/3`), and fewer than 3 counts as low, the same as an expiring buff.
- **XP food:** drag the item in once on the Buffs tab.
- **Weapon enchant:** sharpening stone, weightstone or oil, found by name. Clicking applies it to your main hand.

Each button shows the time left on its buff. When the buff is missing, or about to run out, the button pulses red. "About to run out" is set per buff on the Buffs tab: by default 10 min for the sleeping bag and the weapon enchant, and 1 min for the XP food (so food only warns when it is missing or almost gone). You also get one warning on screen and in chat. The buff an item gives is learned the first time you use it from the button.

**Reminder popup.** Out of combat, when a buff is missing or about to run out, a small popup appears above the panel with one row per buff: the item icon, the time left and the item name. Click the icon to apply it; weapon enchants go on the main hand. The X hides that reminder until the buff is applied again. The popup disappears when combat starts, because the game does not allow it to stay up in combat. It uses the same spot as the progress popup: if a progress popup is showing (e.g. right after combat), the reminder waits until it fades.

## Commands
| Command | What it does |
|---|---|
| `/qf` | toggle the panel (after closing it with X it also comes back when you click a quest) |
| `/qf options` | settings window (Options → AddOns → QuestFocus), includes a Debug tab |
| `/qf zone` | toggle zone focus: only quests of the current zone stay in the Questie tracker |
| `/qf minimap` | toggle the minimap button |
| `/qf bags` | toggle the quest item list next to the bags |
| `/qf junk` | destroy unsellable leftover quest items (asks for each one) |
| `/qf debug` | diagnostics to chat |
| `/qf spell <name>` | tag spell in the macro (e.g. `/qf spell Moonfire`); `/qf spell` = clear, `/qf spell off` = disable |
| `/qf next` | next objective (marker + macro); worth putting in a macro too |
| `/qf all` | macro for all remaining mobs |
| `/qf mark` | place the marker again at the nearest spot |
| `/qf arrow` | toggle the built-in arrow (not shown when TomTom is installed) |
| `/qf ping` | toggle pinging the target in the macro (on by default; party members see it). It only pings a new target: spamming the macro on the mob you already have targeted does not ping again |
| `/qf icon <iconname>` | custom macro icon (e.g. `/qf icon inv_misc_map_01`); `/qf icon` = back to automatic |
| `/qf unmark` | remove the marker (TomTom + map pin + arrow) |
| `/qf clear` | clear the selection and the marker |

**Automatic marker cleanup:** when an objective is done, the marker jumps to the next remaining target. When the quest is complete, it moves to the turn-in NPC. When you turn it in (or abandon it), the marker is removed. Right clicking the built-in arrow also removes it.

## Minimap button and zone focus
- **Minimap button:** left click opens the settings, right click toggles zone focus. Drag it to move it around the minimap.
- **Zone focus:** only quests of the current zone (plus the selected QFocus quest) stay in the Questie tracker; the rest are untracked. It follows you when you change zones. Turning it off restores everything as it was. The zone is taken from the quest log headers, so quests under a collapsed header are not seen.

## Quest items
**List next to the bags.** While your bags are open (Bagnon or the default bags), a list of your quest items appears on their left. It is never taller than the bag window and scrolls if needed; the +/− button collapses it. Row colors:
- **yellow:** needed for an active quest, with your progress (e.g. 5/7). If you carry more than needed it shows "+2 surplus";
- **green:** you have enough. If the whole quest is complete, the row says "quest complete, turn in". If only this objective is done, it says "7/7 done (keep it, quest not finished)";
- **blue:** starts a quest (right click it in the bag);
- **grey:** no active quest needs it;
- **IN BANK:** an active quest needs it and it is in your bank (based on Bagnon/BagBrother's last bank snapshot). If you also have some in your bags, the name shows "+N bank".

Hover a row to see the item tooltip; click it to select the quest (marker + QFocus macro). Turn off with `/qf bags` or in the settings.

**Coloring in Bagnon.** Quest item slots get the same border colors (yellow, green, blue, grey). Can be turned off in the settings.

**Quest item button.** If the selected quest needs a usable item (e.g. to throw at a mob or use at a spot), a button with that item appears left of the QuestFocus panel. You can bind a key to it: Options → Keybindings → AddOns → QuestFocus. The button works in combat, but it can only switch to another item out of combat.

**Destroying leftover quest items.** A button appears at the bottom of the list (or use `/qf junk`) when you have quest items that no active quest needs **and that can't be sold**. It asks for each one (Destroy / Skip). Sellable quest items are never touched.

## Settings (optional)
Esc → Options → AddOns → **QuestFocus**, or `/qf options`. New options are off by default.
- **Spell in the macro (tagging):** drag a spell from your spellbook (P) into the slot, or type its name. The QFocus macro then also casts it on the mob after targeting (e.g. Moonfire, Arcane Shot, Shoot). It does not cast at turn-in.
- **Auto attack:** also starts auto attack after targeting.
- **Ping the target** and **own arrow** on/off (same as `/qf ping` and `/qf arrow`).
- **Zone focus** button and **minimap button** on/off.
- **Quest item list**, **Bagnon coloring** and **quest item button** on/off.
- **Panel tab:** quest suggestions, progress popup, reset kill pace.
- **Buffs tab:** buff buttons, warning and how many minutes before, item slots. Drag an item from your bags onto a slot. Right click cycles through set, automatic and off.
- **Lua errors:** QuestFocus's own Lua errors are listed at the bottom of the Debug tab with time, count and stack. By default they don't open the error window (one chat line instead). The **Lua error popup** checkbox turns the window back on, and **Clear errors** empties the list. Other addons are not affected.
- **Debug tab:** live view of the selected quest, the wanted mobs, the picked nameplate, combat state, the visible quest mob nameplates and the current macro text.

The macro icon changes automatically: **crosshair** while you need to kill mobs or collect items, **letter** when the quest is complete and must be turned in, **map** when no quest is selected.

## Localization
All texts go through `Locales.lua`. The key is the English text; if a translation for the client language (`GetLocale()`, e.g. `deDE`) is missing, English is shown. Only English is included for now.
