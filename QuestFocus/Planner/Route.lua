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
    local route, cx, cy = {}, px, py
    while #route < (maxN or ROUTE_LEN) and #stops > 0 do
        local bi, bp, bd
        for i, s in ipairs(stops) do
            local p, d = Nearest(s.sources, pc, cx, cy)
            if p and (not bd or d < bd) then bi, bp, bd = i, p, d end
        end
        if not bi then break end
        local s = table.remove(stops, bi)
        s.point, s.leg = bp, bd
        route[#route + 1] = s
        cx, cy = bp.wx, bp.wy
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

local starterCache = {} -- qid -> quest giver forrasok

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
        if not inLog[qid] and not IsDone(qid) then
            local q = NS.GetQuestieQuest(qid)
            local ql = q and tonumber(q.level) or 0
            if q and type(q.Starts) == "table" and not q.isHidden
                and (q.requiredLevel or 0) <= level
                and (ql <= 0 or (ql >= level - below and ql <= level + above)) then
                local sources = starterCache[qid]
                if not sources then
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
                end
                local p, d = Nearest(sources, pc, px, py)
                if p then list[#list + 1] = { qid = qid, name = q.name, level = q.level, point = p, dist = d, quest = q } end
            end
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    for i = #list, (maxN or PICKUP_LEN) + 1, -1 do list[i] = nil end
    return list
end

-- Felveheto quest becsult hossza (a DB-ben nincs darabszam, ezert durva becsles):
-- mob objective ~8 kill, item ~6 db (drop rate-tel), object ~30 mp, egyeb/beszelgetes ~1 perc.
local function EstimateQuestTime(q)
    local pace = KillPace()
    local DB = NS.Module("QuestieDB")
    local total, any = 0, false
    for _, o in ipairs(type(q.ObjectiveData) == "table" and q.ObjectiveData or {}) do
        any = true
        if o.Type == "monster" or o.Type == "killcredit" then
            total = total + 8 * pace
        elseif o.Type == "item" then
            local best
            if DB and type(DB.GetItem) == "function" then
                local ok, item = pcall(DB.GetItem, DB, o.Id)
                if ok and type(item) == "table" and type(item.Sources) == "table" then
                    for _, src in ipairs(item.Sources) do
                        if src.Type == "monster" and not src.Vendor and type(DB.GetItemDroprate) == "function" then
                            local ok2, rate = pcall(DB.GetItemDroprate, o.Id, src.Id)
                            if ok2 and type(rate) == "table" then rate = rate[1] end
                            rate = tonumber(rate)
                            if rate and rate > 0 and (not best or rate > best) then best = rate end
                        end
                    end
                end
            end
            total = total + (best and (6 * 100 / math.min(best, 100)) * pace or 6 * 30)
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
