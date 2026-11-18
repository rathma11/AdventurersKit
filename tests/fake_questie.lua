-- Fake Questie for the offline smoke tests: only the parts Adventurer's Kit reads.
--   QuestieLoader:ImportModule(name) -> QuestieDB, QuestiePlayer, ZoneDB, Townsfolk,
--   AvailableQuests, QuestXP, QuestieTracker, QuestieProfessions
--   Questie.db.char.complete / vendorList
-- Coordinates are Questie style: spawns = { [areaId] = { { x%, y% }, ... } }.
local W = ...

local Q = { npcs = {}, objects = {}, items = {}, quests = {} }

local function id2(a, b) if type(a) == "table" then return b end return a end

local QuestieDB = {
    GetQuest = function(a, b) return Q.quests[id2(a, b)] end,
    GetNPC = function(a, b) return Q.npcs[id2(a, b)] end,
    GetObject = function(a, b) return Q.objects[id2(a, b)] end,
    GetItem = function(a, b) return Q.items[id2(a, b)] end,
    GetItemDroprate = function() return 25 end,
    -- one field of a quest (QuestPointers, the list of every quest ID, is set by a test)
    QueryQuestSingle = function(qid, key) local q = Q.quests[qid]; return q and q[key] end,
}
local QuestiePlayer = { currentQuestlog = {} }
local ZoneDB = {
    GetUiMapIdByAreaId = function(a, b) return W.areaToMap[id2(a, b)] end,
    instanceIdToAreaId = {},
}
local Townsfolk = { townsfolk = {}, classSpecificTownsfolk = {}, professionTrainers = {} }
local AvailableQuests = { __availableQuests = {} }
local QuestXP = { db = {}, GetQuestLogRewardXP = function() return 0 end }
local QuestieTracker = { IsTrackedByQuestie = function() return false end }
local QuestieProfessions = {}

local modules = {
    QuestieDB = QuestieDB, QuestiePlayer = QuestiePlayer, ZoneDB = ZoneDB, Townsfolk = Townsfolk,
    AvailableQuests = AvailableQuests, QuestXP = QuestXP, QuestieTracker = QuestieTracker,
    QuestieProfessions = QuestieProfessions,
}
Q.modules = modules

function Q.Install()
    rawset(_G, "QuestieLoader", { ImportModule = function(_, name) return modules[name] end })
    rawset(_G, "Questie", { db = { char = { complete = {}, vendorList = { Food = {}, Drink = {}, Ammo = {} } } } })
end
function Q.Uninstall()
    rawset(_G, "QuestieLoader", nil)
    rawset(_G, "Questie", nil)
end

function Q.NPC(id, name, area, coords, extra)
    local n = { id = id, name = name, spawns = { [area] = coords }, minLevel = 10, maxLevel = 12,
        friendlyToFaction = "AH" }
    for k, v in pairs(extra or {}) do n[k] = v end
    Q.npcs[id] = n
    return n
end

-- Objective of a "kill N mobs" kind, spawnList filled the way Questie does it
function Q.KillObjective(npcId, needed, collected)
    local n = Q.npcs[npcId]
    return {
        Type = "monster", Id = npcId, Description = n.name .. " slain",
        Needed = needed, Collected = collected or 0, Completed = (collected or 0) >= needed,
        spawnList = { [npcId] = { Id = npcId, Name = n.name, Spawns = n.spawns, TooltipKey = "m_" .. npcId } },
    }
end

function Q.Quest(t)
    -- t = { id, name, level, objectives = {...}, finisher = npcId, starter = npcId, zone = areaId }
    local q = {
        Id = t.id, id = t.id, name = t.name, level = t.level or 10, requiredLevel = t.requiredLevel or 1,
        Objectives = t.objectives or {}, SpecialObjectives = {},
        Finisher = { NPC = t.finisher and { t.finisher } or {}, GameObject = {} },
        Starts = { NPC = t.starter and { t.starter } or {}, GameObject = {}, Item = {} },
        zoneOrSort = t.zone or 12, ObjectiveData = {},
    }
    Q.quests[t.id] = q
    return q
end

-- Put quests into the fake quest log (and Questie's player quest log)
function Q.SetLog(entries)
    W.log = {}
    QuestiePlayer.currentQuestlog = {}
    for _, e in ipairs(entries) do
        W.log[#W.log + 1] = { title = Q.quests[e.qid].name, qid = e.qid, complete = e.complete, level = 10 }
        QuestiePlayer.currentQuestlog[e.qid] = Q.quests[e.qid]
    end
end

---------------------------------------------------------------------------
-- The test world: Elwynn Forest (area 12 -> uiMap 1429, 5000 x 5000 yd; 1% = 50 yd)
---------------------------------------------------------------------------
Q.NPC(1001, "Kobold Vermin", 12, { { 50, 50 }, { 51, 50 }, { 50, 51 } })
Q.NPC(1002, "Prowler", 12, { { 60, 60 }, { 61, 60 } })
Q.NPC(1003, "Kobold Worker", 12, { { 40, 30 }, { 41, 30 } })
Q.NPC(900, "Marshal McBride", 12, { { 48, 42 } })
Q.NPC(950, "Test Armorer", 12, { { 30, 80 } })            -- the only vendor / repairer
Q.NPC(951, "Test Innkeeper", 12, { { 70, 20 } })          -- the only innkeeper
Townsfolk.townsfolk.Repair = { 950 }
Townsfolk.townsfolk.Innkeeper = { 951 }

Q.Quest({ id = 100, name = "Kobold Camp Cleanup", objectives = { Q.KillObjective(1001, 10) }, finisher = 900, starter = 900 })
Q.Quest({ id = 101, name = "Wolves Across the Border", objectives = { Q.KillObjective(1002, 8) }, finisher = 900, starter = 900 })
Q.Quest({ id = 102, name = "Investigate Echo Ridge", objectives = { Q.KillObjective(1003, 10) }, finisher = 900, starter = 900 })
Q.Quest({ id = 103, name = "Report to Goldshire", objectives = { Q.KillObjective(1001, 1, 1) }, finisher = 900, starter = 900 })

return Q
