-- Adventurer's Kit: About ful (Options > About): nev, verzio, rovid leiras, funkciolista
-- teruletenkent (egy mondat / funkcio), a fo parancsok es egy gomb a release notes-hoz.
-- A lista a repo FEATURES.md fajljaval egyezik; uj funkcional mindkettot frissitsd.
local ADDON_NAME, NS = ...
local L = NS.L
local S = NS.Style

local FEATURES = {
    { L["Quest focus and targeting"], {
        L["Quest panel: the focused quest with its objectives, the quests also nearby and your route, in a fixed-size panel."],
        L["AKit macro: one key targets a living quest mob of your objectives (and of nearby quests), and keeps a living enemy you clicked."],
        L["Nameplate mode: with enemy nameplates on, the macro picks a quest mob nobody has tapped from the visible nameplates; otherwise it targets by name."],
        L["Ping modes: the macro pings its target always, never, or asks when you join a group (/ak ping)."],
        L["Zone focus: only the current zone's quests in the tracker, with a prompt when you enter another zone (/ak zone)."],
    } },
    { L["Markers"], {
        L["Markers: the addon's own arrow or a TomTom waypoint points to the nearest spot of the current objective; the map button opens the world map there."],
        L["Spawn hopping: an empty spawn point counts as checked for 5 minutes and the marker moves on to the next one."],
    } },
    { L["Quest stepping"], {
        L["Previous / next arrows (with key bindings) step to the next stop of the route, or back through the quests you focused before."],
        L["Skip rules: a skipped quest waits at the end of the route (saved per character) and comes back when you pick it, it makes progress, you get near its target, or you turn in a quest."],
    } },
    { L["Route and travel"], {
        L["Route: the quests in your log in nearest-next order, with the distance from you."],
        L["Next zone: go where most of your quests are, or to the nearest zone with quests for your level; 'Hearth back' when the Hearthstone is fastest."],
        L["Travel planning counts boats, zeppelins, the tram and the Hearthstone, with WoW Forever's own transport routes."],
    } },
    { L["Pace and time left"], {
        L["Pace: your kill pace is learned (per group size) and every quest gets a time-left estimate."],
    } },
    { L["Escort quests"], {
        L["Escorts: the panel shows the escort's health and destination, the macro targets whatever attacks it, and a star marks the escort NPC."],
    } },
    { L["Dungeons"], {
        L["Dungeon list: the dungeons for your level with their quests, WoW Forever's own dungeons included (/ak dungeon)."],
        L["Dungeon prep: a checklist of the dungeon's quests to pick up (chain steps too), then the entrance on the map."],
        L["Inside the dungeon: every objective in boss order, the next step highlighted and its mobs in the macro."],
        L["Share popup: in a group, entering the dungeon offers to share your dungeon quests with the party."],
    } },
    { L["City list"], {
        L["City list: in towns and villages, the quests to pick up nearby with XP, chain step and dungeon tags (town icon or /ak city)."],
        L["Errands: repair, ammo, XP food and full bags, each with the nearest NPC to mark."],
        L["Directions: like asking a guard, the nearest bank, auction house, flight master, inn, trainers or repairer."],
        L["Auto-open: the list opens by itself in towns (can be turned off) and closes when you walk away."],
    } },
    { L["Quest pickup popup"], {
        L["Out in the world a draggable popup shows a quest you can pick up nearby, with its estimated length; click marks the quest giver."],
    } },
    { L["Buff reminder (Buffs module)"], {
        L["Consumables: sleeping bag, XP food and your own items or buffs, with how many you have left."],
        L["Weapon enchants: stones, oils, poisons, scrolls and shaman imbues, picked to fit the weapon in your hand."],
        L["Class buffs and tracking: your own class buffs, and gathering tracking first."],
        L["Outside warnings: bags filling up, worn gear and 'Vendor nearby', with a marker to the nearest vendor or repairer."],
    } },
    { L["Bags module"], {
        L["Quest items: a list next to the bags (Bagnon coloring, click to highlight), use buttons on objective rows with a key binding, and /ak junk for leftovers."],
    } },
    { L["Farm session"], {
        L["Farm session: time, XP per hour with an ETA to level, kills, looted gold and item value (auction price if available), and a summary when you stop (/ak farm)."],
    } },
    { L["Auction house"], {
        L["Quest items tab: the items your quests still need with the cheapest price; click to search, Buy / Buy all with one confirmation."],
    } },
    { L["Settings"], {
        L["Per-character settings: buffs, skipped quests, dungeon prep and the farm session are kept per character."],
        L["Profile export / import: your settings as text to share (/ak export, /ak import)."],
        L["Self test: /ak selftest checks your live data and prints one summary line."],
        L["Debug sections: every feature has its own snapshot and an optional decision log; Options > Debug copies one section or all of them for a bug report (/ak debug <section>, /ak copy <section>)."],
    } },
}

local COMMANDS = {
    { "/ak", L["show / hide the quest panel"] },
    { "/ak options", L["settings"] },
    { "/ak next | all | mark | unmark | clear", L["objectives, marker and focus"] },
    { "/ak ping", L["ping mode (ask / always / never)"] },
    { "/ak zone", L["zone focus on / off"] },
    { "/ak city", L["city list"] },
    { "/ak dungeon [name | off]", L["dungeon list, dungeon prep"] },
    { "/ak farm [stop | pause | resume | reset]", L["farm session"] },
    { "/ak bags | junk", L["quest item list, destroy leftover quest items"] },
    { "/ak export | import", L["share settings"] },
    { "/ak notes", L["release notes"] },
    { "/ak selftest", L["self test"] },
    { "/ak debug [section [on | off]]", L["debug snapshot in chat, a section's log on / off"] },
    { "/ak copy [section | all]", L["debug text to copy for a bug report"] },
}

local page = NS.AddOptionsTab(L["About"], 85)
local fl = NS.OptFlow(page)
local TEXT_W = 410

local function Line(text, x, gap, font)
    local fs = page:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetWidth(TEXT_W - (x or 0))
    fs:SetText(text)
    fl:Place(fs, x or 0, gap or 4)
    return fs
end

-- ikon, nev, verzio, leiras
local logo = page:CreateTexture(nil, "ARTWORK")
logo:SetSize(32, 32)
logo:SetTexture(NS.ICON)
fl:Place(logo, 2, 2)
page.logo = logo
local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetText("Adventurer's Kit")
title:SetTextColor(S.TITLE[1], S.TITLE[2], S.TITLE[3])
title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
local ver = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
ver:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 1)
ver:SetText("v" .. (NS.Version and NS.Version() or "?"))
Line(L["A questing kit for WoW: Forever built on Questie: it picks your next quest target, points the way, plans the route "
    .. "and handles the errands around it (towns, dungeons, buffs, bags, farming, the auction house)."], 2, 6)

fl:Header(L["Features"])
for _, grp in ipairs(FEATURES) do
    local h = S.Section(page, grp[1]:upper())
    fl:Place(h, 2, 12)
    for _, item in ipairs(grp[2]) do Line("- " .. item, 10, 4) end
end

fl:Header(L["Commands"])
for _, c in ipairs(COMMANDS) do
    Line(("|cff%s%s|r  |cff%s%s|r"):format(S.HEX.NAME, c[1], S.HEX.DIM, c[2]), 10, 4)
end

fl:Header(L["Release notes"])
Line(L["Every version's changes are on the Release notes tab (or /ak notes)."], 2, 8)
local btn = S.FlatButton(page, L["Open release notes"], 150, 22)
fl:Place(btn, 2, 8)
btn:SetScript("OnClick", function() if NS.OpenReleaseNotes then NS.OpenReleaseNotes() end end)
btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Open release notes"], 1, 1, 1)
    GameTooltip:AddLine(L["Same as /ak notes."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
