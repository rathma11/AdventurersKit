local ADDON_NAME, NS = ...
local L = NS.L
NS.P = NS.P or {}
local P = NS.P
local announced, BuildPickups, EstimateQuestTime, FormatTime, NEARBY_RADIUS, qpop, ShowQuestPopup, state = P.announced, P.BuildPickups, P.EstimateQuestTime, P.FormatTime, P.NEARBY_RADIUS, P.qpop, P.ShowQuestPopup, P.state

local CITY_RADIUS, CITY_MAX, CITY_VISIBLE, CITY_ROW_H = 600, 40, 12, 19
local CITY_W = 400

---------------------------------------------------------------------------
-- Quest extra info: XP jutalom (Questie QuestXP), lanc pozicio (preQuestSingle /
-- nextQuestInChain) es hogy itemmel indul-e. Cache-elve (az XP a szintedtol fugg).
---------------------------------------------------------------------------
local infoCache, infoLevel = {}, nil
local function ChainOf(qid)
    local DB = NS.Module("QuestieDB")
    if not (DB and DB.QueryQuestSingle) then return end
    local function q(id, field)
        local ok, v = pcall(DB.QueryQuestSingle, id, field)
        return ok and v or nil
    end
    local before, seen, cur = 0, { [qid] = true }, qid
    for _ = 1, 30 do
        local pre = q(cur, "preQuestSingle")
        local p = type(pre) == "table" and pre[1] or nil
        if not p or seen[p] then break end
        seen[p] = true
        before, cur = before + 1, p
    end
    local after, nxt = 0, q(qid, "nextQuestInChain")
    for _ = 1, 30 do
        if not nxt or nxt == 0 or seen[nxt] then break end
        seen[nxt] = true
        after = after + 1
        nxt = q(nxt, "nextQuestInChain")
    end
    if before + after == 0 then return end
    return before + 1, before + 1 + after
end

local function QuestExtraInfo(qid, quest)
    local lvl = UnitLevel("player")
    if infoLevel ~= lvl then wipe(infoCache); infoLevel = lvl end
    local c = infoCache[qid]
    if c then return c end
    c = {}
    local XP = NS.Module("QuestXP")
    if XP and XP.GetQuestLogRewardXP and XP.db then
        local ok, xp = pcall(XP.GetQuestLogRewardXP, XP, qid)
        if ok and tonumber(xp) and xp > 0 then c.xp = xp end
    end
    c.chainPos, c.chainLen = ChainOf(qid)
    quest = quest or NS.GetQuestieQuest(qid)
    c.byItem = quest and type(quest.Starts) == "table" and type(quest.Starts.Item) == "table"
        and #quest.Starts.Item > 0 or nil
    infoCache[qid] = c
    return c
end
NS.QuestExtraInfo = QuestExtraInfo

local function XpText(xp)
    if not xp then return "" end
    return xp >= 1000 and ("%.1fk xp"):format(xp / 1000) or ("%d xp"):format(xp)
end
NS.XpText = XpText

---------------------------------------------------------------------------
-- Varos mod: varosban / fogadoban (IsResting) nem popupol questenkent, hanem egy listaban
-- mutatja az osszes felveheto questet (gorgetheto). Belepeskor jon fel, kilepeskor eltunik.
---------------------------------------------------------------------------
local city = CreateFrame("Frame", "QuestFocusCityList", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
city:SetSize(CITY_W, 80)
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
city.foot:SetText(L["Click: marker on the quest giver. Wheel: scroll. Drag to move."])

-- Gorgetheto tartalom (egergorgo + csuszka)
local cScroll = CreateFrame("ScrollFrame", "QuestFocusCityScroll", city, "UIPanelScrollFrameTemplate")
cScroll:SetPoint("TOPLEFT", 12, -38)
local cContent = CreateFrame("Frame", nil, cScroll)
cContent:SetSize(CITY_W - 48, 10)
cScroll:SetScrollChild(cContent)

local cityRows = {}
local function CityRow(i)
    local r = cityRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, cContent)
    r:SetSize(CITY_W - 48, CITY_ROW_H - 1)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT")
    r.text:SetPoint("RIGHT", -128, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT")
    r.right:SetWidth(126)
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
        NS.TT.Pickup(self, "ANCHOR_RIGHT", d)
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
    local ok, list = pcall(BuildPickups, pc, px, py, CITY_MAX)
    if not ok or not list then return end
    for _, r in ipairs(cityRows) do r:Hide() end
    local y, n = 0, 0
    for _, d in ipairs(list) do
        if d.dist > CITY_RADIUS or n >= CITY_MAX then break end
        n = n + 1
        if announced then announced[d.qid] = true end -- kint mar ne popupoljon
        local info = QuestExtraInfo(d.qid, d.quest)
        local r = CityRow(n)
        r.data = d
        d.dist = math.floor(d.dist + 0.5)
        local col = GetQuestDifficultyColor and d.level and GetQuestDifficultyColor(d.level)
        local hex = col and ("|cff%02x%02x%02x"):format(col.r * 255, col.g * 255, col.b * 255) or "|cffffffff"
        local tags = ""
        if info.chainPos then tags = tags .. (" |cffb48cff%d/%d|r"):format(info.chainPos, info.chainLen) end
        if info.byItem then tags = tags .. " |cffff9933" .. L["item"] .. "|r" end
        r.text:SetText(("%s[%s] %s|r%s  |cff999999%s|r"):format(hex, tostring(d.level or "?"), d.name or "?",
            tags, FormatTime(EstimateQuestTime(d.quest))))
        r.right:SetText(("|cffd8c070%s|r  |cff99ccff%d yd|r"):format(XpText(info.xp), d.dist))
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", cContent, "TOPLEFT", 0, y)
        r:Show()
        y = y - CITY_ROW_H
    end
    if n == 0 then city:Hide() return end
    city.title:SetText((L["Quests to pick up here (%d)"]):format(n))
    cContent:SetHeight(math.max(-y, 1))
    local visH = math.min(n, CITY_VISIBLE) * CITY_ROW_H
    -- csuszka csak ha tobb sor van, mint ami kifer
    local needBar = n > CITY_VISIBLE
    cScroll:SetPoint("BOTTOMRIGHT", city, "TOPLEFT", CITY_W - (needBar and 34 or 12), -38 - visH)
    if cScroll.ScrollBar then cScroll.ScrollBar:SetShown(needBar) end
    if not needBar then cScroll:SetVerticalScroll(0) end
    city.foot:ClearAllPoints()
    city.foot:SetPoint("TOPLEFT", city, "TOPLEFT", 14, -38 - visH - 4)
    city:SetHeight(38 + visH + 26)
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

