local ADDON_NAME, NS = ...
local L = NS.L
NS.C = NS.C or {}
local C = NS.C
local Module = C.Module

---------------------------------------------------------------------------
-- Koordinatak, tavolsag
---------------------------------------------------------------------------
local uiMapCache = {}
local function UiMapFromArea(areaId)
    local cached = uiMapCache[areaId]
    if cached ~= nil then return cached or nil end
    local ZoneDB = Module("ZoneDB")
    local id
    if ZoneDB and type(ZoneDB.GetUiMapIdByAreaId) == "function" then
        local ok, r = pcall(ZoneDB.GetUiMapIdByAreaId, ZoneDB, areaId)
        if ok then id = r end
    end
    uiMapCache[areaId] = id or false
    return id
end

local function WorldPos(uiMap, x, y)
    local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, uiMap, CreateVector2D(x, y))
    if ok and cont and world then return cont, world.x, world.y end
end

local function PlayerWorldPos()
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return end
    local px, py = pos:GetXY()
    return WorldPos(map, px, py)
end

local function ZoneName(uiMap)
    local info = C_Map.GetMapInfo(uiMap)
    return info and info.name or ("map " .. tostring(uiMap))
end

-- Visszaadja a legkozelebbi spawnt a forrasok kozul (+ tavolsag yardban, ha ugyanazon a kontinensen van)
local function FindNearest(sources)
    local pc, px, py = PlayerWorldPos()
    local best, bestScore, bestDist
    for _, src in ipairs(sources) do
        if type(src.spawns) == "table" then
            for areaId, list in pairs(src.spawns) do
                local uiMap = UiMapFromArea(areaId)
                if uiMap and type(list) == "table" then
                    for _, c in ipairs(list) do
                        local x, y = c[1], c[2]
                        if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
                            local wc, wx, wy = WorldPos(uiMap, x / 100, y / 100)
                            local dist, score
                            if pc and wc == pc and wx then
                                dist = math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
                                score = dist
                            else
                                score = wc and 1e9 or 2e9
                            end
                            if not bestScore or score < bestScore then
                                bestScore, bestDist = score, dist
                                best = { map = uiMap, x = x, y = y, name = src.name, wc = wc, wx = wx, wy = wy }
                            end
                        end
                    end
                end
            end
        end
    end
    return best, bestDist
end

-- Marker celpont: ha mar a spawn teruleten vagy (IN_AREA yardon belul van spawn), nem kuld
-- sehova (inArea = true). Kulonben nem a puszta legkozelebbi pontot adja, hanem azt, ami
-- kozel van ES korulotte sok spawn van (suru resz), igy nem egy magányos pontra visz.
local IN_AREA, CLUSTER_R, CLUSTER_W = 150, 80, 40

-- Mar megnezett spawn pontok (odaertel, de nem volt ott a mob / object): VISIT_TTL mp-ig a
-- kereses kihagyja oket (VISIT_R yardon belul), igy a marker a kovetkezo pontra lep.
local VISIT_R, VISIT_TTL = 35, 300
local visited = {}
local function MarkVisited(p)
    if p and p.wx then visited[#visited + 1] = { wc = p.wc, wx = p.wx, wy = p.wy, t = GetTime() } end
end
local function IsVisited(p)
    local now = GetTime()
    for i = #visited, 1, -1 do
        local v = visited[i]
        if now - v.t > VISIT_TTL then
            table.remove(visited, i)
        elseif v.wc == p.wc and (v.wx - p.wx) ^ 2 + (v.wy - p.wy) ^ 2 < VISIT_R * VISIT_R then
            return true
        end
    end
    return false
end
NS.MarkSpawnVisited = MarkVisited
NS.ClearSpawnVisited = function() wipe(visited) end

-- noArea: ne mondja, hogy "a teruleten vagy" (tovabblepesnel mindenkepp kell a kovetkezo pont)
local function FindSpawnTarget(sources, noArea)
    local pc, px, py = PlayerWorldPos()
    if not pc then return FindNearest(sources) end
    local pts = {}
    for _, src in ipairs(sources) do
        if type(src.spawns) == "table" then
            for areaId, list in pairs(src.spawns) do
                local uiMap = UiMapFromArea(areaId)
                if uiMap and type(list) == "table" then
                    for _, c in ipairs(list) do
                        local x, y = c[1], c[2]
                        if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
                            local wc, wx, wy = WorldPos(uiMap, x / 100, y / 100)
                            if wc == pc and wx then
                                local pt = { map = uiMap, x = x, y = y, name = src.name, wc = wc, wx = wx, wy = wy,
                                    d = math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2), static = src.static }
                                if src.static or not IsVisited(pt) then pts[#pts + 1] = pt end
                            end
                        end
                    end
                end
            end
        end
    end
    if #pts == 0 then return FindNearest(sources) end -- masik kontinens: a regi mod
    local nearest
    for _, p in ipairs(pts) do if not nearest or p.d < nearest.d then nearest = p end end
    -- vendor (egy konkret NPC, sokszor epuletben): oda mindig marker kell, nincs "teruleten vagy"
    if nearest.static then return nearest, nearest.d, false end
    if nearest.d <= IN_AREA and not noArea then return nearest, nearest.d, true end
    -- tovabblepes: a legkozelebbi meg nem nezett pont (nem a suru resz, az lehet messzebb)
    if noArea then return nearest, nearest.d, false end
    -- csak a kozelebbi pontokat nezzuk (a legkozelebbi tavolsaganak 3x-osaig), sulyozva a surusseggel
    local best, bestScore
    local limit = nearest.d * 3 + 200
    for _, p in ipairs(pts) do
        if p.d <= limit then
            local n = 0
            for _, q in ipairs(pts) do
                if q ~= p and math.abs(q.wx - p.wx) < CLUSTER_R and math.abs(q.wy - p.wy) < CLUSTER_R then n = n + 1 end
            end
            local score = p.d - CLUSTER_W * math.min(n, 8)
            if not bestScore or score < bestScore then best, bestScore = p, score end
        end
    end
    best = best or nearest
    return best, best.d, false
end


-- belso exportok a tobbi core fajlnak
NS.C.FindNearest, NS.C.FindSpawnTarget, NS.C.PlayerWorldPos, NS.C.UiMapFromArea, NS.C.WorldPos, NS.C.ZoneName = FindNearest, FindSpawnTarget, PlayerWorldPos, UiMapFromArea, WorldPos, ZoneName
