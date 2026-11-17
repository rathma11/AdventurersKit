-- QuestFocus nyelvi tabla.
-- A kulcs az angol szoveg; ha egy nyelvhez nincs forditas, az angol jelenik meg.
-- Uj nyelv: a GetLocale() erteke alapjan (pl. "deDE") toltsd fel az L tablat.
--   if locale == "deDE" then
--       L["Settings"] = "Einstellungen"
--   end

local _, NS = ...
local L = setmetatable({}, { __index = function(_, k) return k end })
NS.L = L
NS.locale = GetLocale and GetLocale() or "enUS"
-- Kozos nevter a kiegeszito addonoknak (QuestFocus_Bags, QuestFocus_Buffs)
_G.QuestFocusNS = NS

-- Tiltott / blokkolt muveletek (a "has been blocked from an action" ablak) naplozasa a Debug fulre,
-- hogy lassuk, melyik fuggvenyrol van szo.
local blockWatch = CreateFrame("Frame")
blockWatch:RegisterEvent("ADDON_ACTION_BLOCKED")
blockWatch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blockWatch:SetScript("OnEvent", function(_, event, addon, func)
    if type(addon) ~= "string" or not addon:find("^QuestFocus") then return end
    local msg = ("%s: %s%s"):format(event == "ADDON_ACTION_FORBIDDEN" and "FORBIDDEN" or "BLOCKED", tostring(func),
        addon ~= "QuestFocus" and (" [" .. addon .. "]") or "")
    for _, x in ipairs(NS.errors) do
        if x.msg == msg then x.count, x.time = x.count + 1, date("%H:%M:%S") return end
    end
    table.insert(NS.errors, 1, { msg = msg, count = 1, time = date("%H:%M:%S"),
        stack = InCombatLockdown() and "(in combat)" or "(out of combat)" })
end)

-- Sajat Lua hibak gyujtese a Debug fulre. Alapbol nem dobunk fel hibaablakot a
-- QuestFocus hibaira (QuestFocusDB.showErrors kapcsolja), mas addonoket nem erinti.
NS.errors = {}
local prevHandler = geterrorhandler and geterrorhandler()
if seterrorhandler and prevHandler then
    seterrorhandler(function(msg, ...)
        local ours = type(msg) == "string" and msg:find("QuestFocus", 1, true)
        if ours then
            local e
            for _, x in ipairs(NS.errors) do if x.msg == msg then e = x end end
            if e then
                e.count, e.time = e.count + 1, date("%H:%M:%S")
            else
                e = { msg = msg, count = 1, time = date("%H:%M:%S"),
                      stack = debugstack and debugstack(2, 6, 0) or "" }
                table.insert(NS.errors, 1, e)
                while #NS.errors > 20 do table.remove(NS.errors) end
                if DEFAULT_CHAT_FRAME and not (QuestFocusDB and (QuestFocusDB.showErrors or QuestFocusDB.quietChat)) then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Adventurer's Kit|r: |cffff5555Lua error|r logged (/qf options > Debug).")
                end
            end
            if not (QuestFocusDB and QuestFocusDB.showErrors) then return end
        end
        return prevHandler(msg, ...)
    end)
end
