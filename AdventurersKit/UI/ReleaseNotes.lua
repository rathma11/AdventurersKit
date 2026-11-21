-- Adventurer's Kit: release notes (Options > Release notes, /ak notes) es a bejelentkezo sor.
-- Uj verzional: a .toc fajlokban a Version, es egy uj blokk a NOTES tetejere.
local ADDON_NAME, NS = ...
local L = NS.L

-- A legfelso bejegyzes a kovetkezo kiadas. Csak jatekosnak szolo valtozasok, a felhasznalo jovahagyasaval;
-- a kiadas elotti 0.x fejlesztoi verziok nem szerepelnek (az elso nyilvanos: 0.10.0 beta).
local NOTES = {
    { version = "0.11.1", date = "2026-11-21", items = {
        "Options > Debug: an Enable all button before Copy all turns on the log of every section (when all are on, "
            .. "it reads Disable all and turns them off). Same as /ak debug all on | off.",
        "The Bags and Buffs modules have their own icons in the addon list: the compass with a bag or a glowing "
            .. "up arrow in the corner.",
        "AKit macro: a quest mob that is already your target (alive, not tapped) is always pinged, even when it is "
            .. "behind you or off screen and its nameplate is not visible.",
    } },
    { version = "0.11.0", date = "2026-11-19", items = {
        "Options > Debug: a section for each feature with a snapshot of what it sees, an optional log of its "
            .. "decisions, and Copy debug / Copy all for bug reports (/ak debug, /ak copy).",
        "AKit macro pings are simpler: pressing the button pings your target, turn-in and other friendly or neutral "
            .. "NPCs too. No ping when every nearby quest mob is tapped; attack pings stay out of combat only.",
    } },
    { version = "0.10.0", date = "2026-11-19", items = {
        "First public beta of Adventurer's Kit for WoW: Forever. Please report bugs with /ak copy all (paste the text "
            .. "into a CurseForge comment or a GitHub issue).",
        "Quest focus and targeting: a quest panel with objectives, progress, time left and kill pace; the AKit macro "
            .. "targets a living, untapped quest mob with one key, also for quests nearby.",
        "Markers and route: an arrow (built-in or TomTom) to the nearest spot; your quests in nearest-next order, the "
            .. "next zone and travel time with boats, zeppelins, the tram and the Hearthstone.",
        "Towns: a city list with quests to pick up, errands (repair, ammo, XP food, full bags) and directions to the "
            .. "bank, auction house, flight master, inn and trainers.",
        "Dungeons: the dungeons for your level, WoW: Forever's own included, with a quest checklist, the entrance on "
            .. "the map and objectives in boss order inside.",
        "Modules: a buff reminder, a quest item list next to your bags, a farm session (XP and gold per hour, time to "
            .. "level) and a Quest items tab at the auction house.",
        "Earlier 0.x versions were development builds and are not listed here.",
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
