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

local function ShowToastFwd(...) if NS.ShowToast then return NS.ShowToast(...) end end -- Planner\Toast.lua

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
                            ShowToastFwd(qid, title, o)
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


-- belso exportok a tobbi core fajlnak
NS.P = NS.P or {}
NS.P.EtaSeconds, NS.P.FormatTime, NS.P.KillPace, NS.P.PICKUP_LEN, NS.P.ROUTE_LEN, NS.P.RecordKill, NS.P.ScanProgress, NS.P.killSeen = EtaSeconds, FormatTime, KillPace, PICKUP_LEN, ROUTE_LEN, RecordKill, ScanProgress, killSeen
NS.P.mobKills, NS.P.progress, NS.P.state = mobKills, progress, state
