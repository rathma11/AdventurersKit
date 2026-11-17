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
local function FindSpawnTarget(sources)
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
                                pts[#pts + 1] = { map = uiMap, x = x, y = y, name = src.name, wc = wc, wx = wx, wy = wy,
                                    d = math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2) }
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
    if nearest.d <= IN_AREA then return nearest, nearest.d, true end
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
