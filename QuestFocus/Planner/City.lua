local ADDON_NAME, NS = ...
local L = NS.L
NS.P = NS.P or {}
local P = NS.P
local announced, BuildPickups, EstimateQuestTime, FormatTime, NEARBY_RADIUS, qpop, ShowQuestPopup, state = P.announced, P.BuildPickups, P.EstimateQuestTime, P.FormatTime, P.NEARBY_RADIUS, P.qpop, P.ShowQuestPopup, P.state

---------------------------------------------------------------------------
-- Varos mod: varosban / fogadoban (IsResting) nem popupol questenkent, hanem egy listaban
-- mutatja az osszes felveheto questet. Belepeskor jon fel, kilepeskor eltunik.
---------------------------------------------------------------------------
local CITY_RADIUS, CITY_MAX = 600, 12
local city = CreateFrame("Frame", "QuestFocusCityList", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
city:SetSize(330, 80)
city:SetPoint("TOP", UIParent, "TOP", 0, -190)
city:SetFrameStrata("MEDIUM")
city:EnableMouse(true)
city:SetMovable(true)
city:SetClampedToScreen(true)
city:RegisterForDrag("LeftButton")
city:SetScript("OnDragStart", city.StartMoving)
city:SetScript("OnDragStop", city.StopMovingOrSizing)
city:Hide()
if city.SetBackdrop then
    city:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 20,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    city:SetBackdropColor(0.04, 0.04, 0.06, 0.93)
    city:SetBackdropBorderColor(0.95, 0.78, 0.40, 1)
end
city.icon = city:CreateTexture(nil, "ARTWORK")
city.icon:SetSize(20, 20)
city.icon:SetPoint("TOPLEFT", 12, -11)
city.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
city.title = city:CreateFontString(nil, "OVERLAY", "GameFontNormal")
city.title:SetPoint("LEFT", city.icon, "RIGHT", 6, 0)
city.title:SetTextColor(1, 0.86, 0.5)
local cClose = CreateFrame("Button", nil, city, "UIPanelCloseButton")
cClose:SetSize(24, 24)
cClose:SetPoint("TOPRIGHT", -4, -4)
cClose:SetScript("OnClick", function() city.closedHere = true; city:Hide() end)
city.foot = city:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
city.foot:SetText(L["Click: marker on the quest giver. Drag to move."])

local cityRows = {}
local function CityRow(i)
    local r = cityRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, city)
    r:SetSize(306, 18)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT")
    r.text:SetPoint("RIGHT", -70, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT")
    r.right:SetJustifyH("RIGHT")
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    r:SetScript("OnClick", function(self)
        local d = self.data
        if not d then return end
        NS.SetWaypoint(d.point, d.point.name or d.name)
        if state.waypoint then state.waypoint.giver = d.qid end
        NS.Print(L["Marker: quest giver |cffffff00%s|r for %s"], d.point.name or "?", d.name or "?")
    end)
    r:SetScript("OnEnter", function(self)
        local d = self.data
        if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(("[%s] %s"):format(tostring(d.level or "?"), d.name or "?"), 1, 1, 1)
        GameTooltip:AddLine((L["Quest giver: %s"]):format(d.point.name or "?"), 1, 0.82, 0)
        GameTooltip:AddLine(("%s %.1f, %.1f"):format(NS.ZoneName(d.point.map), d.point.x, d.point.y), 0.6, 0.8, 1)
        GameTooltip:AddLine(L["Click: marker (TomTom arrow) on the quest giver"], 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cityRows[i] = r
    return r
end

local function InCity() return IsResting and IsResting() end
NS.InCity = function() return InCity() and not QuestFocusDB.noCityMode end

local function RefreshCityList()
    if QuestFocusDB.noCityMode or not NS.QuestieAvailable() then city:Hide() return end
    local pc, px, py = NS.PlayerWorldPos()
    if not pc then return end
    local ok, list = pcall(BuildPickups, pc, px, py, 30)
    if not ok or not list then return end
    for _, r in ipairs(cityRows) do r:Hide() end
    local y, n = -38, 0
    for _, d in ipairs(list) do
        if d.dist > CITY_RADIUS or n >= CITY_MAX then break end
        n = n + 1
        if announced then announced[d.qid] = true end -- kint mar ne popupoljon
        local r = CityRow(n)
        r.data = d
        local col = GetQuestDifficultyColor and d.level and GetQuestDifficultyColor(d.level)
        local hex = col and ("|cff%02x%02x%02x"):format(col.r * 255, col.g * 255, col.b * 255) or "|cffffffff"
        r.text:SetText(("%s[%s] %s|r  |cff999999%s|r"):format(hex, tostring(d.level or "?"), d.name or "?",
            FormatTime(EstimateQuestTime(d.quest))))
        r.right:SetText(("|cff99ccff%d yd|r"):format(d.dist + 0.5))
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", city, "TOPLEFT", 12, y)
        r:Show()
        y = y - 19
    end
    if n == 0 then city:Hide() return end
    city.title:SetText((L["Quests to pick up here (%d)"]):format(n))
    city.foot:ClearAllPoints()
    city.foot:SetPoint("TOPLEFT", city, "TOPLEFT", 14, y - 4)
    city:SetHeight(-y + 26)
    if not city:IsShown() and not city.closedHere then city:Show() end
end

local cityEv = CreateFrame("Frame")
cityEv:RegisterEvent("PLAYER_UPDATE_RESTING")
cityEv:RegisterEvent("PLAYER_ENTERING_WORLD")
cityEv:SetScript("OnEvent", function()
    C_Timer.After(2, function()
        if InCity() then
            RefreshCityList()
        else
            city.closedHere = nil -- kovetkezo varosban ujra feljon
            city:Hide()
        end
        NS.Panel_Update() -- varos mod ki/be: statisztika dobozok
    end)
end)

-- Frissites, amig kint van (mozgas kozben valtozik a tavolsag, kozben felvett quest kikerul)
local cityElapsed = 0
city:SetScript("OnUpdate", function(_, dt)
    cityElapsed = cityElapsed + dt
    if cityElapsed < 5 then return end
    cityElapsed = 0
    if not InCity() and not city.forced then city:Hide() return end
    if not city:IsMouseOver() then RefreshCityList() end
end)
city:HookScript("OnHide", function() city.forced = nil end)
-- /qf city: kezzel is megnyithato (varoson kivul is)
NS.ShowCityList = function() city.closedHere = nil; city.forced = not InCity() or nil; RefreshCityList() end

local qpopTicker = CreateFrame("Frame")
local qpopElapsed = 0
qpopTicker:SetScript("OnUpdate", function(_, dt)
    qpopElapsed = qpopElapsed + dt
    if qpopElapsed < 5 then return end
    qpopElapsed = 0
    -- varosban nincs egyenkenti popup (ott a lista van)
    if InCity() and not QuestFocusDB.noCityMode then return end
    if QuestFocusDB.noQuestPopup or InCombatLockdown() or qpop:IsShown() or not NS.QuestieAvailable() then return end
    local pc, px, py = NS.PlayerWorldPos()
    if not pc then return end
    local ok, list = pcall(BuildPickups, pc, px, py, 10)
    if not ok or not list then return end
    for _, d in ipairs(list) do
        if d.dist > NEARBY_RADIUS then break end
        if not announced[d.qid] then
            announced[d.qid] = true
            ShowQuestPopup(d)
            return
        end
    end
end)

