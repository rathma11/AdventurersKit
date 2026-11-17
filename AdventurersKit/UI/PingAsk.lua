local ADDON_NAME, NS = ...
local L = NS.L

---------------------------------------------------------------------------
-- Ping a QFocus makroban: mod beallitasa (on / off / ask) es a csapatba lepeskori kerdes.
-- A kerdo ablakban is atallithato, mi legyen legkozelebb (mindig / soha / kerdezze).
---------------------------------------------------------------------------
local function RefreshMacro()
    local state = NS.C.state
    if state then state.lastBody = nil end
    if state and state.questId and NS.C.UpdateMacro then NS.C.UpdateMacro() end
    if NS.Panel_Update then NS.Panel_Update() end
end

NS.SetPingMode = function(m)
    if m ~= "on" and m ~= "off" and m ~= "ask" then return end
    QuestFocusDB.pingMode = m
    QuestFocusDB.noPing = (m == "off") or nil -- regi kulcs (export / regi verzio)
    RefreshMacro()
    if NS.RefreshPingUI then NS.RefreshPingUI() end
end

local MODES = {
    { "ask", L["Ask when I join a group"] },
    { "on", L["Always ping"] },
    { "off", L["Never ping"] },
}
NS.PING_MODES = MODES

-- Kerdo ablak
local f = CreateFrame("Frame", "AdventurersKitPingAsk", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
f:SetSize(330, 170)
f:SetPoint("TOP", UIParent, "TOP", 0, -160)
f:SetFrameStrata("DIALOG")
f:EnableMouse(true)
f:SetMovable(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:Hide()
if f.SetBackdrop then
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 20,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    f:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
    f:SetBackdropBorderColor(0.95, 0.78, 0.40, 1)
end
local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", 16, -14)
title:SetText(L["Ping in the QFocus macro?"])
local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
text:SetWidth(298)
text:SetJustifyH("LEFT")
text:SetText(L["You joined a group. Should the macro ping its target? Your group sees the ping."])

local yes = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
yes:SetSize(130, 22)
yes:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -10)
yes:SetText(L["Ping in this group"])
local no = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
no:SetSize(130, 22)
no:SetPoint("LEFT", yes, "RIGHT", 8, 0)
no:SetText(L["No ping"])

local nextLbl = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
nextLbl:SetPoint("TOPLEFT", yes, "BOTTOMLEFT", 0, -10)
nextLbl:SetText(L["Next time:"])
local radios = {}
for i, m in ipairs(MODES) do
    local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("TOPLEFT", nextLbl, "BOTTOMLEFT", (i - 1) * 104 - 2, -2)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 1, 0)
    cb.label:SetWidth(82)
    cb.label:SetJustifyH("LEFT")
    cb.label:SetText(m[2])
    cb.mode = m[1]
    cb:SetScript("OnClick", function(self)
        QuestFocusDB.pingMode = self.mode
        QuestFocusDB.noPing = (self.mode == "off") or nil
        for _, r in ipairs(radios) do r:SetChecked(r.mode == self.mode) end
        if NS.RefreshPingUI then NS.RefreshPingUI() end
    end)
    radios[#radios + 1] = cb
end

local function Answer(v)
    NS.pingSession = v
    QuestFocusDB.pingAnswer = v -- /reload utan is erre a csapatra
    f:Hide()
    RefreshMacro()
    NS.Loud(NS.Print, v and L["Ping on for this group."] or L["No ping for this group."])
end
yes:SetScript("OnClick", function() Answer(true) end)
no:SetScript("OnClick", function() Answer(false) end)

local function ShowAsk()
    for _, r in ipairs(radios) do r:SetChecked(r.mode == NS.PingMode()) end
    f:Show()
end
NS.ShowPingAsk = ShowAsk

-- Csapatba lepes figyelese
local wasInGroup, pendingAsk = false, false
local ev = CreateFrame("Frame")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingAsk and IsInGroup() and NS.PingMode() == "ask" and NS.pingSession == nil then ShowAsk() end
        pendingAsk = false
        return
    end
    local inGroup = IsInGroup and IsInGroup() or false
    if inGroup and not wasInGroup then
        -- /reload csapatban: a korabbi valasz marad
        if event == "PLAYER_ENTERING_WORLD" and NS.pingSession == nil and QuestFocusDB.pingAnswer ~= nil then
            NS.pingSession = QuestFocusDB.pingAnswer
        end
        if NS.PingMode() == "ask" and NS.pingSession == nil then
            if InCombatLockdown() then pendingAsk = true else ShowAsk() end
        end
        RefreshMacro()
    elseif not inGroup and wasInGroup then
        NS.pingSession = nil -- kovetkezo csapatnal ujra kerdez
        QuestFocusDB.pingAnswer = nil
        f:Hide()
        RefreshMacro()
    end
    wasInGroup = inGroup
end)
