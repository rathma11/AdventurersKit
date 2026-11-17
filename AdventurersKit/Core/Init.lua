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


-- belso exportok a tobbi core fajlnak
NS.C = NS.C or {}
NS.C.ICON_FALLBACK, NS.C.ICON_HUNT, NS.C.ICON_IDLE, NS.C.ICON_TURNIN, NS.C.MACRO_MAX, NS.C.MACRO_NAME, NS.C.Print, NS.C.QF = ICON_FALLBACK, ICON_HUNT, ICON_IDLE, ICON_TURNIN, MACRO_MAX, MACRO_NAME, Print, QF
NS.C.state = state
