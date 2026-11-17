local ADDON_NAME, NS = ...
local L = NS.L
NS.C = NS.C or {}
local C = NS.C
local ApplyMacro, ClearWaypoint, CollectTargets, CurrentIcon, FindNearest, FindQuestInLog, GetLogEntry, GetQuestieQuest = C.ApplyMacro, C.ClearWaypoint, C.CollectTargets, C.CurrentIcon, C.FindNearest, C.FindQuestInLog, C.GetLogEntry, C.GetQuestieQuest
local ItemSourceLines, MarkObjective, Panel_Update, Print, QuestieAvailable, state, targetNames, UpdateMacro = C.ItemSourceLines, C.MarkObjective, C.Panel_Update, C.Print, C.QuestieAvailable, C.state, C.targetNames, C.UpdateMacro
local ZoneName = C.ZoneName

---------------------------------------------------------------------------
-- Kijeloles
---------------------------------------------------------------------------
local function Refresh(keepObjective)
    if not state.questId then return end
    local quest = GetQuestieQuest(state.questId)
    state.objectives = quest and CollectTargets(quest, state.isComplete) or {}
    if not keepObjective then state.objIndex = nil end
    if state.objIndex and not state.objectives[state.objIndex] then state.objIndex = nil end
    UpdateMacro()
    Panel_Update()
end

local function SelectObjective(i)
    state.objIndex = i
    UpdateMacro()
    Panel_Update()
    MarkObjective(i)
end

local function SelectQuest(questId, title, isComplete, mark)
    if not questId or questId == 0 then return end
    if not QuestieAvailable() then
        Print(L["Questie is not loaded, without it I don't know where the mobs are."])
    end
    -- Egy kattintasra tobb hook is lefuthat (gomb + C_QuestLog): csak egyszer jeloljunk
    local now = GetTime()
    if mark and state.lastMarkQuest == questId and state.lastMarkTime and now - state.lastMarkTime < 0.5 then
        mark = false
    end
    if mark then state.lastMarkQuest, state.lastMarkTime = questId, now end
    local changed = questId ~= state.questId
    local hadQuest = state.questId ~= nil -- belepeskori visszaallitasnal (nem volt elotte) nem jelolunk
    if changed then state.extra = nil end -- a ticker 3 mp-en belul ujraszamolja
    state.questId = questId
    state.title = title or state.title
    state.isComplete = isComplete and true or false
    QuestFocusDB.lastQuest = questId
    if mark then QuestFocusDB.hidePanel = false end -- kattintasra a bezart panel visszajon
    -- masik questre valtottal (kattintas, kovetes / track, Questie tracker): a regi quest
    -- markere nem maradhat (a nyil kulonben rossz helyre mutat); az uj quest celjara tesszuk
    if changed then ClearWaypoint() end
    Refresh(not changed)
    if mark or (changed and hadQuest) then MarkObjective(state.objIndex) end
end

NS.SelectQuest, NS.SelectObjective = SelectQuest, SelectObjective

-- Kozeli tobbi quest figyelese (3 mp-enkent, harcon kivul): a macro es a panel frissul
-- Optimalizalas: ha nem mozdultal (15 yd) es a quest log se valtozott, nem szamolunk ujra
-- (legalabb 15 mp-enkent azert igen).
NS.questLogGen = NS.questLogGen or 0
-- Mozgas-figyelo: Moved(tag, yd) true, ha az utolso true ota legalabb ennyit mentel (vagy mas kontinens)
local movedAt = {}
NS.Moved = function(tag, yd)
    local pc, px, py = NS.C.PlayerWorldPos()
    if not pc then return true end
    local m = movedAt[tag]
    if m and m.c == pc and (m.x - px) ^ 2 + (m.y - py) ^ 2 < yd * yd then return false end
    movedAt[tag] = { c = pc, x = px, y = py }
    return true
end
local extraTicker = CreateFrame("Frame")
local extraElapsed, lastExtraKey, sinceFull, lastGen, lastQid = 0, nil, 0, -1, nil
extraTicker:SetScript("OnUpdate", function(_, dt)
    extraElapsed = extraElapsed + dt
    if extraElapsed < 3 then return end
    sinceFull = sinceFull + extraElapsed
    extraElapsed = 0
    if not state.questId or InCombatLockdown() then return end
    local moved = NS.Moved("extra", 15)
    if not moved and lastGen == NS.questLogGen and lastQid == state.questId and sinceFull < 15 then return end
    sinceFull, lastGen, lastQid = 0, NS.questLogGen, state.questId
    local list = {}
    if not QuestFocusDB.noNearbyQuests and NS.NearbyQuestTargets then
        local ok, r = pcall(NS.NearbyQuestTargets, state.questId, tonumber(QuestFocusDB.nearbyRadius) or 200)
        if ok and r then list = r end
    end
    -- leadasnal a "messze van-e az NPC" is szamit (a macro ennek megfeleloen valt)
    local far = ""
    if state.isComplete and state.objectives and state.objectives[1] and state.objectives[1].turnIn then
        local _, d = FindNearest(state.objectives[1].sources)
        far = (not d or d > 100) and "far" or "near"
    end
    local key = tostring(state.questId) .. "|" .. far .. "|"
    for _, e in ipairs(list) do key = key .. e.qid .. ":" .. tostring(e.desc) .. ";" end
    state.extra = list
    if key ~= lastExtraKey then
        lastExtraKey = key
        UpdateMacro()
        Panel_Update()
    end
end)

local function ClearQuest()
    state.questId, state.title, state.objectives, state.objIndex = nil, nil, nil, nil
    state.extra = nil
    ClearWaypoint()
    QuestFocusDB.lastQuest = nil
    Panel_Update() -- kijeloles nelkul javaslatokat mutat
    state.macroCount = 0
    wipe(targetNames)
    local body = '/run print("QFocus: no quest selected")'
    if body ~= state.lastBody or CurrentIcon() ~= state.lastIcon then ApplyMacro(body) end
end

local function SelectByLogIndex(index, mark)
    if not index or index == 0 then return end
    local title, isHeader, questId, done = GetLogEntry(index)
    if isHeader or not questId then return end
    SelectQuest(questId, title, done, mark)
end

---------------------------------------------------------------------------
-- Quest log tooltip
---------------------------------------------------------------------------
-- (a tooltip szerkezete kozos: UI\Tooltip.lua)
local function AddQuestTooltip(tooltip, questId, isComplete)
    local quest = GetQuestieQuest(questId)
    if not quest then return end
    local objs = CollectTargets(quest, isComplete)
    if #objs == 0 then return end
    local TT = NS.TT
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine("|cff33ff99Adventurer's Kit|r", TT.Progress(objs, isComplete), 1, 1, 1, 0.75, 0.75, 0.75)
    TT.Objectives(tooltip, objs)
    TT.Finish(tooltip, L["Click: marker + QFocus macro"])
end

local function HookQuestLogButtons()
    local hooked = 0
    for i = 1, 50 do
        local btn = _G["QuestLogTitle" .. i]
        if not btn then break end
        if not btn.QuestFocusHooked then
            btn.QuestFocusHooked = true
            hooked = hooked + 1
            btn:HookScript("OnEnter", function(self)
                local index = self:GetID()
                if not index or index == 0 then return end
                local title, isHeader, questId, done = GetLogEntry(index)
                if isHeader or not questId then return end
                if GameTooltip:GetOwner() ~= self then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(title or "?", 1, 1, 1)
                    self.QuestFocusOwnsTooltip = true
                end
                AddQuestTooltip(GameTooltip, questId, done)
            end)
            btn:HookScript("OnLeave", function(self)
                if self.QuestFocusOwnsTooltip then
                    self.QuestFocusOwnsTooltip = nil
                    if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
                end
            end)
        end
    end
    return hooked
end

local function InstallHooks()
    local clickHooked = false

    -- Kattintas a quest log egy soran -> marker + macro
    if type(QuestLogTitleButton_OnClick) == "function" then
        hooksecurefunc("QuestLogTitleButton_OnClick", function(self, button)
            if not GetQuestLogSelection then return end
            SelectByLogIndex(GetQuestLogSelection(), true)
        end)
        clickHooked = true
    end

    -- Barmilyen kijeloles-valtas -> macro frissites (marker csak ha nincs click hook)
    if type(QuestLog_SetSelection) == "function" then
        hooksecurefunc("QuestLog_SetSelection", function(index)
            local _, isHeader, questId = GetLogEntry(index or 0)
            if isHeader or not questId then return end
            if questId ~= state.questId then SelectByLogIndex(index, not clickHooked) end
        end)
    end

    -- Modern quest log
    if C_QuestLog and type(C_QuestLog.SetSelectedQuest) == "function" then
        hooksecurefunc(C_QuestLog, "SetSelectedQuest", function(questId)
            if not questId or questId == 0 then return end
            local title, done = FindQuestInLog(questId)
            SelectQuest(questId, title, done, true)
        end)
    end

    -- Kovetes (track pipa a quest logban / terkep melletti listaban, shift-klikk): a frissen
    -- kovetett quest lesz a fokuszban, a nyil oda kerul. Quest felvetelkor az automatikus
    -- kovetes (Questie / jatek) nem valt fokuszt (2 mp-en belul a QUEST_ACCEPTED utan).
    local acceptedAt = 0
    local acc = CreateFrame("Frame")
    acc:RegisterEvent("QUEST_ACCEPTED")
    acc:SetScript("OnEvent", function() acceptedAt = GetTime() end)
    local function OnTracked(questId, index)
        if GetTime() - acceptedAt < 2 or InCombatLockdown() then return end
        if index then
            SelectByLogIndex(index, true)
        elseif questId and questId ~= 0 and questId ~= state.questId then
            local title, done = FindQuestInLog(questId)
            if title then SelectQuest(questId, title, done, true) end
        end
    end
    if type(AddQuestWatch) == "function" then
        hooksecurefunc("AddQuestWatch", function(index) OnTracked(nil, index) end)
    end
    if C_QuestLog and type(C_QuestLog.AddQuestWatch) == "function" then
        hooksecurefunc(C_QuestLog, "AddQuestWatch", function(questId) OnTracked(questId) end)
    end
    pcall(acc.RegisterEvent, acc, "QUEST_WATCH_LIST_CHANGED") -- (nem minden kliensen van ilyen esemeny)
    acc:SetScript("OnEvent", function(_, event, questId, added)
        if event == "QUEST_ACCEPTED" then acceptedAt = GetTime() return end
        if added and questId then OnTracked(questId) end
    end)

    HookQuestLogButtons()
    if QuestLogFrame then
        QuestLogFrame:HookScript("OnShow", HookQuestLogButtons)
    end
end


-- belso exportok a tobbi core fajlnak
NS.C.AddQuestTooltip, NS.C.ClearQuest, NS.C.InstallHooks, NS.C.Refresh, NS.C.SelectObjective, NS.C.SelectQuest = AddQuestTooltip, ClearQuest, InstallHooks, Refresh, SelectObjective, SelectQuest
