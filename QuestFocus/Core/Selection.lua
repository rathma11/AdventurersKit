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
    if changed then state.extra = nil end -- a ticker 3 mp-en belul ujraszamolja
    state.questId = questId
    state.title = title or state.title
    state.isComplete = isComplete and true or false
    QuestFocusDB.lastQuest = questId
    if mark then QuestFocusDB.hidePanel = false end -- kattintasra a bezart panel visszajon
    Refresh(not changed)
    if mark then MarkObjective(state.objIndex) end
end

NS.SelectQuest, NS.SelectObjective = SelectQuest, SelectObjective

-- Kozeli tobbi quest figyelese (3 mp-enkent, harcon kivul): a macro es a panel frissul
local extraTicker = CreateFrame("Frame")
local extraElapsed, lastExtraKey = 0, nil
extraTicker:SetScript("OnUpdate", function(_, dt)
    extraElapsed = extraElapsed + dt
    if extraElapsed < 3 then return end
    extraElapsed = 0
    if not state.questId or InCombatLockdown() then return end
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
    local body = '/run print("QuestFocus: no quest selected")'
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
local function AddQuestTooltip(tooltip, questId, isComplete)
    local quest = GetQuestieQuest(questId)
    if not quest then return end
    local objs = CollectTargets(quest, isComplete)
    if #objs == 0 then return end
    local here = C_Map.GetBestMapForUnit("player")
    -- Fejlec: QuestFocus + haladas + hatralevo ido
    local done, total = 0, 0
    for _, o in ipairs(objs) do
        if not o.turnIn then total = total + 1; if o.completed then done = done + 1 end end
    end
    local eta = not isComplete and NS.QuestEta and NS.QuestEta(objs)
    local right = isComplete and ("|cff33ff99" .. L["ready to turn in"] .. "|r")
        or (("%d/%d"):format(done, total) .. (eta and ("  ·  " .. eta) or ""))
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine("|cff33ff99QuestFocus|r", right, 1, 1, 1, 0.8, 0.8, 0.8)

    for _, o in ipairs(objs) do
        local p, dist = FindNearest(o.sources)
        local distTxt = dist and ("%d yd"):format(dist) or ""
        if o.completed then
            tooltip:AddLine("|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t " .. o.desc, 0.5, 0.5, 0.5)
        else
            local icon = o.turnIn and "|TInterface\\GossipFrame\\ActiveQuestIcon:12:12|t "
                or "|TInterface\\COMMON\\Indicator-Yellow:12:12|t "
            tooltip:AddDoubleLine(icon .. o.desc, distTxt, 1, 0.82, 0, 0.6, 0.8, 1)
            -- Forrasok (behuzva, kisebb hangsulyal, ismetles nelkul)
            local seen = {}
            if o.itemId then
                for _, l in ipairs(ItemSourceLines(o, 3)) do
                    local t = l[1]:gsub("%s*%(on the ground / in an object%)", "")
                    if not seen[t] then
                        seen[t] = true
                        tooltip:AddLine("     " .. t, l[2] * 0.85, l[3] * 0.85, l[4] * 0.85)
                    end
                end
            elseif not o.turnIn then
                local names = {}
                for _, s in ipairs(o.sources) do
                    if s.name and not seen[s.name] then
                        seen[s.name] = true
                        if #names >= 3 then names[#names + 1] = "..." break end
                        names[#names + 1] = s.name
                    end
                end
                if #names > 0 then tooltip:AddLine("     " .. table.concat(names, ", "), 0.85, 0.85, 0.85) end
            end
            -- Hol (a zona nevet csak akkor irjuk, ha nem ott vagy) + hatralevo ido
            local info = {}
            if p then
                info[#info + 1] = (p.map ~= here and (ZoneName(p.map) .. " ") or "") .. ("%.0f, %.0f"):format(p.x, p.y)
            end
            local short = NS.EtaShort and NS.EtaShort(o)
            if short then info[#info + 1] = short .. " " .. L["left"] end
            if #info > 0 then tooltip:AddLine("     " .. table.concat(info, "   ·   "), 0.55, 0.7, 0.9) end
        end
    end
    tooltip:AddLine(L["Click: marker + QFocus macro"], 0.45, 0.45, 0.45)
    tooltip:Show()
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

    HookQuestLogButtons()
    if QuestLogFrame then
        QuestLogFrame:HookScript("OnShow", HookQuestLogButtons)
    end
end


-- belso exportok a tobbi core fajlnak
NS.C.AddQuestTooltip, NS.C.ClearQuest, NS.C.InstallHooks, NS.C.Refresh, NS.C.SelectObjective, NS.C.SelectQuest = AddQuestTooltip, ClearQuest, InstallHooks, Refresh, SelectObjective, SelectQuest
