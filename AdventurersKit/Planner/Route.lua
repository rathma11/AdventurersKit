local ADDON_NAME, NS = ...
local L = NS.L
NS.P = NS.P or {}
local P = NS.P
local KillPace, PICKUP_LEN, ROUTE_LEN = P.KillPace, P.PICKUP_LEN, P.ROUTE_LEN

---------------------------------------------------------------------------
-- Vilagkoordinatak cache-elve (spawnok nem valtoznak)
---------------------------------------------------------------------------
local pointCache = {}

local function SourcePoints(src)
    local key = (src.isNpc and "m" or "o") .. tostring(src.id)
    local pts = pointCache[key]
    if pts then return pts end
    pts = {}
    if type(src.spawns) == "table" then
        for areaId, list in pairs(src.spawns) do
            local uiMap = NS.UiMapFromArea(areaId)
            if uiMap and type(list) == "table" then
                for _, c in ipairs(list) do
                    local x, y = c[1], c[2]
                    if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
                        local wc, wx, wy = NS.WorldPos(uiMap, x / 100, y / 100)
                        if wc and wx then
                            pts[#pts + 1] = { map = uiMap, x = x, y = y, wc = wc, wx = wx, wy = wy, name = src.name }
                        end
                    end
                end
            end
        end
    end
    pointCache[key] = pts
    return pts
end

local function Nearest(sources, c, x, y)
    local best, bestD
    for _, s in ipairs(sources) do
        for _, p in ipairs(SourcePoints(s)) do
            if p.wc == c then
                local d = (p.wx - x) ^ 2 + (p.wy - y) ^ 2
                if not bestD or d < bestD then best, bestD = p, d end
            end
        end
    end
    if best then return best, math.sqrt(bestD) end
end

---------------------------------------------------------------------------
-- Javaslatok
---------------------------------------------------------------------------
-- Quest log: minden questnek egy "kovetkezo allomasa" van (hatralevo objective-ek vagy leadas).
-- Mohó utvonal: mindig a legkozelebbi allomas az elozotol.
local function BuildRoute(pc, px, py, maxN)
    local stops = {}
    for i = 1, NS.NumLogEntries() do
        local title, isHeader, qid, done = NS.GetLogEntry(i)
        if not isHeader and qid then
            local q = NS.GetQuestieQuest(qid)
            if q then
                local objs = NS.CollectTargets(q, done)
                local sources = {}
                for _, o in ipairs(objs) do
                    if not o.completed then
                        for _, s in ipairs(o.sources) do sources[#sources + 1] = s end
                    end
                end
                if #sources > 0 then
                    stops[#stops + 1] = { qid = qid, title = title, done = done, sources = sources, objs = objs }
                end
            end
        end
    end
    -- A "kovetkezo" nyillal atugrott questek (Planner\QuestNav.lua, karakterenkent mentve) az
    -- utvonal vegere kerulnek; ha csak ilyenek vannak, azok jonnek, ugyanugy legkozelebbi elol
    local deferred = NS.DeferredQuests and NS.DeferredQuests() or {}
    local later = {}
    for i = #stops, 1, -1 do
        if deferred[stops[i].qid] then
            stops[i].deferred = true
            later[#later + 1] = table.remove(stops, i)
        end
    end
    local route, cx, cy = {}, px, py
    local maxLen = maxN or ROUTE_LEN
    for _, list in ipairs({ stops, later }) do
        while #route < maxLen and #list > 0 do
            local bi, bp, bd
            for i, s in ipairs(list) do
                local p, d = Nearest(s.sources, pc, cx, cy)
                if p and (not bd or d < bd) then bi, bp, bd = i, p, d end
            end
            if not bi then break end
            local s = table.remove(list, bi)
            -- leg: az elozo allomastol (a sorrendhez); dist: tolad legvonalban (ezt mutatjuk)
            s.point, s.leg = bp, bd
            s.dist = math.sqrt((bp.wx - px) ^ 2 + (bp.wy - py) ^ 2)
            route[#route + 1] = s
            cx, cy = bp.wx, bp.wy
        end
    end
    return route
end

-- A kijelolt mellett: a quest log tobbi questjenek hatralevo mob-objective-jei, amiknek
-- van spawnja 'radius' yardon belul. Legkozelebbi elol, max 4.
NS.NearbyQuestTargets = function(exclude, radius)
    local pc, px, py = NS.PlayerWorldPos()
    if not pc then return {} end
    local out = {}
    for i = 1, NS.NumLogEntries() do
        local title, isHeader, qid, done = NS.GetLogEntry(i)
        if not isHeader and qid and qid ~= exclude and not done then
            local q = NS.GetQuestieQuest(qid)
            if q then
                for _, o in ipairs(NS.CollectTargets(q, false)) do
                    if not o.completed and not o.turnIn then
                        local npcs, names = {}, {}
                        for _, s in ipairs(o.sources) do
                            if s.isNpc and s.name then npcs[#npcs + 1] = s; names[#names + 1] = s.name end
                        end
                        if #npcs > 0 then
                            local _, d = Nearest(npcs, pc, px, py)
                            if d and d <= radius then
                                out[#out + 1] = { qid = qid, title = title, desc = o.desc, names = names, dist = d, obj = o }
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    for i = #out, 5, -1 do out[i] = nil end
    return out
end

local function IsDone(qid)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(qid) then return true end
    if IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(qid) then return true end
    local db = _G.Questie and Questie.db and Questie.db.char
    return db and type(db.complete) == "table" and db.complete[qid] and true or false
end

NS.QuestIsDone = IsDone

-- Legkozelebbi NPC egy tipusbol (Questie Townsfolk): "Repair", "Banker", "Innkeeper" a
-- Townsfolk modulbol, "Ammo", "Food", "Drink" a karakter vendor listajabol. A sajat
-- frakciodhoz baratsagosak kozul, ugyanazon a kontinensen. Forras lista tipusonkent egyszer.
local folkCache = {}
local function FolkIds(kind)
    if kind == "Ammo" or kind == "Food" or kind == "Drink" then
        local db = _G.Questie and Questie.db and Questie.db.char
        return db and type(db.vendorList) == "table" and db.vendorList[kind]
    end
    local T = NS.Module("Townsfolk")
    if kind == "Class Trainer" then
        -- a sajat classod trainerei (Questie: classSpecificTownsfolk[CLASS]["Class Trainer"])
        local cls = select(2, UnitClass("player"))
        local c = T and type(T.classSpecificTownsfolk) == "table" and T.classSpecificTownsfolk[cls]
        return c and c["Class Trainer"]
    end
    if kind == "Stable Master" then
        local c = T and type(T.classSpecificTownsfolk) == "table" and T.classSpecificTownsfolk.HUNTER
        return (c and c["Stable Master"]) or (T and type(T.townsfolk) == "table" and T.townsfolk["Stable Master"])
    end
    -- szakma trainer: "Prof:<profession id>" (Questie professionTrainers)
    local prof = tonumber(kind:match("^Prof:(%d+)$"))
    if prof then
        return T and type(T.professionTrainers) == "table" and T.professionTrainers[prof]
    end
    return T and type(T.townsfolk) == "table" and T.townsfolk[kind]
end
NS.NearestTownsfolk = function(kind)
    -- eladas (tele taska): a kozelebbi a javitok (armorer) es a kaja arusok kozul
    if kind == "Sell" then
        local p1, d1 = NS.NearestTownsfolk("Repair")
        local p2, d2 = NS.NearestTownsfolk("Food")
        if p1 and (not p2 or (d1 or 1e9) <= (d2 or 1e9)) then return p1, d1 end
        return p2, d2
    end
    local pc, px, py = NS.PlayerWorldPos()
    if not pc then return end
    local src = folkCache[kind]
    if not src then
        local ids = FolkIds(kind)
        if type(ids) ~= "table" or #ids == 0 then return end -- meg nem toltotte be a Questie
        local fac = UnitFactionGroup("player") == "Alliance" and "A" or "H"
        src = {}
        for _, id in ipairs(ids) do
            local npc = NS.GetNPC(id)
            local f = npc and npc.friendlyToFaction
            if npc and type(npc.spawns) == "table" and (not f or f == "AH" or f == fac) then
                src[#src + 1] = { id = id, name = npc.name, spawns = npc.spawns, isNpc = true }
            end
        end
        folkCache[kind] = src
    end
    return Nearest(src, pc, px, py)
end

local starterCache = {} -- qid -> quest giver forrasok
local function QuestStarters(qid, q)
    local sources = starterCache[qid]
    if sources then return sources end
    sources = {}
    starterCache[qid] = sources
    for _, id in ipairs(type(q.Starts.NPC) == "table" and q.Starts.NPC or {}) do
        local npc = NS.GetNPC(id)
        if npc then sources[#sources + 1] = { id = id, name = npc.name, spawns = npc.spawns, isNpc = true } end
    end
    for _, id in ipairs(type(q.Starts.GameObject) == "table" and q.Starts.GameObject or {}) do
        local obj = NS.GetObject(id)
        if obj then sources[#sources + 1] = { id = id, name = obj.name, spawns = obj.spawns, isNpc = false } end
    end
    return sources
end

-- Felveheto-e most (nincs a logban, nincs kesz, szintsavban); a zona ajanlo is ezt hasznalja
local function PickupOk(qid, q, inLog, level, below, above)
    if not q or inLog[qid] or IsDone(qid) then return false end
    local ql = tonumber(q.level) or 0
    return type(q.Starts) == "table" and not q.isHidden
        and (q.requiredLevel or 0) <= level
        and (ql <= 0 or (ql >= level - below and ql <= level + above))
end

local function BuildPickups(pc, px, py, maxN)
    local AQ = NS.Module("AvailableQuests")
    local avail = AQ and AQ.__availableQuests
    if type(avail) ~= "table" then return {} end
    local QP = NS.Module("QuestiePlayer")
    local inLog = QP and QP.currentQuestlog or {}
    local level = UnitLevel("player") or 1
    -- Szintsav: a quest szintje a sajatodnal max 2-vel kisebb, max 10-zel nagyobb (allithato)
    local below = tonumber(QuestFocusDB.pickupBelow) or 2
    local above = tonumber(QuestFocusDB.pickupAbove) or 10
    local list = {}
    for qid in pairs(avail) do
        local q = NS.GetQuestieQuest(qid)
        if PickupOk(qid, q, inLog, level, below, above) then
            local p, d = Nearest(QuestStarters(qid, q), pc, px, py)
            if p then list[#list + 1] = { qid = qid, name = q.name, level = q.level, point = p, dist = d, quest = q } end
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    for i = #list, (maxN or PICKUP_LEN) + 1, -1 do list[i] = nil end
    return list
end

-- Felveheto quest becsult hossza (a DB-ben nincs darabszam, ezert durva becsles):
-- mob objective ~8 kill, item ~6 db (drop rate-tel), object ~30 mp, egyeb/beszelgetes ~1 perc.
-- Ha nem lehet ertelmesen becsulni (battleground, honor mark, olyan item, aminek nem
-- ismerjuk a forrasat), nil-t ad: inkabb "?" latszik, mint egy felrevezeto 3 perc.
local BG_ZONES = { [2597] = true, [3277] = true, [3358] = true } -- Alterac Valley, Warsong Gulch, Arathi Basin
local BG_SORTS = { [-25] = true }                                -- QuestSort: Battlegrounds
local BG_ITEMS = { [20558] = true, [20559] = true, [20560] = true } -- WSG / AB / AV Mark of Honor

-- Dungeon / raid questek: a Questie zoneOrSort a dungeon area ID-ja. Teljes nev + raid-e.
local DUNGEONS = {
    [2437] = "Ragefire Chasm", [718] = "Wailing Caverns", [1581] = "The Deadmines", [209] = "Shadowfang Keep",
    [719] = "Blackfathom Deeps", [717] = "The Stockade", [133] = "Gnomeregan", [491] = "Razorfen Kraul",
    [796] = "Scarlet Monastery", [722] = "Razorfen Downs", [1337] = "Uldaman", [1176] = "Zul'Farrak",
    [2100] = "Maraudon", [1477] = "Sunken Temple", [1584] = "Blackrock Depths", [1583] = "Blackrock Spire",
    [2557] = "Dire Maul", [2057] = "Scholomance", [2017] = "Stratholme",
}
local RAIDS = {
    [2717] = "Molten Core", [2159] = "Onyxia's Lair", [1977] = "Zul'Gurub", [2677] = "Blackwing Lair",
    [3429] = "Ruins of Ahn'Qiraj", [3428] = "Temple of Ahn'Qiraj", [3456] = "Naxxramas",
}
local function QuestDungeon(q, qid)
    if type(q) ~= "table" then return end
    -- Dungeon Journal (ha fent van): a Forever sajat dungeonjai is
    qid = tonumber(qid or q.Id or q.id)
    local jn = qid and NS.JournalDungeonOfQuest and NS.JournalDungeonOfQuest(qid)
    if jn then return jn, false end
    local zs = tonumber(q.zoneOrSort)
    if not zs then return end
    if DUNGEONS[zs] then return DUNGEONS[zs], false end
    if RAIDS[zs] then return RAIDS[zs], true end
end
NS.QuestDungeon = QuestDungeon
-- Listasor cimke: |cffff7040[Dungeon: Wailing Caverns]|r (raidnel lila); a sor elejere
-- kerul (a hosszu quest nev a vegen vagodik le, igy a cimke mindig latszik)
NS.DungeonTag = function(q, qid)
    local name, raid = QuestDungeon(q, qid)
    if not name then return "" end
    return raid and ("|cffc070ff[" .. L["Raid"] .. ": " .. name .. "]|r ")
        or ("|cffff7040[" .. L["Dungeon"] .. ": " .. name .. "]|r ")
end
local function EstimateQuestTime(q)
    if type(q) ~= "table" then return nil, "?" end
    local zs = tonumber(q.zoneOrSort)
    if zs and (BG_ZONES[zs] or BG_SORTS[zs]) then return nil, "battleground" end
    local pace = KillPace()
    local DB = NS.Module("QuestieDB")
    local total, any = 0, false
    for _, o in ipairs(type(q.ObjectiveData) == "table" and q.ObjectiveData or {}) do
        any = true
        if o.Type == "monster" or o.Type == "killcredit" then
            total = total + 8 * pace
        elseif o.Type == "item" then
            if BG_ITEMS[o.Id] then return nil, "battleground" end
            local best, fromObject
            if DB and type(DB.GetItem) == "function" then
                local ok, item = pcall(DB.GetItem, DB, o.Id)
                if ok and type(item) == "table" and type(item.Sources) == "table" then
                    for _, src in ipairs(item.Sources) do
                        if src.Type == "monster" and not src.Vendor and type(DB.GetItemDroprate) == "function" then
                            local ok2, rate = pcall(DB.GetItemDroprate, o.Id, src.Id)
                            if ok2 and type(rate) == "table" then rate = rate[1] end
                            rate = tonumber(rate)
                            if rate and rate > 0 and (not best or rate > best) then best = rate end
                        elseif src.Type == "object" then
                            fromObject = true
                        end
                    end
                end
            end
            if best then
                total = total + (6 * 100 / math.min(best, 100)) * pace
            elseif fromObject then
                total = total + 6 * 30
            else
                -- nem tudjuk, honnan jon (vendor, crafting, BG, mas quest jutalma...)
                return nil, "unknown source"
            end
        elseif o.Type == "object" then
            total = total + 30
        else
            total = total + 60
        end
    end
    if not any then total = 60 end -- beszelgetos / kezbesito quest
    return total
end
NS.EstimateQuestTime = EstimateQuestTime


-- belso exportok a tobbi core fajlnak
NS.P.BuildPickups, NS.P.BuildRoute, NS.P.EstimateQuestTime, NS.P.Nearest = BuildPickups, BuildRoute, EstimateQuestTime, Nearest
NS.P.SourcePoints, NS.P.QuestStarters, NS.P.PickupOk = SourcePoints, QuestStarters, PickupOk
