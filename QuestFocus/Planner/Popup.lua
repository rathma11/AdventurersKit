local ADDON_NAME, NS = ...
local L = NS.L
NS.P = NS.P or {}
local P = NS.P
local EstimateQuestTime, FormatTime, state = P.EstimateQuestTime, P.FormatTime, P.state

---------------------------------------------------------------------------
-- Kozeli felveheto quest kisablak: kozepen felul, a progress alatt. Kattintasra
-- marker (TomTom nyil) a quest adora. Questenkent egyszer szol egy jatekmenetben.
---------------------------------------------------------------------------
local NEARBY_RADIUS = 300
local qpop = CreateFrame("Button", "QuestFocusQuestPopup", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
qpop:SetSize(270, 50)
qpop:SetFrameStrata("MEDIUM")
qpop:RegisterForClicks("LeftButtonUp")
qpop:Hide()
if qpop.SetBackdrop then
    qpop:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    qpop:SetBackdropColor(0.04, 0.04, 0.06, 0.92)
    qpop:SetBackdropBorderColor(0.95, 0.78, 0.40, 0.9)
end
local qAccent = qpop:CreateTexture(nil, "ARTWORK")
qAccent:SetPoint("TOPLEFT", 4, -4)
qAccent:SetPoint("BOTTOMLEFT", 4, 4)
qAccent:SetWidth(2)
qAccent:SetColorTexture(1, 0.82, 0, 1)
qpop.label = qpop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
qpop.label:SetPoint("TOPLEFT", 12, -7)
qpop.label:SetTextColor(1, 0.82, 0)
qpop.label:SetText(L["QUEST NEARBY"])
qpop.right = qpop:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
qpop.right:SetPoint("TOPRIGHT", -24, -7)
qpop.icon = qpop:CreateTexture(nil, "ARTWORK")
qpop.icon:SetSize(18, 18)
qpop.icon:SetPoint("BOTTOMLEFT", 12, 8)
qpop.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
qpop.text = qpop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
qpop.text:SetPoint("LEFT", qpop.icon, "RIGHT", 6, 0)
qpop.text:SetPoint("RIGHT", -9, 0)
qpop.text:SetJustifyH("LEFT")
qpop.text:SetWordWrap(false)
local qClose = CreateFrame("Button", nil, qpop, "UIPanelCloseButton")
qClose:SetSize(20, 20)
qClose:SetPoint("TOPRIGHT", -2, -2)
qClose:SetScript("OnClick", function() qpop:Hide() end)
local qhl = qpop:CreateTexture(nil, "HIGHLIGHT")
qhl:SetAllPoints()
qhl:SetColorTexture(1, 1, 1, 0.06)

local QPOP_HOLD, QPOP_FADE = 10, 1
qpop:SetScript("OnUpdate", function(self, dt)
    if self:IsMouseOver() then self.t = 0; self:SetAlpha(1) return end -- egerrel folotte nem tunik el
    self.t = (self.t or 0) + dt
    if self.t > QPOP_HOLD + QPOP_FADE then
        self:Hide()
    elseif self.t > QPOP_HOLD then
        self:SetAlpha(1 - (self.t - QPOP_HOLD) / QPOP_FADE)
    end
end)
qpop:SetScript("OnClick", function(self)
    local d = self.data
    if not d then return end
    NS.SetWaypoint(d.point, d.point.name or d.name)
    if state.waypoint then state.waypoint.giver = d.qid end
    NS.Print(L["Marker: quest giver |cffffff00%s|r for %s"], d.point.name or "?", d.name or "?")
    self:Hide()
end)
qpop:SetScript("OnEnter", function(self)
    local d = self.data
    if not d then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(("[%s] %s"):format(tostring(d.level or "?"), d.name or "?"), 1, 1, 1)
    GameTooltip:AddLine((L["Quest giver: %s"]):format(d.point.name or "?"), 1, 0.82, 0)
    GameTooltip:AddLine(("%s %.1f, %.1f"):format(NS.ZoneName(d.point.map), d.point.x, d.point.y), 0.6, 0.8, 1)
    GameTooltip:AddLine(L["Length is a rough estimate (objective types, drop rate, your kill pace)."], 0.6, 0.6, 0.6, true)
    GameTooltip:AddLine(L["Click: marker (TomTom arrow) on the quest giver"], 0.5, 0.5, 0.5)
    GameTooltip:Show()
end)
qpop:SetScript("OnLeave", function() GameTooltip:Hide() end)

local announced = {} -- qid -> true: errol mar szoltunk ebben a jatekmenetben

local function ShowQuestPopup(d)
    local col = GetQuestDifficultyColor and d.level and GetQuestDifficultyColor(d.level)
    local hex = col and ("|cff%02x%02x%02x"):format(col.r * 255, col.g * 255, col.b * 255) or "|cffffffff"
    local est = EstimateQuestTime(d.quest)
    qpop.data = d
    qpop.right:SetText(("|cff99ccff%d yd|r"):format(d.dist + 0.5))
    qpop.text:SetText(("%s[%s] %s|r  |cff999999%s %s|r"):format(hex, tostring(d.level or "?"), d.name or "?",
        FormatTime(est), L["est."]))
    qpop:ClearAllPoints()
    -- kozepen felul, a jatek sajat kiirasai alatt
    if UIErrorsFrame and UIErrorsFrame:IsShown() and UIErrorsFrame:GetBottom() then
        qpop:SetPoint("TOP", UIErrorsFrame, "BOTTOM", 0, -6)
    else
        qpop:SetPoint("TOP", UIParent, "TOP", 0, -190)
    end
    qpop.t = 0
    qpop:SetAlpha(1)
    qpop:Show()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN then PlaySound(SOUNDKIT.IG_QUEST_LIST_OPEN) end
end


-- belso exportok a tobbi core fajlnak
NS.P.NEARBY_RADIUS, NS.P.ShowQuestPopup, NS.P.announced, NS.P.qpop = NEARBY_RADIUS, ShowQuestPopup, announced, qpop
