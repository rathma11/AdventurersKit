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
-- dungeon quest: Start dungeon gomb a sor vegen
qpop.dBtn = NS.MakeDungeonButton(qpop, 16)
qpop.dBtn:SetPoint("BOTTOMRIGHT", -9, 8)
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
-- Mozgathato: huzd el (a hely megmarad, QuestFocusDB.qpopPos = felso kozepe); jobb klikk: alap hely
qpop:SetMovable(true)
qpop:SetClampedToScreen(true)
qpop:RegisterForDrag("LeftButton")
qpop:RegisterForClicks("LeftButtonUp", "RightButtonUp")
qpop:SetScript("OnDragStart", function(self)
    self.dragged = true
    self:StartMoving()
end)
qpop:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local l, r, t = self:GetLeft(), self:GetRight(), self:GetTop()
    if l and r and t then
        QuestFocusDB.qpopPos = { x = (l + r) / 2, y = t }
        self:ClearAllPoints()
        self:SetPoint("TOP", UIParent, "BOTTOMLEFT", QuestFocusDB.qpopPos.x, QuestFocusDB.qpopPos.y)
    end
end)
qpop:SetScript("OnClick", function(self, btn)
    if self.dragged then self.dragged = nil return end -- huzas vege, nem kattintas
    if btn == "RightButton" then
        QuestFocusDB.qpopPos = nil
        NS.Loud(NS.Print, L["Quest popup: back to its default place."])
        self:Hide()
        return
    end
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
    NS.TT.Pickup(self, "ANCHOR_BOTTOM", d,
        L["Length is a rough estimate (objective types, drop rate, your kill pace). "]
        .. L["'?' / unknown: can't be estimated (battleground, item from an unknown source)."]
        .. "\n" .. L["Drag to move; right click: default place."])
end)
qpop:SetScript("OnLeave", function() GameTooltip:Hide() end)

local announced = {} -- qid -> true: errol mar szoltunk ebben a jatekmenetben

local function ShowQuestPopup(d)
    local col = GetQuestDifficultyColor and d.level and GetQuestDifficultyColor(d.level)
    local hex = col and ("|cff%02x%02x%02x"):format(col.r * 255, col.g * 255, col.b * 255) or "|cffffffff"
    local est = EstimateQuestTime(d.quest)
    qpop.data = d
    -- dungeon quest: a teljes dungeon nev is kifer, es Start dungeon gomb
    local dName = NS.QuestDungeon(d.quest, d.qid)
    qpop:SetWidth(dName and 400 or 270)
    qpop.dBtn.qid, qpop.dBtn.dungeon = d.qid, dName
    qpop.dBtn:SetShown(dName ~= nil)
    qpop.text:SetPoint("RIGHT", dName and -30 or -9, 0)
    qpop.right:SetText(("|cff99ccff%d yd|r"):format(d.dist + 0.5))
    qpop.text:SetText(("%s[%s]|r %s%s%s|r  |cff999999%s|r"):format(hex, tostring(d.level or "?"),
        NS.DungeonTag(d.quest, d.qid), hex, d.name or "?", est and (FormatTime(est) .. " " .. L["est."]) or L["length unknown"]))
    qpop:ClearAllPoints()
    local pos = QuestFocusDB.qpopPos
    if pos and pos.x and pos.y then
        -- ahova elhuztad
        qpop:SetPoint("TOP", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    -- kozepen felul, a jatek sajat kiirasai alatt
    elseif UIErrorsFrame and UIErrorsFrame:IsShown() and UIErrorsFrame:GetBottom() then
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
