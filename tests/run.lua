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
    check(type(SlashCmdList.QUESTFOCUS) == "function", "/qf registered")
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
    local m = W.macros.QFocus
    check(m ~= nil, "QFocus macro created")
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
    check(#(W.macros.QFocus.body) <= 255, "saved macro under 255")
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
    eq(W.macros.QFocus.body, "/say combat test", "written after combat")
    eq(NS.state.pendingBody, nil, "pending cleared")
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
    eq(NS.PrepActive(), "The Deadmines", "/qf dungeon deadm")
    W.instance = { name = "The Deadmines", type = "party", instanceID = 36 }
    W.Fire("PLAYER_ENTERING_WORLD", false, false)
    W.Fire("ZONE_CHANGED_NEW_AREA")
    W.Advance(4)
    W.instance = nil
    W.Fire("PLAYER_ENTERING_WORLD", false, false)
    W.Fire("ZONE_CHANGED_NEW_AREA")
    W.Advance(4)
    SlashCmdList.QUESTFOCUS("dungeon off")
    eq(NS.PrepActive(), nil, "/qf dungeon off")
    eq(NS.state.questId, 102, "/qf dungeon off restores the quest")
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
        W.safecall("/qf " .. cmd, SlashCmdList.QUESTFOCUS, cmd)
    end
    local sawSummary = false
    for _, l in ipairs(W.chat) do if contains(l, "Self test:") then sawSummary = true end end
    check(sawSummary, "/qf selftest printed a summary")
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
