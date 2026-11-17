local ADDON_NAME, NS = ...
local L = NS.L
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

-- dest: { wc, wx, wy }. Visszaad: { dist, walk, best = "walk"|"hs"|"fly", bestTime, hs = {...}, fly = {...} }
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

