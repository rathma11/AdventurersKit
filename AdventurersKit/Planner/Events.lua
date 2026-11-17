local ADDON_NAME, NS = ...
local L = NS.L
NS.P = NS.P or {}
local P = NS.P
local killSeen, RecordKill, ScanProgress, state = P.killSeen, P.RecordKill, P.ScanProgress, P.state

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

