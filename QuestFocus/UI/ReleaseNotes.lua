-- QuestFocus: release notes (Options > Release notes, /qf notes) es a bejelentkezo sor.
-- Uj verzional: a .toc fajlokban a Version, es egy uj blokk a NOTES tetejere.
local ADDON_NAME, NS = ...
local L = NS.L

-- Patch (x.y.Z): minden valtozas; minor (x.Y.0): release (git tag + zip a releases\ mappaba).
local NOTES = {
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
