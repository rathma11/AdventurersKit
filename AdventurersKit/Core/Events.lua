local ADDON_NAME, NS = ...
local L = NS.L
NS.C = NS.C or {}
local C = NS.C
local ApplyFontSize, ApplyMacro, ApplyPanelWidth, ClearQuest, FindQuestInLog, InstallHooks, MarkObjective, panel = C.ApplyFontSize, C.ApplyMacro, C.ApplyPanelWidth, C.ClearQuest, C.FindQuestInLog, C.InstallHooks, C.MarkObjective, C.panel
local Panel_Update, PickNameplate, Print, QF, Refresh, RestorePanelPos, SelectQuest, state = C.Panel_Update, C.PickNameplate, C.Print, C.QF, C.Refresh, C.RestorePanelPos, C.SelectQuest, C.state
local TapDenied, targetNames, UpdateMacro = C.TapDenied, C.targetNames, C.UpdateMacro

---------------------------------------------------------------------------
-- Esemenyek
---------------------------------------------------------------------------
local refreshPending = false
local function ScheduleRefresh()
    if refreshPending or not state.questId then return end
    refreshPending = true
    C_Timer.After(1, function()
        refreshPending = false
        if not state.questId then return end
        local title, done = FindQuestInLog(state.questId)
        if not title then
            -- Leadva vagy abandon: marker es kijeloles torlese
            local old = state.title
            ClearQuest()
            Print(L["|cffffff00%s|r left the quest log, marker removed."], old or "Quest")
            return
        end
        local becameComplete = done and not state.isComplete
        local prevDone = {}
        for i, o in ipairs(state.objectives or {}) do prevDone[i] = o.completed end
        state.title, state.isComplete = title, done and true or false
        Refresh(not becameComplete)
        if becameComplete then
            Print(L["|cffffff00%s|r is complete, marker moved to the turn-in NPC."], title)
            MarkObjective(nil)
            return
        end
        -- Ha egy objective most lett kesz, a marker a kovetkezo hatralevore ugrik
        local justDone
        for i, o in ipairs(state.objectives or {}) do
            if o.completed and prevDone[i] == false then justDone = i end
        end
        if justDone and (state.objIndex == nil or state.objIndex == justDone) then
            state.objIndex = nil
            UpdateMacro()
            Panel_Update()
            if state.waypoint or state.tomtomUid then
                Print(L["Objective complete, marker moved to the next target."])
                MarkObjective(nil)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Quest valtozas: a QUEST_LOG_UPDATE nagyon gyakran jon (sokszor valtozas nelkul), ezert a
-- konkret esemenyeket figyeljuk: felvetel, leadas, eltavolitas, haladas (UNIT_QUEST_LOG_CHANGED).
-- A QUEST_LOG_UPDATE csak tartalek, amig a kliens egyszer sem kuldott konkret esemenyt.
-- NS.OnQuestChange(fn): a modulok (Planner, Bags) erre iratkoznak fel.
---------------------------------------------------------------------------
local questCallbacks = {}
NS.OnQuestChange = function(fn) questCallbacks[#questCallbacks + 1] = fn end
local specificSeen = false
local qev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "UNIT_QUEST_LOG_CHANGED", "QUEST_LOG_UPDATE" }) do
    pcall(qev.RegisterEvent, qev, e) -- ha egy esemeny nincs ezen a kliensen, kihagyjuk
end
qev:SetScript("OnEvent", function(_, event, arg1)
    if event == "UNIT_QUEST_LOG_CHANGED" and arg1 ~= "player" then return end
    if event == "QUEST_LOG_UPDATE" then
        if specificSeen then return end
    else
        specificSeen = true
    end
    NS.questLogGen = (NS.questLogGen or 0) + 1 -- a tickerek ebbol latjak, hogy ujra kell szamolni
    ScheduleRefresh()
    for _, fn in ipairs(questCallbacks) do pcall(fn, event) end
end)

QF:RegisterEvent("ADDON_LOADED")
QF:RegisterEvent("PLAYER_LOGIN")
QF:RegisterEvent("PLAYER_REGEN_ENABLED")
QF:RegisterEvent("CVAR_UPDATE")
QF:RegisterEvent("PLAYER_REGEN_DISABLED")
QF:RegisterEvent("PLAYER_TARGET_CHANGED")
QF:SetScript("OnEvent", function(self, event, arg1)
    if event == "CVAR_UPDATE" then
        -- nameplate ki/be: mas macro kell (click vs. targetexact)
        if state.questId then C_Timer.After(0.1, UpdateMacro) end
        return
    elseif event == "PLAYER_TARGET_CHANGED" then
        if UnitExists("target") and targetNames[UnitName("target") or ""] and TapDenied("target")
            and not UnitIsDead("target") and UIErrorsFrame then
            UIErrorsFrame:AddMessage(L["QFocus: this mob is already tapped by someone else"], 1, 0.3, 0.3)
        end
        -- Target valtas: a ping sor ki/be (uj celpontra pingel, a mostanira nem)
        -- Kesleltetve! A /target sor meg a macro futasa KOZBEN valtja ki ezt az esemenyt;
        -- ha azonnal atirnank a macrot, a hatralevo sorai (a ping) mar nem futnanak le.
        if state.questId and not state.targetRebuildPending then
            state.targetRebuildPending = true
            C_Timer.After(0.5, function()
                state.targetRebuildPending = nil
                if state.questId and not InCombatLockdown() then UpdateMacro() end
            end)
        end
        return
    end
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        QuestFocusDB = QuestFocusDB or {}
    elseif event == "PLAYER_LOGIN" then
        -- a regi (scale alapu) meretezes helyett szelesseg + betumeret
        if QuestFocusDB.panelScale then QuestFocusDB.panelScale = nil; panel:SetScale(1) end
        ApplyFontSize()
        ApplyPanelWidth()
        RestorePanelPos()
        -- a WoW layout cache a login utan meg atrakhatja: meg egyszer a sajat mentesunket
        C_Timer.After(1, RestorePanelPos)
        InstallHooks()
        if not _G.QuestieLoader then
            NS.PrintAlways(L["|cffff5555Questie not found.|r Install it, Adventurer's Kit does not work without it."])
        end
        -- Utolso kijelolt quest visszaallitasa, ha a Questie mar betoltott
        C_Timer.After(8, function()
            local id = QuestFocusDB.lastQuest
            if id and not state.questId then
                local title, done = FindQuestInLog(id)
                if title then SelectQuest(id, title, done, false) end
            end
            if not state.questId then Panel_Update() end
        end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Harcban a gombot nem lehet atallitani, a regi nameplate token pedig mar mas mobra
        -- mutathat: inkabb engedjuk el, harc alatt a nev szerinti target dolgozik.
        state.pick = nil
        if state.questId and not InCombatLockdown() then UpdateMacro() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if state.pendingBody then ApplyMacro(state.pendingBody) end
        PickNameplate()
    end
end)

