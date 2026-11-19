-- Debug szekciok: minden funkcionak sajat debug resze (pillanatkep + elo naplo).
--   NS.Debug(key, fmt, ...)       naplosor, csak ha a szekcio naploja be van kapcsolva
--   NS.DebugOn(key)               be van-e kapcsolva (draga argumentumok elott ezzel ellenorizz)
--   NS.DebugSnapshot(key, fn)     pillanatkep sorok: fn(out) a listaba ir (out[#out + 1] = ...)
--   NS.DebugText(key) / NS.DebugTextAll()   a masolhato szoveg (fejlec + pillanatkep + naplo)
-- A kapcsolok fiokszintuek: QuestFocusDB.debugLog[key] = true. A naplo csak memoriaban van
-- (szekcionkent az utolso LOG_MAX sor), /reload utan ures.
-- Ez a fajl a Locales / Style utan, minden mas elott toltodik, igy barhonnan hivhato.
local ADDON_NAME, NS = ...

local LOG_MAX = 200

---------------------------------------------------------------------------
-- Gyuru puffer: az utolso n elem, a legregebbi esik ki. Az egymas utani azonos sorokat
-- osszevonja ("x3"), igy egy sokszor ismetlodo dontes nem szoritja ki a tobbit.
---------------------------------------------------------------------------
local Ring = {}
Ring.__index = Ring
function Ring.new(n) return setmetatable({ n = n or LOG_MAX, head = 0, count = 0, items = {} }, Ring) end
function Ring:push(time, msg)
    local last = self.count > 0 and self.items[self.head]
    if last and last.msg == msg then
        last.rep, last.time = last.rep + 1, time
        return
    end
    self.head = self.head % self.n + 1
    self.items[self.head] = { time = time, msg = msg, rep = 1 }
    if self.count < self.n then self.count = self.count + 1 end
end
-- legregebbitol a legujabbig
function Ring:list()
    local out = {}
    for i = self.count - 1, 0, -1 do
        out[#out + 1] = self.items[(self.head - 1 - i) % self.n + 1]
    end
    return out
end
function Ring:clear() self.head, self.count, self.items = 0, 0, {} end
NS.DebugRing = Ring

---------------------------------------------------------------------------
-- Szekciok (sorrend = lista sorrend az Options Debug fulen es a "Copy all"-ban)
---------------------------------------------------------------------------
local L = NS.L
local SECTIONS = {
    { key = "general", title = "General", desc = "Version, Questie, other addons, settings, Lua errors" },
    { key = "target", title = "Targeting / AKit macro", desc = "Quest, wanted mobs, nameplate pick, ping reason, target, macro" },
    { key = "marker", title = "Markers / arrow / spawns", desc = "Waypoint, own arrow, TomTom, spawn stepping" },
    { key = "route", title = "Route & travel", desc = "Quest order, ETA, travel plan, hearthstone" },
    { key = "quest", title = "Quest panel / stepping / skips", desc = "Panel state, back / next arrows, skipped quests" },
    { key = "city", title = "City list & errands", desc = "In town or not, why the city list opened or closed, errands" },
    { key = "prep", title = "Dungeon prep", desc = "Prep mode, dungeon quests, steps" },
    { key = "escort", title = "Escort", desc = "Escort quest detection, the escorted NPC" },
    { key = "buffs", title = "Buffs module", desc = "Buff slots, items, timers, learned buffs" },
    { key = "bags", title = "Bags module", desc = "Bag tiers, quest item list, bag highlight" },
    { key = "farm", title = "Farm session", desc = "Session state, counters, farm events" },
    { key = "ah", title = "AH quest items & prices", desc = "Needed items, scans, purchases, price sources" },
    { key = "zone", title = "Zone focus", desc = "Focused zone, tracked quests, zone prompts" },
}
local byKey = {}
for i, s in ipairs(SECTIONS) do
    s.order, s.snapshots, s.ring = i, {}, Ring.new(LOG_MAX)
    byKey[s.key] = s
end
NS.DEBUG_SECTIONS = SECTIONS
NS.DEBUG_LOG_MAX = LOG_MAX

NS.DebugSection = function(key) return byKey[key] end

-- Rovid kulcsok es alias-ok a /ak debug <x> / /ak copy <x> parancshoz
local ALIAS = {
    targeting = "target", macro = "target", akit = "target", markers = "marker", arrow = "marker",
    spawns = "marker", travel = "route", panel = "quest", quests = "quest", stepping = "quest",
    errands = "city", dungeon = "prep", buff = "buffs", bag = "bags", auction = "ah", prices = "ah",
    price = "ah", zones = "zone", gen = "general",
}
NS.DebugKey = function(word)
    word = word and word:lower()
    if not word or word == "" then return nil end
    if byKey[word] then return word end
    return ALIAS[word]
end

---------------------------------------------------------------------------
-- Kapcsolo + naplo
---------------------------------------------------------------------------
local function Toggles()
    local db = QuestFocusDB
    if not db then return nil end
    db.debugLog = db.debugLog or {}
    return db.debugLog
end

-- Olcso: egy tabla olvasas. Kikapcsolt naplonal a NS.Debug semmit nem formaz.
local function DebugOn(key)
    local db = QuestFocusDB
    local t = db and db.debugLog
    return t ~= nil and t[key] == true
end
NS.DebugOn = DebugOn

NS.SetDebugOn = function(key, on)
    local s, t = byKey[key], Toggles()
    if not (s and t) then return end
    t[key] = on and true or nil
end

-- Minden szekcio naploja be / ki (Options > Debug: Enable all; /ak debug all on | off)
NS.DebugAllOn = function()
    for _, s in ipairs(SECTIONS) do if not DebugOn(s.key) then return false end end
    return true
end
NS.SetDebugAll = function(on)
    for _, s in ipairs(SECTIONS) do NS.SetDebugOn(s.key, on) end
    if on then for _, s in ipairs(SECTIONS) do NS.Debug(s.key, "log switched on (all)") end end
end

local function Stamp()
    return date and date("%H:%M:%S") or "--:--:--"
end

NS.Debug = function(key, fmt, ...)
    if not DebugOn(key) then return end
    local s = byKey[key]
    if not s then return end
    local msg = fmt
    if select("#", ...) > 0 then
        local ok, r = pcall(string.format, fmt, ...)
        if ok then msg = r else
            local parts = { tostring(fmt) }
            for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
            msg = table.concat(parts, " ")
        end
    end
    s.ring:push(Stamp(), tostring(msg))
end

NS.DebugClear = function(key)
    local s = byKey[key]
    if s then s.ring:clear() end
end
NS.DebugCount = function(key)
    local s = byKey[key]
    return s and s.ring.count or 0
end

---------------------------------------------------------------------------
-- Pillanatkep + masolhato szoveg
---------------------------------------------------------------------------
NS.DebugSnapshot = function(key, fn)
    local s = byKey[key]
    if s and type(fn) == "function" then s.snapshots[#s.snapshots + 1] = fn end
end

local function PlainText(s)
    return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end
NS.DebugPlain = PlainText

-- A szekcio pillanatkep sorai (szinkodokkal; a chat ezt irja ki). Hiba eseten egy sor a hibarol.
local function SnapshotLines(key)
    local s, out = byKey[key], {}
    if not s then return out end
    for _, fn in ipairs(s.snapshots) do
        local ok, err = pcall(fn, out)
        if not ok then out[#out + 1] = "(snapshot error: " .. tostring(err) .. ")" end
    end
    if #out == 0 then out[1] = L["(nothing to show)"] end
    return out
end
NS.DebugSnapshotLines = SnapshotLines

local function LogLines(key)
    local s, out = byKey[key], {}
    if not s then return out end
    for _, e in ipairs(s.ring:list()) do
        out[#out + 1] = ("[%s] %s%s"):format(e.time, e.msg, e.rep > 1 and (" (x%d)"):format(e.rep) or "")
    end
    return out
end
NS.DebugLogLines = LogLines

local function Version()
    return (NS.Version and NS.Version()) or "?"
end

-- Egy szekcio teljes szovege. noHeader: a "Copy all" egyszer irja ki a fejlecet.
local function SectionText(key, noHeader)
    local s = byKey[key]
    if not s then return "" end
    local out = {}
    if not noHeader then
        out[#out + 1] = ("Adventurer's Kit v%s | %s"):format(Version(), date and date("%Y-%m-%d %H:%M:%S") or "?")
    end
    out[#out + 1] = ("== %s [%s] =="):format(s.title, s.key)
    for _, l in ipairs(SnapshotLines(key)) do out[#out + 1] = PlainText(l) end
    local log = LogLines(key)
    if DebugOn(key) or #log > 0 then
        out[#out + 1] = ("-- log (%s, %d lines, newest last) --"):format(DebugOn(key) and "on" or "off", #log)
        for _, l in ipairs(log) do out[#out + 1] = PlainText(l) end
    else
        out[#out + 1] = "-- log: off --"
    end
    -- a hibak szama minden szekcioban latszik (a reszletek: general)
    local errs = NS.errors and #NS.errors or 0
    if key ~= "general" and errs > 0 and not noHeader then
        out[#out + 1] = ("Lua errors: %d (/ak copy general)"):format(errs)
    end
    return table.concat(out, "\n")
end
NS.DebugText = SectionText

NS.DebugTextAll = function()
    local parts = { ("Adventurer's Kit v%s | %s | all sections"):format(Version(), date and date("%Y-%m-%d %H:%M:%S") or "?") }
    for _, s in ipairs(SECTIONS) do parts[#parts + 1] = SectionText(s.key, true) end
    return table.concat(parts, "\n\n")
end

-- Rovid kulcslista a sugohoz: "general, target, marker, ..."
NS.DebugKeyList = function()
    local k = {}
    for _, s in ipairs(SECTIONS) do k[#k + 1] = s.key end
    return table.concat(k, ", ")
end
