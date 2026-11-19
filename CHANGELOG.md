# Changelog

All notable changes to Adventurer's Kit (formerly QuestFocus). The same notes are in game:
Options > Release notes, or `/ak notes`. Generated from `AdventurersKit/UI/ReleaseNotes.lua`.

## 0.11.0 (2026-11-19)

- Debug per feature: Options > Debug lists 13 sections (General, Targeting / AKit macro, Markers / arrow / spawns, Route & travel, Quest panel / stepping / skips, City list & errands, Dungeon prep, Escort, Buffs, Bags, Farm session, AH quest items & prices, Zone focus), each with a snapshot of what it sees now.
- Every section has a log switch (saved for the account). While it is on, that part writes its decisions with the time into a log of the last 200 lines: why the macro was rebuilt, what got picked, why there was no ping, why the marker moved, why the city list opened or closed, farm events, AH purchases. Off costs nothing.
- Copy debug on a section (or Copy all) opens the copy window with a header (version, date, section), the snapshot and the log, selected for Ctrl+C. Commands: /ak debug <section> [on | off], /ak copy <section> | all, /ak debug list; plain /ak debug still prints the targeting snapshot.

## 0.10.1 (2026-11-19)

- AKit macro pings are simpler: pressing the button pings your target. Turn-in NPCs and other neutral or friendly NPCs are pinged too (a neutral goblin like Drizzlik got no ping before), and a quest mob you already target is pinged again (the game limits ping spam itself).
- Still no ping when every nearby quest mob is tapped, and no attack ping when the target was picked only by name in nameplate mode (it could be tapped). Attack pings stay out of combat only.
- /ak debug shows in one line why the macro has a ping or not.

## 0.10.0 (2026-11-19)

- Release: everything since 0.9.0 in one download. Adventurer's Kit's own compass icon in game (addon list, minimap button, AH Quest items tab and window, About tab), the restyled ping question, and the AKit macro pinging the next mob after a kill again.

## 0.9.3 (2026-11-19)

- Adventurer's Kit has its own icon in game, the compass from the CurseForge page: in the addon list, on the minimap button (the round compass under the minimap border), on the Quest items tab and window at the auction house, and next to the name on the About tab. The AKit macro keeps its game icons.

## 0.9.2 (2026-11-19)

- The ping question you get when joining a group has a new look: the question in big letters, two equal full-width answer buttons ("Ping in this group" highlighted in orange, "No ping" next to it) with a short grey explanation, and the next-time choice (Ask / Always ping / Never ping) as an even row with the selected one outlined in orange and a line saying what it does.

## 0.9.1 (2026-11-19)

- AKit macro pings the next mob after a kill again. While you fight a quest mob the macro leaves out the ping (it already is your target); now it is rebuilt when that target dies and when combat ends, so the first press on the next mob targets and pings it.
- /ak debug also shows the ping mode (ask / on / off, your group answer) and your current target (dead, tapped, attackable, whether it is the picked mob).

## 0.9.0 (2026-11-19)

- First public release, ready for CurseForge (WoW: Forever). The download has the three addon folders (AdventurersKit, AdventurersKit_Bags, AdventurersKit_Buffs); the old QuestFocus settings bridge is no longer in it, keep your own copy only if you still upgrade from QuestFocus.
- Adventurer's Kit is now free software under the GPL-3.0 license (LICENSE.txt). CREDITS.txt names the data it carries from Questie, DungeonJournal (Exehn) and OpenMap.
- The addon list shows the author, the license and a longer description; Auctionator, TradeSkillMaster and Auctioneer load before it when installed.

## 0.8.8 (2026-11-18)

- Farm session tooltips are easier to read: the gold one in sections (Coins, Items, Totals) and the XP one (XP gained, Pace, Level), with space between them. Per hour values are grey so the totals stand out, the AH total is green, the price source muted, rested XP blue and the time to level highlighted; the explanations are small grey notes at the bottom.
- Farm session summary: the item lines are real item rows. Hover shows the item's tooltip, shift-click puts the link in chat, ctrl-click opens the dressing room.

## 0.8.7 (2026-11-18)

- Farm session: XP tooltip. Hover the XP box or the XP / level / kill rows on the panel, or the Time and XP rows in the summary: XP gained split into kill XP (base and rested bonus) and quests / other, XP per hour overall and over the last 5 minutes, kills and XP per kill, kills and time to level (with and without your rested XP), rested XP left and about how many kills it lasts, level progress, and this session as a % of a level.

## 0.8.6 (2026-11-18)

- Money shows with the little gold / silver / copper coin icons instead of the letters g s c, sized to the text: farm session panel, summary and tooltips, the AH quest items tab and its purchase confirmation, and the bag item tooltip. The chat lines use the icons too.

## 0.8.5 (2026-11-18)

- Farm session: gold per hour says how it is counted. With Auctionator / TSM / Auctioneer it uses AH prices ("GOLD/H (AH)", "Gold per hour (AH)"), otherwise vendor prices. An item with no AH price, a soulbound one, or one the AH pays less for counts at vendor price, and the item rows say how many.
- Farm session: hover the gold box, a farm row or a Loot row in the summary for the breakdown: raw gold looted, items if vendored, items if sold on the AH (with the price source), and both totals, each with a per hour value after the first minute.

## 0.8.4 (2026-11-18)

- Farm session: the counters move from the first kill. In the first minute the boxes show the XP and gold gained ("+250") instead of "-" (the per hour rate comes after a minute), the panel updates right on each kill / XP / loot, and the kill count is next to the start time.
- Farm session: rested XP. The XP row shows how much was rested bonus; the ETA to level uses your pace without rested plus the rested XP you have left, which is shown too.
- Farm session summary: grouped like the panel (Time and XP, Kills, Loot) with dividers, values on the right and the usual flat gold-edged Start new / Close buttons.

## 0.8.3 (2026-11-18)

- City list: 'Hide for 20 min' button at the bottom. The list closes and won't open by itself for 20 minutes, not even in the next town or after /reload. The town icon on the panel or /ak city still opens it.

## 0.8.2 (2026-11-18)

- AKit macro: when it picks a quest mob by its nameplate, that mob's name is now the first by-name fallback. Before, a long name list could push it out of the 255-character macro, so if the nameplate line missed, the mob right in front of you was not targeted (e.g. Goretusk on Goretusk Liver Pie).

## 0.8.1 (2026-11-18)

- AKit macro, quest mob close by (its nameplate shows, about 20 yd): the macro no longer relies only on the nameplate. If that nameplate is gone or renumbered by the time you press it, it falls back to targeting the quest mobs by name, like it does further away.

## 0.8.0 (2026-11-18)

- The slash command is now /ak (for example /ak options, /ak city, /ak farm). /qf still works as before.
- The target macro is now called AKit. Your old QFocus macro is renamed on the first update, so it stays on your action bar; no second macro is made.
- Every message, tooltip, option and help text now says Adventurer's Kit, AKit and /ak instead of the old QuestFocus names.

## 0.7.19 (2026-11-18)

- The QFocus macro no longer pings a mob someone else has tapped. When every nearby quest mob is taken it just shows the message and pings nothing; in nameplate mode it only pings the mob it picked (living, not tapped), not a by-name fallback target.

## 0.7.18 (2026-11-18)

- Auction house quest items: whatever you buy, also in the auction house's own Buy tab or in Auctionator, now counts as "in the mail" right away; you no longer need to open a mailbox for the quest items list to drop it. (Purchases made with an older version are only seen once you open a mailbox.)
- Auction house quest items: the purchase confirmation looks like the auction house's / Auctionator's own: centred, not see-through, the item's icon, "Buy 4 x Linen Cloth for 3s 20c? (80c each)", Accept / Cancel. Buy all lists every item with its price and marks the bought ones as it goes.

## 0.7.17 (2026-11-18)

- Auction house quest items: the list is always closed when you open the auction house; the tab on the right edge opens it.

## 0.7.16 (2026-11-18)

- Fix: quest items you bought at the auction house stayed on the list, because they go to the mailbox first. Items on their way now count as yours: the row shows "in mail: N" (or disappears), also after /reload or relog. Opening the mailbox checks what is really still there; entries expire after 30 days.
- Auction house quest items: after a successful purchase the list closes (the tab opens it again); if the purchase failed or you cancel, it stays open.
- Auction house quest items: dragging the tab keeps it visible and only follows the mouse up and down; it stops 5% of the auction house window's height from the top and the bottom.

## 0.7.15 (2026-11-18)

- Auction house quest items: the tab now sits right above All The Things' button on the auction house's right edge (near the top of the edge without ATT). Dragging moves it only up and down that edge, kept within the window's height; right click puts it back.
- Auction house quest items: the list looks like the auction house itself: the Blizzard window frame and the red buttons (row Buy, Rescan prices, Buy all). It opens beside the tab, not over ATT's button or panel.

## 0.7.14 (2026-11-18)

- Auction house quest items tab: it no longer sits under All The Things' button. By default it goes below the other side tabs (ATT's), and moves out with them when ATT's Auction Module is open; the list opens next to the tab without covering ATT's panel.
- The tab can be dragged anywhere (the place is kept, relative to the auction house window); right click puts it back. It shows the Adventurer's Kit icon (the map, now also in the addon list) and the tooltip "Adventurer's Kit: quest items".

## 0.7.13 (2026-11-18)

- Item prices come from one place: Auctionator's full auction house scan first (with its age), then TSM, Auctioneer, and finally this addon's own auction house lookups. All optional.
- Auction house 'Quest items' tab: the Auctionator price shows at once as an estimate (~) until the live lookup finishes; the tooltip names the source and age, e.g. "AH (Auctionator, 2d)". Buy still uses only live auctions and never pays above the confirmed price.
- Farm session: the top items tooltip shows where each value comes from (vendor or AH source and age). Bags: leftover quest items show their vendor and auction value in the tooltip.

## 0.7.12 (2026-11-18)

- Fix: Lua error at login 'Attempt to register unknown event AUCTION_ITEM_LIST_UPDATE' (0.7.10), and the auction house quest items tab never showed. WoW: Forever has the modern auction house; the tab now uses it.
- Auction house quest items: stackable goods (commodities, e.g. cloth) are bought in one go for the missing count: the Buy click asks the server for the current price, the next click buys. If the price went above what you confirmed, it is cancelled and skipped. Other items are bought one auction per click, by auction.
- Clicking a row searches the item in the auction house's Buy tab (exact name).

## 0.7.11 (2026-11-18)

- Options > About: the addon's name, version and a short description, every feature in one sentence grouped by area, the main /qf commands and a button to these release notes. The same list is in FEATURES.md.

## 0.7.10 (2026-11-18)

- Auction house: a coin tab on the right of the auction house window opens "Quest items to buy": the items your quests still need that can be sold there (quest-only and soulbound items are left out), with the count, the quest, and the cheapest price from a quick lookup of each item (plus the Auctionator / TSM price when installed).
- Click a row to search for the item in the auction house. Buy asks once ("Buy 4 x Linen Cloth for 3s 20c?"), then buys one auction per click (the game needs a click for every purchase) and never pays more than the price you confirmed. At the bottom: the total if you buy all, and Buy all. Bought items arrive in your mailbox and already count as yours on the list.
- Options > Auction house: 'Show quest items tab at the auction house' (on by default).

## 0.7.9 (2026-11-18)

- City list: a town icon on the quest panel (between the farm clock and the dungeon icon) opens and closes it, also outside towns: then it shows nearby quests, errands and Directions to the nearest bank, trainers... Same as /qf city (it now toggles).
- City list: new option 'Open automatically in towns' (Options > City list, on by default). Off: the list only opens from the icon or /qf city.
- City list: 'Don't open here again' and 'Disable city list everywhere' are gone, with the per-place ignore list and /qf cityreset. Saved ignored places are cleared. The City list tab is tidier.

## 0.7.8 (2026-11-18)

- Farm session on the quest panel: it shows like a quest, titled "Farm session" with a clock. The boxes show time, XP per hour and gold per hour; the rows show XP gained, XP to level with an ETA, mobs killed, looted gold, item value at vendor price and the best sale value. Hover a row for the top items.
- Farm session: it is the first stop of the route while it runs. The next arrow goes to your quests (the session keeps running), the back arrow or its route row brings it back. Clicking a quest also switches.
- Farm session: the clock button glows green and shows a red X while a session runs; click it to stop. Stopping opens a summary window (duration, kills and top mobs, XP, levels, looted gold, items, gold per hour) with Start new / Close, and prints one line to chat. Switch the window off in Options > Route & progress. /qf farm show brings the session back to the panel.
- Fix: the separate farm box (0.7.6) showed only its first line, cut with "...". It is gone; the panel shows the session instead.

## 0.7.7 (2026-11-18)

- Behind the scenes: the addon's look (dark background, gold border, orange strip, flat gold buttons, thin gold scrollbar) is now written down with shared building blocks, so new windows match the quest panel. Nothing changes in game yet.

## 0.7.6 (2026-11-18)

- Farm session: a new coin button on the quest panel (or /qf farm) starts a small "Farm session" box: time, XP gained and XP per hour, XP to level with an ETA, looted gold, looted items at vendor price, and with Auctionator / TSM / Auctioneer a "best sale" value (auction or vendor price, whichever is higher). Hover it for the top 5 items; /qf farm stop prints a summary. /qf farm pause | resume | reset.
- Farm session: looted gold only counts money you loot (not vendor sales or quest rewards; those show in "Net gold change"). The session survives /reload and relog; time while logged out is not counted.
- Panel: the icon order is now farm, dungeons, options, close (options sits next to the X).

## 0.7.5 (2026-11-18)

- Fix: the QFocus macro no longer pings a mob that isn't a quest mob. In combat the macro can't be rewritten and keeps any living enemy you target (e.g. one that attacked you), so it now only pings out of combat, where it has already checked the target.
- Escort: the star raid icon only goes on the escort NPC itself (its NPC ID from the quest data, or the exact name), never on an enemy unit.
- Fix: Buff reminder: another player's class buffs (a druid's Mark of the Wild / Thorns) no longer count as yours when the game doesn't tell who cast them. Food and item buffs (XP food) still do.

## 0.7.4 (2026-11-18)

- Fix: "Dungeons for your level" lists WoW: Forever's own dungeons again (The Drowned City, Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold, Shaper's Terrace, Hall of Thanes, City of Dalaran, Excavation Site: Wetlands, Ruins of Lordaeron). Their levels and quests are built in; no extra addon needed.
- Fix: Razorfen Kraul, Uldaman, Zul'Farrak and Sunken Temple showed 0 quests (Questie files their quests under a different area). Their quests are listed, and dungeon prep finds them.

## 0.7.3 (2026-11-18)

- Dungeon prep: quest chains show up. If a dungeon quest needs earlier quests first (e.g. The Defias Brotherhood), the list shows the chain's next step with its quest giver, marked as chain step N/M.
- Dungeon prep: quests you can't pick up yet are listed greyed at the end (e.g. "from level 17").
- Dungeon prep: a quest that starts from a looted item (The Unsent Letter from VanCleef) is no longer a pickup row; it is in the "starts inside the dungeon" note, and the "No known location" chat spam is gone.
- Dungeon prep: the Entrance row is replaced by two buttons next to the title: the entrance on the world map, and the game's group finder.
- Dungeon data comes only from Questie now; the Dungeon Journal addon is only opened (Shift+click), not read.
- Panel: while you drag the resize grip, the rows follow right away (they used to stay put until you let go).

## 0.7.2 (2026-11-18)

- Fix: during dungeon prep the "What next?" suggestions (next zone, route, pick up nearby) were sometimes drawn over the prep list. Now only the prep list shows until prep ends.

## 0.7.1 (2026-11-17)

- Fix: a syntax error in the dungeon boss table (since 0.6.67) kept boss order inside dungeons from working (the panel fell back to quest log order).
- /qf selftest: a quick self check on your live data (Questie, quest objectives, QFocus macro length, settings, dungeon entrances, boat / zeppelin table). One summary line; details only if something fails.

## 0.7.0 (2026-11-17)

- Dungeon prep: click a dungeon to get a checklist of its quests to pick up, then the entrance; inside the dungeon the panel lists every quest objective in boss order, and in a group you can share the dungeon quests with the party. Aborting goes back to the quest you had before.
- Quest panel: fixed size with shared space for objectives, Also nearby and the route; previous / next quest arrows (with key bindings), skipped quests saved per character; thin scrollbars.
- QFocus macro: keeps a living enemy you clicked; ping modes (always / never / ask in a group); escort quests.
- Travel: next zone suggestion; boats, zeppelins, tram and hearthstone in route planning, with WoW Forever's own transport routes.
- City list: to-do section (repair, ammo, XP food, bags), Bank / Trainer / AH buttons, Directions menu, works in villages with an innkeeper, resizable.
- Buff reminder: tiered bags warning by free slots and vendor distance, one Vendor nearby row, gear warning outside towns, per-character buff settings, gathering tracking first, others' buffs handled correctly. A sleeping bag out in the world is not town.
- Less CPU: quest changes from specific events instead of every quest log update; safer item API calls.

## 0.6.68 (2026-11-17)

- Inside the dungeon, quests that start outside and you didn't pick up are no longer in the list: one dim "Missed outside: N" line at the end, with their names in its tooltip.
- Dungeon prep in a group: when you zone into the dungeon, a small window (same look as the ping question) asks whether to share your dungeon quests with the party. Tick the ones you want and press Share; they are shared one by one. Only out of combat (otherwise right after the fight), once per entry, and only if at least one of them can be shared. Off switch: Options > Route & progress > Dungeon prep.

## 0.6.67 (2026-11-17)

- Dungeon prep continues inside the dungeon: when you zone into the prepped dungeon, the panel lists all its quests in your log in boss order (built-in boss order for the classic and Forever dungeons; otherwise quest log order), each with every objective under it: kills, loot, objects to click, turn-ins inside. Quests from your log whose open objectives point into this instance are listed too, so nothing is missed.
- Quests you can pick up inside (an NPC in the dungeon, or an item that drops there) show as "!" rows at their place in the run. Before you go in, the prep list shows them as "+N quests start inside".
- The next thing to do is highlighted, with a hint (which boss, which object), and the QFocus macro targets its mobs (or the NPC to talk to). Quest items you have to use get the Bags module's use button on the row.
- No arrow inside: Questie has no coordinates for mobs in instances and the game gives no map position there, so the panel shows the Next hint instead (if both ever exist, the marker / arrow works).
- When all of the dungeon's quests are done (and nothing is left to pick up), the mode ends and you are back on the quest you had before. Leaving the dungeon with quests still open goes back to the prep list.

## 0.6.66 (2026-11-17)

- Dungeon list: a plain click on a dungeon or one of its quests now starts dungeon prep for that dungeon (the panel shows its quests to pick up, then the entrance). Shift+click does what a click did before (Dungeon Journal page, or without it a marker on the quest giver).
- Aborting dungeon prep (the small red circle next to the title, or /qf dungeon off) takes you back to the quest and objective you had focused before you started, with its marker and macro. If that quest is no longer in your log, you get the normal suggestion view.

## 0.6.65 (2026-11-17)

- Dungeon prep mode: pick a dungeon and the panel turns into a checklist for it. It lists the dungeon's quests you can still pick up (quest giver, zone, distance; nearest first), the ones already in your log (ticked), and last the entrance with its zone. The marker / TomTom arrow goes to the nearest quest giver; when you have them all, it moves to the entrance. Click a row to send the marker there, right-click for automatic again.
- Start it with the Prep button (or a right click) on a dungeon in the dungeon list, or /qf dungeon <name> (part of the name is enough, e.g. /qf dungeon scarlet). Leave it with the X next to the title or /qf dungeon off. It is saved per character and comes back after a reload. Clicking a quest in your log also ends it.
- In prep mode the QFocus macro does not target mobs: near a quest giver (60 yd) it targets that NPC, otherwise it does nothing.
- Entrance locations for the classic dungeons and Forever's own (Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold, Shaper's Terrace, Hall of Thanes and more) are built in; no extra addon needed.

## 0.6.64 (2026-11-17)

- Sleeping bag: the city list no longer flashes up for a moment right after you lie down.

## 0.6.63 (2026-11-17)

- Lying in a sleeping bag out in the world no longer counts as being in town: the city list doesn't open, and the outside warnings (bags filling up, repair, vendor nearby) still show. Near an innkeeper it's town as before.

## 0.6.62 (2026-11-17)

- Quests you skip with the next arrow stay skipped after a reload or relog (saved per character). A loading screen no longer brings them back.
- All skips end when the quest you moved to is ready to turn in, or you turn in any quest. One skipped quest comes back when you pick it yourself (quest log, tracking, route row, back arrow), when it makes progress (a kill or drop), when you get within ~150 yd of its target after being farther away, or when it leaves your log.
- If every other quest is skipped, the route lists the skipped ones nearest first, and the next arrow cycles through them.

## 0.6.61 (2026-11-17)

- The route on the quest panel shows at most 3 quests; scroll for the rest (or hover its header). The space it frees goes to the Also nearby list.

## 0.6.60 (2026-11-17)

- Scrollable lists on the panel (objectives, route) get a thin gold scrollbar on the right edge instead of the word "scroll". It only shows when the list doesn't fit; drag it, click the bar, or use the mouse wheel.

## 0.6.59 (2026-11-17)

- Previous / next quest arrows next to the quest name on the panel. Next goes to the first stop of the route (ready-to-turn-in quests count too); the marker, the TomTom arrow and the QFocus macro switch over. Previous goes back to the quests you focused before, like a browser's back button. Hover an arrow to see where it takes you and how far it is.
- A quest you skip with the next arrow moves to the end of the route (shown dimmed) until the quest you moved to is ready to turn in, you turn in any quest, or a loading screen comes. Not saved between sessions.
- Key Bindings: "Next quest" and "Previous quest" under Adventurer's Kit (with the Bags module's use-item key).

## 0.6.58 (2026-11-17)

- The QFocus macro keeps the quest mob you clicked: if your target is a living enemy, pressing the macro no longer clears it or switches to another mob (in nameplate mode too). A dead or friendly target is still replaced. Out of combat, a living enemy that is not a quest mob (or is tapped by someone else) is still swapped for the nearest quest mob.

## 0.6.57 (2026-11-17)

- Buff reminder, out in the world: at a vendor you get one "Vendor nearby" row instead of a separate Bags (and Gear) row. It shows your bags (used / free) and, if a repairer is near, your gear %.
- The Bags row now goes by free slots, not percent: at 10 free (your limit in Options) when a vendor is within 300 yd, at 5 free within 600 yd, and at 2 or full always, with the nearest vendor, in a stronger color.

## 0.6.56 (2026-11-17)

- The quest panel has a fixed size now: its width and height follow the text size (Options), so the bottom never moves. The resize handle only shows in the "What next?" list.
- Space in the panel: "Also nearby" and the route get at least 3 rows each (when there are that many), the objectives get the rest. If there are too many objectives to fit, they scroll with the mouse wheel. Spare space goes to nearby quests (up to 4 rows), then the route (up to 5), then more of both.
- The route (your other quests in route order) shows while hunting too, not only at turn-in. It scrolls in its own area; if no row fits, hover its header to see the list. The [+]/[-] toggle is gone.
- Shorter rows: a part repeated at the start of every objective (e.g. "Green Hills of Stranglethorn - ") is left out, so you see "Chapter I", "Chapter II"... The same goes for a quest's rows under Also nearby ("Page 8", "Page 14"). The full text is in the tooltip.
- The Buff Reminder bar always has the panel's width.

## 0.6.55 (2026-11-17)

- After login the quest panel waits until its content has settled (objectives, nearby quests, route) and then appears at once, instead of rows sliding in one by one. Clicking a quest shows it right away.
- "Also nearby" follows the panel's height too. When you shrink the panel, the route goes first, then the nearby list (down to 1 row + "+N more"). When you drag it taller, the nearby list grows past 3 rows.

## 0.6.54 (2026-11-17)

- Fix: after you expanded the route list, resizing and clicking near the bottom of the panel stopped working. The list's off-screen rows were invisible but still caught the mouse. Only the visible rows are active now, and the resize handle always stays on top.

## 0.6.53 (2026-11-17)

- Quest panel: dragging the resize handle now sets the panel's maximum height, and the content is rearranged while you drag. The route list shrinks to 4, then 3 rows and so on, and collapses to its header when nothing fits. Right click on the handle resets it.
- The route header's [+] / [-] toggle is visible now (the icon didn't show before). It reads "+N hidden - click"; expanded, the scrollable list is as tall as the space left (at least 3 rows).

## 0.6.52 (2026-11-17)

- The quest panel keeps a steady maximum height. The "Route (quest log)" list gets only the rows that still fit below the objectives and nearby quests. If some stops don't fit, its header shows "+N hidden": click it to open the whole route in a scrollable list, click again to collapse. The panel remembers your choice.
- "Also nearby" shows at most 3 rows plus a "+N more" row; hover it to see the rest. The macro still targets all of them.

## 0.6.51 (2026-11-17)

- Escort quests without an event objective in Questie (e.g. Zimmix's Great Escape in Stranglethorn) are recognised from the quest's objective text ("Escort X ..."). The marker then points to the turn-in NPC.

## 0.6.50 (2026-11-17)

- Escort quests: the panel shows who you escort, their health (warning with a sound below 35%) and where to. The QFocus macro targets whatever is attacking the escort, otherwise the escort itself. The marker goes to the escort's end point. If the escort fails, the marker and the macro point to the quest giver to restart.
- A star raid icon goes on the escorted NPC when you target or mouse over it (solo, in a party, or as raid leader / assist). An icon already on it is left alone. Option: Macro & marker tab.

## 0.6.49 (2026-11-17)

- XP food row: a Well Fed buff with bonus kill XP (e.g. +5% from Longjaw Mud Snapper) counts. The buff's spell description is checked too, not just its tooltip. /qf debug lists your long buffs and whether each one is an XP buff.

## 0.6.48 (2026-11-17)

- XP food row: an active food buff (e.g. Well Fed from Longjaw Mud Snapper) counts again. The food buff's caster is no longer checked, and a buff description that hasn't loaded yet is retried instead of being remembered as 'no XP'.

## 0.6.47 (2026-11-17)

- Fixed a Lua error outside towns (vendor distance in the buff reminder). Also fixed the raid-quest tag in tooltips and the travel steps of the next-zone suggestion, which were never filled in.

## 0.6.46 (2026-11-17)

- Tracking a quest (the tick in the quest log / map list, shift-click) focuses it: marker and arrow go to the newly tracked quest. Auto-tracking right after accepting a quest doesn't switch focus.

## 0.6.45 (2026-11-17)

- Bags row tiers: 80%+ full now reports a vendor within 300 yd (was 400).

## 0.6.44 (2026-11-17)

- Bags row out in the world is tiered: 70%+ full when a vendor is within 100 yd, 80%+ within 400 yd, 90%+ within 600 yd, 95%+ (or fewer free slots than your limit) always, with the nearest vendor. 'Vendor nearby' then only adds repairs, so the two rows don't repeat each other.

## 0.6.43 (2026-11-17)

- Buff reminder out in the world: the Bags row only comes up when free slots really run low (under the 'fewer free slots than' limit, default 10, or full) - a percentage alone isn't worth a long walk. It shows how far the nearest vendor is; a vendor close by is still reported by 'Vendor nearby'.

## 0.6.42 (2026-11-17)

- Paladin blessing row: another paladin's blessing counts only if it's the same one you would cast (it can't be on you twice); a different one (e.g. Might on you, you cast Kings) still asks for yours. Other class buffs from others (Fortitude, Arcane Intellect, Mark of the Wild) count as before.

## 0.6.41 (2026-11-17)

- Buff reminder: buffs someone else puts on you (e.g. a paladin's blessing or aura) no longer count for your own rows: they don't clear 'missing' for an item buff (XP food, elixir, sleeping bag...), aren't learned as an item's buff, and for a paladin another paladin's blessing isn't yours.

## 0.6.40 (2026-11-17)

- Pace / time left in a group: the kill pace is learned separately per group size (your party's kills count, and quest items drop for each of you). Until there's enough data in a group, it uses your solo pace divided by the group size; the PACE box shows the group size, e.g. '~19s / kill (3)'.

## 0.6.39 (2026-11-17)

- Ping question window redone in the panel's style: header, question, two answer buttons, a divider, and a three-way 'next time I join a group' switch (Ask / Always ping / Never ping).

## 0.6.38 (2026-11-17)

- Macro ping in 'ask' mode: solo it always pings; in a group it follows your answer to the question.

## 0.6.37 (2026-11-17)

- Macro ping: the default is 'ask when I join a group' (if you had turned ping off before, it stays off).

## 0.6.36 (2026-11-17)

- Ping in the QFocus macro has three settings (Macro & marker tab, /qf ping): always, never, or ask when you join a group. The question window (ping in this group / no ping) can change the setting for next time too. Solo there's no ping in ask mode.

## 0.6.35 (2026-11-17)

- Quest nearby popup can be dragged anywhere (the place is kept); right click puts it back to the default place.

## 0.6.34 (2026-11-17)

- Options: the version number is shown small after the name.

## 0.6.33 (2026-11-17)

- Buffs tab: Tracking has its own section (it's not a class buff).

## 0.6.32 (2026-11-17)

- Buff reminder Tracking row: if you know Find Minerals / Find Herbs / Find Fish, only these count and the reminder casts one of them (other tracking like Track Beasts doesn't silence it). Switch on the Buffs tab (Other).

## 0.6.31 (2026-11-17)

- Marker hopping: when you reach a marked spawn point and the mob / object isn't there (no living nameplate with that name after ~4 s), the point counts as checked for 5 minutes and the arrow moves on to the nearest unchecked spawn point ('Not here right now - next spawn point').

## 0.6.30 (2026-11-17)

- What next: the quest log route lists every quest now (scroll with the mouse wheel; the header says how many). Order: each next stop is the closest to the previous one; the yards are from you.
- Quests whose items come from boxes / objects (e.g. Anything of Value) get their locations from Questie's item data when the objective has none, so they show on the route and get a marker.

## 0.6.29 (2026-11-17)

- Vendor nearby: disappears as soon as you are more than 150 yd from the vendor (live distance); the row's title stays put and only the part after it scrolls.

## 0.6.28 (2026-11-17)

- Buff reminder warning rows (vendor nearby, bags, repair): the whole row is clickable (marker), and the text scrolls when it doesn't fit. 'Vendor nearby' shows a vendor icon, or the repair icon for a repairer, and only mentions your gear when a repairer is near.

## 0.6.27 (2026-11-17)

- Switching to another quest (also by tracking it) removes the old quest's marker and puts the arrow on the new quest's target; if the new quest has no known location, no old arrow is left pointing the wrong way.

## 0.6.26 (2026-11-17)

- Panel with a focused quest: no icon in front of the title, and the map / clear focus buttons sit right after the quest name.

## 0.6.25 (2026-11-17)

- Buff reminder out in the world: 'Vendor nearby' when a vendor / repairer is within ~150 yd and your bags are at least half full (or your gear is under 90%), e.g. 'bags 36/66, gear 85% - <vendor>'. Click: marker; X: hide until you move on.

## 0.6.24 (2026-11-17)

- Per character: the Buffs tab's ticks, chosen items, own buffs, minutes and class buff choices, and the city list's ignore list. Each character starts once from the old shared values, after that they are separate. Share settings exports / imports the current character's.

## 0.6.23 (2026-11-17)

- Travel: WoW Forever's own boat / zeppelin / airship list with exact dock positions from the game tables: Stormwind Harbor - Auberdine, the Menethil -> Southshore -> Auberdine loop (one way), Menethil - Theramore, Auberdine - Rut'theran, Feathermoon, Booty Bay - Ratchet, Steamwheedle Port - Powderfuse Port (Riverglades), the Zephras Isle airships (Dalaran for the Alliance, Skywatcher Plateau for the Horde) and the Horde zeppelins.

## 0.6.22 (2026-11-17)

- City list also opens in villages: within ~250 yd of an innkeeper counts as a town (not only resting in the inn); it closes when you walk away, and never pops up on a flight path.
- Directions only lists what is around (within ~700 yd): in a small village no Auction House or Bank line; Profession Trainer only when one is nearby.

## 0.6.21 (2026-11-17)

- What next: 'Next zone' line on top. 'Go to <zone>' when another zone has 5+ quests from your log (more than here); otherwise the nearest zone with 5+ quests to pick up for your level. 'Hearth back to <zone>' when the Hearthstone is the fastest way. Hover: the quests and the way; click: marker. Switch: Route & progress tab.
- Travel: boats, zeppelins and the Deeprun Tram count in travel times and advice (also to the other continent); the Hearthstone (with its cooldown) is part of the route search.
- The nearby quest popup no longer shows while you are on a flight path.

## 0.6.20 (2026-11-17)

- Directions > Profession Trainer: every profession has its icon.

## 0.6.19 (2026-11-17)

- City list: the quest chain tag (chain icon + 2/5) is clickable: it opens your quest log at the quest of that chain you already have; hover shows which one.

## 0.6.18 (2026-11-17)

- City list: 'Start dungeon' is now 'Dungeon quests'; a thin line separates the bottom buttons; XP and distance sit closer to the quest name.
- Directions menu opens beside the city list and is narrower; the distance shows when you hover a line.

## 0.6.17 (2026-11-17)

- City list: the Bank / AH / Trainer buttons are replaced by one 'Directions' drop-down, like asking a guard: Auction House, Bank, Flight Master, Inn, Class Trainer, Profession Trainer (sub-menu, your professions first), Weapons Trainer, Repair, Food & Drink, Battlemaster (hunters: Stable Master, Ammo). Each shows the distance to the nearest one; click for a marker.

## 0.6.16 (2026-11-17)

- Buff reminder, out in the world (not in cities / inns): 'Bags filling up / full' and 'Gear worn / broken' rows, using the City to-do thresholds. Click the icon for a marker on the nearest vendor / repairer; X hides it until fixed. Switch: Options > Buffs.

## 0.6.15 (2026-11-17)

- Fix: the city list's resize corner was invisible (broken texture path); now it shows like the panel's.

## 0.6.14 (2026-11-17)

- City list is resizable: drag the bottom right corner (width, and how many quests show without scrolling); saved, right-click the corner for the default size.
- City list: removed the estimated quest length (~3m) from the rows.

## 0.6.13 (2026-11-17)

- City list: Bank and AH buttons use the game's own banker / auctioneer tracking icons.

## 0.6.12 (2026-11-17)

- City list: flat buttons in the list's own style instead of the red ones; Bank / AH / Trainer have small icons (Trainer shows your class icon).
- City list: in a skipped place the button reads 'Remove from ignore list'; the Options section is now 'Ignore list'.

## 0.6.11 (2026-11-17)

- Options: Quest pickup split in two tabs. Quest pickup = the nearby popup out in the world and the quest level range; City list = the list in cities / inns, skipped places, to-do thresholds. Each starts with a short intro and its on / off switch.
- City list tab: skipped places are listed one per line with a Remove button (Remove all when there are several).

## 0.6.10 (2026-11-17)

- City list: 'Ignore this place' is now 'Don't open here again' (and 'Open here again'); the tooltip names the place and says other cities are not affected.

## 0.6.9 (2026-11-17)

- Weapon enchant rows recognise items by their tooltip ('Use:' text) instead of a fixed name list: any stone, oil, poison or Scroll of Imbue that temporarily enchants a weapon is found, and only offered for a weapon it fits (sharp / blunt, or the named type: dagger, staff, sword...).

## 0.6.8 (2026-11-17)

- Weapon enchant rows: mage Scroll of Imbue (e.g. Lesser Flame) counts as a weapon enchant, offered only when a staff is equipped.

## 0.6.7 (2026-11-17)

- City list title row: Trainer (nearest trainer of your class) and AH (nearest auctioneer) next to Bank; hover shows the nearest one and its distance, click puts a marker on it.

## 0.6.6 (2026-11-17)

- Fix: 'attempt to call a nil value' in GetItemCount / GetItemInfoInstant (Bags, Buffs). Item lookups now use the C_Item API first and the old one as a fallback, both protected, so a broken item function can't stop the modules.

## 0.6.5 (2026-11-17)

- City to-do: bags full warning (default 70% used, or fewer than 10 free slots) with the nearest vendor to sell to; the quest list stays below it.
- Quest pickup tab: 'City to-do' thresholds for bags (% and free slots), repair % and hunter ammo; 0 turns a line off.

## 0.6.4 (2026-11-17)

- City list: a to-do section above the quests - repair (most worn item under 60%), hunter ammo (under 400), no XP food in your bags - each with the nearest repairer / ammo vendor / food vendor; click for a marker.
- City list: Bank button in the title row (marker on the nearest banker). NPCs come from Questie's town data, your faction only.

## 0.6.3 (2026-11-17)

- Buffs tab: choosing an item / spell for a row (icon click or drag) also ticks that row on.

## 0.6.2 (2026-11-17)

- XP food picker: removed the leftover 'Don't ask again' button (it silently turned off the login setup question).

## 0.6.1 (2026-11-17)

- Less CPU: quest changes come from specific events (accepted, turned in, removed, objective progress) instead of every quest log update (that one is only a fallback if the client never sends the others).

## 0.6.0 (2026-11-17)

- Folders renamed to AdventurersKit, AdventurersKit_Bags, AdventurersKit_Buffs (the CPU / addon lists now say Adventurer's Kit). A small code-free 'QuestFocus' folder carries your old settings over; delete it after one login.
- Less CPU: nearby-quest, pickup-popup and city-list scans only run again after you move (or the quest log changes); nameplate picking only with a focused quest; usable quest items and buff items are cached until your bags change; item-info events from other addons no longer rebuild the buff reminder; the bag quest item scan only runs while the bag is open and the quest item list is expanded.
- Summary of 0.5.x: Start dungeon (Dungeon Journal), panel icon row, settings export / import, map buttons, vendor markers.

## 0.5.5 (2026-11-17)

- Map button: the focused quest's zone header is expanded and the quest is selected in the quest log (the quest list next to the map follows it); other collapsed headers stay collapsed.

## 0.5.4 (2026-11-17)

- Map button also opens the focused quest in the map's quest panel, when the client has one.

## 0.5.3 (2026-11-17)

- Vendors (e.g. a trade supplies NPC selling a quest item) always get a marker; it no longer says 'you are in the spawn area' when the vendor is nearby but hidden in a building.
- Map button: on the panel before the clear-focus button, and at the end of every open objective row; it opens the world map on the target and puts the marker there.

## 0.5.2 (2026-11-17)

- Share settings tab (and /qf export, /qf import): your settings as text to send to others, or load theirs. Item choices (XP food, sleeping bag, stones / oils, own item buffs) are only taken if the importer has the item; class settings only for the same class; panel position, ignore list and kill pace are not shared.
- XP food: only real food / drink is listed (camp tents, sleeping bags and scrolls no longer show up).
- Buff reminder: the weapon enchant and XP food rows always have the small arrow to choose another one.

## 0.5.1 (2026-11-17)

- Spacing: the chain icon no longer touches the quest name / 2/5, '(in log)' sits further right, and the panel's top icons no longer touch the close button.

## 0.5.0 (2026-11-17)

- Start dungeon: skull button on the panel (and /qf dungeon) lists the dungeons for your level with their quests. With the Dungeon Journal addon it uses its data (Forever's own dungeons too) and opens the quest there; without it, a similar list from Questie and a click puts a marker on the quest giver.
- Dungeon quests in the city list and the pickup popup get a small skull button (Start dungeon); the city list has a 'Start dungeon' button when it shows dungeon quests.
- Panel: a small icon row on top (options, dungeons, close); the quest name is one line lower, with the clear-focus button at its end.
- Quest chains show the Dungeon Journal's chain icon (when it's installed).
- Summary of 0.4.x: buff tracking reworked (groups, weapon type aware stones / oils, setup popup, per-row X), usable quest items on objective rows, bag highlight fix, dungeon quest highlight, 'Disable city list everywhere'.

## 0.4.10 (2026-11-17)

- Dungeon and raid quests are highlighted in the city list (tinted row) and the pickup popup, with the dungeon's full name in front of the quest, e.g. [Dungeon: Wailing Caverns]; the tooltip says it needs a group.
- City list button renamed to 'Disable city list everywhere': it turns the list off in every city and inn, not just here.

## 0.4.9 (2026-11-17)

- Weapon enchant rows only for a hand that holds a melee weapon: with a two-hander the off-hand row is gone (Buffs tab, setup popup, reminder); it comes back when you equip an off-hand weapon.

## 0.4.8 (2026-11-17)

- Buffs tab: three groups - items (sleeping bag, XP food, weapon enchants), class buffs, and your own additions.
- Weapon swap (out of combat): stones / oils / poisons are picked to fit the new weapon (sharpening stone for edged, weightstone for blunt); if nothing fits, the buff reminder row says so and lets you choose. Ranged-only hands are ignored.

## 0.4.7 (2026-11-17)

- XP food, sleeping bag, weapon enchants and class buffs are always on by default (hunters too); found items / spells are set automatically.
- First login on a character: if nothing is found for a ticked item buff, a popup offers to set it up (Set up / Later / Don't ask again).

## 0.4.6 (2026-11-17)

- Buff reminder: ticked item buffs (sleeping bag, weapon enchant, your own items) show up even when you have none in your bags; click the icon to choose one, or drag an item onto it.
- Buff reminder: a small X at the end of each row stops watching that buff (tick it again on the Buffs tab).

## 0.4.5 (2026-11-17)

- Tracking reminder fixed: it now checks by name whether one of your tracking spells is really active (it used to think something was on when nothing was).

## 0.4.4 (2026-11-17)

- XP food picker lists only XP food (food whose description mentions experience); others can still be dragged onto the XP food icon.
- Hunters: main / off-hand enchant are off by default (tick them on the Buffs tab if you want them).

## 0.4.3 (2026-11-17)

- Usable quest items: only for the selected quest and nearby objectives, as a small button at the end of the objective row on the panel.
- ALSO NEARBY row click: focuses that quest and that objective (marker + arrow + macro).

## 0.4.2 (2026-11-17)

- Usable quest item buttons: only items the quest gives you to use (or quest-type objective items), not collected consumables like drinks or food.
- Options: when a module is off, the rest of its tab is greyed out and can't be clicked.

## 0.4.1 (2026-11-17)

- Bag highlight fixed: clicking an item in the quest item list highlights it in the open bag (Bagnon or Blizzard bags) and dims the rest; click again to clear.

## 0.4.0 (2026-11-17)

- New name: Adventurer's Kit (formerly QuestFocus). Folders, /qf, the QFocus macro and your settings stay the same.
- Panel: a small button next to the close button clears the focus (the quest stays in your log), same as /qf clear.
- Summary of 0.3.1 - 0.3.9: buff tracking rework (ticks, off-hand / poisons / shaman imbue, custom items and buffs, item count), module on/off switches, usable quest items on the panel, per-state macro icons, zone switch prompt, unknown length for battleground quests, route distances from you.

## 0.3.9 (2026-11-17)

- Route list: every stop shows its straight-line distance from you (no more '+N yd' from the previous stop). The order is still nearest-next.

## 0.3.8 (2026-11-17)

- Buff reminder: item buffs show how many you still have in your bags (on the icon and as xN).

## 0.3.7 (2026-11-17)

- Buff buttons under the panel removed.
- Buffs tab: every type with a tick (watch / don't watch), its item or spell (click the icon to choose), and minutes; 0 = remind only when it's missing.
- New types: off-hand enchant (only with an off-hand weapon), rogue poisons on both hands, shaman weapon imbue (Windfury / Flametongue / Frostbrand / Rockbiter).
- Add buff: any item (flask, elixir, scroll, juju) or any buff by spell ID / name, or picked from the buffs on you; castable ones are cast from the reminder, others only remind.

## 0.3.6 (2026-11-17)

- Pickup quest length: '?' / 'length unknown' instead of a misleading guess for battleground quests (e.g. Arathi Basin) and items whose source is unknown.

## 0.3.5 (2026-11-17)

- Bags and Buffs tabs start with a 'Module on' switch (on by default): off keeps the module loaded but it does nothing; no reload needed.
- Fixes a syntax error in 0.3.4 that broke the options window.

## 0.3.4 (2026-11-17)

- Module enable switch via the AddOns list (replaced in 0.3.5; this build had an options error).

## 0.3.3 (2026-11-17)

- Usable quest items of every active quest are on the panel's left edge (up to 4, selected quest first) instead of the bag list.

## 0.3.2 (2026-11-17)

- Macro icons per state (hunting, turn-in, no quest): Macro & marker tab, click an icon to pick from a list opening to the side; the panel icon follows. /qf icon <name> sets all three.

## 0.3.1 (2026-11-17)

- Zone focus: entering another zone with quests asks Switch / Keep / Turn off focus (or switch without asking: Zone focus tab).
- Minimap tooltip shows the new zone focus state right after a right click.

## 0.3.0 (2026-11-17)

- Options reorganized into feature tabs (General, Macro & marker, Route & progress, Quest pickup, Zone focus, Bags, Buffs) with a short description under every option.
- Chat messages can be turned off (General tab or /qf chat): then only one line at login and the replies to your own commands.
- Release notes tab (this page) and a what's-new line at login after an update.
- City list: scrollable, XP reward, quest chain position (e.g. 2/10), item-start tag; 'Ignore this place' and 'Disable city list' buttons; reopens after relog.
- Bag list collapsed: a slim tab on top of the bag frame.
- Buff reminder: no raid warning sound, a short gold flash only the first time a buff goes missing.

## 0.2.0 (2026-11-17)

- Split into modules: QuestFocus (core), QuestFocus_Bags and QuestFocus_Buffs (separate addons, can be disabled).
- Shared tooltip style for panel rows, suggestions, popups, the city list and the quest log.
- Turn-in mode: the next quests of your quest-log route at the bottom of the panel.
- Panel keeps its top left corner when its height changes.
- City mode with travel advice (walk / Hearthstone / flight); nearby pickup popups; zone focus prompt.
- Nearby quests: mobs of other quests within 200 yd go into the macro too (ALSO NEARBY).
- Class buff and tracking reminders, XP food picker, bag item focus highlight in Bagnon.
- Fixes: combat 'secret value' errors (auras, run speed), no combat log registration, blocked actions.

## 0.1.0 (2026-11-16)

- First alpha: QFocus target macro, markers (own arrow or TomTom), quest tooltips, zone focus, minimap button.
- Quest item list next to the bags, Bagnon coloring, use-item button with keybind.
- Panel with time-left estimate, quest suggestions, progress popup and buff reminders.
