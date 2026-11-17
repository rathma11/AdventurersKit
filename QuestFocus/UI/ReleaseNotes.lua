-- QuestFocus: release notes (Options > Release notes, /qf notes) es a bejelentkezo sor.
-- Uj verzional: a .toc fajlokban a Version, es egy uj blokk a NOTES tetejere.
local ADDON_NAME, NS = ...
local L = NS.L

local NOTES = {
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
