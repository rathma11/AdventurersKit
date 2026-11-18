-- QuestFocus: release notes (Options > Release notes, /qf notes) es a bejelentkezo sor.
-- Uj verzional: a .toc fajlokban a Version, es egy uj blokk a NOTES tetejere.
local ADDON_NAME, NS = ...
local L = NS.L

-- Patch (x.y.Z): minden valtozas; minor (x.Y.0): release (git tag + zip a releases\ mappaba).
local NOTES = {
    { version = "0.7.11", date = "2026-11-18", items = {
        "Options > About: the addon's name, version and a short description, every feature in one sentence grouped "
            .. "by area, the main /qf commands and a button to these release notes. The same list is in FEATURES.md.",
    } },
    { version = "0.7.10", date = "2026-11-18", items = {
        "Auction house: a coin tab on the right of the auction house window opens \"Quest items to buy\": the "
            .. "items your quests still need that can be sold there (quest-only and soulbound items are left out), "
            .. "with the count, the quest, and the cheapest price from a quick lookup of each item (plus the "
            .. "Auctionator / TSM price when installed).",
        "Click a row to search for the item in the auction house. Buy asks once (\"Buy 4 x Linen Cloth for 3s 20c?\"), "
            .. "then buys one auction per click (the game needs a click for every purchase) and never pays more than "
            .. "the price you confirmed. At the bottom: the total if you buy all, and Buy all. Bought items arrive in "
            .. "your mailbox and already count as yours on the list.",
        "Options > Auction house: 'Show quest items tab at the auction house' (on by default).",
    } },
    { version = "0.7.9", date = "2026-11-18", items = {
        "City list: a town icon on the quest panel (between the farm clock and the dungeon icon) opens and closes "
            .. "it, also outside towns: then it shows nearby quests, errands and Directions to the nearest bank, "
            .. "trainers... Same as /qf city (it now toggles).",
        "City list: new option 'Open automatically in towns' (Options > City list, on by default). Off: the list "
            .. "only opens from the icon or /qf city.",
        "City list: 'Don't open here again' and 'Disable city list everywhere' are gone, with the per-place ignore "
            .. "list and /qf cityreset. Saved ignored places are cleared. The City list tab is tidier.",
    } },
    { version = "0.7.8", date = "2026-11-18", items = {
        "Farm session on the quest panel: it shows like a quest, titled \"Farm session\" with a clock. The boxes show "
            .. "time, XP per hour and gold per hour; the rows show XP gained, XP to level with an ETA, mobs killed, "
            .. "looted gold, item value at vendor price and the best sale value. Hover a row for the top items.",
        "Farm session: it is the first stop of the route while it runs. The next arrow goes to your quests (the "
            .. "session keeps running), the back arrow or its route row brings it back. Clicking a quest also switches.",
        "Farm session: the clock button glows green and shows a red X while a session runs; click it to stop. "
            .. "Stopping opens a summary window (duration, kills and top mobs, XP, levels, looted gold, items, gold per "
            .. "hour) with Start new / Close, and prints one line to chat. Switch the window off in Options > Route & "
            .. "progress. /qf farm show brings the session back to the panel.",
        "Fix: the separate farm box (0.7.6) showed only its first line, cut with \"...\". It is gone; the panel shows "
            .. "the session instead.",
    } },
    { version = "0.7.7", date = "2026-11-18", items = {
        "Behind the scenes: the addon's look (dark background, gold border, orange strip, flat gold buttons, "
            .. "thin gold scrollbar) is now written down with shared building blocks, so new windows match the "
            .. "quest panel. Nothing changes in game yet.",
    } },
    { version = "0.7.6", date = "2026-11-18", items = {
        "Farm session: a new coin button on the quest panel (or /qf farm) starts a small \"Farm session\" box: "
            .. "time, XP gained and XP per hour, XP to level with an ETA, looted gold, looted items at vendor price, "
            .. "and with Auctionator / TSM / Auctioneer a \"best sale\" value (auction or vendor price, whichever is "
            .. "higher). Hover it for the top 5 items; /qf farm stop prints a summary. /qf farm pause | resume | reset.",
        "Farm session: looted gold only counts money you loot (not vendor sales or quest rewards; those show in "
            .. "\"Net gold change\"). The session survives /reload and relog; time while logged out is not counted.",
        "Panel: the icon order is now farm, dungeons, options, close (options sits next to the X).",
    } },
    { version = "0.7.5", date = "2026-11-18", items = {
        "Fix: the QFocus macro no longer pings a mob that isn't a quest mob. In combat the macro can't be "
            .. "rewritten and keeps any living enemy you target (e.g. one that attacked you), so it now only pings "
            .. "out of combat, where it has already checked the target.",
        "Escort: the star raid icon only goes on the escort NPC itself (its NPC ID from the quest data, or the "
            .. "exact name), never on an enemy unit.",
        "Fix: Buff reminder: another player's class buffs (a druid's Mark of the Wild / Thorns) no longer count "
            .. "as yours when the game doesn't tell who cast them. Food and item buffs (XP food) still do.",
    } },
    { version = "0.7.4", date = "2026-11-18", items = {
        "Fix: \"Dungeons for your level\" lists WoW: Forever's own dungeons again (The Drowned City, Krol'dok "
            .. "Stronghold, Alcaz Prison, Blackmaw Hold, Shaper's Terrace, Hall of Thanes, City of Dalaran, Excavation "
            .. "Site: Wetlands, Ruins of Lordaeron). Their levels and quests are built in; no extra addon needed.",
        "Fix: Razorfen Kraul, Uldaman, Zul'Farrak and Sunken Temple showed 0 quests (Questie files their quests "
            .. "under a different area). Their quests are listed, and dungeon prep finds them.",
    } },
    { version = "0.7.3", date = "2026-11-18", items = {
        "Dungeon prep: quest chains show up. If a dungeon quest needs earlier quests first (e.g. The Defias "
            .. "Brotherhood), the list shows the chain's next step with its quest giver, marked as chain step N/M.",
        "Dungeon prep: quests you can't pick up yet are listed greyed at the end (e.g. \"from level 17\").",
        "Dungeon prep: a quest that starts from a looted item (The Unsent Letter from VanCleef) is no longer a "
            .. "pickup row; it is in the \"starts inside the dungeon\" note, and the \"No known location\" chat spam is gone.",
        "Dungeon prep: the Entrance row is replaced by two buttons next to the title: the entrance on the world map, "
            .. "and the game's group finder.",
        "Dungeon data comes only from Questie now; the Dungeon Journal addon is only opened (Shift+click), not read.",
        "Panel: while you drag the resize grip, the rows follow right away (they used to stay put until you let go).",
    } },
    { version = "0.7.2", date = "2026-11-18", items = {
        "Fix: during dungeon prep the \"What next?\" suggestions (next zone, route, pick up nearby) were sometimes "
            .. "drawn over the prep list. Now only the prep list shows until prep ends.",
    } },
    { version = "0.7.1", date = "2026-11-17", items = {
        "Fix: a syntax error in the dungeon boss table (since 0.6.67) kept boss order inside dungeons from working "
            .. "(the panel fell back to quest log order).",
        "/qf selftest: a quick self check on your live data (Questie, quest objectives, QFocus macro length, settings, "
            .. "dungeon entrances, boat / zeppelin table). One summary line; details only if something fails.",
    } },
    { version = "0.7.0", date = "2026-11-17", items = {
        "Dungeon prep: click a dungeon to get a checklist of its quests to pick up, then the entrance; inside the "
            .. "dungeon the panel lists every quest objective in boss order, and in a group you can share the dungeon "
            .. "quests with the party. Aborting goes back to the quest you had before.",
        "Quest panel: fixed size with shared space for objectives, Also nearby and the route; previous / next quest "
            .. "arrows (with key bindings), skipped quests saved per character; thin scrollbars.",
        "QFocus macro: keeps a living enemy you clicked; ping modes (always / never / ask in a group); escort quests.",
        "Travel: next zone suggestion; boats, zeppelins, tram and hearthstone in route planning, with WoW Forever's "
            .. "own transport routes.",
        "City list: to-do section (repair, ammo, XP food, bags), Bank / Trainer / AH buttons, Directions menu, works "
            .. "in villages with an innkeeper, resizable.",
        "Buff reminder: tiered bags warning by free slots and vendor distance, one Vendor nearby row, gear warning "
            .. "outside towns, per-character buff settings, gathering tracking first, others' buffs handled correctly. "
            .. "A sleeping bag out in the world is not town.",
        "Less CPU: quest changes from specific events instead of every quest log update; safer item API calls.",
    } },
    { version = "0.6.68", date = "2026-11-17", items = {
        "Inside the dungeon, quests that start outside and you didn't pick up are no longer in the list: one dim "
            .. "\"Missed outside: N\" line at the end, with their names in its tooltip.",
        "Dungeon prep in a group: when you zone into the dungeon, a small window (same look as the ping question) "
            .. "asks whether to share your dungeon quests with the party. Tick the ones you want and press Share; they "
            .. "are shared one by one. Only out of combat (otherwise right after the fight), once per entry, and only "
            .. "if at least one of them can be shared. Off switch: Options > Route & progress > Dungeon prep.",
    } },
    { version = "0.6.67", date = "2026-11-17", items = {
        "Dungeon prep continues inside the dungeon: when you zone into the prepped dungeon, the panel lists all its "
            .. "quests in your log in boss order (built-in boss order for the classic and Forever dungeons; otherwise "
            .. "quest log order), each with every objective under it: kills, loot, objects to click, turn-ins inside. "
            .. "Quests from your log whose open objectives point into this instance are listed too, so nothing is missed.",
        "Quests you can pick up inside (an NPC in the dungeon, or an item that drops there) show as \"!\" rows at "
            .. "their place in the run. Before you go in, the prep list shows them as \"+N quests start inside\".",
        "The next thing to do is highlighted, with a hint (which boss, which object), and the QFocus macro targets "
            .. "its mobs (or the NPC to talk to). Quest items you have to use get the Bags module's use button on the "
            .. "row.",
        "No arrow inside: Questie has no coordinates for mobs in instances and the game gives no map position "
            .. "there, so the panel shows the Next hint instead (if both ever exist, the marker / arrow works).",
        "When all of the dungeon's quests are done (and nothing is left to pick up), the mode ends and you are back "
            .. "on the quest you had before. Leaving the dungeon with quests still open goes back to the prep list.",
    } },
    { version = "0.6.66", date = "2026-11-17", items = {
        "Dungeon list: a plain click on a dungeon or one of its quests now starts dungeon prep for that dungeon (the "
            .. "panel shows its quests to pick up, then the entrance). Shift+click does what a click did before (Dungeon "
            .. "Journal page, or without it a marker on the quest giver).",
        "Aborting dungeon prep (the small red circle next to the title, or /qf dungeon off) takes you back to the quest "
            .. "and objective you had focused before you started, with its marker and macro. If that quest is no longer "
            .. "in your log, you get the normal suggestion view.",
    } },
    { version = "0.6.65", date = "2026-11-17", items = {
        "Dungeon prep mode: pick a dungeon and the panel turns into a checklist for it. It lists the dungeon's quests "
            .. "you can still pick up (quest giver, zone, distance; nearest first), the ones already in your log "
            .. "(ticked), and last the entrance with its zone. The marker / TomTom arrow goes to the nearest quest "
            .. "giver; when you have them all, it moves to the entrance. Click a row to send the marker there, "
            .. "right-click for automatic again.",
        "Start it with the Prep button (or a right click) on a dungeon in the dungeon list, or /qf dungeon <name> "
            .. "(part of the name is enough, e.g. /qf dungeon scarlet). Leave it with the X next to the title or "
            .. "/qf dungeon off. It is saved per character and comes back after a reload. Clicking a quest in your log "
            .. "also ends it.",
        "In prep mode the QFocus macro does not target mobs: near a quest giver (60 yd) it targets that NPC, "
            .. "otherwise it does nothing.",
        "Entrance locations for the classic dungeons and Forever's own (Krol'dok Stronghold, Alcaz Prison, Blackmaw "
            .. "Hold, Shaper's Terrace, Hall of Thanes and more) are built in; no extra addon needed.",
    } },
    { version = "0.6.64", date = "2026-11-17", items = {
        "Sleeping bag: the city list no longer flashes up for a moment right after you lie down.",
    } },
    { version = "0.6.63", date = "2026-11-17", items = {
        "Lying in a sleeping bag out in the world no longer counts as being in town: the city list doesn't open, and "
            .. "the outside warnings (bags filling up, repair, vendor nearby) still show. Near an innkeeper it's town as before.",
    } },
    { version = "0.6.62", date = "2026-11-17", items = {
        "Quests you skip with the next arrow stay skipped after a reload or relog (saved per character). A loading "
            .. "screen no longer brings them back.",
        "All skips end when the quest you moved to is ready to turn in, or you turn in any quest. One skipped quest "
            .. "comes back when you pick it yourself (quest log, tracking, route row, back arrow), when it makes "
            .. "progress (a kill or drop), when you get within ~150 yd of its target after being farther away, or when "
            .. "it leaves your log.",
        "If every other quest is skipped, the route lists the skipped ones nearest first, and the next arrow cycles "
            .. "through them.",
    } },
    { version = "0.6.61", date = "2026-11-17", items = {
        "The route on the quest panel shows at most 3 quests; scroll for the rest (or hover its header). The space it "
            .. "frees goes to the Also nearby list.",
    } },
    { version = "0.6.60", date = "2026-11-17", items = {
        "Scrollable lists on the panel (objectives, route) get a thin gold scrollbar on the right edge instead of the "
            .. "word \"scroll\". It only shows when the list doesn't fit; drag it, click the bar, or use the mouse wheel.",
    } },
    { version = "0.6.59", date = "2026-11-17", items = {
        "Previous / next quest arrows next to the quest name on the panel. Next goes to the first stop of the route "
            .. "(ready-to-turn-in quests count too); the marker, the TomTom arrow and the QFocus macro switch over. "
            .. "Previous goes back to the quests you focused before, like a browser's back button. Hover an arrow to "
            .. "see where it takes you and how far it is.",
        "A quest you skip with the next arrow moves to the end of the route (shown dimmed) until the quest you moved "
            .. "to is ready to turn in, you turn in any quest, or a loading screen comes. Not saved between sessions.",
        "Key Bindings: \"Next quest\" and \"Previous quest\" under Adventurer's Kit (with the Bags module's use-item key).",
    } },
    { version = "0.6.58", date = "2026-11-17", items = {
        "The QFocus macro keeps the quest mob you clicked: if your target is a living enemy, pressing the macro no "
            .. "longer clears it or switches to another mob (in nameplate mode too). A dead or friendly target is still "
            .. "replaced. Out of combat, a living enemy that is not a quest mob (or is tapped by someone else) is still "
            .. "swapped for the nearest quest mob.",
    } },
    { version = "0.6.57", date = "2026-11-17", items = {
        "Buff reminder, out in the world: at a vendor you get one \"Vendor nearby\" row instead of a separate Bags "
            .. "(and Gear) row. It shows your bags (used / free) and, if a repairer is near, your gear %.",
        "The Bags row now goes by free slots, not percent: at 10 free (your limit in Options) when a vendor is within "
            .. "300 yd, at 5 free within 600 yd, and at 2 or full always, with the nearest vendor, in a stronger color.",
    } },
    { version = "0.6.56", date = "2026-11-17", items = {
        "The quest panel has a fixed size now: its width and height follow the text size (Options), so the bottom never "
            .. "moves. The resize handle only shows in the \"What next?\" list.",
        "Space in the panel: \"Also nearby\" and the route get at least 3 rows each (when there are that many), the "
            .. "objectives get the rest. If there are too many objectives to fit, they scroll with the mouse wheel. Spare "
            .. "space goes to nearby quests (up to 4 rows), then the route (up to 5), then more of both.",
        "The route (your other quests in route order) shows while hunting too, not only at turn-in. It scrolls in its "
            .. "own area; if no row fits, hover its header to see the list. The [+]/[-] toggle is gone.",
        "Shorter rows: a part repeated at the start of every objective (e.g. \"Green Hills of Stranglethorn - \") is "
            .. "left out, so you see \"Chapter I\", \"Chapter II\"... The same goes for a quest's rows under Also nearby "
            .. "(\"Page 8\", \"Page 14\"). The full text is in the tooltip.",
        "The Buff Reminder bar always has the panel's width.",
    } },
    { version = "0.6.55", date = "2026-11-17", items = {
        "After login the quest panel waits until its content has settled (objectives, nearby quests, route) and then "
            .. "appears at once, instead of rows sliding in one by one. Clicking a quest shows it right away.",
        "\"Also nearby\" follows the panel's height too. When you shrink the panel, the route goes first, then the nearby "
            .. "list (down to 1 row + \"+N more\"). When you drag it taller, the nearby list grows past 3 rows.",
    } },
    { version = "0.6.54", date = "2026-11-17", items = {
        "Fix: after you expanded the route list, resizing and clicking near the bottom of the panel stopped working. "
            .. "The list's off-screen rows were invisible but still caught the mouse. Only the visible rows are active now, "
            .. "and the resize handle always stays on top.",
    } },
    { version = "0.6.53", date = "2026-11-17", items = {
        "Quest panel: dragging the resize handle now sets the panel's maximum height, and the content is rearranged "
            .. "while you drag. The route list shrinks to 4, then 3 rows and so on, and collapses to its header when "
            .. "nothing fits. Right click on the handle resets it.",
        "The route header's [+] / [-] toggle is visible now (the icon didn't show before). It reads \"+N hidden - click\"; "
            .. "expanded, the scrollable list is as tall as the space left (at least 3 rows).",
    } },
    { version = "0.6.52", date = "2026-11-17", items = {
        "The quest panel keeps a steady maximum height. The \"Route (quest log)\" list gets only the rows that still "
            .. "fit below the objectives and nearby quests. If some stops don't fit, its header shows \"+N hidden\": "
            .. "click it to open the whole route in a scrollable list, click again to collapse. The panel remembers your choice.",
        "\"Also nearby\" shows at most 3 rows plus a \"+N more\" row; hover it to see the rest. The macro still targets all of them.",
    } },
    { version = "0.6.51", date = "2026-11-17", items = {
        "Escort quests without an event objective in Questie (e.g. Zimmix's Great Escape in Stranglethorn) are "
            .. "recognised from the quest's objective text (\"Escort X ...\"). The marker then points to the turn-in NPC.",
    } },
    { version = "0.6.50", date = "2026-11-17", items = {
        "Escort quests: the panel shows who you escort, their health (warning with a sound below 35%) and where to. "
            .. "The QFocus macro targets whatever is attacking the escort, otherwise the escort itself. The marker goes "
            .. "to the escort's end point. If the escort fails, the marker and the macro point to the quest giver to restart.",
        "A star raid icon goes on the escorted NPC when you target or mouse over it (solo, in a party, or as raid "
            .. "leader / assist). An icon already on it is left alone. Option: Macro & marker tab.",
    } },
    { version = "0.6.49", date = "2026-11-17", items = {
        "XP food row: a Well Fed buff with bonus kill XP (e.g. +5% from Longjaw Mud Snapper) counts. The buff's spell "
            .. "description is checked too, not just its tooltip. /qf debug lists your long buffs and whether each one is an XP buff.",
    } },
    { version = "0.6.48", date = "2026-11-17", items = {
        "XP food row: an active food buff (e.g. Well Fed from Longjaw Mud Snapper) counts again. The food buff's caster "
            .. "is no longer checked, and a buff description that hasn't loaded yet is retried instead of being remembered as 'no XP'.",
    } },
    { version = "0.6.47", date = "2026-11-17", items = {
        "Fixed a Lua error outside towns (vendor distance in the buff reminder). Also fixed the raid-quest tag in "
            .. "tooltips and the travel steps of the next-zone suggestion, which were never filled in.",
    } },
    { version = "0.6.46", date = "2026-11-17", items = {
        "Tracking a quest (the tick in the quest log / map list, shift-click) focuses it: marker and arrow go to the "
            .. "newly tracked quest. Auto-tracking right after accepting a quest doesn't switch focus.",
    } },
    { version = "0.6.45", date = "2026-11-17", items = {
        "Bags row tiers: 80%+ full now reports a vendor within 300 yd (was 400).",
    } },
    { version = "0.6.44", date = "2026-11-17", items = {
        "Bags row out in the world is tiered: 70%+ full when a vendor is within 100 yd, 80%+ within 400 yd, 90%+ within "
            .. "600 yd, 95%+ (or fewer free slots than your limit) always, with the nearest vendor. 'Vendor nearby' then "
            .. "only adds repairs, so the two rows don't repeat each other.",
    } },
    { version = "0.6.43", date = "2026-11-17", items = {
        "Buff reminder out in the world: the Bags row only comes up when free slots really run low (under the "
            .. "'fewer free slots than' limit, default 10, or full) - a percentage alone isn't worth a long walk. "
            .. "It shows how far the nearest vendor is; a vendor close by is still reported by 'Vendor nearby'.",
    } },
    { version = "0.6.42", date = "2026-11-17", items = {
        "Paladin blessing row: another paladin's blessing counts only if it's the same one you would cast "
            .. "(it can't be on you twice); a different one (e.g. Might on you, you cast Kings) still asks for yours. "
            .. "Other class buffs from others (Fortitude, Arcane Intellect, Mark of the Wild) count as before.",
    } },
    { version = "0.6.41", date = "2026-11-17", items = {
        "Buff reminder: buffs someone else puts on you (e.g. a paladin's blessing or aura) no longer count for your own "
            .. "rows: they don't clear 'missing' for an item buff (XP food, elixir, sleeping bag...), aren't learned as an "
            .. "item's buff, and for a paladin another paladin's blessing isn't yours.",
    } },
    { version = "0.6.40", date = "2026-11-17", items = {
        "Pace / time left in a group: the kill pace is learned separately per group size (your party's kills count, "
            .. "and quest items drop for each of you). Until there's enough data in a group, it uses your solo pace "
            .. "divided by the group size; the PACE box shows the group size, e.g. '~19s / kill (3)'.",
    } },
    { version = "0.6.39", date = "2026-11-17", items = {
        "Ping question window redone in the panel's style: header, question, two answer buttons, a divider, "
            .. "and a three-way 'next time I join a group' switch (Ask / Always ping / Never ping).",
    } },
    { version = "0.6.38", date = "2026-11-17", items = {
        "Macro ping in 'ask' mode: solo it always pings; in a group it follows your answer to the question.",
    } },
    { version = "0.6.37", date = "2026-11-17", items = {
        "Macro ping: the default is 'ask when I join a group' (if you had turned ping off before, it stays off).",
    } },
    { version = "0.6.36", date = "2026-11-17", items = {
        "Ping in the QFocus macro has three settings (Macro & marker tab, /qf ping): always, never, or ask when you join a group. "
            .. "The question window (ping in this group / no ping) can change the setting for next time too. Solo there's no ping in ask mode.",
    } },
    { version = "0.6.35", date = "2026-11-17", items = {
        "Quest nearby popup can be dragged anywhere (the place is kept); right click puts it back to the default place.",
    } },
    { version = "0.6.34", date = "2026-11-17", items = {
        "Options: the version number is shown small after the name.",
    } },
    { version = "0.6.33", date = "2026-11-17", items = {
        "Buffs tab: Tracking has its own section (it's not a class buff).",
    } },
    { version = "0.6.32", date = "2026-11-17", items = {
        "Buff reminder Tracking row: if you know Find Minerals / Find Herbs / Find Fish, only these count and the reminder "
            .. "casts one of them (other tracking like Track Beasts doesn't silence it). Switch on the Buffs tab (Other).",
    } },
    { version = "0.6.31", date = "2026-11-17", items = {
        "Marker hopping: when you reach a marked spawn point and the mob / object isn't there (no living nameplate with "
            .. "that name after ~4 s), the point counts as checked for 5 minutes and the arrow moves on to the nearest "
            .. "unchecked spawn point ('Not here right now - next spawn point').",
    } },
    { version = "0.6.30", date = "2026-11-17", items = {
        "What next: the quest log route lists every quest now (scroll with the mouse wheel; the header says how many). "
            .. "Order: each next stop is the closest to the previous one; the yards are from you.",
        "Quests whose items come from boxes / objects (e.g. Anything of Value) get their locations from Questie's item "
            .. "data when the objective has none, so they show on the route and get a marker.",
    } },
    { version = "0.6.29", date = "2026-11-17", items = {
        "Vendor nearby: disappears as soon as you are more than 150 yd from the vendor (live distance); the row's title stays "
            .. "put and only the part after it scrolls.",
    } },
    { version = "0.6.28", date = "2026-11-17", items = {
        "Buff reminder warning rows (vendor nearby, bags, repair): the whole row is clickable (marker), and the text "
            .. "scrolls when it doesn't fit. 'Vendor nearby' shows a vendor icon, or the repair icon for a repairer, "
            .. "and only mentions your gear when a repairer is near.",
    } },
    { version = "0.6.27", date = "2026-11-17", items = {
        "Switching to another quest (also by tracking it) removes the old quest's marker and puts the arrow on the new quest's "
            .. "target; if the new quest has no known location, no old arrow is left pointing the wrong way.",
    } },
    { version = "0.6.26", date = "2026-11-17", items = {
        "Panel with a focused quest: no icon in front of the title, and the map / clear focus buttons sit right after the quest name.",
    } },
    { version = "0.6.25", date = "2026-11-17", items = {
        "Buff reminder out in the world: 'Vendor nearby' when a vendor / repairer is within ~150 yd and your bags are at "
            .. "least half full (or your gear is under 90%), e.g. 'bags 36/66, gear 85% - <vendor>'. Click: marker; X: hide until you move on.",
    } },
    { version = "0.6.24", date = "2026-11-17", items = {
        "Per character: the Buffs tab's ticks, chosen items, own buffs, minutes and class buff choices, and the city list's "
            .. "ignore list. Each character starts once from the old shared values, after that they are separate. "
            .. "Share settings exports / imports the current character's.",
    } },
    { version = "0.6.23", date = "2026-11-17", items = {
        "Travel: WoW Forever's own boat / zeppelin / airship list with exact dock positions from the game tables: "
            .. "Stormwind Harbor - Auberdine, the Menethil -> Southshore -> Auberdine loop (one way), Menethil - Theramore, "
            .. "Auberdine - Rut'theran, Feathermoon, Booty Bay - Ratchet, Steamwheedle Port - Powderfuse Port (Riverglades), "
            .. "the Zephras Isle airships (Dalaran for the Alliance, Skywatcher Plateau for the Horde) and the Horde zeppelins.",
    } },
    { version = "0.6.22", date = "2026-11-17", items = {
        "City list also opens in villages: within ~250 yd of an innkeeper counts as a town (not only resting in the inn); "
            .. "it closes when you walk away, and never pops up on a flight path.",
        "Directions only lists what is around (within ~700 yd): in a small village no Auction House or Bank line; "
            .. "Profession Trainer only when one is nearby.",
    } },
    { version = "0.6.21", date = "2026-11-17", items = {
        "What next: 'Next zone' line on top. 'Go to <zone>' when another zone has 5+ quests from your log (more than here); "
            .. "otherwise the nearest zone with 5+ quests to pick up for your level. 'Hearth back to <zone>' when the "
            .. "Hearthstone is the fastest way. Hover: the quests and the way; click: marker. Switch: Route & progress tab.",
        "Travel: boats, zeppelins and the Deeprun Tram count in travel times and advice (also to the other continent); "
            .. "the Hearthstone (with its cooldown) is part of the route search.",
        "The nearby quest popup no longer shows while you are on a flight path.",
    } },
    { version = "0.6.20", date = "2026-11-17", items = {
        "Directions > Profession Trainer: every profession has its icon.",
    } },
    { version = "0.6.19", date = "2026-11-17", items = {
        "City list: the quest chain tag (chain icon + 2/5) is clickable: it opens your quest log at the quest of that "
            .. "chain you already have; hover shows which one.",
    } },
    { version = "0.6.18", date = "2026-11-17", items = {
        "City list: 'Start dungeon' is now 'Dungeon quests'; a thin line separates the bottom buttons; "
            .. "XP and distance sit closer to the quest name.",
        "Directions menu opens beside the city list and is narrower; the distance shows when you hover a line.",
    } },
    { version = "0.6.17", date = "2026-11-17", items = {
        "City list: the Bank / AH / Trainer buttons are replaced by one 'Directions' drop-down, like asking a guard: "
            .. "Auction House, Bank, Flight Master, Inn, Class Trainer, Profession Trainer (sub-menu, your professions first), "
            .. "Weapons Trainer, Repair, Food & Drink, Battlemaster (hunters: Stable Master, Ammo). Each shows the distance "
            .. "to the nearest one; click for a marker.",
    } },
    { version = "0.6.16", date = "2026-11-17", items = {
        "Buff reminder, out in the world (not in cities / inns): 'Bags filling up / full' and 'Gear worn / broken' rows, "
            .. "using the City to-do thresholds. Click the icon for a marker on the nearest vendor / repairer; X hides it until fixed. "
            .. "Switch: Options > Buffs.",
    } },
    { version = "0.6.15", date = "2026-11-17", items = {
        "Fix: the city list's resize corner was invisible (broken texture path); now it shows like the panel's.",
    } },
    { version = "0.6.14", date = "2026-11-17", items = {
        "City list is resizable: drag the bottom right corner (width, and how many quests show without scrolling); "
            .. "saved, right-click the corner for the default size.",
        "City list: removed the estimated quest length (~3m) from the rows.",
    } },
    { version = "0.6.13", date = "2026-11-17", items = {
        "City list: Bank and AH buttons use the game's own banker / auctioneer tracking icons.",
    } },
    { version = "0.6.12", date = "2026-11-17", items = {
        "City list: flat buttons in the list's own style instead of the red ones; Bank / AH / Trainer have small icons "
            .. "(Trainer shows your class icon).",
        "City list: in a skipped place the button reads 'Remove from ignore list'; the Options section is now 'Ignore list'.",
    } },
    { version = "0.6.11", date = "2026-11-17", items = {
        "Options: Quest pickup split in two tabs. Quest pickup = the nearby popup out in the world and the quest level range; "
            .. "City list = the list in cities / inns, skipped places, to-do thresholds. Each starts with a short intro and its on / off switch.",
        "City list tab: skipped places are listed one per line with a Remove button (Remove all when there are several).",
    } },
    { version = "0.6.10", date = "2026-11-17", items = {
        "City list: 'Ignore this place' is now 'Don't open here again' (and 'Open here again'); the tooltip names the place "
            .. "and says other cities are not affected.",
    } },
    { version = "0.6.9", date = "2026-11-17", items = {
        "Weapon enchant rows recognise items by their tooltip ('Use:' text) instead of a fixed name list: any stone, oil, "
            .. "poison or Scroll of Imbue that temporarily enchants a weapon is found, and only offered for a weapon it fits "
            .. "(sharp / blunt, or the named type: dagger, staff, sword...).",
    } },
    { version = "0.6.8", date = "2026-11-17", items = {
        "Weapon enchant rows: mage Scroll of Imbue (e.g. Lesser Flame) counts as a weapon enchant, offered only when a staff is equipped.",
    } },
    { version = "0.6.7", date = "2026-11-17", items = {
        "City list title row: Trainer (nearest trainer of your class) and AH (nearest auctioneer) next to Bank; "
            .. "hover shows the nearest one and its distance, click puts a marker on it.",
    } },
    { version = "0.6.6", date = "2026-11-17", items = {
        "Fix: 'attempt to call a nil value' in GetItemCount / GetItemInfoInstant (Bags, Buffs). Item lookups now use the "
            .. "C_Item API first and the old one as a fallback, both protected, so a broken item function can't stop the modules.",
    } },
    { version = "0.6.5", date = "2026-11-17", items = {
        "City to-do: bags full warning (default 70% used, or fewer than 10 free slots) with the nearest vendor to sell to; "
            .. "the quest list stays below it.",
        "Quest pickup tab: 'City to-do' thresholds for bags (% and free slots), repair % and hunter ammo; 0 turns a line off.",
    } },
    { version = "0.6.4", date = "2026-11-17", items = {
        "City list: a to-do section above the quests - repair (most worn item under 60%), hunter ammo (under 400), "
            .. "no XP food in your bags - each with the nearest repairer / ammo vendor / food vendor; click for a marker.",
        "City list: Bank button in the title row (marker on the nearest banker). NPCs come from Questie's town data, your faction only.",
    } },
    { version = "0.6.3", date = "2026-11-17", items = {
        "Buffs tab: choosing an item / spell for a row (icon click or drag) also ticks that row on.",
    } },
    { version = "0.6.2", date = "2026-11-17", items = {
        "XP food picker: removed the leftover 'Don't ask again' button (it silently turned off the login setup question).",
    } },
    { version = "0.6.1", date = "2026-11-17", items = {
        "Less CPU: quest changes come from specific events (accepted, turned in, removed, objective progress) "
            .. "instead of every quest log update (that one is only a fallback if the client never sends the others).",
    } },
    { version = "0.6.0", date = "2026-11-17", items = {
        "Folders renamed to AdventurersKit, AdventurersKit_Bags, AdventurersKit_Buffs (the CPU / addon lists now say Adventurer's Kit). "
            .. "A small code-free 'QuestFocus' folder carries your old settings over; delete it after one login.",
        "Less CPU: nearby-quest, pickup-popup and city-list scans only run again after you move (or the quest log changes); "
            .. "nameplate picking only with a focused quest; usable quest items and buff items are cached until your bags change; "
            .. "item-info events from other addons no longer rebuild the buff reminder; "
            .. "the bag quest item scan only runs while the bag is open and the quest item list is expanded.",
        "Summary of 0.5.x: Start dungeon (Dungeon Journal), panel icon row, settings export / import, map buttons, vendor markers.",
    } },
    { version = "0.5.5", date = "2026-11-17", items = {
        "Map button: the focused quest's zone header is expanded and the quest is selected in the quest log "
            .. "(the quest list next to the map follows it); other collapsed headers stay collapsed.",
    } },
    { version = "0.5.4", date = "2026-11-17", items = {
        "Map button also opens the focused quest in the map's quest panel, when the client has one.",
    } },
    { version = "0.5.3", date = "2026-11-17", items = {
        "Vendors (e.g. a trade supplies NPC selling a quest item) always get a marker; it no longer says "
            .. "'you are in the spawn area' when the vendor is nearby but hidden in a building.",
        "Map button: on the panel before the clear-focus button, and at the end of every open objective row; "
            .. "it opens the world map on the target and puts the marker there.",
    } },
    { version = "0.5.2", date = "2026-11-17", items = {
        "Share settings tab (and /qf export, /qf import): your settings as text to send to others, or load theirs. "
            .. "Item choices (XP food, sleeping bag, stones / oils, own item buffs) are only taken if the importer has the item; "
            .. "class settings only for the same class; panel position, ignore list and kill pace are not shared.",
        "XP food: only real food / drink is listed (camp tents, sleeping bags and scrolls no longer show up).",
        "Buff reminder: the weapon enchant and XP food rows always have the small arrow to choose another one.",
    } },
    { version = "0.5.1", date = "2026-11-17", items = {
        "Spacing: the chain icon no longer touches the quest name / 2/5, '(in log)' sits further right, "
            .. "and the panel's top icons no longer touch the close button.",
    } },
    { version = "0.5.0", date = "2026-11-17", items = {
        "Start dungeon: skull button on the panel (and /qf dungeon) lists the dungeons for your level with their quests. "
            .. "With the Dungeon Journal addon it uses its data (Forever's own dungeons too) and opens the quest there; "
            .. "without it, a similar list from Questie and a click puts a marker on the quest giver.",
        "Dungeon quests in the city list and the pickup popup get a small skull button (Start dungeon); "
            .. "the city list has a 'Start dungeon' button when it shows dungeon quests.",
        "Panel: a small icon row on top (options, dungeons, close); the quest name is one line lower, "
            .. "with the clear-focus button at its end.",
        "Quest chains show the Dungeon Journal's chain icon (when it's installed).",
        "Summary of 0.4.x: buff tracking reworked (groups, weapon type aware stones / oils, setup popup, per-row X), "
            .. "usable quest items on objective rows, bag highlight fix, dungeon quest highlight, 'Disable city list everywhere'.",
    } },
    { version = "0.4.10", date = "2026-11-17", items = {
        "Dungeon and raid quests are highlighted in the city list (tinted row) and the pickup popup, with the dungeon's full name "
            .. "in front of the quest, e.g. [Dungeon: Wailing Caverns]; the tooltip says it needs a group.",
        "City list button renamed to 'Disable city list everywhere': it turns the list off in every city and inn, not just here.",
    } },
    { version = "0.4.9", date = "2026-11-17", items = {
        "Weapon enchant rows only for a hand that holds a melee weapon: with a two-hander the off-hand row is gone "
            .. "(Buffs tab, setup popup, reminder); it comes back when you equip an off-hand weapon.",
    } },
    { version = "0.4.8", date = "2026-11-17", items = {
        "Buffs tab: three groups - items (sleeping bag, XP food, weapon enchants), class buffs, and your own additions.",
        "Weapon swap (out of combat): stones / oils / poisons are picked to fit the new weapon (sharpening stone for edged, weightstone for blunt); "
            .. "if nothing fits, the buff reminder row says so and lets you choose. Ranged-only hands are ignored.",
    } },
    { version = "0.4.7", date = "2026-11-17", items = {
        "XP food, sleeping bag, weapon enchants and class buffs are always on by default (hunters too); found items / spells are set automatically.",
        "First login on a character: if nothing is found for a ticked item buff, a popup offers to set it up (Set up / Later / Don't ask again).",
    } },
    { version = "0.4.6", date = "2026-11-17", items = {
        "Buff reminder: ticked item buffs (sleeping bag, weapon enchant, your own items) show up even when you have none in your bags; click the icon to choose one, or drag an item onto it.",
        "Buff reminder: a small X at the end of each row stops watching that buff (tick it again on the Buffs tab).",
    } },
    { version = "0.4.5", date = "2026-11-17", items = {
        "Tracking reminder fixed: it now checks by name whether one of your tracking spells is really active (it used to think something was on when nothing was).",
    } },
    { version = "0.4.4", date = "2026-11-17", items = {
        "XP food picker lists only XP food (food whose description mentions experience); others can still be dragged onto the XP food icon.",
        "Hunters: main / off-hand enchant are off by default (tick them on the Buffs tab if you want them).",
    } },
    { version = "0.4.3", date = "2026-11-17", items = {
        "Usable quest items: only for the selected quest and nearby objectives, as a small button at the end of the objective row on the panel.",
        "ALSO NEARBY row click: focuses that quest and that objective (marker + arrow + macro).",
    } },
    { version = "0.4.2", date = "2026-11-17", items = {
        "Usable quest item buttons: only items the quest gives you to use (or quest-type objective items), not collected consumables like drinks or food.",
        "Options: when a module is off, the rest of its tab is greyed out and can't be clicked.",
    } },
    { version = "0.4.1", date = "2026-11-17", items = {
        "Bag highlight fixed: clicking an item in the quest item list highlights it in the open bag (Bagnon or Blizzard bags) and dims the rest; click again to clear.",
    } },
    { version = "0.4.0", date = "2026-11-17", items = {
        "New name: Adventurer's Kit (formerly QuestFocus). Folders, /qf, the QFocus macro and your settings stay the same.",
        "Panel: a small button next to the close button clears the focus (the quest stays in your log), same as /qf clear.",
        "Summary of 0.3.1 - 0.3.9: buff tracking rework (ticks, off-hand / poisons / shaman imbue, custom items and buffs, item count), "
            .. "module on/off switches, usable quest items on the panel, per-state macro icons, zone switch prompt, "
            .. "unknown length for battleground quests, route distances from you.",
    } },
    { version = "0.3.9", date = "2026-11-17", items = {
        "Route list: every stop shows its straight-line distance from you (no more '+N yd' from the previous stop). The order is still nearest-next.",
    } },
    { version = "0.3.8", date = "2026-11-17", items = {
        "Buff reminder: item buffs show how many you still have in your bags (on the icon and as xN).",
    } },
    { version = "0.3.7", date = "2026-11-17", items = {
        "Buff buttons under the panel removed.",
        "Buffs tab: every type with a tick (watch / don't watch), its item or spell (click the icon to choose), and minutes; 0 = remind only when it's missing.",
        "New types: off-hand enchant (only with an off-hand weapon), rogue poisons on both hands, shaman weapon imbue (Windfury / Flametongue / Frostbrand / Rockbiter).",
        "Add buff: any item (flask, elixir, scroll, juju) or any buff by spell ID / name, or picked from the buffs on you; castable ones are cast from the reminder, others only remind.",
    } },
    { version = "0.3.6", date = "2026-11-17", items = {
        "Pickup quest length: '?' / 'length unknown' instead of a misleading guess for battleground quests (e.g. Arathi Basin) and items whose source is unknown.",
    } },
    { version = "0.3.5", date = "2026-11-17", items = {
        "Bags and Buffs tabs start with a 'Module on' switch (on by default): off keeps the module loaded but it does nothing; no reload needed.",
        "Fixes a syntax error in 0.3.4 that broke the options window.",
    } },
    { version = "0.3.4", date = "2026-11-17", items = {
        "Module enable switch via the AddOns list (replaced in 0.3.5; this build had an options error).",
    } },
    { version = "0.3.3", date = "2026-11-17", items = {
        "Usable quest items of every active quest are on the panel's left edge (up to 4, selected quest first) instead of the bag list.",
    } },
    { version = "0.3.2", date = "2026-11-17", items = {
        "Macro icons per state (hunting, turn-in, no quest): Macro & marker tab, click an icon to pick from a list opening to the side; the panel icon follows. /qf icon <name> sets all three.",
    } },
    { version = "0.3.1", date = "2026-11-17", items = {
        "Zone focus: entering another zone with quests asks Switch / Keep / Turn off focus (or switch without asking: Zone focus tab).",
        "Minimap tooltip shows the new zone focus state right after a right click.",
    } },
    { version = "0.3.0", date = "2026-11-17", items = {
        "Options reorganized into feature tabs (General, Macro & marker, Route & progress, Quest pickup, Zone focus, Bags, Buffs) with a short description under every option.",
        "Chat messages can be turned off (General tab or /qf chat): then only one line at login and the replies to your own commands.",
        "Release notes tab (this page) and a what's-new line at login after an update.",
        "City list: scrollable, XP reward, quest chain position (e.g. 2/10), item-start tag; 'Ignore this place' and 'Disable city list' buttons; reopens after relog.",
        "Bag list collapsed: a slim tab on top of the bag frame.",
        "Buff reminder: no raid warning sound, a short gold flash only the first time a buff goes missing.",
    } },
    { version = "0.2.0", date = "2026-11-17", items = {
        "Split into modules: QuestFocus (core), QuestFocus_Bags and QuestFocus_Buffs (separate addons, can be disabled).",
        "Shared tooltip style for panel rows, suggestions, popups, the city list and the quest log.",
        "Turn-in mode: the next quests of your quest-log route at the bottom of the panel.",
        "Panel keeps its top left corner when its height changes.",
        "City mode with travel advice (walk / Hearthstone / flight); nearby pickup popups; zone focus prompt.",
        "Nearby quests: mobs of other quests within 200 yd go into the macro too (ALSO NEARBY).",
        "Class buff and tracking reminders, XP food picker, bag item focus highlight in Bagnon.",
        "Fixes: combat 'secret value' errors (auras, run speed), no combat log registration, blocked actions.",
    } },
    { version = "0.1.0", date = "2026-11-16", items = {
        "First alpha: QFocus target macro, markers (own arrow or TomTom), quest tooltips, zone focus, minimap button.",
        "Quest item list next to the bags, Bagnon coloring, use-item button with keybind.",
        "Panel with time-left estimate, quest suggestions, progress popup and buff reminders.",
    } },
}
NS.RELEASE_NOTES = NOTES

local function Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get(ADDON_NAME, "Version") or NOTES[1].version
end
NS.Version = Version

-- Options ful (Debug ele)
local page = NS.AddOptionsTab(L["Release notes"], 80)
local fl = NS.OptFlow(page)
fl:Text((L["Installed: |cffffffff%s|r (alpha test). Bugs and ideas: /qf copy on the Debug tab helps."]):format(Version()), 2)
for _, rel in ipairs(NOTES) do
    fl:Header(("%s  |cff808080%s|r"):format(rel.version, rel.date))
    for _, item in ipairs(rel.items) do
        local fs = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        fs:SetWidth(410)
        fs:SetText("- " .. item)
        fl:Place(fs, 10, 4)
    end
end

NS.OpenReleaseNotes = function() NS.OpenOptionsTab(L["Release notes"]) end

-- Bejelentkezes: egy sor (akkor is, ha a chat uzenetek ki vannak kapcsolva).
-- Frissites utan az uj verzio elso pontja is.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    C_Timer.After(3, function()
        local v = Version()
        local quiet = QuestFocusDB.quietChat and L[" (chat messages off)"] or ""
        if QuestFocusDB.lastVersion ~= v then
            local first = NOTES[1].version == v and NOTES[1].items[1] or nil
            NS.PrintAlways(L["v%s alpha loaded%s. |cffffff00New:|r %s |cff808080(/qf notes)|r"], v, quiet,
                first or L["see /qf notes"])
            QuestFocusDB.lastVersion = v
        else
            NS.PrintAlways(L["v%s alpha loaded%s. |cff808080/qf options|r"], v, quiet)
        end
    end)
end)
