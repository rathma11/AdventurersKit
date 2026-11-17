local ADDON_NAME, NS = ...
local L = NS.L
NS.P = NS.P or {}
local P = NS.P

---------------------------------------------------------------------------
-- Zona ajanlo a "What next?" panelen:
--  1) ha egy masik zonaban sok questod van (quest log, legalabb ZONE_MIN), es itt kevesebb:
--     "Go to <zona>: N quests in your log" - a leggyorsabban elerhetot elore (gyalog, hajo,
--     zeppelin, villamos, Hearthstone: NS.TravelTime).
--  2) ha nincs ilyen: a legkozelebbi zona, ahol legalabb ZONE_MIN felveheto quest van a
--     szintsavodban (Questie AvailableQuests).
-- Draga szamolas (a teljes felveheto lista bejarasa), ezert cache-elve: 20 mp-enkent, vagy
-- ha valtozik a quest log / szint.
---------------------------------------------------------------------------
local ZONE_MIN = 5
local REFRESH = 20

-- Egy pont zonaja: a terkep (uiMap) felfele a zona szintig (barlang, varosresz -> zona)
local zoneOfMap = {}
local function ZoneOf(uiMap)
    if not uiMap then return end
    local c = zoneOfMap[uiMap]
    if c ~= nil then return c or nil end
    -- UIMapType: 2 Continent, 3 Zone, 4 Dungeon, 5 Micro, 6 Orphan
    local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    local m, res = uiMap, nil
    for _ = 1, 6 do
        local info = m and C_Map.GetMapInfo(m)
        if not info or info.mapType < ZONE then break end -- kontinens / vilag: nincs zona
        if info.mapType == ZONE then
            res = { id = m, name = info.name }
            break
        end
        m = info.parentMapID -- barlang, varosresz: a szulo zona
    end
    zoneOfMap[uiMap] = res or false
    return res
end

local function PlayerZone()
    local m = C_Map.GetBestMapForUnit("player")
    return ZoneOf(m)
end

-- forrasok pontjai kozul a jatekoshoz legkozelebbi (ugyanazon a kontinensen), kulonben az elso
local function PickPoint(sources, pc, px, py)
    local best, bd, first
    for _, s in ipairs(sources) do
        for _, p in ipairs(P.SourcePoints(s)) do
            first = first or p
            if pc and p.wc == pc then
                local d = (p.wx - px) ^ 2 + (p.wy - py) ^ 2
                if not bd or d < bd then best, bd = p, d end
            end
        end
    end
    return best or first
end

local function Collect(pc, px, py)
    local zones = {} -- zone id -> { name, log = {quests}, pick = {quests}, point }
    local function Z(p)
        local z = ZoneOf(p.map)
        if not z then return end
        local e = zones[z.id]
        if not e then
            e = { id = z.id, name = z.name, log = {}, pick = {} }
            zones[z.id] = e
        end
        return e
    end
    -- 1) quest log: a quest kovetkezo allomasa (hatralevo objective / leadas)
    for i = 1, NS.NumLogEntries() do
        local title, isHeader, qid, done = NS.GetLogEntry(i)
        if not isHeader and qid then
            local q = NS.GetQuestieQuest(qid)
            if q and not NS.QuestDungeon(q, qid) then
                local sources = {}
                for _, o in ipairs(NS.CollectTargets(q, done)) do
                    if not o.completed then
                        for _, s in ipairs(o.sources) do sources[#sources + 1] = s end
                    end
                end
                local p = #sources > 0 and PickPoint(sources, pc, px, py)
                local e = p and Z(p)
                if e then
                    e.log[#e.log + 1] = { qid = qid, title = title, point = p }
                end
            end
        end
    end
    -- 2) felveheto questek a szintsavban
    local AQ = NS.Module("AvailableQuests")
    local avail = AQ and AQ.__availableQuests
    if type(avail) == "table" then
        local QP = NS.Module("QuestiePlayer")
        local inLog = QP and QP.currentQuestlog or {}
        local level = UnitLevel("player") or 1
        local below = tonumber(QuestFocusDB.pickupBelow) or 2
        local above = tonumber(QuestFocusDB.pickupAbove) or 10
        for qid in pairs(avail) do
            local q = NS.GetQuestieQuest(qid)
            if P.PickupOk(qid, q, inLog, level, below, above) and not NS.QuestDungeon(q, qid) then
                local p = PickPoint(P.QuestStarters(qid, q), pc, px, py)
                local e = p and Z(p)
                if e then
                    e.pick[#e.pick + 1] = { qid = qid, title = q.name, level = q.level, point = p }
                end
            end
        end
    end
    return zones
end

-- a zona questjei kozul a leggyorsabban elerheto pont (es az ido + lepesek)
local function BestTarget(list)
    local best
    for i, e in ipairs(list) do
        if i > 6 then break end -- eleg nehany pont zonankent (utvonal kereses: kis, de nem ingyen)
        local t, steps = NS.TravelTime and NS.TravelTime(e.point)
        if t and (not best or t < best.time) then best = { point = e.point, time = t, steps = steps } end
    end
    return best
end

local cache, cacheAt, cacheKey = nil, 0, ""
local function Compute()
    local pc, px, py = NS.PlayerWorldPos()
    if not pc then return end
    local here = PlayerZone()
    local zones = Collect(pc, px, py)
    local hereLog = here and zones[here.id] and #zones[here.id].log or 0
    -- 1) masik zona sok quest log questtel
    local cands = {}
    for id, z in pairs(zones) do
        if (not here or id ~= here.id) and #z.log >= ZONE_MIN and #z.log > hereLog then
            cands[#cands + 1] = z
        end
    end
    local kind = "log"
    if #cands == 0 and hereLog < ZONE_MIN then
        -- 2) felveheto questek egy masik zonaban
        kind = "pick"
        for id, z in pairs(zones) do
            if (not here or id ~= here.id) and #z.pick >= ZONE_MIN then cands[#cands + 1] = z end
        end
    end
    if #cands == 0 then return end
    local best
    for _, z in ipairs(cands) do
        local list = kind == "log" and z.log or z.pick
        local t = BestTarget(list)
        if t then
            -- quest logos: a tobb quest szamit jobban (perc / quest), felveheto: a kozelebbi
            local score = kind == "log" and (t.time / #list) or t.time
            if not best or score < best.score then
                best = { kind = kind, zone = z.name, count = #list, quests = list, score = score,
                    point = t.point, time = t.time, steps = t.steps }
            end
        end
    end
    return best
end

NS.ZoneSuggestion = function()
    if QuestFocusDB.noZoneSuggest or not NS.QuestieAvailable() then return end
    local key = tostring(NS.questLogGen or 0) .. ":" .. tostring(UnitLevel("player"))
    if key ~= cacheKey or GetTime() - cacheAt > REFRESH then
        local ok, r = pcall(Compute)
        cache = ok and r or nil
        cacheAt, cacheKey = GetTime(), key
    end
    return cache
end
