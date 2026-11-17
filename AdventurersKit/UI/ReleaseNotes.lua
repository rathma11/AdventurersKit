-- QuestFocus: release notes (Options > Release notes, /qf notes) es a bejelentkezo sor.
-- Uj verzional: a .toc fajlokban a Version, es egy uj blokk a NOTES tetejere.
local ADDON_NAME, NS = ...
local L = NS.L

-- Patch (x.y.Z): minden valtozas; minor (x.Y.0): release (git tag + zip a releases\ mappaba).
local NOTES = {
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
