local ADDON_NAME, NS = ...
local L = NS.L
NS.C = NS.C or {}
local C = NS.C

---------------------------------------------------------------------------
-- Questie hozzaferes
---------------------------------------------------------------------------
local function Module(name)
    local loader = _G.QuestieLoader
    if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return nil end
    local ok, mod = pcall(loader.ImportModule, loader, name)
    if ok and type(mod) == "table" then return mod end
end

local function QuestieAvailable()
    return Module("QuestieDB") ~= nil
end

local function GetQuestieQuest(questId)
    local QP = Module("QuestiePlayer")
    if QP and type(QP.currentQuestlog) == "table" then
        local q = QP.currentQuestlog[questId]
        if type(q) == "table" then return q end
    end
    local DB = Module("QuestieDB")
    if DB and type(DB.GetQuest) == "function" then
        local ok, q = pcall(DB.GetQuest, questId)
        if ok and type(q) == "table" then return q end
        ok, q = pcall(DB.GetQuest, DB, questId)
        if ok and type(q) == "table" then return q end
    end
end

local function GetNPC(id)
    local DB = Module("QuestieDB")
    if not (DB and type(DB.GetNPC) == "function") then return end
    local ok, npc = pcall(DB.GetNPC, DB, id)
    if ok and type(npc) == "table" then return npc end
    ok, npc = pcall(DB.GetNPC, id)
    if ok and type(npc) == "table" then return npc end
end

local function GetObject(id)
    local DB = Module("QuestieDB")
    if not (DB and type(DB.GetObject) == "function") then return end
    local ok, obj = pcall(DB.GetObject, DB, id)
    if ok and type(obj) == "table" then return obj end
    ok, obj = pcall(DB.GetObject, id)
    if ok and type(obj) == "table" then return obj end
end

local function SortedValues(t)
    local keys, out = {}, {}
    if type(t) ~= "table" then return out end
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return tostring(a) < tostring(b)
    end)
    for _, k in ipairs(keys) do out[#out + 1] = t[k] end
    return out
end

-- Egy quest objective-jei, mindegyikhez a forrasok (mob / object) spawnokkal.
local function CollectTargets(quest, isComplete)
    local result = {}

    if isComplete and type(quest.Finisher) == "table" then
        local f = quest.Finisher
        local sources, names = {}, {}
        for _, id in ipairs(type(f.NPC) == "table" and f.NPC or {}) do
            local npc = GetNPC(id)
            if npc then
                sources[#sources + 1] = { id = id, name = npc.name, spawns = npc.spawns, isNpc = true }
                names[#names + 1] = npc.name
            end
        end
        for _, id in ipairs(type(f.GameObject) == "table" and f.GameObject or {}) do
            local obj = GetObject(id)
            if obj then
                sources[#sources + 1] = { id = id, name = obj.name, spawns = obj.spawns, isNpc = false }
                names[#names + 1] = obj.name
            end
        end
        if #sources > 0 then
            result[1] = {
                desc = L["Turn in: "] .. table.concat(names, ", "),
                completed = false,
                turnIn = true,
                sources = sources,
            }
            return result
        end
    end

    local all = SortedValues(quest.Objectives)
    for _, o in ipairs(SortedValues(quest.SpecialObjectives)) do all[#all + 1] = o end

    for _, o in ipairs(all) do
        if type(o) == "table" then
            local desc = o.Description or o.Text or o.Type or "?"
            if type(o.Collected) == "number" and type(o.Needed) == "number" and o.Needed > 0
                and not tostring(desc):find("%d+%s*/%s*%d+") then
                desc = ("%s %d/%d"):format(desc, o.Collected, o.Needed)
            end
            local entry = { desc = desc, completed = o.Completed and true or false, sources = {} }
            if o.Type == "item" and o.Id then entry.itemId = o.Id end
            entry.qid = quest.Id
            entry.qo = o -- Questie objective (Collected/Needed) az ETA szamitashoz
            local seen = {}

            for id, s in pairs(o.spawnList or {}) do
                if type(s) == "table" then
                    local isNpc
                    if type(s.TooltipKey) == "string" then
                        isNpc = s.TooltipKey:sub(1, 2) == "m_"
                    else
                        isNpc = (o.Type == "monster" or o.Type == "killcredit")
                    end
                    local key = (isNpc and "m" or "o") .. tostring(s.Id or id)
                    if not seen[key] then
                        seen[key] = true
                        entry.sources[#entry.sources + 1] = {
                            id = s.Id or id, name = s.Name, spawns = s.Spawns, isNpc = isNpc,
                        }
                    end
                end
            end

            -- Vendorok (a spawnList-ben mobkent szerepelnek): ezeket meg kell talalni, nem
            -- "a teruleten vagy" - a marker mindig kell (static = egy konkret NPC)
            if entry.itemId and #entry.sources > 0 then
                local DB = Module("QuestieDB")
                local ok, item = false, nil
                if DB and type(DB.GetItem) == "function" then ok, item = pcall(DB.GetItem, DB, entry.itemId) end
                if ok and type(item) == "table" and type(item.Sources) == "table" then
                    local vend = {}
                    for _, src in ipairs(item.Sources) do
                        if src.Vendor and src.Id then vend[src.Id] = true end
                    end
                    for _, s in ipairs(entry.sources) do
                        if s.isNpc and vend[s.id] then s.static = true end
                    end
                end
            end

            -- Tartalek: ha a Questie meg nem toltotte ki a spawnList-et
            if #entry.sources == 0 and o.Type == "monster" and o.Id then
                local npc = GetNPC(o.Id)
                if npc then
                    entry.sources[1] = { id = o.Id, name = npc.name, spawns = npc.spawns, isNpc = true }
                end
            end

            result[#result + 1] = entry
        end
    end
    return result
end

-- Keresett item: honnan szerezheto (foldon/objectbol, mobbol dropol, vendor).
-- Visszaad egy listat { text, r, g, b } sorokkal; max 'limit' forrassor.
local function ItemSourceLines(entry, limit)
    local lines = {}
    if not entry.itemId then return lines end
    limit = limit or 4
    local DB = Module("QuestieDB")
    local objs, mobs = {}, {}
    for _, s in ipairs(entry.sources) do
        if s.isNpc then mobs[#mobs + 1] = s else objs[#objs + 1] = s end
    end
    local n = 0
    for _, s in ipairs(objs) do
        if n >= limit then break end
        n = n + 1
        lines[#lines + 1] = { L["Pick up: "] .. (s.name or "?") .. L[" (on the ground / in an object)"], 0.6, 1, 0.6 }
    end
    for _, s in ipairs(mobs) do
        if n >= limit then break end
        n = n + 1
        local txt = L["Dropped by: "] .. (s.name or "?")
        local npc = GetNPC(s.id)
        if npc and type(npc.minLevel) == "number" then
            local maxL = type(npc.maxLevel) == "number" and npc.maxLevel or npc.minLevel
            txt = txt .. (maxL ~= npc.minLevel and (" (lvl %d-%d)"):format(npc.minLevel, maxL)
                or (" (lvl %d)"):format(npc.minLevel))
        end
        if DB and type(DB.GetItemDroprate) == "function" then
            local ok, rate = pcall(DB.GetItemDroprate, entry.itemId, s.id)
            if ok and type(rate) == "table" then rate = rate[1] end
            rate = tonumber(rate)
            if rate and rate > 0 then txt = txt .. (" ~%s%%"):format(rate >= 10 and ("%d"):format(rate) or ("%.1f"):format(rate)) end
        end
        lines[#lines + 1] = { txt, 1, 0.7, 0.4 }
    end
    -- Vendor forras (a spawnList-ben nincs kulon jelolve)
    if DB then
        local ok, item = pcall(DB.GetItem, DB, entry.itemId)
        if ok and type(item) == "table" and type(item.Sources) == "table" then
            for _, src in ipairs(item.Sources) do
                if src.Vendor and n < limit + 1 then
                    local npc = GetNPC(src.Id)
                    if npc then
                        n = n + 1
                        lines[#lines + 1] = { L["Sold by: "] .. (npc.name or "?"), 1, 0.9, 0.3 }
                    end
                end
            end
        end
    end
    local total = #objs + #mobs
    if total > limit then
        lines[#lines + 1] = { (L["+%d more sources"]):format(total - limit), 0.6, 0.6, 0.6 }
    end
    return lines
end

---------------------------------------------------------------------------
-- Quest log segedek (classic es modern API-ra is)
---------------------------------------------------------------------------
local function GetLogEntry(index)
    if GetQuestLogTitle then
        local title, _, _, isHeader, _, isComplete, _, questId = GetQuestLogTitle(index)
        return title, isHeader, questId, (isComplete == 1 or isComplete == true)
    elseif C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(index)
        if info then
            local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID) or false
            return info.title, info.isHeader, info.questID, done
        end
    end
end

local function NumLogEntries()
    if GetNumQuestLogEntries then return (GetNumQuestLogEntries()) end
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then return (C_QuestLog.GetNumQuestLogEntries()) end
    return 0
end

local function FindQuestInLog(questId)
    for i = 1, NumLogEntries() do
        local title, isHeader, qid, done = GetLogEntry(i)
        if not isHeader and qid == questId then return title, done end
    end
end


-- belso exportok a tobbi core fajlnak
NS.C.CollectTargets, NS.C.FindQuestInLog, NS.C.GetLogEntry, NS.C.GetNPC, NS.C.GetObject, NS.C.GetQuestieQuest, NS.C.ItemSourceLines, NS.C.Module = CollectTargets, FindQuestInLog, GetLogEntry, GetNPC, GetObject, GetQuestieQuest, ItemSourceLines, Module
NS.C.NumLogEntries, NS.C.QuestieAvailable = NumLogEntries, QuestieAvailable
