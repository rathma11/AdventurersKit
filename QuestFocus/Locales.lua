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
