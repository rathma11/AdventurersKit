local ADDON_NAME, NS = ...
local L = NS.L
NS.P = NS.P or {}
local P = NS.P
local mobKills, progress, state = P.mobKills, P.progress, P.state

---------------------------------------------------------------------------
-- Kapcsolo a beallitasokban
---------------------------------------------------------------------------
local pagePanel = NS.AddOptionsTab(L["Panel"])
local cbSuggest = NS.OptCheck(L["Suggest quests when none is selected"],
    L["With no quest selected the panel shows a route through your quest log (nearest next stop each time) "]
    .. L["and nearby quests you can pick up."],
    function() return not QuestFocusDB.noSuggest end,
    function(v)
        QuestFocusDB.noSuggest = not v
        NS.Panel_Update()
    end, pagePanel)
cbSuggest:SetPoint("TOPLEFT", pagePanel, "TOPLEFT", -2, 0)

local cbToast = NS.OptCheck(L["Progress popup"],
    L["A small popup above the panel for a few seconds when an objective progresses, with the estimated time left."],
    function() return not QuestFocusDB.noToast end,
    function(v) QuestFocusDB.noToast = not v end, pagePanel)
cbToast:SetPoint("TOPLEFT", cbSuggest, "BOTTOMLEFT", 0, -6)

local cbNearby = NS.OptCheck(L["Also target mobs of other nearby quests"],
    L["Mobs of other quests in your log that are within ~200 yards are added to the QFocus macro, "]
    .. L["and listed on the panel under ALSO NEARBY (click one to focus that quest)."],
    function() return not QuestFocusDB.noNearbyQuests end,
    function(v)
        QuestFocusDB.noNearbyQuests = not v
        if not v then state.extra = nil end
        NS.Panel_Update()
    end, pagePanel)
cbNearby:SetPoint("TOPLEFT", cbToast, "BOTTOMLEFT", 0, -6)

local cbQPop = NS.OptCheck(L["Popup for quests you can pick up nearby"],
    L["When a quest you can pick up is within ~300 yards, a popup shows its level, an estimated length and the distance. "]
    .. L["Click it for a marker (TomTom arrow) on the quest giver. Each quest only once per session."],
    function() return not QuestFocusDB.noQuestPopup end,
    function(v) QuestFocusDB.noQuestPopup = not v end, pagePanel)
cbQPop:SetPoint("TOPLEFT", cbNearby, "BOTTOMLEFT", 0, -6)

-- Szintsav a felveheto questekhez (javaslatok + kisablak)
local lvlLabel = pagePanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
lvlLabel:SetPoint("TOPLEFT", cbQPop, "BOTTOMLEFT", 32, -8)
lvlLabel:SetText(L["Quest level: your level minus"])
local function LvlBox(key, default, anchor)
    local b = CreateFrame("EditBox", nil, pagePanel, "InputBoxTemplate")
    b:SetSize(28, 18)
    b:SetAutoFocus(false)
    b:SetNumeric(true)
    b:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
    b:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v then QuestFocusDB[key] = v end
        self:SetText(tonumber(QuestFocusDB[key]) or default)
        self:ClearFocus()
    end)
    b:SetScript("OnEscapePressed", function(self) self:SetText(tonumber(QuestFocusDB[key]) or default); self:ClearFocus() end)
    b.refresh = function() b:SetText(tonumber(QuestFocusDB[key]) or default) end
    return b
end
local belowBox = LvlBox("pickupBelow", 2, lvlLabel)
local lvlMid = pagePanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
lvlMid:SetPoint("LEFT", belowBox, "RIGHT", 6, 0)
lvlMid:SetText(L["... plus"])
local aboveBox = LvlBox("pickupAbove", 10, lvlMid)

local cbCity = NS.OptCheck(L["City mode"],
    L["In a city or inn (resting): no popup per quest, one list of every quest you can pick up nearby instead, "]
    .. L["and the panel boxes show distance / travel time / best way (walk, Hearthstone, flight) instead."],
    function() return not QuestFocusDB.noCityMode end,
    function(v)
        QuestFocusDB.noCityMode = not v
        if v then NS.ShowCityList() end
        NS.Panel_Update()
    end, pagePanel)
cbCity:SetPoint("TOPLEFT", lvlLabel, "BOTTOMLEFT", -32, -8)

-- Betumeret (a panel atmeretezese nem valtoztatja)
local fontLabel = pagePanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
fontLabel:SetPoint("TOPLEFT", cbCity, "BOTTOMLEFT", 32, -8)
fontLabel:SetText(L["Panel font size (8-20, default 10):"])
local fontBox = CreateFrame("EditBox", nil, pagePanel, "InputBoxTemplate")
fontBox:SetSize(32, 18)
fontBox:SetAutoFocus(false)
fontBox:SetNumeric(true)
fontBox:SetPoint("LEFT", fontLabel, "RIGHT", 8, 0)
fontBox:SetScript("OnEnterPressed", function(self)
    local v = tonumber(self:GetText())
    if v then QuestFocusDB.fontSize = math.max(8, math.min(20, v)) end
    self:SetText(NS.FontSize())
    self:ClearFocus()
    NS.ApplyFontSize()
    NS.Panel_Update()
end)
fontBox:SetScript("OnEscapePressed", function(self) self:SetText(NS.FontSize()); self:ClearFocus() end)

local etaNote = pagePanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
etaNote:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", -30, -14)
etaNote:SetWidth(520)
etaNote:SetJustifyH("LEFT")
etaNote:SetText(L["Time left is learned from your own pace: how fast each objective counter grew, otherwise "]
    .. L["the time between your kills combined with the Questie drop rate. A '?' means there is no kill data yet."])

local resetPace = CreateFrame("Button", nil, pagePanel, "UIPanelButtonTemplate")
resetPace:SetSize(160, 22)
resetPace:SetPoint("TOPLEFT", etaNote, "BOTTOMLEFT", -2, -10)
resetPace:SetText(L["Reset kill pace"])
resetPace:SetScript("OnClick", function()
    QuestFocusDB.killPace, QuestFocusDB.killSamples = nil, nil
    wipe(progress)
    wipe(mobKills)
    NS.Print(L["Kill pace reset."])
end)
NS.opt:HookScript("OnShow", function()
    cbSuggest.refresh(); cbToast.refresh(); cbNearby.refresh(); cbQPop.refresh(); cbCity.refresh()
    belowBox.refresh(); aboveBox.refresh()
    fontBox:SetText(NS.FontSize())
end)
