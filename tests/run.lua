-- Adventurer's Kit offline smoke tests (Lua 5.1 / LuaJIT).
--   lua5.1 tests\run.lua        (or: powershell -File tests\run.ps1)
--   lua5.1 tests\run.lua -v     (also list auto-stubbed globals and chat output)
-- Loads the 3 code addons in .toc order with (ADDON_NAME, NS), fires ADDON_LOADED /
-- PLAYER_LOGIN / PLAYER_ENTERING_WORLD on a fake game (tests\wowstub.lua, tests\fake_questie.lua),
-- then exercises the key logic paths. Exit code 0 = all passed.
-- What it cannot check: rendering / layout, real secure frames and taint, combat lockdown
-- beyond the InCombatLockdown() flag, real Questie data, the real map / world coordinates.

local verbose = false
for _, a in ipairs(arg or {}) do if a == "-v" then verbose = true end end

local scriptDir = ((arg and arg[0]) or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = scriptDir .. "/.."
local function out(s) io.write(tostring(s), "\n") end

local W = dofile(scriptDir .. "/wowstub.lua")
local Q = assert(loadfile(scriptDir .. "/fake_questie.lua"))(W)
W.metadata = {}
W.loadedAddons = {}

---------------------------------------------------------------------------
-- Tiny test framework
---------------------------------------------------------------------------
local results, current = {}, nil
local function check(cond, msg)
    if not cond then current.fails[#current.fails + 1] = msg end
    return cond
end
local function eq(got, want, msg)
    return check(got == want, ("%s: expected %s, got %s"):format(msg or "value", tostring(want), tostring(got)))
end
local function test(name, fn)
    current = { name = name, fails = {} }
    local errBefore = #W.errors
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then current.fails[#current.fails + 1] = "Lua error: " .. tostring(err) end
    for i = errBefore + 1, #W.errors do
        current.fails[#current.fails + 1] = "Lua error in a handler: " .. W.errors[i]
    end
    results[#results + 1] = current
end
local function firstLine(body) return (body or ""):match("^[^\n]*") end
local function hasLine(body, line) return (("\n" .. (body or "") .. "\n"):find("\n" .. line .. "\n", 1, true)) ~= nil end
local function contains(s, part) return (s or ""):find(part, 1, true) ~= nil end

---------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------
local function readToc(folder)
    local files, meta = {}, {}
    for line in io.lines(ROOT .. "/" .. folder .. "/" .. folder .. ".toc") do
        line = line:gsub("\r$", "")
        local k, v = line:match("^##%s*([%w%-]+)%s*:%s*(.-)%s*$")
        if k then
            meta[k] = v
        elseif line:match("%S") and not line:match("^%s*#") then
            files[#files + 1] = (line:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\\", "/"))
        end
    end
    return files, meta
end

local ADDONS = { "AdventurersKit", "AdventurersKit_Bags", "AdventurersKit_Buffs" }
local loadProblems = {}
local sourceFiles = {}

local function loadAddon(folder)
    local files, meta = readToc(folder)
    W.metadata[folder] = meta
    local NS = {} -- every addon gets its own private table, like the game does
    for _, f in ipairs(files) do
        local path = ROOT .. "/" .. folder .. "/" .. f
        sourceFiles[#sourceFiles + 1] = path
        local chunk, err = loadfile(path)
        if not chunk then
            loadProblems[#loadProblems + 1] = "syntax: " .. tostring(err)
        else
            W.trackGlobals = true
            local ok, e = xpcall(function() chunk(folder, NS) end, debug.traceback)
            W.trackGlobals = false
            if not ok then loadProblems[#loadProblems + 1] = folder .. "/" .. f .. ": " .. tostring(e) end
        end
    end
    W.loadedAddons[folder] = true
end

Q.Install()
-- the test world: you stand in Elwynn Forest, 4 quests in the log (103 is ready to turn in)
Q.SetLog({ { qid = 100 }, { qid = 101 }, { qid = 102 }, { qid = 103, complete = true } })
W.MovePlayer(1429, 0.50, 0.55)

for _, a in ipairs(ADDONS) do loadAddon(a) end
-- SavedVariables arrive after the files ran, right before ADDON_LOADED (first login: none)
for _, a in ipairs(ADDONS) do W.Fire("ADDON_LOADED", a) end
W.Fire("PLAYER_LOGIN")
W.Fire("PLAYER_ENTERING_WORLD", true, false)
W.Advance(12)

local NS = rawget(_G, "QuestFocusNS")

---------------------------------------------------------------------------
-- Tests
---------------------------------------------------------------------------
local ALLOWED_GLOBAL = { "^SLASH_", "^BINDING_", "^QuestFocus", "^AdventurersKit" }

test("load: all files, events, SavedVariables", function()
    for _, p in ipairs(loadProblems) do check(false, p) end
    check(NS ~= nil, "QuestFocusNS (shared namespace) exists")
    check(type(rawget(_G, "QuestFocusDB")) == "table", "QuestFocusDB created at ADDON_LOADED")
    check(type(SlashCmdList.QUESTFOCUS) == "function", "slash handler registered")
    eq(rawget(_G, "SLASH_QUESTFOCUS1"), "/ak", "/ak is the primary slash command")
    eq(rawget(_G, "SLASH_QUESTFOCUS2"), "/qf", "/qf kept as an alias")
    for name, where in pairs(W.newGlobals) do
        local ok = false
        for _, p in ipairs(ALLOWED_GLOBAL) do if name:find(p) then ok = true end end
        check(ok, ("accidental global '%s' (%s)"):format(name, where))
    end
end)

test("version: .toc files match the top release note", function()
    local v = W.metadata.AdventurersKit.Version
    eq(NS.Version(), v, "NS.Version()")
    eq(NS.RELEASE_NOTES[1].version, v, "top entry of NOTES")
    eq(W.metadata.AdventurersKit_Bags.Version, v, "Bags .toc")
    eq(W.metadata.AdventurersKit_Buffs.Version, v, "Buffs .toc")
end)

test("SelectQuest: focus, saved quest, macro", function()
    W.Advance(1)
    NS.SelectQuest(100, "Kobold Camp Cleanup", false, true)
    eq(NS.state.questId, 100, "focused quest")
    eq(QuestFocusDB.lastQuest, 100, "QuestFocusDB.lastQuest")
    local m = W.macros.AKit
    check(m ~= nil, "AKit macro created")
    check(m and contains(m.body, "Kobold Vermin"), "macro targets the quest mob")
    check(#NS.state.objectives == 1, "one objective")
    -- no-ops
    NS.SelectQuest(nil)
    NS.SelectQuest(0)
    eq(NS.state.questId, 100, "SelectQuest(nil / 0) keeps the focus")
end)

test("macro: first line keeps a living hostile target", function()
    W.Advance(1)
    NS.SelectQuest(100, "Kobold Camp Cleanup", false, true)
    local build = function() return NS.C.BuildMacroBody(NS.state.objectives, nil) end
    W.units.target = nil
    local body = build()
    eq(firstLine(body), "/cleartarget [noharm][dead]", "no target")
    check(hasLine(body, "/targetexact [noexists] Kobold Vermin"), "targets by name: " .. body)
    check(hasLine(body, "/cleartarget [dead]"), "drops corpses")
    check(contains(body, "/ping"), "solo 'ask' mode pings a new target")

    W.units.target = { name = "Kobold Vermin", hostile = true }
    body = build()
    eq(firstLine(body), "/cleartarget [noharm][dead]", "living quest mob as target is kept")
    check(not contains(body, "/ping"), "no ping when the target already is a quest mob")

    W.units.target = { name = "Murloc Raider", hostile = true }
    eq(firstLine(build()), "/cleartarget", "living non-quest enemy is dropped")

    W.units.target = { name = "Murloc Raider", hostile = true, tapped = true }
    eq(firstLine(build()), "/cleartarget", "tapped enemy is dropped")

    W.units.target = { name = "Kobold Vermin", hostile = true, dead = true }
    eq(firstLine(build()), "/cleartarget [noharm][dead]", "dead target: the [dead] condition clears it")

    W.units.target = { name = "Kobold Vermin", hostile = true, tapped = true }
    eq(firstLine(build()), "/cleartarget", "quest mob tapped by someone else is dropped")

    W.units.target = { name = "Guard Thomas", hostile = false }
    eq(firstLine(build()), "/cleartarget [noharm][dead]", "friendly target: [noharm] clears it")

    -- nameplate mode: /target nameplateN
    W.cvars.nameplateShowEnemies = "1"
    NS.state.pick = "nameplate3"
    W.units.nameplate3 = { name = "Kobold Vermin", hostile = true }
    W.units.target = { name = "Kobold Vermin", hostile = true }
    eq(firstLine(build()), "/target [noharm][dead] nameplate3", "nameplate pick keeps a living target")
    W.units.target = { name = "Murloc Raider", hostile = true }
    eq(firstLine(build()), "/target nameplate3", "nameplate pick replaces a non-quest enemy")
    NS.state.pick = "busy"
    check(contains(firstLine(build()), "quest mobs are taken"), "all quest mobs tapped: message instead of a target")
    NS.state.pick = nil
    W.units.nameplate3 = nil
    W.cvars.nameplateShowEnemies = "0"
    W.units.target = nil

    -- turn-in: friendly NPC, always retarget
    W.Advance(1)
    NS.SelectQuest(103, "Report to Goldshire", true, true)
    W.units.target = { name = "Kobold Vermin", hostile = true }
    body = build()
    eq(firstLine(body), "/cleartarget", "turn-in always retargets")
    check(hasLine(body, "/targetexact [noexists] Marshal McBride"), "turn-in targets the NPC: " .. body)
    W.units.target = nil
end)

test("macro: 255 character limit", function()
    local sources = {}
    for i = 1, 40 do
        sources[#sources + 1] = { id = 5000 + i, name = ("Very Long Named Test Creature %02d"):format(i), isNpc = true }
    end
    local objs = { { desc = "x", completed = false, sources = sources } }
    NS.state.extra = nil -- nearby quests would add names
    QuestFocusDB.startAttack, QuestFocusDB.useSpell, QuestFocusDB.spell = true, true, "Heroic Strike"
    local body, n = NS.C.BuildMacroBody(objs, nil)
    check(#body <= 255, ("body is %d chars"):format(#body))
    eq(n, 40, "every name counts for targeting")
    check(contains(body, "/startattack"), "auto attack line kept")
    check(contains(body, "/cast [@target,harm,nodead] Heroic Strike"), "spell line kept")
    QuestFocusDB.startAttack, QuestFocusDB.useSpell, QuestFocusDB.spell = nil, nil, nil
    -- the real macro, after a refresh
    NS.C.UpdateMacro()
    check(#(W.macros.AKit.body) <= 255, "saved macro under 255")
    -- nothing to target
    local b2, n2 = NS.C.BuildMacroBody({}, nil)
    eq(n2, 0, "empty objective list")
    check(contains(b2, "no targetable mob"), "empty body says so")
end)

test("macro: combat defers the edit", function()
    W.inCombat = true
    NS.C.ApplyMacro("/say combat test")
    eq(NS.state.pendingBody, "/say combat test", "pending body in combat")
    W.inCombat = false
    W.Fire("PLAYER_REGEN_ENABLED")
    eq(W.macros.AKit.body, "/say combat test", "written after combat")
    eq(NS.state.pendingBody, nil, "pending cleared")
    NS.C.UpdateMacro()
end)

test("macro: old QFocus macro renamed in place to AKit", function()
    local slot = GetMacroIndexByName("AKit")
    check(slot > 0, "AKit macro exists")
    -- pretend it still has the pre-0.8.0 name
    W.macroOrder[slot], W.macros.QFocus, W.macros.AKit = "QFocus", W.macros.AKit, nil
    local before = #W.macroOrder
    NS.C.ApplyMacro("/say renamed")
    eq(#W.macroOrder, before, "no second macro created")
    eq(GetMacroIndexByName("AKit"), slot, "same macro index (action bar slot kept)")
    eq(GetMacroIndexByName("QFocus"), 0, "old name gone")
    eq(W.macros.AKit and W.macros.AKit.body, "/say renamed", "body written to the renamed macro")
    NS.C.UpdateMacro()
end)

test("next / previous quest: deferral rules", function()
    W.MovePlayer(1429, 0.50, 0.55)
    NS.ClearDeferredQuests()
    W.Advance(1)
    NS.SelectQuest(100, "Kobold Camp Cleanup", false, true)
    local route = NS.QuestNavRoute()
    check(#route >= 2, "route has the other quests")
    for _, s in ipairs(route) do check(s.qid ~= 100, "route leaves out the focused quest") end
    local first = route[1] and route[1].qid
    W.Advance(1)
    NS.NextQuest()
    eq(NS.state.questId, first, "next goes to the first stop of the route")
    check(NS.DeferredQuests()[100], "the quest you left is skipped")
    check(rawget(NS.CharDB(), "deferredQuests") and rawget(NS.CharDB(), "deferredQuests")[100], "skip saved per character")
    local r2 = NS.QuestNavRoute()
    local last = r2[#r2]
    check(last and last.qid == 100 and last.deferred, "skipped quest at the end of the route, flagged")

    W.Advance(1)
    NS.PrevQuest()
    eq(NS.state.questId, 100, "previous goes back")
    check(not NS.DeferredQuests()[100], "picking the quest yourself ends its skip")

    W.Advance(1)
    NS.NextQuest()
    check(NS.DeferredQuests()[100], "skipped again")
    W.Fire("QUEST_REMOVED", 100)
    check(not NS.DeferredQuests()[100], "QUEST_REMOVED ends the skip")

    W.Advance(1)
    NS.SelectQuest(102, "Investigate Echo Ridge", false, true)
    W.Advance(1)
    NS.NextQuest()
    check(NS.DeferredQuests()[102], "102 skipped")
    W.Fire("QUEST_TURNED_IN", 999, 0, 0)
    check(next(NS.DeferredQuests()) == nil, "turning in any quest ends every skip")

    -- (a) the quest you jumped to becomes ready to turn in
    W.Advance(1)
    NS.SelectQuest(102, "Investigate Echo Ridge", false, true)
    W.Advance(1)
    NS.NextQuest()
    local anchor = NS.state.questId
    check(NS.DeferredQuests()[102], "102 skipped (anchor test)")
    for _, e in ipairs(W.log) do if e.qid == anchor then e.complete = true end end
    W.Fire("QUEST_LOG_UPDATE")
    check(next(NS.DeferredQuests()) == nil, "anchor quest ready to turn in ends every skip")
    for _, e in ipairs(W.log) do if e.qid == anchor and e.qid ~= 103 then e.complete = nil end end
    W.Advance(3)
end)

test("bags warning tiers (10 / 5 / 2 free)", function()
    check(NS.BuffsOutsideWarnings ~= nil, "Buffs module exported OutsideWarnings")
    if not NS.BuffsOutsideWarnings then return end
    W.player.resting, W.player.auras = false, {}
    local function scenario(free, yd)
        W.bags = { [0] = { 16, free }, { 10, 0 }, { 10, 0 }, { 10, 0 }, { 10, 0 } }
        W.PlaceNear(1429, 0.30, 0.80, yd) -- the vendor (Test Armorer) stands at 30, 80
        W.Advance(6)                      -- vendor search cache: 5 s
        local rows = {}
        for _, r in ipairs(NS.BuffsOutsideWarnings()) do rows[r.slot.key] = r end
        return rows
    end
    check(not scenario(12, 250).w_bags, "12 free: no bags row")
    local r = scenario(10, 250).w_bags
    check(r and contains(r.status, "|cffffcc33"), "10 free, vendor 250 yd: mild bags row")
    check(not scenario(10, 350).w_bags, "10 free, vendor 350 yd: nothing")
    r = scenario(5, 550).w_bags
    check(r and contains(r.status, "|cffff8833"), "5 free, vendor 550 yd: medium bags row")
    check(not scenario(5, 650).w_bags, "5 free, vendor 650 yd: nothing")
    r = scenario(2, 3000).w_bags
    check(r and contains(r.status, "|cffff2020") and contains(r.status, "almost full"), "2 free: urgent at any distance")
    r = scenario(0, 3000).w_bags
    check(r and contains(r.status, "full"), "0 free: full")
    local rows = scenario(10, 100)
    check(rows.w_vendor and not rows.w_bags, "vendor within 150 yd: one Vendor nearby row instead")
    W.player.resting = true
    rows = scenario(2, 3000)
    check(next(rows) == nil, "in town: no outside warnings")
    W.player.resting = false
    W.bags = { [0] = { 16, 10 }, { 10, 5 }, { 10, 5 }, { 10, 5 }, { 10, 5 } }
end)

test("in town: inn, resting, sleeping bag, taxi", function()
    local BAG = { name = "Cozy Sleeping Bag", spellId = 429959, count = 3, expires = W.time + 3600 }
    local function at(x, y, resting, auras, taxi)
        W.MovePlayer(1429, x, y)
        W.player.resting, W.player.auras, W.player.onTaxi = resting, auras or {}, taxi or false
        W.Advance(5) -- inn / aura caches
        return NS.InTown()
    end
    eq(at(0.30, 0.80, false), false, "out in the world")
    eq(at(0.30, 0.80, true), true, "resting (city / inn building)")
    eq(at(0.30, 0.80, true, { BAG }), false, "sleeping bag out in the world is not town")
    eq(at(0.30, 0.80, true, { { name = "Cozy Sleeping Bag", spellId = 1 } }), false, "sleeping bag found by name")
    eq(at(0.72, 0.20, false), true, "within 250 yd of an innkeeper (village)")
    eq(at(0.72, 0.20, true, { BAG }), true, "sleeping bag next to an inn is still town")
    eq(at(0.72, 0.20, true, nil, true), false, "on a taxi: never town")
    QuestFocusDB.noCityMode = true
    eq(NS.InCity(), false, "city list off: InCity false")
    eq(NS.InTown(), false, "...InTown (taxi) false")
    QuestFocusDB.noCityMode = nil
    at(0.50, 0.55, false)
end)

-- 0.7.9: no per-place ignore list; "Open automatically in towns" option + the panel's town icon
test("city list: auto-open option, town icon toggle", function()
    local city = _G.QuestFocusCityList
    local saveBags = W.bags
    W.bags = { [0] = { 16, 0 }, { 10, 0 }, { 10, 0 }, { 10, 0 }, { 10, 0 } } -- full bags: a Sell errand always shows
    local function arrive(resting)
        W.MovePlayer(1429, 0.30, 0.80) -- no innkeeper nearby: only resting makes it a town
        W.player.resting, W.player.auras, W.player.onTaxi = resting, {}, false
        W.Fire("PLAYER_UPDATE_RESTING")
        W.Advance(9)
    end
    check(NS.panel.cityBtn ~= nil, "panel has the town icon")
    arrive(false)
    eq(city:IsShown(), false, "out of town: closed")
    eq(NS.CityAutoOpen(), true, "auto-open is on by default")
    QuestFocusDB.cityNoAuto = true
    arrive(true)
    eq(city:IsShown(), false, "auto-open off: stays closed in town")
    NS.ToggleCityList()
    eq(city:IsShown(), true, "town icon opens it")
    NS.ToggleCityList()
    eq(city:IsShown(), false, "...and closes it")
    arrive(false)
    QuestFocusDB.cityNoAuto = nil
    arrive(true)
    eq(city:IsShown(), true, "auto-open on: opens in town")
    NS.ToggleCityList()
    W.Advance(9)
    eq(city:IsShown(), false, "closed by hand: stays closed in this town")
    arrive(false)
    NS.ToggleCityList()
    eq(city:IsShown(), true, "town icon opens it outside towns too")
    check(contains(city.title:GetText(), "nearby") or contains(city.title:GetText(), "Not in town"), "...with a not-in-town title")
    W.Advance(10)
    eq(city:IsShown(), true, "opened by hand: stays open outside towns")
    NS.ToggleCityList()
    QuestFocusDB.noCityMode = true
    arrive(true)
    eq(city:IsShown(), false, "city list off: no auto-open")
    NS.ToggleCityList()
    eq(city:IsShown(), true, "city list off: the icon still opens it")
    NS.ToggleCityList()
    QuestFocusDB.noCityMode = nil
    -- "Hide for 20 min": no auto-open for 20 minutes (also in the next town), the icon still opens it
    arrive(false)
    arrive(true)
    eq(city:IsShown(), true, "hide button: list is up in town")
    city.hideBtn:GetScript("OnClick")(city.hideBtn)
    eq(city:IsShown(), false, "hide button closes it")
    local untilT = NS.CharDB().cityHideUntil
    check(untilT and untilT - time() > 1190 and untilT - time() <= 1200, "hidden until now + 20 min (per character)")
    arrive(false)
    arrive(true)
    eq(city:IsShown(), false, "hidden: no auto-open in the next town either")
    NS.ToggleCityList()
    eq(city:IsShown(), true, "hidden: the icon still opens it")
    NS.ToggleCityList()
    NS.CharDB().cityHideUntil = time() - 1
    arrive(false)
    arrive(true)
    eq(city:IsShown(), true, "after 20 minutes it opens by itself again")
    NS.CharDB().cityHideUntil = nil
    check(NS.ResetCityIgnore == nil and NS.CityIgnoredHere == nil, "ignore list functions are gone")
    W.bags = saveBags
    arrive(false)
    W.MovePlayer(1429, 0.50, 0.55)
end)

test("ping modes", function()
    W.Advance(1)
    NS.SelectQuest(100, "Kobold Camp Cleanup", false, true)
    QuestFocusDB.pingMode, QuestFocusDB.noPing = nil, nil
    eq(NS.PingMode(), "ask", "default mode")
    eq(NS.UsePing(), true, "ask, solo: pings")
    QuestFocusDB.noPing = true
    eq(NS.PingMode(), "off", "old noPing switch means off")
    QuestFocusDB.noPing = nil
    NS.SetPingMode("on")
    eq(QuestFocusDB.pingMode, "on", "SetPingMode saves")
    W.inGroup = true
    eq(NS.UsePing(), true, "on, in a group")
    NS.SetPingMode("off")
    W.inGroup = false
    eq(NS.UsePing(), false, "off, solo")
    NS.SetPingMode("ask")
    W.Fire("GROUP_ROSTER_UPDATE")
    -- join a group: asks, no ping until answered
    W.inGroup, W.groupSize = true, 3
    W.Fire("GROUP_ROSTER_UPDATE")
    eq(NS.pingSession, nil, "not answered yet")
    eq(NS.UsePing(), false, "ask, in a group, no answer: no ping")
    check(not contains(NS.C.BuildMacroBody(NS.state.objectives, nil), "/ping"), "macro has no ping line")
    NS.pingSession = true
    eq(NS.UsePing(), true, "answered yes")
    -- leave: the answer is forgotten
    W.inGroup = false
    W.Fire("GROUP_ROSTER_UPDATE")
    eq(NS.pingSession, nil, "leaving the group clears the answer")
    eq(QuestFocusDB.pingAnswer, nil, "saved answer cleared")
    eq(NS.UsePing(), true, "solo again: pings")
    -- /reload in a group: the saved answer comes back
    QuestFocusDB.pingAnswer = false
    W.inGroup = true
    W.Fire("PLAYER_ENTERING_WORLD", false, true)
    eq(NS.pingSession, false, "saved answer restored after a reload")
    eq(NS.UsePing(), false, "...and used")
    W.inGroup = false
    W.Fire("GROUP_ROSTER_UPDATE")
    QuestFocusDB.pingMode = nil
end)

test("dungeon prep: start, auto-select blocked, abort restores", function()
    W.Advance(1)
    NS.SelectQuest(101, "Wolves Across the Border", false, true)
    NS.SelectObjective(1)
    NS.StartPrep("The Deadmines")
    eq(NS.PrepActive(), "The Deadmines", "prep active")
    eq(NS.state.questId, nil, "focus cleared while prepping")
    eq(rawget(NS.CharDB(), "prepDungeon"), "The Deadmines", "saved per character")
    local prev = rawget(NS.CharDB(), "prepPrev")
    check(prev and prev.qid == 101 and prev.obj == 1, "previous focus remembered")
    W.Advance(1)
    NS.SelectQuest(100, "Kobold Camp Cleanup", false, false) -- automatic selection
    eq(NS.PrepActive(), "The Deadmines", "automatic selection does not end prep")
    eq(NS.state.questId, nil, "...and does not take the panel")
    NS.StopPrep(false, true)
    eq(NS.PrepActive(), nil, "prep ended")
    eq(NS.state.questId, 101, "abort restores the quest")
    eq(NS.state.objIndex, 1, "...and the objective")
    eq(rawget(NS.CharDB(), "prepDungeon"), nil, "saved prep cleared")
    -- clicking a quest ends prep
    NS.StartPrep("The Deadmines")
    W.Advance(3)
    NS.SelectQuest(102, "Investigate Echo Ridge", false, true)
    eq(NS.PrepActive(), nil, "a click on a quest ends prep")
    eq(NS.state.questId, 102, "...and focuses it")
    -- slash command, partial name, inside the instance and out
    SlashCmdList.QUESTFOCUS("dungeon deadm")
    eq(NS.PrepActive(), "The Deadmines", "/ak dungeon deadm")
    W.instance = { name = "The Deadmines", type = "party", instanceID = 36 }
    W.Fire("PLAYER_ENTERING_WORLD", false, false)
    W.Fire("ZONE_CHANGED_NEW_AREA")
    W.Advance(4)
    W.instance = nil
    W.Fire("PLAYER_ENTERING_WORLD", false, false)
    W.Fire("ZONE_CHANGED_NEW_AREA")
    W.Advance(4)
    SlashCmdList.QUESTFOCUS("dungeon off")
    eq(NS.PrepActive(), nil, "/ak dungeon off")
    eq(NS.state.questId, 102, "/ak dungeon off restores the quest")
end)

-- Regression (0.7.2): the suggestion view's own refreshers (its 3 s OnUpdate, the
-- QUEST_LOG_UPDATE re-scan in Planner\Events.lua) drew "What next?" over the prep list.
test("dungeon prep: suggestion view stays hidden while prepping", function()
    local panel = NS.panel
    local function sugShown()
        local shown = {}
        for text, h in pairs(panel.sugHeaders or {}) do
            if h:IsShown() then shown[#shown + 1] = text end
        end
        table.sort(shown)
        return shown
    end
    NS.C.ClearQuest()
    W.Advance(4)
    check(#sugShown() > 0, "suggestion headers shown without prep")
    NS.StartPrep("The Deadmines")
    W.Advance(4)                                   -- suggestion OnUpdate (3 s) + prep ticker
    W.Fire("QUEST_LOG_UPDATE")
    W.Fire("QUEST_ACCEPTED", 1, 100)
    W.Advance(4)                                   -- Planner\Events.lua re-scan timer (1.5 s)
    eq(table.concat(sugShown(), ", "), "", "no suggestion headers while prepping")
    eq(panel.title:GetText(), "Prep: The Deadmines", "panel title stays the prep title")
    NS.StopPrep(false, true)
    if NS.state.questId then NS.C.ClearQuest() end
    W.Advance(4)
    check(#sugShown() > 0, "suggestions come back after prep")
    eq(panel.title:GetText(), "What next?", "...with their title")
end)

-- 0.7.3: the prep list comes from Questie only (every quest of the dungeon), quest chains show
-- their next step, quests you can't pick up yet show greyed, a quest that starts from a looted
-- item goes into the "starts inside" note, and the entrance is a title button, not a row.
test("dungeon prep: chains, later quests, item-started quests, title buttons", function()
    local DB = Q.modules.QuestieDB
    local AQ = Q.modules.AvailableQuests
    Q.NPC(960, "Gryan Test", 12, { { 45, 45 } })
    Q.Quest({ id = 2001, name = "Brotherhood 1", starter = 960, finisher = 960 })
    Q.Quest({ id = 2002, name = "Brotherhood 2", starter = 960, finisher = 960 }).preQuestSingle = { 2001 }
    Q.Quest({ id = 2003, name = "Red Silk", zone = 1581, starter = 960, finisher = 960 }).preQuestSingle = { 2002 }
    Q.Quest({ id = 2004, name = "VanCleef", zone = 1581, starter = 960, finisher = 960 }).preQuestGroup = { 2001, 2002 }
    local letter = Q.Quest({ id = 2005, name = "Unsent", zone = 1581, finisher = 960 })
    letter.Starts.Item = { 7001 }
    Q.Quest({ id = 2006, name = "Too High", zone = 1581, starter = 960, finisher = 960, requiredLevel = 30 })
    DB.QuestPointers = { [2001] = true, [2002] = true, [2003] = true, [2004] = true, [2005] = true, [2006] = true }
    local oldAvail = AQ.__availableQuests
    AQ.__availableQuests = { [2001] = true, [2005] = true }
    if NS.state.questId then NS.C.ClearQuest() end
    W.chat = {}
    NS.StartPrep("The Deadmines")
    W.Advance(2)
    local rows, entrance = NS.PrepRows()
    local byQid, note = {}, nil
    for _, r in ipairs(rows) do
        check(r.kind ~= "entrance", "the entrance is not a row any more")
        if r.qid then byQid[r.qid] = r end
        if r.kind == "note" then note = r end
    end
    local step = byQid[2001]
    check(step and step.kind == "pickup", "chain: its first step (Brotherhood 1) is a pickup row")
    eq(step and #step.chainFor, 2, "...shared by both dungeon quests of the chain")
    check(not byQid[2003] and not byQid[2004], "...the chained dungeon quests are not rows of their own")
    eq(byQid[2006] and byQid[2006].kind, "later", "a quest above your level: greyed 'later' row")
    check(not byQid[2005], "item-started quest: no pickup row")
    local inNote = false
    for _, x in ipairs(note and note.list or {}) do if x.qid == 2005 then inNote = true end end
    check(inNote, "...it is in the 'starts inside' note")
    check(entrance and entrance.kind == "entrance", "entrance kept as the marker target")
    eq(NS.state.waypoint and NS.state.waypoint.title, "Gryan Test", "marker on the chain step's quest giver")
    for _, l in ipairs(W.chat) do
        check(not contains(l, "No known location"), "no 'No known location' spam: " .. l)
    end
    local panel = NS.panel
    check(panel.prepEntranceBtn:IsShown() and panel.prepLfgBtn:IsShown(), "entrance + group finder buttons shown")
    panel.prepEntranceBtn:GetScript("OnClick")(panel.prepEntranceBtn)
    check(contains(NS.state.waypoint and NS.state.waypoint.title, "entrance"), "entrance button: marker on the entrance")
    panel.prepLfgBtn:GetScript("OnEnter")(panel.prepLfgBtn)
    panel.prepEntranceBtn:GetScript("OnEnter")(panel.prepEntranceBtn)
    NS.StopPrep(true)
    check(not panel.prepEntranceBtn:IsShown() and not panel.prepLfgBtn:IsShown(), "buttons hidden after prep")
    AQ.__availableQuests = oldAvail
end)

-- 0.7.4: the "Dungeons for your level" popup lists Forever's own dungeons (The Drowned City at
-- 35-42 was missing for a level 36 character) and the classic ones whose quests Questie files
-- under another area ID (Razorfen Kraul quests are 1717, Uldaman 1517: they showed 0 quests)
test("dungeon list: Forever dungeons and Questie's alternative area IDs", function()
    local DB = Q.modules.QuestieDB
    local oldLevel, oldFaction, oldPtrs = W.player.level, W.player.faction, DB.QuestPointers
    W.player.level, W.player.faction = 36, "Horde"
    Q.NPC(961, "Kraul Giver", 17, { { 40, 80 } })
    Q.Quest({ id = 2101, name = "Blueleaf Tubers", zone = 1717, starter = 961, finisher = 961 })
    Q.Quest({ id = 2102, name = "Badlands Relic", zone = 1517, starter = 961, finisher = 961 })
    -- a Forever quest that Questie does know, filed under its outdoor zone (Stranglethorn)
    Q.Quest({ id = 95776, name = "The Only Good Brinescale...", zone = 33, starter = 961, finisher = 961 })
    DB.QuestPointers = { [2101] = true, [2102] = true, [95776] = true }
    -- the dungeon -> quest ID map is built once (an earlier test may have built it): offer them
    local AQ = Q.modules.AvailableQuests
    local oldAvail = AQ.__availableQuests
    AQ.__availableQuests = { [2101] = true, [2102] = true }
    local byName = {}
    for _, e in ipairs(NS.DungeonsForLevel(36)) do byName[e.name] = e end
    local dc = byName["The Drowned City"]
    check(dc ~= nil, "The Drowned City (35-42) is listed at level 36")
    eq(dc and dc.lo, 35, "...from level 35")
    local q = {}
    for _, d in ipairs(dc and dc.quests or {}) do q[d.qid] = d end
    check(q[95775] and q[95775].name == "The Drowned City", "...a quest Questie does not know comes from the built-in table")
    check(q[95776] ~= nil, "...a quest Questie files under Stranglethorn still belongs to the dungeon")
    check(not q[95787], "...no Alliance quests for a Horde character")
    check(q[95789] ~= nil, "...quests for both factions are listed")
    local function has(name, qid)
        for _, d in ipairs(byName[name] and byName[name].quests or {}) do if d.qid == qid then return true end end
    end
    check(has("Razorfen Kraul", 2101), "Razorfen Kraul: its quests (area 1717) are counted")
    check(byName["Krol'dok Stronghold"] ~= nil, "Krol'dok Stronghold (40-47) is in range too")
    check(not byName["Blackmaw Hold"], "Blackmaw Hold (55-60) is not")
    eq(NS.QuestDungeon(NS.GetQuestieQuest(95776), 95776), "The Drowned City", "dungeon tag for the Forever quest")
    eq(NS.QuestDungeon(NS.GetQuestieQuest(2102), 2102), "Uldaman", "Uldaman quest (area 1517) tagged")
    for _, n in ipairs({ "The Drowned City", "Krol'dok Stronghold", "Alcaz Prison", "Blackmaw Hold",
        "Shaper's Terrace", "Hall of Thanes", "City of Dalaran", "Excavation Site: Wetlands", "Ruins of Lordaeron" }) do
        check(NS.DungeonEntrances[n] ~= nil, n .. ": entrance known")
        check(NS.DungeonBosses[n] ~= nil, n .. ": boss order known")
        local e = NS.CollectDungeon(n)
        check(e and e.name == n, n .. ": dungeon prep finds it")
    end
    NS.ToggleDungeonList()
    check(_G.QuestFocusDungeonList:IsShown(), "popup opens")
    NS.ToggleDungeonList()
    W.player.level, W.player.faction, DB.QuestPointers = oldLevel, oldFaction, oldPtrs
    AQ.__availableQuests = oldAvail
end)

-- 0.7.3: dragging the resize grip lays the rows out again right away; the panel does not go
-- below its content (rows used to stay where they were while only the frame shrank)
test("panel resize: rows follow while dragging", function()
    local panel = NS.panel
    if NS.state.questId then NS.C.ClearQuest() end
    QuestFocusDB.panelH = 500
    NS.Panel_Update()
    W.Advance(1)
    local grip = panel.grip
    check(grip:IsShown(), "grip shown in the suggestion view")
    W.cursorX, W.cursorY = 0, 0
    grip:GetScript("OnMouseDown")(grip, "LeftButton")
    W.cursorY = 480                                -- drag far up: smaller than the content
    W.Advance(0.5, 0.25)
    check(panel:GetHeight() > 120, ("mid-drag the panel keeps its content height (got %s)"):format(tostring(panel:GetHeight())))
    grip:GetScript("OnMouseUp")(grip)
    check(QuestFocusDB.panelH >= panel:GetHeight() - 1, "saved height is not below the real one")
    W.cursorX, W.cursorY = nil, nil
    QuestFocusDB.panelH = nil
    NS.Panel_Update()
end)

test("travel route (Dijkstra) sanity", function()
    local TR = NS.TransportRoute
    local t, steps = TR({ wc = 0, wx = 0, wy = 0 }, { wc = 0, wx = 300, wy = 400 }, 7, false)
    check(t and math.abs(t - 500 / 7) < 0.01, "short walk: distance / speed, got " .. tostring(t))
    eq(steps and #steps, 0, "short walk: no transport steps")
    -- Stormwind Harbor -> Auberdine (Alliance boat)
    t, steps = TR({ wc = 0, wx = -8650, wy = 1344 }, { wc = 1, wx = 6548, wy = 950 }, 7, false)
    check(t ~= nil, "Stormwind -> Darkshore has a route")
    local boat
    for _, s in ipairs(steps or {}) do if s.kind == "boat" and s.from == "Stormwind Harbor" then boat = s end end
    check(boat and boat.to == "Auberdine", "...by the Stormwind - Auberdine boat")
    check(t and t < 90 + 1572 / 25 + 60, "...in about the boat's time, got " .. tostring(t))
    -- Alliance never takes a Horde zeppelin
    t, steps = TR({ wc = 1, wx = 1320, wy = -4650 }, { wc = 0, wx = 2060, wy = 290 }, 7, false)
    for _, s in ipairs(steps or {}) do check(s.kind ~= "zeppelin", "Alliance route uses a zeppelin") end
    W.player.faction = "Horde"
    t, steps = TR({ wc = 1, wx = 1320, wy = -4650 }, { wc = 0, wx = 2060, wy = 290 }, 7, false)
    local zep
    for _, s in ipairs(steps or {}) do if s.kind == "zeppelin" then zep = s end end
    check(zep ~= nil, "Horde: Orgrimmar -> Undercity by zeppelin")
    W.player.faction = "Alliance"
    -- no way to an unknown continent
    t = TR({ wc = 0, wx = 0, wy = 0 }, { wc = 999, wx = 0, wy = 0 }, 7, false)
    eq(t, nil, "unreachable continent")
    -- a route is never slower than walking straight (same continent)
    local pairsList = { { -8650, 1344, -3900, -580 }, { -14270, 580, -1100, -550 }, { 0, 0, 5000, 5000 } }
    for _, p in ipairs(pairsList) do
        local d = math.sqrt((p[1] - p[3]) ^ 2 + (p[2] - p[4]) ^ 2) / 7
        local rt = TR({ wc = 0, wx = p[1], wy = p[2] }, { wc = 0, wx = p[3], wy = p[4] }, 7, false)
        check(rt and rt <= d + 0.01, ("route %s <= walk %s"):format(tostring(rt), tostring(d)))
    end
    -- custom transport from QuestFocusDB.customTransports
    QuestFocusDB.customTransports = { { kind = "boat", a = { 0, 50, 50, "Test Dock A" }, b = { 1, 60, 60, "Test Dock B" }, time = 30 } }
    t, steps = TR({ wc = 0, wx = 50, wy = 50 }, { wc = 1, wx = 60, wy = 60 }, 7, false)
    check(t and math.abs(t - 30) < 0.01, "custom transport used, got " .. tostring(t))
    QuestFocusDB.customTransports = nil
    -- the built-in table itself
    local n, bad = NS.TransportCheck()
    check(n > 10, "transport table has routes")
    for _, b in ipairs(bad) do check(false, b) end
end)

test("escort: star icon only on the confirmed escort NPC", function()
    local E = NS.Escort
    check(E and E.Info and E.IsEscortUnit and E.Observe, "Escort exports Info / IsEscortUnit / Observe")
    if not (E and E.IsEscortUnit) then return end
    Q.NPC(1010, "Captive Scout", 12, { { 55, 55 } }, { friendlyToFaction = "AH" })
    Q.NPC(1011, "Shadowmaw Panther", 12, { { 56, 56 } })
    local esc = Q.Quest({ id = 110, name = "Free the Scout", starter = 1010, finisher = 900 })
    esc.ObjectiveData = { { Type = "event", Text = "Escort Captive Scout to safety", Coordinates = { [12] = { { 57, 57 } } } } }
    Q.Quest({ id = 192, name = "Panther Mastery", objectives = { Q.KillObjective(1011, 10) }, finisher = 900, starter = 900 })
    eq(E.Info(192), nil, "a kill quest (Panther Mastery) is not an escort")
    eq(E.Info(100), nil, "Kobold Camp Cleanup is not an escort")
    local info = E.Info(110)
    check(info and info.name == "Captive Scout" and info.npcId == 1010, "escort NPC from the quest data")
    if not info then return end
    local marks = 0
    local realSet = SetRaidTarget
    rawset(_G, "SetRaidTarget", function() marks = marks + 1 end)
    local function try(u)
        W.units.target = u
        local r = E.IsEscortUnit("target", info)
        E.Observe("target", info)
        return r
    end
    eq(try({ name = "Young Panther", hostile = true, id = 2000, guid = "Creature-0-0-0-0-2000-1" }), false, "attacking non-quest mob")
    eq(try({ name = "Captive Scout", hostile = true, id = 1010, guid = "Creature-0-0-0-0-1010-2" }), false, "hostile unit is never the escort")
    eq(try({ name = "Captive Scout", hostile = false, id = 3000, guid = "Creature-0-0-0-0-3000-3" }), false, "same name, other NPC ID")
    eq(try({ name = "Captive Scou", hostile = false, guid = "Player-1-2" }), false, "partial name")
    eq(marks, 0, "no raid icon on any of them")
    eq(try({ name = "Captive Scout", hostile = false, id = 1010, guid = "Creature-0-0-0-0-1010-4" }), true, "the escort NPC")
    eq(marks, 1, "star icon on the escort")
    rawset(_G, "SetRaidTarget", realSet)
    W.units.target = nil
end)

test("macro ping: only out of combat (in combat it would ping any attacker)", function()
    W.Advance(1)
    NS.SelectQuest(100, "Kobold Camp Cleanup", false, true)
    W.units.target = nil
    local body = NS.C.BuildMacroBody(NS.state.objectives, nil)
    check(hasLine(body, "/ping [nocombat,@target,harm,nodead] attack; [nocombat,@target,help,nodead] assist"),
        "ping line has [nocombat]: " .. body)
end)

test("macro ping: never a tapped or unpicked mob (nameplate mode)", function()
    W.Advance(1)
    NS.SelectQuest(100, "Kobold Camp Cleanup", false, true)
    local build = function() return NS.C.BuildMacroBody(NS.state.objectives, nil) end
    W.cvars.nameplateShowEnemies = "1"
    -- all nearby quest mobs tapped: no target line, the old (tapped) target must not be pinged
    W.units.target = { name = "Kobold Vermin", hostile = true, tapped = true }
    NS.state.pick = "busy"
    local body = build()
    check(contains(firstLine(body), "quest mobs are taken"), "busy message: " .. body)
    check(not contains(body, "/ping"), "busy: no ping line: " .. body)
    W.units.target = nil
    check(not contains(build(), "/ping"), "busy, no target: no ping line")
    -- no visible quest nameplate: by-name fallback could hit a tapped mob -> no ping
    NS.state.pick = nil
    body = build()
    check(hasLine(body, "/targetexact [noexists] Kobold Vermin"), "falls back to names: " .. body)
    check(not contains(body, "/ping"), "unpicked by-name target: no ping: " .. body)
    -- a real pick (living, untapped): ping it
    NS.state.pick = "nameplate3"
    W.units.nameplate3 = { name = "Kobold Vermin", hostile = true }
    check(contains(build(), "/ping"), "picked mob is pinged")
    -- nameplates off: nothing to decide from, ping stays
    NS.state.pick = nil
    W.units.nameplate3 = nil
    W.cvars.nameplateShowEnemies = "0"
    check(contains(build(), "/ping"), "nameplates off: ping stays")
end)

test("macro: picked nameplate mob's name comes first in the fallback (Goretusk Liver Pie)", function()
    -- /ak debug from the user: Picked: Goretusk (nameplate1); the fallback had only Great Goretusk + Bellygrub
    local src = function(id, name) return { id = id, name = name, isNpc = true } end
    local objs = { { desc = "Goretusk Liver", completed = false, sources = {
        src(157, "Great Goretusk"), src(345, "Bellygrub"), src(454, "Young Goretusk"), src(547, "Goretusk"),
    } } }
    local saveExtra = NS.state.extra
    NS.state.extra = nil
    W.cvars.nameplateShowEnemies = "1"
    W.units.target = nil
    NS.state.pick = "nameplate1"
    W.units.nameplate1 = { name = "Goretusk", hostile = true }
    local body, n = NS.C.BuildMacroBody(objs, nil)
    eq(n, 4, "all four wanted mobs count")
    check(#body <= 255, ("fits: %d chars"):format(#body))
    eq(firstLine(body), "/target [noharm][dead] nameplate1", "nameplate line first")
    local lines = {}
    for l in (body .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
    eq(lines[2], "/cleartarget [dead]", "corpse from the token line cleared")
    eq(lines[3], "/targetexact [noexists] Goretusk", "picked mob's name is the first fallback: " .. body)
    check(contains(body, "/ping"), "ping kept")
    -- without a pick the quest order stays
    NS.state.pick = nil
    W.units.nameplate1 = nil
    W.cvars.nameplateShowEnemies = "0"
    body = NS.C.BuildMacroBody(objs, nil)
    check(contains(body, "/targetexact [noexists] Great Goretusk\n"), "no pick: quest order: " .. body)
    NS.state.extra = saveExtra
end)

test("macro: nameplate pick (mob within ~20 yd) keeps a by-name fallback", function()
    W.Advance(1)
    NS.SelectQuest(100, "Kobold Camp Cleanup", false, true)
    W.cvars.nameplateShowEnemies = "1"
    W.units.target = nil
    NS.state.pick = "nameplate3"
    W.units.nameplate3 = { name = "Kobold Vermin", hostile = true }
    local body = NS.C.BuildMacroBody(NS.state.objectives, nil)
    eq(firstLine(body), "/target [noharm][dead] nameplate3", "targets the picked nameplate first")
    -- stale token (plate gone or renumbered since the macro was written): names still work
    check(hasLine(body, "/targetexact [noexists] Kobold Vermin"), "by-name fallback after the token: " .. body)
    local l1 = ("\n" .. body .. "\n"):find("\n/cleartarget [dead]\n", 1, true)
    local l2 = ("\n" .. body .. "\n"):find("\n/targetexact [noexists] Kobold Vermin\n", 1, true)
    check(l1 and l2 and l1 < l2, "a corpse left by the token line is cleared before the names")
    check(#body <= NS.C.MACRO_MAX, "fits in the macro limit")
    -- busy: still no targeting at all
    NS.state.pick = "busy"
    check(not contains(NS.C.BuildMacroBody(NS.state.objectives, nil), "/targetexact"), "busy: no by-name targeting")
    NS.state.pick = nil
    W.units.nameplate3 = nil
    W.cvars.nameplateShowEnemies = "0"
end)

test("buffs: other players' buffs are not mine", function()
    local mine = NS.BuffsAuraMine
    check(mine ~= nil, "Buffs exports BuffsAuraMine")
    if not mine then return end
    eq(mine("player", "Mark of the Wild"), true, "cast by you")
    eq(mine("pet", "Blood Pact"), true, "your pet")
    eq(mine("vehicle", "Some Buff"), true, "your vehicle")
    W.units.party1 = { name = "Druidfriend", hostile = false }
    eq(mine("party1", "Mark of the Wild"), false, "druid's Mark of the Wild")
    eq(mine("party1", "Well Fed"), false, "food buff with a known other source")
    eq(mine(nil, "Mark of the Wild"), false, "class spell, unknown source")
    eq(mine(nil, "Thorns"), false, "Thorns, unknown source")
    eq(mine(nil, "Well Fed"), true, "consumable, unknown source (XP food row needs it)")
    eq(mine(nil, "Spicy Beefstick"), true, "item buff, unknown source")
    -- end to end: the /ak debug aura lines
    local T = W.time + 3600
    W.player.auras = {
        { name = "Mark of the Wild", spellId = 5234, duration = 1800, expires = T, source = "party1" },
        { name = "Thorns", spellId = 8914, duration = 600, expires = T, noSource = true },
        { name = "Well Fed", spellId = 19705, duration = 900, expires = T, noSource = true },
    }
    local text = table.concat(NS.BuffDebugLines(), "\n")
    check(contains(text, "aura Mark of the Wild (5234) 1800s mine=false"), "MotW from a druid: " .. text)
    check(contains(text, "aura Thorns (8914) 600s mine=false"), "Thorns, nil source")
    check(contains(text, "aura Well Fed (19705) 900s mine=true"), "Well Fed, nil source")
    W.player.auras = {}
    W.units.party1 = nil
end)

test("TomTom is optional", function()
    W.Advance(1)
    NS.SelectQuest(101, "Wolves Across the Border", false, true) -- no TomTom: own arrow / map pin
    local added = 0
    rawset(_G, "TomTom", {
        AddWaypoint = function() added = added + 1; return { "uid" } end,
        RemoveWaypoint = function() end,
        SetClosestWaypoint = function() end,
    })
    W.Advance(1)
    NS.SelectQuest(102, "Investigate Echo Ridge", false, true)
    check(added > 0, "TomTom waypoint added when TomTom is there")
    rawset(_G, "TomTom", nil)
    W.Advance(1)
    NS.SelectQuest(101, "Wolves Across the Border", false, true)
end)

-- 0.7.6: farm session (Planner\Farm.lua): looted money / item parsing, XP across a level up,
-- vendor and "best sale" (auction addon) totals, pause, rates, summary, panel button.
test("farm session: parsing", function()
    local F = NS.Farm
    eq(F.ParseMoney("You loot 1 Gold, 2 Silver, 3 Copper"), 10203, "loot money")
    eq(F.ParseMoney("Your share of the loot is 45 Silver, 6 Copper."), 4506, "group share")
    eq(F.ParseMoney("You loot 7 Copper"), 7, "copper only")
    eq(F.ParseMoney("nothing here"), 0, "no money")
    eq(("3 Golds"):match(F.FormatToPattern("%d |4Gold:Golds;")), "3", "plural escape in the format")
    eq(("Hans gets 5"):match(F.FormatToPattern("%1$s gets %2$d")), "Hans", "positional %1$s")
    local link = "|cffffffff|Hitem:2589::::::::36:::::::|h[Linen Cloth]|h|r"
    local id, l, n = F.ParseLoot("You receive loot: " .. link .. "x3.")
    eq(id, 2589, "multiple: item id") eq(n, 3, "multiple: count") eq(l, link, "multiple: link")
    id, l, n = F.ParseLoot("You receive loot: " .. link .. ".")
    eq(id, 2589, "single: item id") eq(n, 1, "single: count")
    eq(F.ParseLoot("You receive item: " .. link .. "."), nil, "pushed item (bought / quest reward) is not loot")
    eq(F.ParseLoot("Bob receives loot: " .. link .. "."), nil, "someone else's loot")
    eq(F.FormatMoney(10203, true), "1g 02s 03c", "money format")
    eq(F.FormatMoney(506, true), "5s 06c", "money format (silver)")
    eq(F.FormatTime(3725), "1:02:05", "time format")
end)

test("farm session: totals, pause, summary", function()
    local F = NS.Farm
    local function item(id, name) return "|cffffffff|Hitem:" .. id .. "::::::::36:::::::|h[" .. name .. "]|h|r" end
    W.money, W.player.xp, W.player.xpMax = 5000, 100, 1000
    local level = W.player.level
    W.itemInfo = { [2589] = { "Linen Cloth", 13 }, [1111] = false, [2222] = { "Quest Thing", 0 }, [3333] = { "BoP Ring", 500, 1 } }
    SlashCmdList.QUESTFOCUS("farm start")
    check(F.IsRunning(), "running after /ak farm start")
    check(F.Viewing(), "the panel shows the farm session")
    check(NS.panel:IsShown(), "panel shown")
    eq(NS.panel.title:GetText(), "Farm session", "panel title")
    eq(NS.panel.statBoxes[1].label:GetText(), "TIME", "stat box 1")
    eq(NS.panel.statBoxes[3].label:GetText(), "GOLD GAINED", "stat box 3 (first minute: the gain)")
    W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Mangy Wolf dies, you gain 45 experience.")
    W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Mangy Wolf dies, you gain 45 experience.")
    W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Vermin dies, you gain 40 experience.")
    W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "You gain 300 experience.") -- quest / exploration: not a kill
    W.Fire("CHAT_MSG_MONEY", "You loot 1 Gold, 2 Silver, 3 Copper")
    W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. item(2589, "Linen Cloth") .. "x3.")
    W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. item(1111, "Late") .. ".")
    W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. item(2222, "Quest Thing") .. ".")
    W.Fire("CHAT_MSG_LOOT", "You receive item: " .. item(2589, "Linen Cloth") .. ".") -- bought: not counted
    W.player.xp = 400; W.Fire("PLAYER_XP_UPDATE", "player")      -- +300
    W.player.xp = 50; W.Fire("PLAYER_XP_UPDATE", "player")       -- level up before UnitLevel updates: +600 +50
    W.player.level = level + 1
    W.player.xp = 80; W.Fire("PLAYER_XP_UPDATE", "player")       -- +30
    local t = F.Totals()
    eq(t.xp, 980, "XP across a level up")
    eq(t.money, 10203, "looted gold")
    eq(t.vendor, 39, "vendor value (3 x 13c; quest item 0)")
    eq(t.pending, 1, "item info not cached yet")
    W.itemInfo[1111] = { "Late", 100 }
    W.Fire("GET_ITEM_INFO_RECEIVED", 1111, true)
    t = F.Totals()
    eq(t.pending, 0, "item info arrived")
    eq(t.vendor, 139, "vendor value after item info")
    eq(t.best, t.vendor, "no auction addon: best = vendor")
    check(F.AHSource() == nil, "no auction addon")

    -- auction addon (Auctionator API): best = max(AH, vendor); unsellable and BoP stay vendor
    rawset(_G, "Auctionator", { API = { v1 = { GetAuctionPriceByItemID = function(caller, itemID)
        return ({ [2589] = 50, [2222] = 99, [3333] = 100000, [1111] = 20 })[itemID]
    end } } })
    W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. item(3333, "BoP Ring") .. ".")
    t = F.Totals()
    eq(t.vendor, 639, "vendor value with the BoP ring")
    eq(t.best, 3 * 50 + 100 + 0 + 500, "best sale: AH for cloth, vendor for the rest")
    eq(t.items[1].id, 3333, "top item by value")

    -- time: 1 hour in game; pause stops time, loot and XP
    W.Advance(3600, 5)
    t = F.Totals()
    check(math.abs(t.elapsed - 3600) < 6, "elapsed ~1 h, got " .. tostring(t.elapsed))
    check(t.xpH and math.abs(t.xpH - 980) < 3, "XP per hour")
    eq(t.need, 920, "XP to level")
    check(t.eta and math.abs(t.eta - 920 / 980 * 3600) < 15, "ETA at the current rate")
    check(t.goldH and math.abs(t.goldH - (10203 + 639)) < 5, "gold + vendor per hour")
    W.money = 7000
    eq(F.Totals().net, 2000, "net gold change")
    SlashCmdList.QUESTFOCUS("farm pause")
    check(F.IsPaused(), "paused")
    local e0 = F.Totals().elapsed
    W.Fire("CHAT_MSG_MONEY", "You loot 9 Gold")
    W.player.xp = 180; W.Fire("PLAYER_XP_UPDATE", "player")
    W.Advance(20, 1)
    eq(F.Totals().elapsed, e0, "time stands while paused")
    eq(F.Totals().money, 10203, "no loot while paused")
    eq(F.Totals().xp, 980, "no XP while paused")
    SlashCmdList.QUESTFOCUS("farm resume")
    check(not F.IsPaused(), "resumed")
    W.player.xp = 200; W.Fire("PLAYER_XP_UPDATE", "player")
    eq(F.Totals().xp, 1000, "XP after resume counts from the resume point")

    -- saved per character; a long gap (loading screen / offline) adds at most a few seconds
    local fd = rawget(NS.CharDB(), "farm")
    check(fd and fd.running and fd.items[2589].n == 3, "session saved in the character DB")
    e0 = fd.elapsed
    W.time = W.time + 10000
    W.Fire("PLAYER_LOGIN")
    W.Advance(2, 1)
    check(fd.elapsed - e0 < 10, "a gap of 10000 s is not counted, got +" .. tostring(fd.elapsed - e0))

    eq(fd.killCount, 3, "kills from the XP messages")
    eq(F.TopKills(fd)[1].name, "Mangy Wolf", "most killed mob")

    -- panel rows: every line is set (0.7.6 drew only the first line of the box), hover: top items
    NS.Panel_Update()
    local rowsText = {}
    for _, f in ipairs(W.frames) do
        if f.__parent == NS.panel and f.__kind == "Button" and f:IsShown() and f.text and f.text:GetText() then
            rowsText[#rowsText + 1] = f.text:GetText()
        end
    end
    local all = table.concat(rowsText, "\n")
    for _, want in ipairs({ "XP gained", "To level", "Mobs killed", "Looted gold", "Items (vendor)", "Best sale" }) do
        check(contains(all, want), "panel row: " .. want)
    end
    eq(#F.PanelLines(F.Totals(), fd), 6, "six farm rows")
    F.RouteTooltip(NS.panel)
    local tip = table.concat(GameTooltip.__lines or {}, "\n")
    check(contains(tip, "[BoP Ring]") and contains(tip, "[Linen Cloth]"), "tooltip lists the top items")
    GameTooltip:Hide()

    -- stop: summary window + one line in chat, panel back to quests
    local before = #W.chat
    W.player.level = level + 1
    SlashCmdList.QUESTFOCUS("farm stop")
    check(not F.IsRunning(), "stopped")
    check(not F.Viewing(), "farm view ends with the session")
    local sawSummary = false
    for i = before + 1, #W.chat do
        if contains(W.chat[i], "Farm session: ") and contains(W.chat[i], "3 kills") then sawSummary = true end
    end
    check(sawSummary, "one-line summary in chat")
    local sf = F.SummaryFrame()
    check(sf and sf:IsShown(), "summary window shown")
    local sum = table.concat(F.SummaryLines(fd), "\n")
    for _, want in ipairs({ "TIME AND XP", "KILLS", "LOOT", "Duration", "Mobs killed", "Mangy Wolf: x2", "XP gained",
        "Levels gained", "Looted gold", "Items looted", "Vendor value", "Best sale", "Gold per hour" }) do
        check(contains(sum, want), "summary: " .. want)
    end
    sf.newBtn:Click()
    check(F.IsRunning() and not sf:IsShown(), "Start new: a new session, window closed")
    SlashCmdList.QUESTFOCUS("farm stop")
    sf.closeBtn:Click()
    check(not sf:IsShown(), "Close button")
    QuestFocusDB.noFarmSummary = true
    SlashCmdList.QUESTFOCUS("farm start")
    SlashCmdList.QUESTFOCUS("farm stop")
    check(not sf:IsShown(), "summary window off in Options")
    QuestFocusDB.noFarmSummary = nil
    NS.panel.farmBtn:Click()
    check(F.IsRunning(), "panel button starts a session")
    NS.panel.farmBtn:Click()
    check(not F.IsRunning(), "panel button stops it")

    rawset(_G, "Auctionator", nil)
    W.itemInfo = nil
    W.player.level, W.player.xp, W.money = level, 0, 0
end)

-- 0.8.4: live counters right after the first kill (the boxes showed "-" for the first minute, as if
-- nothing counted), XP even when PLAYER_XP_UPDATE came before / without the chat line, rested XP
-- (part of the gain, ETA from the base pace, pool left), and the summary window's groups.
test("farm session: live counters, rested XP, summary groups", function()
    local F = NS.Farm
    local function rowsText()
        local t = {}
        for _, f in ipairs(W.frames) do
            if f.__parent == NS.panel and f.__kind == "Button" and f:IsShown() and f.text and f.text:GetText() then
                t[#t + 1] = f.text:GetText()
            end
        end
        return table.concat(t, "\n")
    end
    eq(F.ParseRested("Mangy Wolf dies, you gain 250 experience. (+125 exp Rested bonus)"), 125, "rested bonus")
    eq(F.ParseRested("Mangy Wolf dies, you gain 150 experience. (+20 exp group bonus)"), 0, "group bonus is not rested")
    eq(F.ParseRested("Mangy Wolf dies, you gain 125 experience."), 0, "no bonus")
    eq(F.EtaSeconds(1000, 1000, 0), 3600, "ETA without rested")
    eq(F.EtaSeconds(1000, 1000, 300), 2520, "ETA: rested pool covers part")
    eq(F.EtaSeconds(1000, 1000, 5000), 1800, "ETA: rested doubles everything")
    eq(F.EtaSeconds(1000, nil, 0), nil, "no ETA without a pace")

    W.player.xp, W.player.xpMax, W.player.rested = 100, 10000, 3000
    SlashCmdList.QUESTFOCUS("farm start")
    local b = NS.panel.statBoxes
    -- the game sends PLAYER_XP_UPDATE, then the chat line; no clock tick in between
    W.player.xp, W.player.rested = 350, 2875
    W.Fire("PLAYER_XP_UPDATE", "player")
    W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Mangy Wolf dies, you gain 250 experience. (+125 exp Rested bonus)")
    local txt = rowsText()
    check(contains(txt, "XP gained:|r 250"), "XP row right after the kill")
    check(contains(txt, "Mobs killed:|r 1"), "kill row right after the kill")
    check(contains(txt, "rested 125"), "rested part on the XP row")
    check(contains(txt, "rested left 2,875"), "rested pool left on the To level row")
    eq(b[2].label:GetText(), "XP GAINED", "first minute: the box shows the gain")
    eq(b[2].value:GetText(), "+250", "XP box right after the kill")
    check(contains(NS.panel.sub:GetText(), "1 kills"), "kill count in the sub line")
    -- only the chat line (PLAYER_XP_UPDATE missed / late): XP still counts, once
    W.player.xp = 600
    W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Vermin dies, you gain 250 experience. (+125 exp Rested bonus)")
    W.Advance(1, 0.5)
    W.Fire("PLAYER_XP_UPDATE", "player")
    local fd = rawget(NS.CharDB(), "farm")
    eq(fd.xp, 500, "XP from the kill without its own XP event, not counted twice")
    eq(fd.killCount, 2, "two kills")
    -- after a minute: rates; ETA from the base pace with the rested pool
    W.Advance(60, 1)
    local t = F.Totals()
    eq(b[2].label:GetText(), "XP / HOUR", "after a minute: rate")
    eq(t.rested, 250, "rested part")
    check(t.baseH and math.abs(t.baseH - 250 / (t.elapsed / 3600)) < 1, "base pace without rested")
    check(t.eta and math.abs(t.eta - F.EtaSeconds(t.need, t.baseH, 2875)) < 1, "ETA uses the base pace and the pool")

    SlashCmdList.QUESTFOCUS("farm stop")
    local data = F.SummaryData(fd)
    local secs, divs = {}, 0
    for _, e in ipairs(data) do
        if e.sec then secs[#secs + 1] = e.sec end
        if e.div then divs = divs + 1 end
    end
    eq(table.concat(secs, ","), "TIME AND XP,KILLS,LOOT", "summary groups")
    eq(divs, 2, "dividers between the groups")
    local sum = table.concat(F.SummaryLines(fd), "\n")
    check(contains(sum, "of it rested bonus: 250"), "summary: rested part")
    check(contains(sum, "Rested XP left: 2,875"), "summary: rested pool left")
    local sf = F.SummaryFrame()
    check(sf and sf:IsShown() and sf.newBtn and sf.closeBtn and sf.footLine, "summary window with styled buttons")
    sf.closeBtn:Click()
    W.player.rested, W.player.xp, W.player.xpMax = nil, 0, 1000
end)

-- 0.7.8: the farm session is a pseudo-quest on the panel: the first stop of the route while it runs,
-- next arrow to the quests, back arrow to the farm session, a quest click leaves the farm view.

test("farm session: pseudo-quest on the route and the arrows", function()
    local F = NS.Farm
    W.Advance(1)
    NS.SelectQuest(100, "Kobold Camp Cleanup", false, true)
    SlashCmdList.QUESTFOCUS("farm start")
    check(F.Viewing(), "start shows the farm session")
    eq(NS.state.questId, 100, "the focused quest stays (macro keeps working)")
    check(NS.panel.farmBtn.glow and NS.panel.farmBtn.glow:IsShown(), "clock button glows while running")
    check(NS.panel.farmBtn.stop and NS.panel.farmBtn.stop:IsShown(), "stop mark on the clock button")
    -- farm view: the route lists the focused quest too, no farm row
    NS.PrepareTurnInRoute()
    local route = NS.TurnInRouteList()
    check(#route > 0 and not route[1].farm, "farm view: no farm row on the route")
    local has100 = false
    for _, s in ipairs(route) do if s.qid == 100 then has100 = true end end
    check(has100, "farm view: the focused quest is on the route")
    check(NS.panel.prevBtn:IsShown() and NS.panel.nextBtn:IsShown(), "arrows shown in farm view")
    -- next arrow: back to the focused quest
    NS.NextQuest()
    check(not F.Viewing(), "next arrow leaves the farm view")
    check(F.IsRunning(), "the session keeps running")
    eq(NS.state.questId, 100, "next arrow shows the focused quest")
    -- quest view: the farm session is the first route stop
    NS.PrepareTurnInRoute()
    route = NS.TurnInRouteList()
    check(route[1] and route[1].farm, "quest view: farm session first on the route")
    for i = 2, #route do check(not route[i].farm and route[i].qid ~= 100, "route " .. i .. " is another quest") end
    for _, s in ipairs(NS.QuestNavRoute()) do check(not s.farm, "the next arrow's route has no farm stop") end
    check(contains(F.RouteText(1), "Farm session"), "farm route row text")
    -- back arrow: to the farm session
    check(NS.HasQuestHistory(), "back arrow enabled")
    NS.PrevQuest()
    check(F.Viewing(), "back arrow brings the farm session back")
    eq(NS.state.questId, 100, "quest focus unchanged")
    -- next twice: the quest, then the next route stop; back twice: the quest, the farm session
    NS.NextQuest()
    NS.NextQuest()
    local second = NS.state.questId
    check(second and second ~= 100, "second next goes to another quest")
    NS.PrevQuest()
    eq(NS.state.questId, 100, "back: the quest before")
    NS.PrevQuest()
    check(F.Viewing(), "back again: the farm session")
    -- a quest click leaves the farm view; an automatic selection does not
    NS.SelectQuest(101, "Wolves Across the Border", false, true)
    check(not F.Viewing(), "clicking a quest leaves the farm view")
    F.SetView(true)
    check(F.Viewing(), "the farm route row (F.SetView) brings it back")
    W.Advance(1)
    NS.SelectQuest(102, "Investigate Echo Ridge", false, false)
    check(F.Viewing(), "an automatic selection does not leave the farm view")
    -- stop: the back arrow no longer offers the farm session
    SlashCmdList.QUESTFOCUS("farm stop")
    local sf = F.SummaryFrame()
    if sf then sf:Hide() end
    check(not NS.panel.farmBtn.glow:IsShown(), "no glow after stop")
    if NS.HasQuestHistory() then NS.PrevQuest() end
    check(not F.Viewing(), "no farm view after stop")end)

test("style helpers (NS.Style, DESIGN.md)", function()
    local S = NS.Style
    if not check(S, "NS.Style exists") then return end
    eq(S.GOLD[1] .. "," .. S.GOLD[2] .. "," .. S.GOLD[3], "0.95,0.78,0.4", "gold")
    local f = S.Box("AdventurersKitStyleTestBox", 250, 60, "TEST")
    check(f.accent and f.header and f.close, "box has accent, header, close")
    S.Backdrop(f, "window")
    local b = S.FlatButton(f, "x", 90, 18)
    check(b.text and b.bg, "flat button")
    local seg = S.Segmented(f, { { "a", "A" }, { "b", "B" } })
    seg:Select("b")
    eq(seg.value, "b", "segmented select")
    check(S.Divider(f) and S.ClearButton(f) and S.ArrowButton(f, "next") and S.RowHighlight(b)
        and S.ResizeGrip(f) and S.Section(f, "S") and S.IconButton(f, "Interface\\Icons\\INV_Misc_Gear_01", "t", "d"),
        "other helpers")
    S.Draggable(f, "styleTestPos")
    check(not S.RestorePos(f, "styleTestPos"), "no saved position yet")
end)

test("events and timers smoke", function()
    local events = {
        { "QUEST_ACCEPTED", 5, 104 }, { "QUEST_LOG_UPDATE" }, { "UNIT_QUEST_LOG_CHANGED", "player" },
        { "BAG_UPDATE", 0 }, { "BAG_UPDATE_DELAYED" }, { "UNIT_AURA", "player" }, { "PLAYER_TARGET_CHANGED" },
        { "PLAYER_REGEN_DISABLED" }, { "PLAYER_REGEN_ENABLED" }, { "ZONE_CHANGED_NEW_AREA" }, { "ZONE_CHANGED" },
        { "PLAYER_UPDATE_RESTING" }, { "GROUP_ROSTER_UPDATE" }, { "MERCHANT_SHOW" }, { "MERCHANT_CLOSED" },
        { "PLAYER_LEVEL_UP", 21 }, { "CVAR_UPDATE", "nameplateShowEnemies", "1" }, { "UPDATE_MOUSEOVER_UNIT" },
        { "GOSSIP_SHOW" }, { "GOSSIP_CLOSED" }, { "TAXIMAP_OPENED" }, { "PLAYER_CONTROL_LOST" }, { "PLAYER_CONTROL_GAINED" },
        { "NAME_PLATE_UNIT_ADDED", "nameplate1" }, { "NAME_PLATE_UNIT_REMOVED", "nameplate1" },
        { "PLAYER_EQUIPMENT_CHANGED", 16 }, { "UNIT_INVENTORY_CHANGED", "player" }, { "GET_ITEM_INFO_RECEIVED", 6948, true },
        { "SPELLS_CHANGED" }, { "MINIMAP_UPDATE_TRACKING" }, { "PLAYER_DEAD" }, { "PLAYER_ALIVE" }, { "PLAYER_UNGHOST" },
        { "UPDATE_BINDINGS" }, { "QUEST_DETAIL" }, { "QUEST_COMPLETE" }, { "QUEST_FINISHED" }, { "UI_INFO_MESSAGE", 0, "x" },
        { "CHAT_MSG_SYSTEM", "You are now in a group." }, { "PLAYER_XP_UPDATE", "player" }, { "HEARTHSTONE_BOUND" },
    }
    for _, e in ipairs(events) do W.Fire(unpack(e)) end
    W.Advance(30, 1)
end)

test("slash commands", function()
    for _, cmd in ipairs({ "help", "", "", "debug", "notes", "options", "city", "dungeon", "dungeon", "zone", "zone",
        "next", "all", "mark", "unmark", "arrow", "arrow", "chat", "chat", "clear", "selftest" }) do
        W.safecall("/ak " .. cmd, SlashCmdList.QUESTFOCUS, cmd)
    end
    local sawSummary = false
    for _, l in ipairs(W.chat) do if contains(l, "Self test:") then sawSummary = true end end
    check(sawSummary, "/ak selftest printed a summary")
    W.Advance(5)
end)

test("in-game self test logic (fake world)", function()
    local pass, total, fails = NS.SelfTest()
    check(total >= 7, "self test has its checks")
    for _, f in ipairs(fails) do
        -- the fake world only knows a few uiMaps, so unknown entrance maps are expected here
        if f.name ~= "Dungeon entrances" then
            check(false, "self test failed: " .. f.name .. ": " .. tostring(f.details[1]))
        end
    end
end)

test("tooltips (OnEnter / OnLeave on every visible frame)", function()
    for _, f in ipairs(W.frames) do
        if f.__scripts.OnEnter and f:IsVisible() then W.FireScript(f, "OnEnter") end
        if f.__scripts.OnLeave then W.FireScript(f, "OnLeave") end
    end
end)

test("locale: every L[\"...\"] key has a value", function()
    local seen = {}
    local function specs(s)
        local t = {}
        for x in s:gsub("%%%%", ""):gmatch("%%[%-+ #0]*%d*%.?%d*([sdifxXcgq])") do t[#t + 1] = x end
        return table.concat(t)
    end
    for _, path in ipairs(sourceFiles) do
        local f = io.open(path, "rb")
        local src = f:read("*a")
        f:close()
        local pos = 1
        while true do
            local s, e = src:find('L%["', pos)
            if not s then break end
            local i = e + 1
            while i <= #src do
                local c = src:sub(i, i)
                if c == "\\" then i = i + 2
                elseif c == '"' then break
                else i = i + 1 end
            end
            local lit = src:sub(e, i)
            pos = i + 1
            local fn = loadstring("return " .. lit)
            local ok, key = pcall(fn or function() end)
            if ok and type(key) == "string" and not seen[key] then
                seen[key] = true
                local v = NS.L[key]
                check(type(v) == "string" and v ~= "", "no value for L[" .. lit .. "]")
                if type(v) == "string" then
                    check(specs(v) == specs(key), "format specifiers differ for L[" .. lit .. "]")
                end
            end
        end
    end
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    check(n > 100, "found the locale keys (" .. n .. ")")
end)

-- 0.7.10: auction house "Quest items" tab (Planner\AuctionQuest.lua): what is still needed,
-- the cheapest set of auctions, and the one-auction-per-click buy flow that never goes over the
-- confirmed price.
test("AH quest items: price math", function()
    local A = NS.AHQ
    eq(A.FormatCoins(10203), "1g 2s 3c", "coins")
    eq(A.FormatCoins(500), "5s", "silver only")
    eq(A.FormatCoins(0), "0c", "zero")
    local ls = {
        { count = 5, buyout = 500 },                    -- 100 / unit
        { count = 2, buyout = 150 },                    -- 75
        { count = 2, buyout = 170 },                    -- 85
        { count = 1, buyout = 50, owner = "Tester" },   -- own auction: never
        { count = 3, buyout = 0 },                      -- bid only: never
    }
    local p = A.Plan(ls, 4, "Tester")
    eq(p.cost, 320, "4 needed: 2 + 2 is cheaper than the stack of 5")
    eq(p.covered, 4, "covered")
    eq(#p.picks, 2, "two auctions")
    eq(p.lowestUnit, 75, "lowest unit price")
    eq(p.maxUnit, 85, "highest unit price in the plan")
    p = A.Plan(ls, 1, "Tester")
    eq(p.cost, 150, "1 needed: the cheapest whole auction")
    p = A.Plan(ls, 5, "Tester")
    eq(p.cost, 500, "5 needed: the stack of 5 (500) beats 2+2+5")
    p = A.Plan(ls, 20, "Tester")
    check(p.partial, "not enough on the AH: partial")
    eq(p.covered, 9, "partial: everything there is")
    eq(p.available, 9, "available")
    eq(A.Plan(ls, 0, "Tester"), nil, "nothing needed")
    eq(A.Plan({ { count = 1, buyout = 0 } }, 2), nil, "no buyout auctions")
    -- buying: the cheapest that still fits the confirmed price
    local st = { maxUnit = 85, spent = 0, cap = 320 }
    eq(A.PickNext(ls, st, "Tester").buyout, 150, "next: cheapest")
    st.spent = 200
    eq(A.PickNext(ls, st, "Tester"), nil, "over the confirmed total: nothing")
    eq(A.PickNext({ { count = 2, buyout = 400 } }, { maxUnit = 85, spent = 0, cap = 1000 }), nil,
        "dearer per unit than confirmed: nothing")
end)

test("AH quest items: needed items, scan, buy one auction per click", function()
    local A = NS.AHQ
    Q.Quest({ id = 104, name = "Cloth for the Poor", finisher = 900, starter = 900, objectives = {
        { Type = "item", Id = 2589, Description = "Linen Cloth", Needed = 6, Collected = 1 },
        { Type = "item", Id = 2592, Description = "Wool Cloth", Needed = 1, Collected = 0 },
        { Type = "item", Id = 5000, Description = "Quest Thing", Needed = 1, Collected = 0 },
        { Type = "item", Id = 5001, Description = "BoP Thing", Needed = 1, Collected = 0 },
    } })
    Q.SetLog({ { qid = 100 }, { qid = 104 } })
    W.itemInfo = { [2589] = { "Linen Cloth", 13 }, [2592] = { "Wool Cloth", 33 },
        [5000] = { "Quest Thing", 0, 4 }, [5001] = { "BoP Thing", 0, 1 } }
    W.items = { [2589] = 2 }
    local items = A.NeededItems()
    eq(#items, 2, "quest-only and BoP items left out")
    eq(items[1].name, "Linen Cloth", "first item")
    eq(items[1].need, 4, "needed 6, have max(collected 1, bags 2) = 2")
    eq(items[1].quest, "Cloth for the Poor", "quest name")
    eq(items[2].need, 1, "wool")

    W.ahAll = {
        { name = "Linen Cloth", count = 5, buyout = 500, owner = "Bob", itemId = 2589 },
        { name = "Linen Cloth", count = 2, buyout = 150, owner = "Bob", itemId = 2589 },
        { name = "Linen Cloth", count = 2, buyout = 170, owner = "Ann", itemId = 2589 },
        { name = "Wool Cloth", count = 20, buyout = 2000, owner = "Bob", itemId = 2592 },
        { name = "Wool Cloth", count = 1, buyout = 300, owner = "Ann", itemId = 2592 },
    }
    W.ahQueries, W.ahBids, W.money = {}, {}, 100000
    W.Fire("AUCTION_HOUSE_SHOW")
    check(A.tab and A.tab:IsShown(), "tab shown at the AH")
    A.tab:Click()
    check(A.frame:IsShown(), "panel opens from the tab")
    for _ = 1, 4 do
        W.Advance(0.5)
        W.Fire("AUCTION_ITEM_LIST_UPDATE")
    end
    eq(#W.ahQueries, 2, "one query per item")
    eq(W.ahQueries[1].text, "Linen Cloth", "query text")
    check(W.ahQueries[1].exact, "exact match")
    eq(A.current[1].plan.cost, 320, "linen price")
    eq(A.current[2].plan.cost, 300, "wool price")
    check(contains(A.frame.total:GetText(), "6s 20c"), "total in the footer: " .. tostring(A.frame.total:GetText()))

    -- Buy linen: confirm, then one auction per click
    A.rows[1].buy:Click()
    local pop = rawget(_G, "AdventurersKitAHBuy")
    check(pop and pop:IsShown(), "confirm popup")
    check(contains(pop.text:GetText(), "Buy 4 x Linen Cloth for 3s 20c?"), "confirm text: " .. tostring(pop.text:GetText()))
    check(contains(pop.text:GetText(), "(80c each)"), "unit price under the question")
    check(pop.rows[1] and not pop.rows[1]:IsShown(), "one item: no list")
    check(not pop.ok:IsEnabled(), "button waits for a fresh list")
    pop.ok:Click()
    eq(#W.ahBids, 0, "no purchase before the fresh query")
    W.Advance(0.5)
    W.Fire("AUCTION_ITEM_LIST_UPDATE")
    check(pop.ok:IsEnabled(), "ready after the fresh query")
    pop.ok:Click()
    eq(#W.ahBids, 1, "one click = one auction")
    eq(W.ahBids[1].amount, 150, "cheapest first, at its buyout")
    pop.ok:Click()
    eq(#W.ahBids, 1, "second click waits for the next query")
    -- meanwhile someone buys the 170 one: only the 500 stack is left, dearer than confirmed
    for k, a in ipairs(W.ahAll) do if a.buyout == 170 then table.remove(W.ahAll, k) break end end
    W.Advance(0.5)
    W.Fire("AUCTION_ITEM_LIST_UPDATE")
    pop.ok:Click()
    eq(#W.ahBids, 1, "never above the confirmed price")
    check(A.buy == nil or A.buy.done, "buying stops")
    eq(A.InMail(2589), 2, "bought count waits for the mailbox")
    eq(A.NeededItems()[1].need, 2, "still needed counts the mailbox")
    pop.ok:Click() -- Close
    check(not pop:IsShown(), "popup closes")

    -- Buy all: wool (1 auction) + the rest of the linen (now 2 x 5-stack? no: only the 500 one)
    A.Scan(A.NeededItems(), true)
    for _ = 1, 4 do
        W.Advance(0.5)
        W.Fire("AUCTION_ITEM_LIST_UPDATE")
    end
    A.Refresh()
    eq(A.current[1].plan.cost, 500, "linen: only the stack of 5 left")
    A.frame.buyAll:Click()
    eq(pop.text:GetText(), "Buy all: 2 items (2 auctions) for 8s?", "buy all text")
    check(pop.rows[1]:IsShown() and pop.rows[2]:IsShown() and not pop.rows[3]:IsShown(), "buy all: the items are listed")
    check(contains(pop.rows[1].name:GetText(), "Linen Cloth"), "list row: item name")
    local guard = 0
    while A.buy and not A.buy.done and guard < 20 do
        guard = guard + 1
        W.Advance(0.5)
        W.Fire("AUCTION_ITEM_LIST_UPDATE")
        pop.ok:Click()
    end
    eq(#W.ahBids, 3, "buy all: two more clicks")
    eq(W.ahBids[3].amount, 300, "wool at 300")

    -- AH closes: tab and panel go; Options off keeps the tab away
    W.Fire("AUCTION_HOUSE_CLOSED")
    check(not A.tab:IsShown(), "tab hidden after closing the AH")
    check(not A.frame:IsShown(), "panel hidden after closing the AH")
    A.SetEnabled(false)
    W.Fire("AUCTION_HOUSE_SHOW")
    check(not A.tab:IsShown(), "option off: no tab")
    W.Fire("AUCTION_HOUSE_CLOSED")
    A.SetEnabled(true)
    QuestFocusDB.ahqOpen = nil
    NS.AHQ.MailDB().buys = {} -- (test) forget the bought items on their way
    Q.SetLog({ { qid = 100 }, { qid = 101 }, { qid = 102 }, { qid = 103, complete = true } })
    W.items, W.itemInfo, W.ahAll = {}, nil, {}
end)

-- 0.7.11: WoW: Forever has the modern auction house (C_AuctionHouse); AUCTION_ITEM_LIST_UPDATE
-- does not exist there (registering it was a Lua error at load).
test("AH quest items: modern auction house (commodities and item auctions)", function()
    local A = NS.AHQ
    eq(A.PlanCommodity({ { unit = 40, count = 3 }, { unit = 60, count = 10 } }, 4).cost, 180, "commodity: 3 x 40 + 1 x 60")
    eq(A.PlanCommodity({ { unit = 40, count = 3 } }, 5).partial, true, "commodity: not enough")
    W.InstallModernAH()
    check(A.Modern() ~= nil, "modern AH detected")
    Q.SetLog({ { qid = 100 }, { qid = 104 } })
    W.itemInfo = { [2589] = { "Linen Cloth", 13 }, [2592] = { "Wool Cloth", 33 },
        [5000] = { "Quest Thing", 0, 4 }, [5001] = { "BoP Thing", 0, 1 } }
    W.items = { [2589] = 2 }
    W.ahAll = {
        { itemId = 2589, unit = 40, count = 3 },
        { itemId = 2589, unit = 60, count = 10 },
        { itemId = 2589, unit = 30, count = 2, own = true },          -- mine: not bought
        { itemId = 2592, buyout = 300, count = 1, auctionID = 11 },
        { itemId = 2592, buyout = 2000, count = 20, auctionID = 12 },
        { itemId = 2592, buyout = 100, count = 1, auctionID = 13, own = true },
    }
    W.ahQueries, W.ahBids = {}, {}
    local function respond()
        W.Advance(0.5)
        local q = W.ahQueries[#W.ahQueries]
        if not q then return end
        if q.itemID == 2589 then W.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
        else W.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = q.itemID }) end
    end
    W.Fire("AUCTION_HOUSE_SHOW")
    A.Toggle(true)
    A.Scan(A.NeededItems(), true)
    for _ = 1, 4 do respond() end
    A.Refresh()
    eq(A.current[1].plan and A.current[1].plan.cost, 180, "linen (commodity): cheapest 4 units, own ones left out")
    eq(A.current[2].plan and A.current[2].plan.cost, 300, "wool (item): the single one, own auction left out")

    -- commodity: the Buy click asks the price at once, the next click confirms
    local nq = #W.ahQueries
    A.rows[1].buy:Click()
    local pop = rawget(_G, "AdventurersKitAHBuy")
    eq(#W.ahStarts, 1, "price asked in the Buy click")
    eq(W.ahStarts[1].quantity, 4, "for the missing count")
    W.Fire("COMMODITY_PRICE_UPDATED", 45, 180)
    check(pop.ok:IsEnabled(), "ready at the confirmed price")
    pop.ok:Click()
    eq(#W.ahBids, 1, "confirmed")
    check(W.ahBids[1].commodity and W.ahBids[1].quantity == 4, "commodity purchase of 4")
    check(A.buy and A.buy.done, "done")
    pop.ok:Click()
    eq(#W.ahQueries, nq, "no search needed for a commodity")

    -- Buy all: the commodity price went up -> cancelled and skipped; wool bought by auction ID
    NS.AHQ.MailDB().buys = {} -- (test) forget the bought items on their way
    A.Refresh()
    A.frame.buyAll:Click()
    eq(#W.ahStarts, 2, "first item: price asked")
    W.Fire("COMMODITY_PRICE_UPDATED", 50, 200)
    eq(W.ahCancelled, 1, "dearer than confirmed: cancelled")
    eq(#W.ahBids, 1, "nothing bought for it")
    respond()
    check(pop.ok:IsEnabled(), "wool ready")
    pop.ok:Click()
    eq(#W.ahBids, 2, "wool bought")
    eq(W.ahBids[2].auctionID, 11, "the cheapest auction that is not mine")
    eq(W.ahBids[2].amount, 300, "at its buyout")
    check(A.buy and A.buy.done, "buy all done")
    pop.ok:Click()

    W.Fire("AUCTION_HOUSE_CLOSED")
    W.RemoveModernAH()
    QuestFocusDB.ahqOpen = nil
    NS.AHQ.MailDB().buys = {} -- (test) forget the bought items on their way
    Q.SetLog({ { qid = 100 }, { qid = 101 }, { qid = 102 }, { qid = 103, complete = true } })
    W.items, W.itemInfo, W.ahAll = {}, nil, {}
end)

-- 0.7.14 / 0.7.15: All The Things puts its AH button on the shared side bar
-- (AuctionHouseFrameTabSideBar, -52 below the top). Our tab sits right above it by default, drags
-- only up and down that edge (clamped to the AH height, saved as ahqTabY), right click resets.
-- Inside the AH the list uses the AH's own look (ButtonFrameTemplate, UIPanelButtonTemplate).
test("AH quest items: tab above All The Things' button, vertical drag, AH look", function()
    local A = NS.AHQ
    eq(A.AddonIcon(), "Interface\\Icons\\INV_Misc_Map_01", "addon icon from the .toc IconTexture")
    local host = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
    host:SetSize(800, 600)
    local sb = CreateFrame("Frame", "AuctionHouseFrameTabSideBar", host)
    local att = CreateFrame("Frame", nil, sb)
    sb.Tabs = { att } -- ATT's button
    QuestFocusDB.ahqTabY, QuestFocusDB.ahqPos = nil, nil
    W.Fire("AUCTION_HOUSE_SHOW")
    local p = A.tab.__pts[1]
    check(p and p[1] == "BOTTOMLEFT" and p[2] == att and p[3] == "TOPLEFT" and p[5] > 0, "default: right above ATT's button")
    -- vertical drag: only the y offset changes, clamped to the AH height
    W.cursorX, W.cursorY = 0, 0
    A.tab.__scripts.OnDragStart(A.tab)
    W.cursorX, W.cursorY = 300, -100 -- sideways movement is ignored
    A.tab.__scripts.OnUpdate(A.tab, 0.1)
    p = A.tab.__pts[1]
    check(p[2] == sb and p[1] == "TOPLEFT" and p[3] == "TOPRIGHT", "stays on the edge column")
    eq(p[4], -2, "x does not follow the mouse")
    eq(p[5], -100, "y follows the mouse")
    W.cursorY = -5000
    A.tab.__scripts.OnUpdate(A.tab, 0.1)
    eq(A.tab.__pts[1][5], -(600 - 34 - 30), "clamped to the AH height, 5% margin at the bottom")
    A.tab.__scripts.OnDragStop(A.tab)
    eq(QuestFocusDB.ahqTabY, -536, "vertical offset saved")
    A.tab:Click("RightButton")
    eq(QuestFocusDB.ahqTabY, nil, "right click resets the place")
    check(A.tab.__pts[1][2] == att, "back above ATT's button")
    rawset(_G, "AuctionHouseFrameTabSideBar", nil)
    A.PlaceTab()
    p = A.tab.__pts[1]
    check(p[2] == host and p[5] == -52, "no ATT: near the top of the AH's right edge")
    A.Toggle(true)
    local fp = A.frame.__pts
    check(fp[#fp][2] == A.tab, "panel opens beside the tab")
    check(A.frame.blizz and A.frame.__template == "ButtonFrameTemplate", "panel uses the AH's frame template")
    check(A.frame.buyAll.blizz and A.frame.rescan.blizz, "Buy all / Rescan prices: the AH's red buttons")
    check(A.frame.buyAll.__template == "UIPanelButtonTemplate", "UIPanelButtonTemplate")
    W.cursorX, W.cursorY = nil, nil
    A.Toggle(false)
    W.Fire("AUCTION_HOUSE_CLOSED")
    QuestFocusDB.ahqOpen = nil
    rawset(_G, "AuctionHouseFrame", nil)
    rawset(_G, "AuctionHouseFrameTabSideBar", nil)
end)

-- 0.7.16: bought AH items go to the mailbox. They count as yours (saved per character, survive
-- /reload), the mailbox scan is the truth, 30-day expiry. After a successful buy the list closes.
test("AH quest items: items in the mail count, list closes after buying", function()
    local A = NS.AHQ
    -- top margin of the tab drag (5%)
    local host = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
    host:SetSize(800, 600)
    eq(A.ClampTabY(0), -30, "5% margin at the top")
    rawset(_G, "AuctionHouseFrame", nil)

    local m = A.MailDB()
    m.snap, m.snapT, m.buys = {}, 0, {}
    Q.SetLog({ { qid = 104 } })
    W.itemInfo = { [2589] = { "Linen Cloth", 13 }, [2592] = { "Wool Cloth", 33 },
        [5000] = { "Quest Thing", 0, 4 }, [5001] = { "BoP Thing", 0, 1 } }
    W.items = { [2589] = 2 }
    eq(A.NeededItems()[1].need, 4, "no mail: 6 - max(1, 2)")
    A.AddPending(2589, 3)
    local e = A.NeededItems()[1]
    eq(e.need, 1, "3 bought, on their way")
    eq(e.inMail, 3, "row shows 'in mail'")
    check(NS.CharDB().ahMail and #NS.CharDB().ahMail.buys == 1, "saved per character (survives /reload)")
    A.AddPending(2589, 1)
    eq(#A.NeededItems(), 1, "linen fully covered by the mail: row gone (wool left)")
    -- mailbox open: the inbox is the truth (2 there, 2 already taken out)
    W.inbox = { { { 2589, 2 } }, { { 9999, 5 } } }
    W.Fire("MAIL_SHOW")
    eq(A.InMail(2589), 2, "mailbox scan replaces the guesses")
    eq(#A.MailDB().buys, 0, "our purchase records are folded into the scan")
    W.inbox = {}
    W.Fire("MAIL_INBOX_UPDATE")
    W.Fire("MAIL_CLOSED")
    eq(A.InMail(2589), 0, "all taken out")
    W.Fire("MAIL_INBOX_UPDATE") -- mailbox closed: no scan
    -- 30 days
    A.AddPending(2589, 2)
    A.MailDB().buys[1].t = time() - 31 * 24 * 3600
    eq(A.InMail(2589), 0, "expired after 30 days")

    -- a successful buy closes the list; the tab reopens it
    W.InstallModernAH()
    W.ahAll = { { itemId = 2592, buyout = 300, count = 1, auctionID = 21 } }
    W.ahQueries, W.ahBids = {}, {}
    W.Fire("AUCTION_HOUSE_SHOW")
    A.Toggle(true)
    A.Scan(A.NeededItems(), true)
    for _ = 1, 3 do
        W.Advance(0.5)
        local q = W.ahQueries[#W.ahQueries]
        if q and q.itemID == 2589 then W.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
        elseif q then W.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = q.itemID }) end
    end
    A.Refresh()
    local wool
    for i, x in ipairs(A.current) do if x.entry.id == 2592 then wool = i end end
    check(wool and A.current[wool].plan, "wool priced")
    A.rows[wool].buy:Click()
    W.Advance(0.5)
    W.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 2592 })
    local pop = rawget(_G, "AdventurersKitAHBuy")
    pop.ok:Click()
    eq(#W.ahBids, 1, "bought")
    check(A.frame:IsShown(), "list still open right after the click (a late error could undo it)")
    W.Advance(2)
    check(not A.frame:IsShown(), "list closed after the purchase")
    W.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 21) -- the game confirms our purchase
    eq(A.InMail(2592), 1, "wool on its way (our own purchase counted once)")
    pop.ok:Click()
    A.tab:Click()
    check(A.frame:IsShown(), "the tab reopens it")
    A.Toggle(false)
    W.Fire("AUCTION_HOUSE_CLOSED")
    W.RemoveModernAH()
    QuestFocusDB.ahqOpen = nil
    A.MailDB().buys = {}
    Q.SetLog({ { qid = 100 }, { qid = 101 }, { qid = 102 }, { qid = 103, complete = true } })
    W.items, W.itemInfo, W.ahAll = {}, nil, {}
end)

-- 0.7.17: the list is always closed when the AH opens; only the tab opens it
-- 0.7.18: purchases made in the AH's own Buy tab or Auctionator also count as "in the mail",
-- without opening a mailbox (hooks on C_AuctionHouse.PlaceBid / ConfirmCommoditiesPurchase)
test("AH quest items: purchases from any AH UI count without a mailbox", function()
    local A = NS.AHQ
    A.MailDB().buys, A.MailDB().snap = {}, {}
    W.InstallModernAH()
    W.ahAll = { { itemId = 2592, buyout = 300, count = 2, auctionID = 41 } }
    W.Fire("AUCTION_HOUSE_SHOW")
    local C = rawget(_G, "C_AuctionHouse")
    C.PlaceBid(41, 300) -- the AH's own Buy tab
    eq(A.InMail(2592), 0, "not counted before the game confirms it")
    W.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 41)
    eq(A.InMail(2592), 2, "item auction bought elsewhere: in the mail")
    C.ConfirmCommoditiesPurchase(2589, 3)
    W.Fire("COMMODITY_PURCHASE_SUCCEEDED")
    eq(A.InMail(2589), 3, "commodity bought elsewhere: in the mail")
    C.ConfirmCommoditiesPurchase(2589, 5)
    W.Fire("COMMODITY_PURCHASE_FAILED")
    W.Fire("COMMODITY_PURCHASE_SUCCEEDED") -- a stray success later must not count the failed one
    eq(A.InMail(2589), 3, "failed purchase not counted")
    W.Fire("AUCTION_HOUSE_CLOSED")
    W.RemoveModernAH()
    A.MailDB().buys = {}
end)

test("AH quest items: list closed when the AH opens", function()
    local A = NS.AHQ
    W.Fire("AUCTION_HOUSE_SHOW")
    A.tab:Click()
    check(A.frame:IsShown(), "the tab opens the list")
    W.Fire("AUCTION_HOUSE_CLOSED")
    W.Fire("AUCTION_HOUSE_SHOW")
    check(A.tab:IsShown(), "tab shown")
    check(not A.frame:IsShown(), "list closed on the next AH visit")
    W.Fire("AUCTION_HOUSE_CLOSED")
end)

test("no errors logged by the addon", function()
    for _, e in ipairs(NS.errors or {}) do check(false, "NS.errors: " .. tostring(e.msg)) end
end)

test("globals read but not stubbed (typo / scope check)", function()
    -- functions the addon defines as `local function X` somewhere: reading X as a global means
    -- a file uses a function that is local to another file (or defined later in the same file)
    local declared = {}
    for _, path in ipairs(sourceFiles) do
        local f = io.open(path, "rb")
        local src = f:read("*a")
        f:close()
        for n in src:gmatch("local%s+function%s+([%a_][%w_]*)") do declared[n] = true end
    end
    for name in pairs(W.autoGlobals) do
        check(not declared[name], ("'%s' is read as a global but is a local function somewhere (scope bug?)"):format(name))
    end
end)

-- 0.7.13: shared item price (Core\Prices.lua): Auctionator present / absent / erroring, TSM and
-- own AH scan fallbacks, per-item cache, source text.
test("item price: Auctionator, fallbacks, cache", function()
    local savedInfo, savedA, savedT = W.itemInfo, rawget(_G, "Auctionator"), rawget(_G, "TSM_API")
    W.itemInfo = { [2589] = { "Linen Cloth", 13 }, [4444] = { "Rune Thing", 0 } }
    local AQ = NS.AHQ and NS.AHQ.prices or {}
    local savedScan = AQ[2589]
    AQ[2589] = nil -- an earlier AH tab test left a scan for it
    rawset(_G, "Auctionator", nil); rawset(_G, "TSM_API", nil)
    NS.ItemPriceFlush()

    -- absent: vendor only
    local v, ah, best, src, age = NS.ItemPrice(2589)
    eq(v, 13, "absent: vendor") eq(ah, nil, "absent: no AH price") eq(best, 13, "absent: best = vendor")
    eq(src, nil, "absent: no source") eq(NS.PriceAddon(), nil, "absent: no price addon")
    eq(NS.PriceSourceText("vendor"), "vendor", "vendor source text")

    -- present: price by ID + age, callerID is our registered string
    local callers, price, registered = {}, { [2589] = 50 }, nil
    rawset(_G, "Auctionator", { API = { v1 = {
        GetAuctionPriceByItemID = function(caller, id) callers[#callers + 1] = caller return price[id] end,
        GetAuctionAge = function(caller, id) return price[id] and 2 or nil end,
        RegisterForDBUpdate = function(caller, fn) registered = fn end,
    } } })
    v, ah, best, src, age = NS.ItemPrice(2589)
    eq(ah, 50, "present: AH price") eq(best, 50, "present: best = AH") eq(src, "Auctionator", "present: source")
    eq(age, 2, "present: age in days") eq(callers[1], "AdventurersKit", "callerID")
    eq(NS.PriceSourceText(src, age), "AH (Auctionator, 2d)", "source text with age")
    eq(NS.PriceSourceText("Auctionator", 0), "AH (Auctionator, today)", "source text today")
    eq(NS.PriceAddon(), "Auctionator", "price addon")
    eq(select(3, NS.ItemPrice("|cffffffff|Hitem:2589::::::::36:::::::|h[Linen Cloth]|h|r")), 50, "item link accepted")
    -- cache: a new scan value shows after the TTL or the Auctionator DB update callback
    price[2589] = 70
    eq(select(2, NS.ItemPrice(2589)), 50, "cached")
    check(type(registered) == "function", "registered for Auctionator DB updates")
    if registered then registered() end
    eq(select(2, NS.ItemPrice(2589)), 70, "DB update clears the cache")
    price[2589] = 80
    W.time = W.time + 31
    eq(select(2, NS.ItemPrice(2589)), 80, "cache expires")
    -- vendor price 0 (not vendorable) still gets the AH price
    price[4444] = 900
    v, ah, best = NS.ItemPrice(4444)
    eq(v, 0, "unvendorable: vendor 0") eq(best, 900, "unvendorable: AH price is the best")

    -- erroring: no Lua error, falls back to TSM
    rawset(_G, "Auctionator", { API = { v1 = {
        GetAuctionPriceByItemID = function() error("boom") end,
        GetAuctionPriceByItemLink = function() error("boom") end,
        GetAuctionAge = function() error("boom") end,
    } } })
    local ok
    ok, v, ah, best, src = pcall(NS.ItemPrice, 2589)
    check(ok, "erroring Auctionator: no error") eq(ah, nil, "erroring Auctionator: no AH price") eq(best, 13, "erroring: vendor")
    rawset(_G, "TSM_API", { GetCustomPriceValue = function(p, s) return s == "i:2589" and 60 or nil end })
    v, ah, best, src = NS.ItemPrice(2589)
    eq(ah, 60, "TSM fallback") eq(src, "TSM", "TSM source")
    rawset(_G, "TSM_API", { GetCustomPriceValue = function() error("tsm boom") end })
    ok, v, ah = pcall(NS.ItemPrice, 2589)
    check(ok and ah == nil, "erroring TSM: no error, no price")

    -- own AH tab scan as the last fallback (cheapest unit price)
    rawset(_G, "Auctionator", nil); rawset(_G, "TSM_API", nil)
    local A = NS.AHQ
    if A and A.prices then
        A.prices[2589] = { listings = { { count = 4, buyout = 200 }, { count = 1, buyout = 45 } }, time = W.time }
        NS.ItemPriceFlush()
        v, ah, best, src, age = NS.ItemPrice(2589)
        eq(ah, 45, "own scan: cheapest unit") eq(src, "AH scan", "own scan source") eq(NS.PriceAgeText(age), "today", "own scan age")
        A.prices[2589] = nil
    end
    AQ[2589] = savedScan

    W.itemInfo = savedInfo
    rawset(_G, "Auctionator", savedA); rawset(_G, "TSM_API", savedT)
    NS.ItemPriceFlush()
end)

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------
local failed = 0
for _, r in ipairs(results) do
    if #r.fails == 0 then
        out("PASS  " .. r.name)
    else
        failed = failed + 1
        out("FAIL  " .. r.name)
        for i, m in ipairs(r.fails) do
            if i > 12 and not verbose then out(("      ... %d more (-v)"):format(#r.fails - 12)) break end
            out("      " .. m:gsub("\n", "\n      "))
        end
    end
end
local auto = {}
for k, n in pairs(W.autoGlobals) do auto[#auto + 1] = k .. " x" .. n end
table.sort(auto)
if verbose then
    out("\nAuto-stubbed globals (not in wowstub.lua): " .. table.concat(auto, ", "))
    out("\nChat output:")
    for _, l in ipairs(W.chat) do out("  " .. l) end
else
    out(("\n%d globals were auto-stubbed (-v lists them)"):format(#auto))
end
out(("\n%d/%d tests passed"):format(#results - failed, #results))
os.exit(failed == 0 and 0 or 1)
