-- QuestFocus: hatralevo ido becsles es questjavaslat.
--  * ETA: objective-onkent a sajat tempodbol (mikor nott a szamlalo), ennek hianyaban a
--    kill-tempodbol (ket kill kozt eltelt ido) es a Questie drop rate-bol.
--  * Javaslat: ha nincs kijelolt quest, a panel egy utvonalat mutat a quest logbol
--    (mindig a legkozelebbi kovetkezo allomas) es a kozelben felveheto questeket.

local _, NS = ...
local L = NS.L
local state = NS.state

local DEFAULT_KILL_TIME = 45   -- mp/kill, amig nincs sajat meres
local MAX_GAP = 900            -- ennel hosszabb (15 perc) kihagyas szunetnek szamit, nem keresesnek
local ROUTE_LEN = 5
local PICKUP_LEN = 3

---------------------------------------------------------------------------
-- Kill tempo
---------------------------------------------------------------------------
local lastKill, killSeen = nil, {}
local mobKills = {} -- mob nev -> kill idopontok (a kereses ideje is benne van a kozokben)

local function RecordKill(guid, name)
    if not guid or killSeen[guid] then return end
    killSeen[guid] = true
    local now = GetTime()
    if name and name ~= "" then
        local t = mobKills[name] or {}
        mobKills[name] = t
        t[#t + 1] = now
        while #t > 15 do table.remove(t, 1) end
    end
    if lastKill then
        local dt = now - lastKill
        if dt > 1 and dt < MAX_GAP then
            local db = QuestFocusDB
            db.killPace = db.killPace and (db.killPace * 0.75 + dt * 0.25) or dt
            db.killSamples = (db.killSamples or 0) + 1
        end
    end
    lastKill = now
end

local function KillPace()
    local db = QuestFocusDB or {}
    if db.killPace and (db.killSamples or 0) >= 3 then return db.killPace, false end
    return DEFAULT_KILL_TIME, true
end

---------------------------------------------------------------------------
-- Objective tempo (mikor nott a Collected)
---------------------------------------------------------------------------
local progress = {} -- key -> { last = n, hits = { t1, t2, ... } }

local function ObjKey(qid, o)
    return tostring(qid) .. ":" .. tostring(o.Type) .. ":" .. tostring(o.Id or o.Description)
end

local ShowToast -- lent

local function ScanProgress()
    local now = GetTime()
    for i = 1, NS.NumLogEntries() do
        local title, isHeader, qid = NS.GetLogEntry(i)
        if not isHeader and qid then
            local q = NS.GetQuestieQuest(qid)
            if q and type(q.Objectives) == "table" then
                for _, o in pairs(q.Objectives) do
                    local c = type(o) == "table" and tonumber(o.Collected)
                    if c then
                        local key = ObjKey(qid, o)
                        local p = progress[key]
                        if not p then
                            progress[key] = { last = c, hits = {} }
                        elseif c > p.last then
                            for _ = 1, math.min(c - p.last, 10) do p.hits[#p.hits + 1] = now end
                            while #p.hits > 12 do table.remove(p.hits, 1) end
                            p.last = c
                            if ShowToast then ShowToast(qid, title, o) end
                        else
                            p.last = c
                        end
                    end
                end
            end
        end
    end
end

-- Idopontok listajabol: atlagos koz (szunetek nelkul), kozok szama, utolso idopont.
-- Ha az utolso ota mar tobb ido telt el, mint az atlag (most is keresed), az is beleszamit:
-- a becsles lassu keresesnel menet kozben no.
local function PaceFromTimes(times, minN)
    if not times or #times < 2 then return end
    local sum, n = 0, 0
    for i = 2, #times do
        local dt = times[i] - times[i - 1]
        if dt > 0.5 and dt < MAX_GAP then sum, n = sum + dt, n + 1 end
    end
    if n < (minN or 2) then return end
    local avg, last = sum / n, times[#times]
    local since = GetTime() - last
    if since > avg and since < MAX_GAP then avg = (sum + since) / (n + 1) end
    return avg, n, since
end

-- Objective tempo: a quest szamlalo novekedesei kozti ido (kereses + kill + drop egyutt)
local function ObjPace(key)
    local p = progress[key]
    return PaceFromTimes(p and p.hits, 2)
end

-- Mob tempo: az objective mobjainak killjei kozti ido (keresessel egyutt)
local function MobPace(o)
    local all = {}
    for _, s in ipairs(o.sources or {}) do
        if s.isNpc and s.name and mobKills[s.name] then
            for _, t in ipairs(mobKills[s.name]) do all[#all + 1] = t end
        end
    end
    if #all < 3 then return end
    table.sort(all)
    return PaceFromTimes(all, 2)
end

local function BestDropRate(o)
    if not o.itemId then return end
    local DB = NS.Module("QuestieDB")
    if not (DB and type(DB.GetItemDroprate) == "function") then return end
    local best
    for _, s in ipairs(o.sources or {}) do
        if s.isNpc then
            local ok, rate = pcall(DB.GetItemDroprate, o.itemId, s.id)
            if ok and type(rate) == "table" then rate = rate[1] end
            rate = tonumber(rate)
            if rate and rate > 0 and (not best or rate > best) then best = rate end
        end
    end
    return best
end

-- Visszaad: mp, info tabla { how = "pace"|"kills", guess = bool, kills, rate, per }
local function EtaSeconds(o)
    if not o or o.completed or o.turnIn or not o.qo then return end
    local c, n = tonumber(o.qo.Collected), tonumber(o.qo.Needed)
    if not (c and n) or n <= c then return end
    local remaining = n - c
    -- 1) a sajat haladasod ezen az objective-en (legpontosabb)
    local per, _, since = nil, nil, nil
    if o.qid then per, _, since = ObjPace(ObjKey(o.qid, o.qo)) end
    if per then
        -- a mostani egyseg mar 'since' ideje tart
        local eta = (remaining - 1) * per + math.max(per - (since or 0), 0)
        return eta, { how = "pace", per = per, remaining = remaining }
    end
    -- 2) ennek a mobnak a killjei kozti ido (keresessel), 3) altalanos kill tempo, 4) alap
    local pace, guess, how = MobPace(o), false, "mob"
    if not pace then pace, guess = KillPace(); how = "kills" end
    local t = o.qo.Type
    if t == "monster" or t == "killcredit" then
        return remaining * pace, { how = how, kills = remaining, per = pace, guess = guess }
    elseif t == "item" then
        local rate = BestDropRate(o)
        if rate then
            local kills = math.ceil(remaining * 100 / math.min(rate, 100))
            return kills * pace, { how = how, kills = kills, rate = rate, per = pace, guess = guess }
        end
    end
end

local function FmtSec(s)
    s = math.floor(s + 0.5)
    if s >= 60 then return ("%dm%02ds"):format(math.floor(s / 60), s % 60) end
    return ("%ds"):format(s)
end

-- PACE doboz: a kijelolt quest elso hatralevo objective-jenek tempoja (keresessel egyutt)
NS.PaceText = function(objectives)
    for _, o in ipairs(objectives or {}) do
        if not o.completed and not o.turnIn and o.qo then
            local per = o.qid and ObjPace(ObjKey(o.qid, o.qo))
            if per then return FmtSec(per) .. " / " .. L["each"] end
            per = MobPace(o)
            if per then return FmtSec(per) .. " / " .. L["kill"] end
            break
        end
    end
    local pace, guess = KillPace()
    if guess then return "|cff808080" .. L["no data"] .. "|r" end
    return FmtSec(pace) .. " / " .. L["kill"]
end

local function FormatTime(sec)
    if sec < 60 then return L["<1m"] end
    local m = math.floor(sec / 60 + 0.5)
    if m < 60 then return ("~%dm"):format(m) end
    return ("~%dh %dm"):format(math.floor(m / 60), m % 60)
end

NS.EtaShort = function(o)
    local sec, info = EtaSeconds(o)
    if not sec then return end
    return FormatTime(sec) .. (info.guess and "?" or "")
end

NS.EtaLine = function(o)
    local sec, info = EtaSeconds(o)
    if not sec then return end
    local txt = L["Time left: "] .. FormatTime(sec)
    if info.how == "pace" then
        txt = txt .. (L[" (your pace on this: 1 every %s, searching included)"]):format(FmtSec(info.per))
    elseif info.rate then
        txt = txt .. (L[" (~%d kills at %s%% drop, %s/kill)"]):format(info.kills,
            info.rate >= 10 and ("%d"):format(info.rate) or ("%.1f"):format(info.rate), FmtSec(info.per))
    else
        txt = txt .. (L[" (%d kills, %s/kill)"]):format(info.kills, FmtSec(info.per))
    end
    if info.how == "mob" then txt = txt .. L[" - time between your kills of this mob, searching included"] end
    if info.guess then txt = txt .. L[" - estimated, no kill data yet"] end
    return txt
end

NS.QuestEta = function(objectives)
    local total, any, guess = 0, false, false
    for _, o in ipairs(objectives or {}) do
        local sec, info = EtaSeconds(o)
        if sec then total, any, guess = total + sec, true, guess or info.guess end
    end
    if any then return FormatTime(total) .. (guess and "?" or "") end
end

---------------------------------------------------------------------------
-- Haladas toast: kis felugro ablak a panel folott, ha nott egy objective
---------------------------------------------------------------------------
local toast = CreateFrame("Frame", "QuestFocusToast", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
toast:SetSize(250, 48)
toast:SetFrameStrata("MEDIUM")
toast:Hide()
if toast.SetBackdrop then
    toast:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    toast:SetBackdropColor(0.04, 0.04, 0.06, 0.92)
    toast:SetBackdropBorderColor(0.95, 0.78, 0.40, 0.9)
end
local accent = toast:CreateTexture(nil, "ARTWORK")
accent:SetPoint("TOPLEFT", 4, -4)
accent:SetPoint("BOTTOMLEFT", 4, 4)
accent:SetWidth(2)
accent:SetColorTexture(0.95, 0.78, 0.40, 1)
toast.label = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
toast.label:SetPoint("TOPLEFT", 12, -7)
toast.label:SetTextColor(0.95, 0.78, 0.40)
toast.label:SetWidth(170)
toast.label:SetJustifyH("LEFT")
toast.label:SetWordWrap(false)
toast.right = toast:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
toast.right:SetPoint("TOPRIGHT", -9, -7)
toast.icon = toast:CreateTexture(nil, "ARTWORK")
toast.icon:SetSize(18, 18)
toast.icon:SetPoint("BOTTOMLEFT", 12, 7)
toast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
toast.text:SetPoint("LEFT", toast.icon, "RIGHT", 6, 0)
toast.text:SetPoint("RIGHT", -9, 0)
toast.text:SetJustifyH("LEFT")
toast.text:SetWordWrap(false)

local TOAST_HOLD, TOAST_FADE = 3.5, 0.6
NS.ToastFrame = toast -- a buff emlekezteto megvarja, amig ez eltunik
local toastQueue = {} -- egyszerre tobb quest haladasa: egymas utan jonnek
toast:SetScript("OnUpdate", function(self, dt)
    self.t = (self.t or 0) + dt
    local hold = #toastQueue > 0 and 2 or TOAST_HOLD -- ha var meg valami, rovidebben
    if self.t > hold + TOAST_FADE then
        self:Hide()
        local nxt = table.remove(toastQueue, 1)
        if nxt then ShowToast(nxt[1], nxt[2], nxt[3], true) end
    elseif self.t > hold then
        self:SetAlpha(1 - (self.t - hold) / TOAST_FADE)
    end
end)

ShowToast = function(qid, title, o, fromQueue)
    if QuestFocusDB.noToast then return end
    -- Ha mar latszik egy (masik questhez), ez sorba all
    if not fromQueue and toast:IsShown() and toast.qo ~= o then
        for _, q in ipairs(toastQueue) do if q[3] == o then return end end
        toastQueue[#toastQueue + 1] = { qid, title, o }
        return
    end
    toast.qo = o
    -- A kijelolt quest objective-jeiben megvannak a forrasok is (drop rate-hez)
    local entry
    if state.questId == qid then
        for _, e in ipairs(state.objectives or {}) do if e.qo == o then entry = e end end
    end
    entry = entry or { qo = o, qid = qid, itemId = o.Type == "item" and o.Id or nil, sources = {} }
    local c, n = tonumber(o.Collected) or 0, tonumber(o.Needed) or 0
    local desc = tostring(o.Description or o.Text or "?")
    local done = n > 0 and c >= n
    toast.label:SetText((done and L["OBJECTIVE COMPLETE"] or L["QUEST PROGRESS"])
        .. (title and ("  |cffd8c8a0" .. title .. "|r") or ""))
    local sec = not done and EtaSeconds(entry)
    toast.right:SetText(sec and (FormatTime(sec) .. L[" left"]) or "")
    toast.text:SetText((done and "|cff33ff99" or "|cffffffff") .. desc .. "|r  |cffffd100" .. ("%d/%d"):format(c, n) .. "|r")
    local tex = o.Type == "item" and o.Id and GetItemIcon and GetItemIcon(o.Id)
    toast.icon:SetTexture(tex or "Interface\\Icons\\Ability_Hunter_SniperShot")
    toast:ClearAllPoints()
    -- A panel folott (ha a buff emlekezteto kint van, afolott)
    if NS.BuffAlertFrame and NS.BuffAlertFrame:IsShown() then
        toast:SetPoint("BOTTOMRIGHT", NS.BuffAlertFrame, "TOPRIGHT", 0, 4)
    elseif NS.panel:IsShown() then
        toast:SetPoint("BOTTOMRIGHT", NS.panel, "TOPRIGHT", 0, 4)
    else
        toast:SetPoint("TOP", UIParent, "TOP", 0, -190)
    end
    toast.t = 0
    toast:SetAlpha(1)
    toast:Show()
end

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
local function BuildRoute(pc, px, py)
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
    while #route < ROUTE_LEN and #stops > 0 do
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

---------------------------------------------------------------------------
-- Kozeli felveheto quest kisablak: kozepen felul, a progress alatt. Kattintasra
-- marker (TomTom nyil) a quest adora. Questenkent egyszer szol egy jatekmenetben.
---------------------------------------------------------------------------
local NEARBY_RADIUS = 300
local qpop = CreateFrame("Button", "QuestFocusQuestPopup", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
qpop:SetSize(270, 50)
qpop:SetFrameStrata("MEDIUM")
qpop:RegisterForClicks("LeftButtonUp")
qpop:Hide()
if qpop.SetBackdrop then
    qpop:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    qpop:SetBackdropColor(0.04, 0.04, 0.06, 0.92)
    qpop:SetBackdropBorderColor(0.95, 0.78, 0.40, 0.9)
end
local qAccent = qpop:CreateTexture(nil, "ARTWORK")
qAccent:SetPoint("TOPLEFT", 4, -4)
qAccent:SetPoint("BOTTOMLEFT", 4, 4)
qAccent:SetWidth(2)
qAccent:SetColorTexture(1, 0.82, 0, 1)
qpop.label = qpop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
qpop.label:SetPoint("TOPLEFT", 12, -7)
qpop.label:SetTextColor(1, 0.82, 0)
qpop.label:SetText(L["QUEST NEARBY"])
qpop.right = qpop:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
qpop.right:SetPoint("TOPRIGHT", -24, -7)
qpop.icon = qpop:CreateTexture(nil, "ARTWORK")
qpop.icon:SetSize(18, 18)
qpop.icon:SetPoint("BOTTOMLEFT", 12, 8)
qpop.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
qpop.text = qpop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
qpop.text:SetPoint("LEFT", qpop.icon, "RIGHT", 6, 0)
qpop.text:SetPoint("RIGHT", -9, 0)
qpop.text:SetJustifyH("LEFT")
qpop.text:SetWordWrap(false)
local qClose = CreateFrame("Button", nil, qpop, "UIPanelCloseButton")
qClose:SetSize(20, 20)
qClose:SetPoint("TOPRIGHT", -2, -2)
qClose:SetScript("OnClick", function() qpop:Hide() end)
local qhl = qpop:CreateTexture(nil, "HIGHLIGHT")
qhl:SetAllPoints()
qhl:SetColorTexture(1, 1, 1, 0.06)

local QPOP_HOLD, QPOP_FADE = 10, 1
qpop:SetScript("OnUpdate", function(self, dt)
    if self:IsMouseOver() then self.t = 0; self:SetAlpha(1) return end -- egerrel folotte nem tunik el
    self.t = (self.t or 0) + dt
    if self.t > QPOP_HOLD + QPOP_FADE then
        self:Hide()
    elseif self.t > QPOP_HOLD then
        self:SetAlpha(1 - (self.t - QPOP_HOLD) / QPOP_FADE)
    end
end)
qpop:SetScript("OnClick", function(self)
    local d = self.data
    if not d then return end
    NS.SetWaypoint(d.point, d.point.name or d.name)
    if state.waypoint then state.waypoint.giver = d.qid end
    NS.Print(L["Marker: quest giver |cffffff00%s|r for %s"], d.point.name or "?", d.name or "?")
    self:Hide()
end)
qpop:SetScript("OnEnter", function(self)
    local d = self.data
    if not d then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(("[%s] %s"):format(tostring(d.level or "?"), d.name or "?"), 1, 1, 1)
    GameTooltip:AddLine((L["Quest giver: %s"]):format(d.point.name or "?"), 1, 0.82, 0)
    GameTooltip:AddLine(("%s %.1f, %.1f"):format(NS.ZoneName(d.point.map), d.point.x, d.point.y), 0.6, 0.8, 1)
    GameTooltip:AddLine(L["Length is a rough estimate (objective types, drop rate, your kill pace)."], 0.6, 0.6, 0.6, true)
    GameTooltip:AddLine(L["Click: marker (TomTom arrow) on the quest giver"], 0.5, 0.5, 0.5)
    GameTooltip:Show()
end)
qpop:SetScript("OnLeave", function() GameTooltip:Hide() end)

local announced = {} -- qid -> true: errol mar szoltunk ebben a jatekmenetben

local function ShowQuestPopup(d)
    local col = GetQuestDifficultyColor and d.level and GetQuestDifficultyColor(d.level)
    local hex = col and ("|cff%02x%02x%02x"):format(col.r * 255, col.g * 255, col.b * 255) or "|cffffffff"
    local est = EstimateQuestTime(d.quest)
    qpop.data = d
    qpop.right:SetText(("|cff99ccff%d yd|r"):format(d.dist + 0.5))
    qpop.text:SetText(("%s[%s] %s|r  |cff999999%s %s|r"):format(hex, tostring(d.level or "?"), d.name or "?",
        FormatTime(est), L["est."]))
    qpop:ClearAllPoints()
    -- kozepen felul, a jatek sajat kiirasai alatt
    if UIErrorsFrame and UIErrorsFrame:IsShown() and UIErrorsFrame:GetBottom() then
        qpop:SetPoint("TOP", UIErrorsFrame, "BOTTOM", 0, -6)
    else
        qpop:SetPoint("TOP", UIParent, "TOP", 0, -190)
    end
    qpop.t = 0
    qpop:SetAlpha(1)
    qpop:Show()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN then PlaySound(SOUNDKIT.IG_QUEST_LIST_OPEN) end
end

---------------------------------------------------------------------------
-- Utazas: gyalog / Hearthstone / repules ido a markerig
-- A HS helyet a jatek nem adja meg (csak a nevet: GetBindLocation), ezert megtanuljuk:
-- bindolaskor (az innkeepernel allsz) es HS-elés utan erkezeskor elmentjuk a poziciot.
---------------------------------------------------------------------------
local HS_ITEM, HS_CAST, FLY_SPEED = 6948, 10, 25 -- repules: legvonalban ~25 yd/mp (kerulokkel)

local function Speed()
    local _, run = GetUnitSpeed("player")
    return math.max(tonumber(run) or 7, 7)
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

---------------------------------------------------------------------------
-- Varos mod: varosban / fogadoban (IsResting) nem popupol questenkent, hanem egy listaban
-- mutatja az osszes felveheto questet. Belepeskor jon fel, kilepeskor eltunik.
---------------------------------------------------------------------------
local CITY_RADIUS, CITY_MAX = 600, 12
local city = CreateFrame("Frame", "QuestFocusCityList", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
city:SetSize(330, 80)
city:SetPoint("TOP", UIParent, "TOP", 0, -190)
city:SetFrameStrata("MEDIUM")
city:EnableMouse(true)
city:SetMovable(true)
city:SetClampedToScreen(true)
city:RegisterForDrag("LeftButton")
city:SetScript("OnDragStart", city.StartMoving)
city:SetScript("OnDragStop", city.StopMovingOrSizing)
city:Hide()
if city.SetBackdrop then
    city:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 20,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    city:SetBackdropColor(0.04, 0.04, 0.06, 0.93)
    city:SetBackdropBorderColor(0.95, 0.78, 0.40, 1)
end
city.icon = city:CreateTexture(nil, "ARTWORK")
city.icon:SetSize(20, 20)
city.icon:SetPoint("TOPLEFT", 12, -11)
city.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
city.title = city:CreateFontString(nil, "OVERLAY", "GameFontNormal")
city.title:SetPoint("LEFT", city.icon, "RIGHT", 6, 0)
city.title:SetTextColor(1, 0.86, 0.5)
local cClose = CreateFrame("Button", nil, city, "UIPanelCloseButton")
cClose:SetSize(24, 24)
cClose:SetPoint("TOPRIGHT", -4, -4)
cClose:SetScript("OnClick", function() city.closedHere = true; city:Hide() end)
city.foot = city:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
city.foot:SetText(L["Click: marker on the quest giver. Drag to move."])

local cityRows = {}
local function CityRow(i)
    local r = cityRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, city)
    r:SetSize(306, 18)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT")
    r.text:SetPoint("RIGHT", -70, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT")
    r.right:SetJustifyH("RIGHT")
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    r:SetScript("OnClick", function(self)
        local d = self.data
        if not d then return end
        NS.SetWaypoint(d.point, d.point.name or d.name)
        if state.waypoint then state.waypoint.giver = d.qid end
        NS.Print(L["Marker: quest giver |cffffff00%s|r for %s"], d.point.name or "?", d.name or "?")
    end)
    r:SetScript("OnEnter", function(self)
        local d = self.data
        if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(("[%s] %s"):format(tostring(d.level or "?"), d.name or "?"), 1, 1, 1)
        GameTooltip:AddLine((L["Quest giver: %s"]):format(d.point.name or "?"), 1, 0.82, 0)
        GameTooltip:AddLine(("%s %.1f, %.1f"):format(NS.ZoneName(d.point.map), d.point.x, d.point.y), 0.6, 0.8, 1)
        GameTooltip:AddLine(L["Click: marker (TomTom arrow) on the quest giver"], 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cityRows[i] = r
    return r
end

local function InCity() return IsResting and IsResting() end
NS.InCity = function() return InCity() and not QuestFocusDB.noCityMode end

local function RefreshCityList()
    if QuestFocusDB.noCityMode or not NS.QuestieAvailable() then city:Hide() return end
    local pc, px, py = NS.PlayerWorldPos()
    if not pc then return end
    local ok, list = pcall(BuildPickups, pc, px, py, 30)
    if not ok or not list then return end
    for _, r in ipairs(cityRows) do r:Hide() end
    local y, n = -38, 0
    for _, d in ipairs(list) do
        if d.dist > CITY_RADIUS or n >= CITY_MAX then break end
        n = n + 1
        if announced then announced[d.qid] = true end -- kint mar ne popupoljon
        local r = CityRow(n)
        r.data = d
        local col = GetQuestDifficultyColor and d.level and GetQuestDifficultyColor(d.level)
        local hex = col and ("|cff%02x%02x%02x"):format(col.r * 255, col.g * 255, col.b * 255) or "|cffffffff"
        r.text:SetText(("%s[%s] %s|r  |cff999999%s|r"):format(hex, tostring(d.level or "?"), d.name or "?",
            FormatTime(EstimateQuestTime(d.quest))))
        r.right:SetText(("|cff99ccff%d yd|r"):format(d.dist + 0.5))
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", city, "TOPLEFT", 12, y)
        r:Show()
        y = y - 19
    end
    if n == 0 then city:Hide() return end
    city.title:SetText((L["Quests to pick up here (%d)"]):format(n))
    city.foot:ClearAllPoints()
    city.foot:SetPoint("TOPLEFT", city, "TOPLEFT", 14, y - 4)
    city:SetHeight(-y + 26)
    if not city:IsShown() and not city.closedHere then city:Show() end
end

local cityEv = CreateFrame("Frame")
cityEv:RegisterEvent("PLAYER_UPDATE_RESTING")
cityEv:RegisterEvent("PLAYER_ENTERING_WORLD")
cityEv:SetScript("OnEvent", function()
    C_Timer.After(2, function()
        if InCity() then
            RefreshCityList()
        else
            city.closedHere = nil -- kovetkezo varosban ujra feljon
            city:Hide()
        end
        NS.Panel_Update() -- varos mod ki/be: statisztika dobozok
    end)
end)

-- Frissites, amig kint van (mozgas kozben valtozik a tavolsag, kozben felvett quest kikerul)
local cityElapsed = 0
city:SetScript("OnUpdate", function(_, dt)
    cityElapsed = cityElapsed + dt
    if cityElapsed < 5 then return end
    cityElapsed = 0
    if not InCity() and not city.forced then city:Hide() return end
    if not city:IsMouseOver() then RefreshCityList() end
end)
city:HookScript("OnHide", function() city.forced = nil end)
-- /qf city: kezzel is megnyithato (varoson kivul is)
NS.ShowCityList = function() city.closedHere = nil; city.forced = not InCity() or nil; RefreshCityList() end

local qpopTicker = CreateFrame("Frame")
local qpopElapsed = 0
qpopTicker:SetScript("OnUpdate", function(_, dt)
    qpopElapsed = qpopElapsed + dt
    if qpopElapsed < 5 then return end
    qpopElapsed = 0
    -- varosban nincs egyenkenti popup (ott a lista van)
    if InCity() and not QuestFocusDB.noCityMode then return end
    if QuestFocusDB.noQuestPopup or InCombatLockdown() or qpop:IsShown() or not NS.QuestieAvailable() then return end
    local pc, px, py = NS.PlayerWorldPos()
    if not pc then return end
    local ok, list = pcall(BuildPickups, pc, px, py, 10)
    if not ok or not list then return end
    for _, d in ipairs(list) do
        if d.dist > NEARBY_RADIUS then break end
        if not announced[d.qid] then
            announced[d.qid] = true
            ShowQuestPopup(d)
            return
        end
    end
end)

---------------------------------------------------------------------------
-- Panel sorok
---------------------------------------------------------------------------
local panel = NS.panel
local rows = {}

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, panel)
    r:SetSize(276, 16)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetAllPoints()
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    r:SetScript("OnClick", function(self)
        local d = self.data
        if not d then return end
        if d.kind == "route" then
            NS.SelectQuest(d.qid, d.title, d.done, true)
        elseif d.kind == "pickup" then
            NS.SetWaypoint(d.point, d.point.name or d.name)
            if state.waypoint then state.waypoint.giver = d.qid end
            NS.Print(L["Marker: quest giver |cffffff00%s|r for %s"], d.point.name or "?", d.name or "?")
        end
    end)
    r:SetScript("OnEnter", function(self)
        local d = self.data
        if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if d.kind == "route" then
            GameTooltip:SetText(d.title or "?", 1, 1, 1)
            NS.AddQuestTooltip(GameTooltip, d.qid, d.done)
            GameTooltip:AddLine(L["Click: select this quest (marker + QFocus macro)"], 0.5, 0.5, 0.5)
        else
            GameTooltip:SetText(("[%s] %s"):format(tostring(d.level or "?"), d.name or "?"), 1, 1, 1)
            GameTooltip:AddLine((L["Quest giver: %s"]):format(d.point.name or "?"), 1, 0.82, 0)
            GameTooltip:AddLine(("%s %.1f, %.1f"):format(NS.ZoneName(d.point.map), d.point.x, d.point.y), 0.6, 0.8, 1)
            GameTooltip:AddLine(L["Click: marker on the quest giver"], 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

local function Header(text)
    if not panel.sugHeaders then panel.sugHeaders = {} end
    local h = panel.sugHeaders[text]
    if not h then
        h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetJustifyH("LEFT")
        h:SetText(text)
        h:SetTextColor(0.75, 0.65, 0.45)
        panel.sugHeaders[text] = h
    end
    return h
end

NS.HideSuggestions = function()
    for _, r in ipairs(rows) do r:Hide() end
    for _, h in pairs(panel.sugHeaders or {}) do h:Hide() end
end

local function YdText(d)
    return d and ("|cff99ccff%d yd|r"):format(d) or ""
end

NS.ShowSuggestions = function()
    NS.HideSuggestions()
    if QuestFocusDB.noSuggest then return false end
    panel.title:SetText(L["What next?"])
    local y = NS.PanelChrome("list")
    if not NS.QuestieAvailable() then
        panel.sub:SetText("")
        panel.footer:SetText(L["Questie is not loaded."])
        NS.PanelFinish(y)
        return true
    end
    local pc, px, py = NS.PlayerWorldPos()
    local route, pickups = {}, {}
    if pc then
        route = BuildRoute(pc, px, py)
        pickups = BuildPickups(pc, px, py)
    end
    panel.sub:SetText((L["%d on the route, %d to pick up"]):format(#route, #pickups))

    local n = 0
    local function place(fs)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)
        fs:Show()
        y = y - 15
    end

    if #route > 0 then
        place(Header(L["Route (quest log):"]))
        for i, s in ipairs(route) do
            n = n + 1
            local r = Row(n)
            r.data = { kind = "route", qid = s.qid, title = s.title, done = s.done }
            local name = s.done and ("|cffffff00" .. L["Turn in: "] .. "|r" .. (s.title or "?")) or (s.title or "?")
            local leg = (i == 1 and "" or "+") .. YdText(s.leg and math.floor(s.leg + 0.5))
            local eta = not s.done and NS.QuestEta(s.objs)
            r.text:SetText(("%d. %s  %s%s"):format(i, name, leg, eta and ("  |cff999999" .. eta .. "|r") or ""))
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
            r:Show()
            y = y - 16
        end
        y = y - 4
    end
    if #pickups > 0 then
        place(Header(L["Pick up nearby:"]))
        for _, p in ipairs(pickups) do
            n = n + 1
            local r = Row(n)
            r.data = { kind = "pickup", qid = p.qid, name = p.name, level = p.level, point = p.point }
            local col = GetQuestDifficultyColor and p.level and GetQuestDifficultyColor(p.level)
            local hex = col and ("|cff%02x%02x%02x"):format(col.r * 255, col.g * 255, col.b * 255) or "|cffffffff"
            r.text:SetText(("%s[%s] %s|r  %s"):format(hex, tostring(p.level or "?"), p.name or "?",
                YdText(p.dist and math.floor(p.dist + 0.5))))
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
            r:Show()
            y = y - 16
        end
    end

    if n == 0 then
        panel.footer:SetText(pc and L["Nothing nearby. Select a quest in the quest log (L)."]
            or L["Position unknown here (instance?)."])
    else
        panel.footer:SetText(L["Click a row. Pick a quest in the log (L) to focus it."])
    end
    NS.PanelFinish(y)
    return true
end

-- Javaslatok frissitese, amig latszanak (mozgas kozben valtozik a sorrend)
local sugElapsed = 0
panel:HookScript("OnUpdate", function(_, dt)
    if state.questId or QuestFocusDB.noSuggest then return end
    sugElapsed = sugElapsed + dt
    if sugElapsed < 3 then return end
    sugElapsed = 0
    if not panel:IsMouseOver() then NS.ShowSuggestions() end
end)

---------------------------------------------------------------------------
-- Esemenyek
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
-- A combat logra feliratkozas ezen a kliensen tiltott addonoknak (ADDON_ACTION_FORBIDDEN),
-- ezert a killeket az XP uzenetbol szamoljuk ("X dies, you gain N experience").
ev:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:RegisterEvent("QUEST_ACCEPTED")
ev:RegisterEvent("PLAYER_LOGIN")
local scanPending = false
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "CHAT_MSG_COMBAT_XP_GAIN" then
        -- Csak a kill XP szamit (quest leadas / felfedezes XP nem): a szoveg "dies"-t tartalmaz
        pcall(function()
            if type(arg1) == "string" and arg1:find(" dies", 1, true) then
                RecordKill("xp" .. GetTime(), arg1:match("^(.-) dies"))
            end
        end)
    elseif event == "QUEST_LOG_UPDATE" then
        -- A Questie a sajat esemenyere frissiti a Collected ertekeket: kicsit kesobb nezzuk
        if scanPending then return end
        scanPending = true
        C_Timer.After(1.5, function()
            scanPending = false
            ScanProgress()
            if not state.questId and NS.panel:IsShown() then NS.ShowSuggestions() end
        end)
    elseif event == "QUEST_ACCEPTED" then
        if state.waypoint and state.waypoint.giver and not state.questId then NS.ClearWaypoint() end
    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(10, ScanProgress)
    end
end)

-- A killSeen ne nojon vegtelenre
C_Timer.NewTicker(600, function() wipe(killSeen) end)

---------------------------------------------------------------------------
-- Kapcsolo a beallitasokban
---------------------------------------------------------------------------
local pagePanel = NS.AddOptionsTab(L["Panel"])
local cbSuggest = NS.OptCheck(L["Suggest quests when none is selected"],
    L["With no quest selected the panel shows a route through your quest log (nearest next stop each time) "]
    .. L["and nearby quests you can pick up."],
    function() return not QuestFocusDB.noSuggest end,
    function(v)
        QuestFocusDB.noSuggest = not v
        NS.Panel_Update()
    end, pagePanel)
cbSuggest:SetPoint("TOPLEFT", pagePanel, "TOPLEFT", -2, 0)

local cbToast = NS.OptCheck(L["Progress popup"],
    L["A small popup above the panel for a few seconds when an objective progresses, with the estimated time left."],
    function() return not QuestFocusDB.noToast end,
    function(v) QuestFocusDB.noToast = not v end, pagePanel)
cbToast:SetPoint("TOPLEFT", cbSuggest, "BOTTOMLEFT", 0, -6)

local cbNearby = NS.OptCheck(L["Also target mobs of other nearby quests"],
    L["Mobs of other quests in your log that are within ~200 yards are added to the QFocus macro, "]
    .. L["and listed on the panel under ALSO NEARBY (click one to focus that quest)."],
    function() return not QuestFocusDB.noNearbyQuests end,
    function(v)
        QuestFocusDB.noNearbyQuests = not v
        if not v then state.extra = nil end
        NS.Panel_Update()
    end, pagePanel)
cbNearby:SetPoint("TOPLEFT", cbToast, "BOTTOMLEFT", 0, -6)

local cbQPop = NS.OptCheck(L["Popup for quests you can pick up nearby"],
    L["When a quest you can pick up is within ~300 yards, a popup shows its level, an estimated length and the distance. "]
    .. L["Click it for a marker (TomTom arrow) on the quest giver. Each quest only once per session."],
    function() return not QuestFocusDB.noQuestPopup end,
    function(v) QuestFocusDB.noQuestPopup = not v end, pagePanel)
cbQPop:SetPoint("TOPLEFT", cbNearby, "BOTTOMLEFT", 0, -6)

-- Szintsav a felveheto questekhez (javaslatok + kisablak)
local lvlLabel = pagePanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
lvlLabel:SetPoint("TOPLEFT", cbQPop, "BOTTOMLEFT", 32, -8)
lvlLabel:SetText(L["Quest level: your level minus"])
local function LvlBox(key, default, anchor)
    local b = CreateFrame("EditBox", nil, pagePanel, "InputBoxTemplate")
    b:SetSize(28, 18)
    b:SetAutoFocus(false)
    b:SetNumeric(true)
    b:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
    b:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v then QuestFocusDB[key] = v end
        self:SetText(tonumber(QuestFocusDB[key]) or default)
        self:ClearFocus()
    end)
    b:SetScript("OnEscapePressed", function(self) self:SetText(tonumber(QuestFocusDB[key]) or default); self:ClearFocus() end)
    b.refresh = function() b:SetText(tonumber(QuestFocusDB[key]) or default) end
    return b
end
local belowBox = LvlBox("pickupBelow", 2, lvlLabel)
local lvlMid = pagePanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
lvlMid:SetPoint("LEFT", belowBox, "RIGHT", 6, 0)
lvlMid:SetText(L["... plus"])
local aboveBox = LvlBox("pickupAbove", 10, lvlMid)

local cbCity = NS.OptCheck(L["City mode"],
    L["In a city or inn (resting): no popup per quest, one list of every quest you can pick up nearby instead, "]
    .. L["and the panel boxes show distance / travel time / best way (walk, Hearthstone, flight) instead."],
    function() return not QuestFocusDB.noCityMode end,
    function(v)
        QuestFocusDB.noCityMode = not v
        if v then NS.ShowCityList() end
        NS.Panel_Update()
    end, pagePanel)
cbCity:SetPoint("TOPLEFT", lvlLabel, "BOTTOMLEFT", -32, -8)

local etaNote = pagePanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
etaNote:SetPoint("TOPLEFT", cbCity, "BOTTOMLEFT", 2, -12)
etaNote:SetWidth(520)
etaNote:SetJustifyH("LEFT")
etaNote:SetText(L["Time left is learned from your own pace: how fast each objective counter grew, otherwise "]
    .. L["the time between your kills combined with the Questie drop rate. A '?' means there is no kill data yet."])

local resetPace = CreateFrame("Button", nil, pagePanel, "UIPanelButtonTemplate")
resetPace:SetSize(160, 22)
resetPace:SetPoint("TOPLEFT", etaNote, "BOTTOMLEFT", -2, -10)
resetPace:SetText(L["Reset kill pace"])
resetPace:SetScript("OnClick", function()
    QuestFocusDB.killPace, QuestFocusDB.killSamples = nil, nil
    wipe(progress)
    wipe(mobKills)
    NS.Print(L["Kill pace reset."])
end)
NS.opt:HookScript("OnShow", function()
    cbSuggest.refresh(); cbToast.refresh(); cbNearby.refresh(); cbQPop.refresh(); cbCity.refresh()
    belowBox.refresh(); aboveBox.refresh()
end)
