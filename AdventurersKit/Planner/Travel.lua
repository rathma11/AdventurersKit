local ADDON_NAME, NS = ...
local L = NS.L
local GetItemCount, GetItemInfoInstant, GetItemInfo, GetItemIcon, GetItemSpell = NS.SafeItem.GetItemCount, NS.SafeItem.GetItemInfoInstant, NS.SafeItem.GetItemInfo, NS.SafeItem.GetItemIcon, NS.SafeItem.GetItemSpell -- biztonsagos item API (CoreInit.lua)
NS.P = NS.P or {}
local P = NS.P
local FormatTime, Nearest, state = P.FormatTime, P.Nearest, P.state

---------------------------------------------------------------------------
-- Utazas: gyalog / Hearthstone / repules ido a markerig
-- A HS helyet a jatek nem adja meg (csak a nevet: GetBindLocation), ezert megtanuljuk:
-- bindolaskor (az innkeepernel allsz) es HS-elés utan erkezeskor elmentjuk a poziciot.
---------------------------------------------------------------------------
local HS_ITEM, HS_CAST, FLY_SPEED = 6948, 10, 25 -- repules: legvonalban ~25 yd/mp (kerulokkel)

-- Futasi sebesseg. Combatban a GetUnitSpeed "secret" erteket ad (nem szabad szamolni vele),
-- ezert csak combaton kivul olvassuk, kozben az utolso jo ertek marad.
local lastSpeed = 7
local function Speed()
    if InCombatLockdown() then return lastSpeed end
    local ok, v = pcall(function()
        local _, run = GetUnitSpeed("player")
        if issecretvalue and issecretvalue(run) then return nil end
        run = tonumber(run)
        return run and math.max(run, 7) or nil
    end)
    if ok and v then lastSpeed = v end
    return lastSpeed
end

local function SaveHearth()
    local wc, wx, wy = NS.PlayerWorldPos()
    if not wc then return end
    QuestFocusDB.hearth = { name = GetBindLocation and GetBindLocation() or "?", wc = wc, wx = wx, wy = wy }
end

local function HearthInfo()
    local h = QuestFocusDB.hearth
    if not h then return end
    -- ha azota mashova bindoltal, a regi pozicio mar nem jo
    if GetBindLocation and h.name ~= GetBindLocation() then return end
    local start, dur = 0, 0
    local getCD = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if getCD then start, dur = getCD(HS_ITEM) end
    local cd = (start and start > 0 and dur and dur > 0) and math.max(0, start + dur - GetTime()) or 0
    return h, cd, GetItemCount(HS_ITEM) > 0
end

-- Ismert repulopontok a kontinensen (ha a kliens adja: C_TaxiMap)
local function ContinentMap()
    local m = C_Map.GetBestMapForUnit("player")
    for _ = 1, 6 do
        local info = m and C_Map.GetMapInfo(m)
        if not info then return end
        if Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Continent then return m end
        m = info.parentMapID
    end
end

local function KnownTaxiNodes()
    if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return {} end
    local cont = ContinentMap()
    if not cont then return {} end
    local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, cont)
    if not ok or type(nodes) ~= "table" then return {} end
    local out = {}
    for _, n in ipairs(nodes) do
        local known = n.state == nil or n.state == 0 or n.state == 1 -- Current / Reachable
        if known and n.position then
            local px, py = n.position.x or n.position[1], n.position.y or n.position[2]
            local wc, wx, wy = NS.WorldPos(cont, px, py)
            if wc and wx then out[#out + 1] = { name = n.name, wc = wc, wx = wx, wy = wy } end
        end
    end
    return out
end

local function Dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

---------------------------------------------------------------------------
-- Hajok, zeppelinek, villamos. Ket allomas (uiMap, x %, y %, nev) es a menetido masodpercben
-- (atlagos varakozas + ut). Az allomasok vilagkoordinatait futas kozben szamoljuk (egyszer).
-- faction: csak annak a frakcionak (nil = mindenki). Bovitheto: QuestFocusDB.customTransports
-- ugyanilyen formaban (pl. a Forever sajat hajojaihoz).
---------------------------------------------------------------------------
local TRANSPORTS = {
    { kind = "boat", a = { 1437, 4.6, 57.1, "Menethil Harbor" }, b = { 1445, 71.6, 56.4, "Theramore" }, time = 180, faction = "Alliance" },
    { kind = "boat", a = { 1437, 4.4, 62.6, "Menethil Harbor" }, b = { 1439, 32.4, 43.8, "Auberdine" }, time = 180, faction = "Alliance" },
    { kind = "boat", a = { 1439, 33.2, 40.2, "Auberdine" }, b = { 1438, 54.9, 96.8, "Rut'theran Village" }, time = 120, faction = "Alliance" },
    { kind = "boat", a = { 1434, 25.9, 73.1, "Booty Bay" }, b = { 1413, 63.7, 38.6, "Ratchet" }, time = 180 },
    { kind = "zeppelin", a = { 1411, 50.8, 13.7, "Orgrimmar" }, b = { 1420, 60.7, 58.8, "Undercity" }, time = 180, faction = "Horde" },
    { kind = "zeppelin", a = { 1411, 50.6, 12.6, "Orgrimmar" }, b = { 1434, 31.5, 29.1, "Grom'gol" }, time = 180, faction = "Horde" },
    { kind = "zeppelin", a = { 1420, 61.9, 59.0, "Undercity" }, b = { 1434, 31.6, 29.2, "Grom'gol" }, time = 180, faction = "Horde" },
    { kind = "tram", a = { 1453, 69.2, 31.0, "Stormwind" }, b = { 1455, 76.6, 51.2, "Ironforge" }, time = 90 },
}
local KIND_NAME = { boat = L["Boat"], zeppelin = L["Zeppelin"], tram = L["Tram"] }

local stationCache = {} -- "uiMap:x:y" -> { wc, wx, wy } vagy false
local function Station(s)
    local key = s[1] .. ":" .. s[2] .. ":" .. s[3]
    local c = stationCache[key]
    if c == nil then
        local wc, wx, wy = NS.WorldPos(s[1], s[2] / 100, s[3] / 100)
        c = wc and wx and { wc = wc, wx = wx, wy = wy, name = s[4] } or nil
        if c then stationCache[key] = c end -- sikertelen: kesobb ujraprobalja
    end
    return c
end

local function Transports()
    local fac = UnitFactionGroup("player")
    local out = {}
    local function add(list)
        for _, t in ipairs(type(list) == "table" and list or {}) do
            if not t.faction or t.faction == fac then
                local a, b = Station(t.a), Station(t.b)
                if a and b then out[#out + 1] = { a = a, b = b, time = tonumber(t.time) or 180, kind = t.kind } end
            end
        end
    end
    add(TRANSPORTS)
    add(QuestFocusDB.customTransports)
    return out
end

-- Leggyorsabb ut gyalog + hajo / zeppelin / villamos kombinacioval (Dijkstra, kis graf).
-- from, to: { wc, wx, wy }. Visszaad: ido (mp), lepesek ({ kind, from, to }) - vagy nil, ha
-- nincs ut (masik kontinens, hajo nelkul).
-- useHearth: a kiindulo pont a jatekos, a Hearthstone is szamit (cast + hatralevo cooldown).
local function TransportRoute(from, to, speed, useHearth)
    speed = speed or 7
    local nodes = { from, to }
    local edges = {} -- [i] = { {j, ido, lepes} }
    local function edge(i, j, t, step)
        edges[i] = edges[i] or {}
        table.insert(edges[i], { j, t, step })
    end
    if useHearth then
        local h, cd, have = HearthInfo()
        if h and have and h.wx then
            nodes[#nodes + 1] = { wc = h.wc, wx = h.wx, wy = h.wy, name = h.name }
            edge(1, #nodes, HS_CAST + cd, { kind = "hs", to = h.name, cd = cd })
        end
    end
    for _, tr in ipairs(Transports()) do
        nodes[#nodes + 1] = tr.a
        local ia = #nodes
        nodes[#nodes + 1] = tr.b
        local ib = #nodes
        local step = { kind = tr.kind, from = tr.a.name, to = tr.b.name }
        local back = { kind = tr.kind, from = tr.b.name, to = tr.a.name }
        edge(ia, ib, tr.time, step)
        edge(ib, ia, tr.time, back)
    end
    -- gyalog: minden ket pont kozott ugyanazon a kontinensen
    for i = 1, #nodes do
        for j = 1, #nodes do
            if i ~= j and j ~= 1 and i ~= 2 and nodes[i].wc == nodes[j].wc then
                edge(i, j, Dist(nodes[i].wx, nodes[i].wy, nodes[j].wx, nodes[j].wy) / speed)
            end
        end
    end
    local best, prev, done = { [1] = 0 }, {}, {}
    while true do
        local u, ud
        for i, d in pairs(best) do
            if not done[i] and (not ud or d < ud) then u, ud = i, d end
        end
        if not u or u == 2 then break end
        done[u] = true
        for _, e in ipairs(edges[u] or {}) do
            local v, t = e[1], ud + e[2]
            if not best[v] or t < best[v] then best[v], prev[v] = t, { u, e[3] } end
        end
    end
    if not best[2] then return end
    local steps, v = {}, 2
    while prev[v] do
        if prev[v][2] then table.insert(steps, 1, prev[v][2]) end
        v = prev[v][1]
    end
    return best[2], steps
end
NS.TransportRoute = TransportRoute

-- Lepesek szovegben: "Boat: Menethil Harbor -> Theramore"
local function StepsText(steps)
    local t = {}
    for _, s in ipairs(steps or {}) do
        if s.kind == "hs" then
            t[#t + 1] = (L["Hearthstone to %s"]):format(s.to or "?")
                .. ((s.cd or 0) > 0 and (L[" (cooldown %s)"]):format(FormatTime(s.cd)) or "")
        else
            t[#t + 1] = ("%s: %s -> %s"):format(KIND_NAME[s.kind] or s.kind or "?", s.from or "?", s.to or "?")
        end
    end
    return table.concat(t, ", ")
end
NS.TransportStepsText = StepsText

-- Utazasi ido a celig (gyalog vagy hajoval / zeppelinnel, ami gyorsabb; repules nelkul)
NS.TravelTime = function(dest)
    local pc, px, py = NS.PlayerWorldPos()
    if not (pc and dest and dest.wx) then return end
    return TransportRoute({ wc = pc, wx = px, wy = py }, dest, Speed(), true)
end

-- dest: { wc, wx, wy }. Visszaad: { dist, walk, best = "walk"|"hs"|"fly"|"boat", bestTime, hs = {...}, fly = {...}, boat = {...} }
local function TravelAdvice(dest)
    local pc, px, py = NS.PlayerWorldPos()
    if not (pc and dest and dest.wx) then return end
    local speed = Speed()
    local r = {}
    if dest.wc == pc then
        r.dist = Dist(px, py, dest.wx, dest.wy)
        r.walk = r.dist / speed
    end
    r.best, r.bestTime = "walk", r.walk
    -- Hearthstone
    local h, cd, have = HearthInfo()
    if h and have and h.wc == dest.wc then
        local t = HS_CAST + cd + Dist(h.wx, h.wy, dest.wx, dest.wy) / speed
        r.hs = { time = t, name = h.name, cd = cd }
        if not r.bestTime or t < r.bestTime * 0.7 - 30 then r.best, r.bestTime = "hs", t end
    end
    -- Repules (azonos kontinensen)
    if dest.wc == pc then
        local nodes = KnownTaxiNodes()
        local a, ad, b, bd
        for _, n in ipairs(nodes) do
            if n.wc == pc then
                local d1 = Dist(px, py, n.wx, n.wy)
                if not ad or d1 < ad then a, ad = n, d1 end
                local d2 = Dist(dest.wx, dest.wy, n.wx, n.wy)
                if not bd or d2 < bd then b, bd = n, d2 end
            end
        end
        if a and b and a ~= b then
            local t = ad / speed + Dist(a.wx, a.wy, b.wx, b.wy) / FLY_SPEED + 20 + bd / speed
            r.fly = { time = t, from = a.name, to = b.name }
            if not r.bestTime or t < r.bestTime * 0.7 - 30 then r.best, r.bestTime = "fly", t end
        end
    end
    -- Hajo / zeppelin / villamos (masik kontinensre is)
    local t, steps = TransportRoute({ wc = pc, wx = px, wy = py }, dest, speed)
    if t and steps and #steps > 0 then
        r.boat = { time = t, steps = steps, kind = steps[1].kind }
        if not r.bestTime or t < r.bestTime * 0.85 then r.best, r.bestTime = "boat", t end
    end
    return r
end
NS.TravelAdvice = TravelAdvice

-- Hany kesz quest adhato le a HS helyen (a leado NPC ~400 yardon belul van a HS-tol)?
-- Csak ha messze vagy a HS-tol (>500 yd). Visszaad: lista (quest nevek), HS neve, cooldown
NS.HearthTurnIns = function()
    local h, cd, have = HearthInfo()
    if not (h and have) then return end
    local pc, px, py = NS.PlayerWorldPos()
    if pc and pc == h.wc and Dist(px, py, h.wx, h.wy) <= 500 then return end
    local list = {}
    for i = 1, NS.NumLogEntries() do
        local title, isHeader, qid, done = NS.GetLogEntry(i)
        if not isHeader and qid and done then
            local q = NS.GetQuestieQuest(qid)
            local objs = q and NS.CollectTargets(q, true)
            if objs and objs[1] and objs[1].turnIn then
                local _, d = Nearest(objs[1].sources, h.wc, h.wx, h.wy)
                if d and d <= 400 then list[#list + 1] = title or ("Quest " .. qid) end
            end
        end
    end
    if #list == 0 then return end
    return list, h.name, cd
end

local function BestWayText(r)
    if not r then return "-" end
    if r.best == "hs" then return "|cff33ff99" .. L["Hearth"] .. "|r" end
    if r.best == "fly" then return "|cff33ff99" .. L["Fly"] .. "|r" end
    if r.best == "boat" then return "|cff33ff99" .. (KIND_NAME[r.boat and r.boat.kind] or L["Boat"]) .. "|r" end
    return L["Walk"]
end
NS.BestWayText = BestWayText

-- Egyszer szolunk markerenkent, ha HS / repules joval gyorsabb
local lastAdviceKey
local function AdviseTravel()
    local w = state.waypoint
    if not (w and w.wx) or InCombatLockdown() then return end
    local key = ("%d:%d"):format(w.wx, w.wy)
    if key == lastAdviceKey then return end
    local r = TravelAdvice(w)
    if not r then return end
    lastAdviceKey = key
    if r.best == "hs" then
        NS.Print(L["Faster: |cff33ff99Hearthstone|r to %s (~%s instead of ~%s on foot)%s"], r.hs.name,
            FormatTime(r.hs.time), r.walk and FormatTime(r.walk) or "?",
            r.hs.cd > 0 and (L[" - cooldown %s"]):format(FormatTime(r.hs.cd)) or "")
    elseif r.best == "fly" then
        NS.Print(L["Faster: |cff33ff99fly|r %s -> %s (~%s instead of ~%s on foot)"], r.fly.from or "?", r.fly.to or "?",
            FormatTime(r.fly.time), r.walk and FormatTime(r.walk) or "?")
    elseif r.best == "boat" then
        NS.Print(L["Faster: |cff33ff99%s|r (~%s%s)"], StepsText(r.boat.steps), FormatTime(r.boat.time),
            r.walk and (L[" instead of ~%s on foot"]):format(FormatTime(r.walk)) or "")
    end
end

local travelEv = CreateFrame("Frame")
travelEv:RegisterEvent("HEARTHSTONE_BOUND")
travelEv:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
travelEv:RegisterEvent("PLAYER_ENTERING_WORLD")
travelEv:RegisterEvent("ZONE_CHANGED_NEW_AREA")
local hearthAt
travelEv:SetScript("OnEvent", function(_, event, unit, _, spellId)
    if event == "HEARTHSTONE_BOUND" then
        C_Timer.After(1, SaveHearth)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit == "player" and spellId == 8690 then hearthAt = GetTime() end -- Hearthstone
    elseif hearthAt and GetTime() - hearthAt < 20 then
        hearthAt = nil
        C_Timer.After(2, SaveHearth)
    end
end)

-- A marker letetelet figyeljuk (SetWaypoint utan): 1 mp-enkent nezzuk, uj-e
local adviceElapsed = 0
travelEv:SetScript("OnUpdate", function(_, dt)
    adviceElapsed = adviceElapsed + dt
    if adviceElapsed < 1 then return end
    adviceElapsed = 0
    AdviseTravel()
end)

