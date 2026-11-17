-- /qf selftest: gyors onellenorzes a jatekban, az elo adatokon (csak tiszta logika, semmit
-- nem allit at). Rovid osszegzes; reszletek csak hiba eseten.
-- Az offline tesztek (tests\run.lua) ugyanezt is lefuttatjak a hamis vilagban.
local ADDON_NAME, NS = ...
local L = NS.L

local MAX_DETAILS = 5

local function Checks()
    local C = NS.C
    local list = {}
    local function add(name, fn) list[#list + 1] = { name = name, fn = fn } end

    add("Questie loaded", function()
        if not NS.QuestieAvailable() then return { "QuestieLoader / QuestieDB not found" } end
    end)

    add("Quest data (CollectTargets)", function()
        local bad, n = {}, 0
        for i = 1, NS.NumLogEntries() do
            local title, isHeader, qid, done = NS.GetLogEntry(i)
            if not isHeader and qid then
                n = n + 1
                local q = NS.GetQuestieQuest(qid)
                if q then
                    local ok, r = pcall(NS.CollectTargets, q, done)
                    if not ok then
                        bad[#bad + 1] = ("%s (%d): %s"):format(tostring(title), qid, tostring(r))
                    elseif type(r) ~= "table" then
                        bad[#bad + 1] = ("%s (%d): no objective list"):format(tostring(title), qid)
                    end
                end
            end
        end
        return bad, n .. " quests"
    end)

    add("QFocus macro under 255 chars", function()
        local bad, n = {}, 0
        local state = NS.state
        for i = 1, NS.NumLogEntries() do
            local title, isHeader, qid, done = NS.GetLogEntry(i)
            local q = not isHeader and qid and NS.GetQuestieQuest(qid)
            if q then
                local okT, objs = pcall(NS.CollectTargets, q, done)
                if okT and type(objs) == "table" then
                    n = n + 1
                    local ok, body = pcall(C.BuildMacroBody, objs, nil)
                    if not ok then
                        bad[#bad + 1] = ("%s: %s"):format(tostring(title), tostring(body))
                    elseif type(body) ~= "string" or #body > (C.MACRO_MAX or 255) then
                        bad[#bad + 1] = ("%s: %d chars"):format(tostring(title), type(body) == "string" and #body or -1)
                    end
                end
            end
        end
        -- vissza a mostani allapotra (a BuildMacroBody a celpont neveket is beallitja)
        pcall(C.BuildMacroBody, state.objectives, state.objIndex)
        if state.lastBody and #state.lastBody > (C.MACRO_MAX or 255) then
            bad[#bad + 1] = ("current macro: %d chars"):format(#state.lastBody)
        end
        return bad, n .. " bodies"
    end)

    add("Character settings (CharDB)", function()
        if type(QuestFocusDB) ~= "table" then return { "QuestFocusDB missing" } end
        local c = NS.CharDB()
        if type(c) ~= "table" then return { "CharDB() is not a table" } end
        local found = false
        for _, v in pairs(QuestFocusDB.chars or {}) do if v == c then found = true end end
        if not found then return { "CharDB() is not saved under QuestFocusDB.chars" } end
    end)

    add("TomTom (optional)", function()
        if TomTom == nil then return nil, "not installed, own arrow" end
        if type(TomTom.AddWaypoint) ~= "function" then return { "TomTom is there but has no AddWaypoint" } end
        return nil, "installed"
    end)

    add("Dungeon entrances", function()
        local bad, n = {}, 0
        for name, e in pairs(NS.DungeonEntrances or {}) do
            n = n + 1
            if type(e.pts) ~= "table" or #e.pts == 0 then bad[#bad + 1] = name .. ": no points" end
            for _, p in ipairs(e.pts or {}) do
                local m, x, y = p[1], p[2], p[3]
                if type(x) ~= "number" or type(y) ~= "number" or x < 0 or x > 1 or y < 0 or y > 1 then
                    bad[#bad + 1] = ("%s: bad coordinates on map %s"):format(name, tostring(m))
                elseif not C_Map.GetMapInfo(m) then
                    bad[#bad + 1] = ("%s: unknown uiMap %s"):format(name, tostring(m))
                elseif not NS.WorldPos(m, x, y) then
                    bad[#bad + 1] = ("%s: uiMap %s has no world position"):format(name, tostring(m))
                end
            end
        end
        if n == 0 then bad[#bad + 1] = "the entrance table is empty" end
        return bad, n .. " dungeons"
    end)

    add("Transport table", function()
        if not NS.TransportCheck then return { "Planner\\Travel.lua not loaded" } end
        local n, bad = NS.TransportCheck()
        return bad, n .. " routes"
    end)

    return list
end

NS.SelfTest = function()
    local pass, fails = 0, {}
    local list = Checks()
    for _, c in ipairs(list) do
        local ok, bad, info = pcall(c.fn)
        if not ok then
            fails[#fails + 1] = { name = c.name, details = { "Lua error: " .. tostring(bad) } }
        elseif type(bad) == "table" and #bad > 0 then
            fails[#fails + 1] = { name = c.name, details = bad }
        else
            pass = pass + 1
        end
    end
    local col = #fails == 0 and "|cff33ff33" or "|cffff5555"
    NS.PrintAlways(L["Self test: %s%d/%d passed|r"], col, pass, #list)
    for _, f in ipairs(fails) do
        NS.PrintAlways("|cffff5555%s|r %s", L["FAIL"], f.name)
        for i, d in ipairs(f.details) do
            if i > MAX_DETAILS then
                NS.PrintAlways(L["    ... and %d more"], #f.details - MAX_DETAILS)
                break
            end
            NS.PrintAlways("    %s", tostring(d))
        end
    end
    return pass, #list, fails
end
