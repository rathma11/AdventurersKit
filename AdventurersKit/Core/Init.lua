-- QuestFocus
-- Quest kijelolesre: QFocus target macro, marker (waypoint + nyil), tooltip.
-- Az adatokat (mobok, itemek, spawn helyek, leado NPC) a Questie-bol veszi.

local ADDON_NAME, NS = ...
local L = NS.L

-- Biztonsagos item API: a globalis GetItemCount / GetItemInfo... ezen a kliensen elavult
-- atiranyitas lehet (vagy mas addon horgolja), ami "attempt to call a nil value"-t dob.
-- Elobb a C_Item valtozat, aztan a regi globalis, mindketto pcall-lal; hiba eseten alapertek.
-- A fajlok tetejen: local GetItemCount = NS.SafeItem.GetItemCount (stb.)
local function Pack(...) return { n = select("#", ...), ... } end
local function Try(names, ...)
    for _, f in ipairs(names) do
        local fn = f()
        if fn then
            local r = Pack(pcall(fn, ...))
            if r[1] then return unpack(r, 2, r.n) end
        end
    end
end
local CI = function(k) return function() return C_Item and C_Item[k] end end
local G = function(k) return function() return _G[k] end end
NS.SafeItem = {
    GetItemCount = function(id, ...)
        if not id then return 0 end
        for _, f in ipairs({ CI("GetItemCount"), G("GetItemCount") }) do
            local fn = f()
            if fn then
                local ok, n = pcall(fn, id, ...)
                if ok then return tonumber(n) or 0 end
            end
        end
        return 0
    end,
    GetItemInfoInstant = function(id) if id then return Try({ CI("GetItemInfoInstant"), G("GetItemInfoInstant") }, id) end end,
    GetItemInfo = function(id) if id then return Try({ CI("GetItemInfo"), G("GetItemInfo") }, id) end end,
    GetItemIcon = function(id) if id then return Try({ CI("GetItemIconByID"), G("GetItemIcon") }, id) end end,
    GetItemSpell = function(id) if id then return Try({ CI("GetItemSpell"), G("GetItemSpell") }, id) end end,
}

local MACRO_NAME = "QFocus"
local ICON_FALLBACK = 134400 -- INV_Misc_QuestionMark
local ICON_HUNT = "Ability_Hunter_SniperShot"   -- celkereszt: mobok
local ICON_TURNIN = "INV_Misc_Note_01"          -- level: leadas
local ICON_IDLE = "INV_Misc_Map_01"             -- nincs kijelolt quest
local MACRO_MAX = 255
local PREFIX = "|cff33ff99Adventurer's Kit|r: "

local QF = CreateFrame("Frame", "QuestFocusEventFrame")
local state = {
    questId = nil,      -- kijelolt quest
    title = nil,
    isComplete = false,
    objectives = nil,   -- CollectTargets eredmenye
    objIndex = nil,     -- ha egy konkret objective van kivalasztva
    lastBody = nil,
    pendingBody = nil,
    macroCount = 0,
    waypoint = nil,
    tomtomUid = nil,
}

-- Chat uzenetek: QuestFocusDB.quietChat eseten csak az kerul ki, amit te kertel
-- (/qf parancsok, gombok: NS.Loud alatt) es a bejelentkezo sor (PrintAlways).
local loud = 0
local function PrintAlways(msg, ...)
    if select("#", ...) > 0 then msg = msg:format(...) end
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end
local function Print(msg, ...)
    if loud == 0 and QuestFocusDB and QuestFocusDB.quietChat then return end
    PrintAlways(msg, ...)
end
-- fn(...) futtatasa ugy, hogy a chat uzenetei akkor is kikeruljenek, ha a chat ki van kapcsolva
local function Loud(fn, ...)
    loud = loud + 1
    local ok, err = pcall(fn, ...)
    loud = loud - 1
    if not ok then error(err, 0) end
end
NS.Print, NS.PrintAlways, NS.Loud = Print, PrintAlways, Loud


---------------------------------------------------------------------------
-- Karakterenkenti beallitasok: QuestFocusDB.chars["Nev-Realm"]. Ide kerulnek a buff
-- kapcsolok (noBuff_*), a valasztott itemek / sajat buffok / percek / class buff valasztasok
-- es a city list kihagyott helyei. Ami itt nincs, a kozos QuestFocusDB-bol olvas (__index).
-- Elso alkalommal karakterenkent a korabbi kozos ertekek masolatabol indul.
---------------------------------------------------------------------------
NS.CHAR_KEYS = { "buffItems", "customBuffs", "buffWarn", "classPref", "cityIgnore" }
local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = DeepCopy(x) end
    return t
end
local charKey
NS.CharDB = function()
    local db = QuestFocusDB
    if not db then return {} end
    db.chars = db.chars or {}
    charKey = charKey or ((UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?"))
    local c = db.chars[charKey]
    if not c then
        c = {}
        for _, k in ipairs(NS.CHAR_KEYS) do
            if db[k] ~= nil then c[k] = DeepCopy(db[k]) end
        end
        for k, v in pairs(db) do
            if type(k) == "string" and k:find("^noBuff_") then c[k] = v end
        end
        db.chars[charKey] = c
    end
    if not getmetatable(c) then
        -- a karakteres kulcsok soha nem olvasnak a kozosbol (kulonben a kozos tablat kapnad
        -- vissza, es a ket karakter ugyanazt irna); minden mas igen
        local own = {}
        for _, k in ipairs(NS.CHAR_KEYS) do own[k] = true end
        setmetatable(c, { __index = function(_, k)
            if own[k] or (type(k) == "string" and k:find("^noBuff_")) then return nil end
            return db[k]
        end })
    end
    return c
end

-- belso exportok a tobbi core fajlnak
NS.C = NS.C or {}
NS.C.ICON_FALLBACK, NS.C.ICON_HUNT, NS.C.ICON_IDLE, NS.C.ICON_TURNIN, NS.C.MACRO_MAX, NS.C.MACRO_NAME, NS.C.Print, NS.C.QF = ICON_FALLBACK, ICON_HUNT, ICON_IDLE, ICON_TURNIN, MACRO_MAX, MACRO_NAME, Print, QF
NS.C.state = state
