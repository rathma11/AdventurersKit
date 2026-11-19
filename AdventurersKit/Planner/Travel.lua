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
    NS.Debug("route", "hearthstone position learned: %s", tostring(QuestFocusDB.hearth.name))
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
-- Hajok, zeppelinek, leghajok, villamos (WoW Forever, build 1.60.1).
-- Kikotok vilag-yardban, kontinensenkent (0 Eastern Kingdoms, 1 Kalimdor, 2991 Zephras Isle):
-- a jatek sajat tablajabol (az OpenMap addon Places.lua adata, MIT, Copyright (c) 2026 OpenMap contributors;
-- lasd AdventurersKit\CREDITS.txt), ugyanabban a rendszerben, amit
-- a C_Map.GetWorldPosFromMapPos ad. ido = atlagos varakozas + ut (masodperc, becsles az
-- ut hosszabol: 90 + yard / 25). oneway: csak A -> B (korjarat).
-- faction: csak annak a frakcionak (nil = mindenki). Bovitheto: QuestFocusDB.customTransports
-- (ugyanilyen formaban, vagy a = { uiMap, x %, y %, nev } terkep koordinatakkal).
---------------------------------------------------------------------------
local function T(len) return math.floor(90 + len / 25) end
local W = {
    stormwind = { 0, -8654.5, 1344.4, "Stormwind Harbor" },
    menethilT = { 0, -3905.2, -585.8, "Menethil Harbor" },
    menethilL = { 0, -3709.5, -575.1, "Menethil Harbor" },
    southshore = { 0, -1102.6, -554.7, "Southshore" },
    theramore = { 1, -4016.4, -4740.6, "Theramore" },
    auberdineL = { 1, 6406.2, 823.1, "Auberdine" },
    auberdineS = { 1, 6548.3, 942.2, "Auberdine" },
    auberdineR = { 1, 6594.4, 759.8, "Auberdine" },
    ruttheran = { 1, 8532.0, 1023.7, "Rut'theran Village" },
    feathermoon = { 1, -4197.3, 3286.6, "Feathermoon Stronghold" },
    feralas = { 1, -4347.8, 2444.4, "Forgotten Coast" },
    bootybay = { 0, -14277.7, 582.9, "Booty Bay" },
    ratchet = { 1, -1005.6, -3841.6, "Ratchet" },
    steamwheedle = { 1, -6932.6, -4950.8, "Steamwheedle Port" },
    powderfuse = { 0, -8232.3, -5800.8, "Powderfuse Port" },
    dalaran = { 0, 544.8, 424.2, "Dalaran" },
    skywatcher = { 1, -802.0, 366.5, "Skywatcher Plateau" },
    valanaarA = { 2991, 1848.3, 569.1, "Valanaar" },
    valanaarH = { 2991, 1952.5, 1019.1, "Valanaar" },
    orgUC = { 1, 1318.1, -4658.0, "Orgrimmar" },
    orgGG = { 1, 1360.9, -4631.3, "Orgrimmar" },
    ucOrg = { 0, 2062.4, 293.0, "Undercity" },
    ucGG = { 0, 2062.6, 235.3, "Undercity" },
    ggOrg = { 0, -12464.0, 231.6, "Grom'gol" },
    ggUC = { 0, -12406.9, 211.8, "Grom'gol" },
}
local TRANSPORTS = {
    { kind = "boat", a = W.stormwind, b = W.auberdineS, time = T(1572), faction = "Alliance" },
    { kind = "boat", a = W.menethilT, b = W.theramore, time = T(2441), faction = "Alliance" },
    -- korjarat, egy iranyban: Menethil -> Southshore -> Auberdine -> Menethil
    { kind = "boat", a = W.menethilL, b = W.southshore, time = T(3336), faction = "Alliance", oneway = true },
    { kind = "boat", a = W.southshore, b = W.auberdineL, time = T(1964), faction = "Alliance", oneway = true },
    { kind = "boat", a = W.auberdineL, b = W.menethilL, time = T(2154), faction = "Alliance", oneway = true },
    { kind = "boat", a = W.auberdineR, b = W.ruttheran, time = T(2219), faction = "Alliance" },
    { kind = "boat", a = W.feathermoon, b = W.feralas, time = 60 + T(899) - 90, faction = "Alliance" },
    { kind = "boat", a = W.bootybay, b = W.ratchet, time = T(2787) },
    { kind = "boat", a = W.steamwheedle, b = W.powderfuse, time = T(1561) },
    { kind = "airship", a = W.dalaran, b = W.valanaarA, time = T(2690), faction = "Alliance" },
    { kind = "airship", a = W.skywatcher, b = W.valanaarH, time = T(2214), faction = "Horde" },
    { kind = "zeppelin", a = W.orgUC, b = W.ucOrg, time = T(3297), faction = "Horde" },
    { kind = "zeppelin", a = W.orgGG, b = W.ggOrg, time = T(2422), faction = "Horde" },
    { kind = "zeppelin", a = W.ucGG, b = W.ggUC, time = T(3000), faction = "Horde" },
    -- Deeprun Tram (instance, nincs a tablaban): a ket bejarat terkep koordinataval
    { kind = "tram", a = { 1453, 69.2, 31.0, "Stormwind" }, b = { 1455, 76.6, 51.2, "Ironforge" }, time = 90 },
}
local KIND_NAME = { boat = L["Boat"], zeppelin = L["Zeppelin"], airship = L["Airship"], tram = L["Tram"] }

local stationCache = {} -- "uiMap:x:y" -> { wc, wx, wy } vagy false
local function Station(s)
    -- vilagkoordinata (kontinens 0 / 1 / 2991 ...): kozvetlenul
    if s[1] == 0 or s[1] == 1 or s[1] == 2991 or math.abs(s[2]) > 100 or math.abs(s[3]) > 100 then
        return { wc = s[1], wx = s[2], wy = s[3], name = s[4] }
    end
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
                if a and b then
                    out[#out + 1] = { a = a, b = b, time = tonumber(t.time) or 180, kind = t.kind, oneway = t.oneway }
                end
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
        if not tr.oneway then edge(ib, ia, tr.time, back) end
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

-- /ak selftest (Core\SelfTest.lua): a beepitett jaratok ellenorzese. Visszaad: darabszam, hibak
NS.TransportCheck = function()
    local bad = {}
    local function name(s) return type(s) == "table" and tostring(s[4]) or "?" end
    for i, t in ipairs(TRANSPORTS) do
        local a, b = Station(t.a), Station(t.b)
        if not a then bad[#bad + 1] = ("#%d %s: start %s has no world position"):format(i, tostring(t.kind), name(t.a)) end
        if not b then bad[#bad + 1] = ("#%d %s: end %s has no world position"):format(i, tostring(t.kind), name(t.b)) end
        if not KIND_NAME[t.kind] then bad[#bad + 1] = ("#%d: unknown kind %s"):format(i, tostring(t.kind)) end
        if not (tonumber(t.time) and t.time > 0) then bad[#bad + 1] = ("#%d %s: bad time"):format(i, name(t.a)) end
        if a and b and a.wc == b.wc and a.wx == b.wx and a.wy == b.wy then
            bad[#bad + 1] = ("#%d %s: start and end are the same point"):format(i, name(t.a))
        end
    end
    return #TRANSPORTS, bad
end

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
    if NS.DebugOn("route") then
        NS.Debug("route", "travel advice for %s: best %s (%s) | walk %s | hs %s | fly %s | boat %s", tostring(w.title),
            tostring(r.best), r.bestTime and FormatTime(r.bestTime) or "?", r.walk and FormatTime(r.walk) or "-",
            r.hs and FormatTime(r.hs.time) or "-", r.fly and FormatTime(r.fly.time) or "-",
            r.boat and FormatTime(r.boat.time) or "-")
    end
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

