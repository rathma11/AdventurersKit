local ADDON_NAME, NS = ...
local L = NS.L
NS.P = NS.P or {}
local P = NS.P
local announced, BuildPickups, EstimateQuestTime, FormatTime, NEARBY_RADIUS, qpop, ShowQuestPopup, state = P.announced, P.BuildPickups, P.EstimateQuestTime, P.FormatTime, P.NEARBY_RADIUS, P.qpop, P.ShowQuestPopup, P.state

local CITY_RADIUS, CITY_MAX, CITY_VISIBLE, CITY_ROW_H = 600, 40, 12, 19
local CITY_W = 500

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

---------------------------------------------------------------------------
-- Ignoralt helyek: QuestFocusDB.cityIgnore = { {c, x, y, name} }. Vilag koordinatan
-- (yard) tarolva, CITY_IGNORE_R sugaron belul ignoralt (varos es fogados falu is).
---------------------------------------------------------------------------
local CITY_IGNORE_R = 500
local function PlaceName()
    local z, s = GetZoneText and GetZoneText() or "", GetMinimapZoneText and GetMinimapZoneText() or ""
    if s ~= "" and s ~= z then return s .. " (" .. z .. ")" end
    return z ~= "" and z or "?"
end
local function IgnoredHere()
    local list = QuestFocusDB.cityIgnore
    if not list or #list == 0 then return end
    local pc, px, py = NS.PlayerWorldPos()
    if not pc then return end
    for i, e in ipairs(list) do
        if e.c == pc then
            local dx, dy = e.x - px, e.y - py
            if dx * dx + dy * dy <= CITY_IGNORE_R * CITY_IGNORE_R then return i, e end
        end
    end
end
NS.CityIgnoredHere = IgnoredHere

local function MakeBtn(text, w)
    local b = CreateFrame("Button", nil, city, "UIPanelButtonTemplate")
    b:SetSize(w, 20)
    b:SetText(text)
    if b:GetFontString() then b:GetFontString():SetFontObject("GameFontNormalSmall") end
    return b
end
city.ignoreBtn = MakeBtn(L["Ignore this place"], 150)
city.disableBtn = MakeBtn(L["Disable city list everywhere"], 190)
city.ignoreBtn:SetScript("OnClick", function() NS.Loud(function()
    local i, e = IgnoredHere()
    if i then
        table.remove(QuestFocusDB.cityIgnore, i)
        NS.Print(L["City list: |cffffff00%s|r is no longer ignored."], e.name or "?")
        city.ignoreBtn:SetText(L["Ignore this place"])
        return
    end
    local pc, px, py = NS.PlayerWorldPos()
    if not pc then return end
    QuestFocusDB.cityIgnore = QuestFocusDB.cityIgnore or {}
    local name = PlaceName()
    table.insert(QuestFocusDB.cityIgnore, { c = pc, x = px, y = py, name = name })
    NS.Print(L["City list: |cffffff00%s|r ignored (also next time). |cffffff00/qf city|r opens it anyway, |cffffff00/qf cityreset|r clears the ignore list."], name)
    city:Hide()
end) end)
city.ignoreBtn:SetScript("OnEnter", function(self)
    local tt = NS.TT.Begin(self, "ANCHOR_TOP", L["Ignore this place"])
    NS.TT.Note(tt, L["Don't open the list automatically here (within ~500 yd), not even next time you come back."])
    NS.TT.Finish(tt)
end)
city.ignoreBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
city.disableBtn:SetScript("OnClick", function()
    QuestFocusDB.noCityMode = true
    city:Hide()
    NS.PrintAlways(L["City list disabled everywhere (all cities and inns). Turn it back on: Options > Quest pickup > City mode."])
    NS.Panel_Update()
end)
city.disableBtn:SetScript("OnEnter", function(self)
    local tt = NS.TT.Begin(self, "ANCHOR_TOP", L["Disable city list everywhere"])
    NS.TT.Note(tt, L["Turns off the city list in every city and inn, not just here. Turn it back on: Options > Quest pickup > City mode."])
    NS.TT.Finish(tt)
end)
city.disableBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
city.dungeonBtn = MakeBtn("    " .. L["Start dungeon"], 124)
city.dungeonBtn:SetPoint("BOTTOMRIGHT", city, "BOTTOMRIGHT", -12, 12)
do
    local ic = city.dungeonBtn:CreateTexture(nil, "OVERLAY")
    ic:SetSize(14, 14)
    ic:SetPoint("LEFT", 6, 0)
    ic:SetTexture(NS.DUNGEON_ICON)
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end
city.dungeonBtn:SetScript("OnClick", function() if NS.ToggleDungeonList then NS.ToggleDungeonList() end end)
city.dungeonBtn:SetScript("OnEnter", function(self)
    local tt = NS.TT.Begin(self, "ANCHOR_TOP", L["Start dungeon"])
    NS.TT.Note(tt, NS.HasDungeonJournal() and L["Dungeons for your level and their quests; click one to open it in Dungeon Journal."]
        or L["Dungeons for your level and their quests (click: marker on the quest giver)."])
    NS.TT.Finish(tt)
end)
city.dungeonBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
city.dungeonBtn:Hide()

-- Gorgetheto tartalom (egergorgo + csuszka)
local cScroll = CreateFrame("ScrollFrame", "QuestFocusCityScroll", city, "UIPanelScrollFrameTemplate")
cScroll:SetPoint("TOPLEFT", 12, -38)
local cContent = CreateFrame("Frame", nil, cScroll)
cContent:SetSize(CITY_W - 48, 10)
cScroll:SetScrollChild(cContent)
-- Sajat gorgo kezeles: rejtett csuszkaval is mukodik, 3 sor / kattanas
cScroll:EnableMouseWheel(true)
cScroll:SetScript("OnMouseWheel", function(self, delta)
    local max = self:GetVerticalScrollRange() or 0
    local v = math.max(0, math.min(max, self:GetVerticalScroll() - delta * CITY_ROW_H * 3))
    if self.ScrollBar and self.ScrollBar:IsShown() then self.ScrollBar:SetValue(v) else self:SetVerticalScroll(v) end
end)

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
    -- dungeon quest: kis "Start dungeon" gomb a sor jobb oldalan (az XP / tavolsag elott)
    r.dBtn = NS.MakeDungeonButton(r, 14)
    r.dBtn:SetPoint("RIGHT", r, "RIGHT", -128, 0)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:Hide()
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

---------------------------------------------------------------------------
-- Teendok a varosban (a questek folott): javitas, hunter ammo, XP kaja. Kattintasra marker
-- a legkozelebbi javitora / ammo arusra / kaja arusra. Plusz Bank gomb a fejlecben.
---------------------------------------------------------------------------
-- Kuszobok (Options > Quest pickup > City to-do); 0 = az a sor ki van kapcsolva
local LIMIT_DEFAULTS = { bagPct = 70, bagFree = 10, repair = 60, ammo = 400 }
local LIMIT_KEYS = { bagPct = "cityBagPct", bagFree = "cityBagFree", repair = "cityRepairPct", ammo = "cityAmmo" }
NS.CityLimit = function(which)
    local v = tonumber(QuestFocusDB[LIMIT_KEYS[which]])
    if v == nil then v = LIMIT_DEFAULTS[which] end
    return v
end

local function BagSlots()
    local free, total = 0, 0
    local numSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    local numFree = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local n = numSlots and numSlots(bag) or 0
        local f, bagType = 0, 0
        if numFree then f, bagType = numFree(bag) end
        -- csak altalanos taskak (lőszer / soul / szakmai taska nem szamit)
        if n > 0 and (bagType == nil or bagType == 0) then
            total = total + n
            free = free + (f or 0)
        end
    end
    return free, total
end

local function CityNeeds()
    local out = {}
    -- tele taska: szazalek VAGY kevés szabad hely (barmelyik)
    local free, total = BagSlots()
    local pctLimit, freeLimit = NS.CityLimit("bagPct"), NS.CityLimit("bagFree")
    if total > 0 then
        local used = math.floor((total - free) / total * 100 + 0.5)
        if (pctLimit > 0 and used >= pctLimit) or (freeLimit > 0 and free < freeLimit) then
            out[#out + 1] = { kind = "Sell", icon = "Interface\\Icons\\INV_Misc_Bag_10",
                text = (L["Bags: %d%% full, %d free slots - sell or bank"]):format(used, free) }
        end
    end
    local REPAIR_AT, AMMO_AT = NS.CityLimit("repair") / 100, NS.CityLimit("ammo")
    -- tartossag: a legrosszabb targy aranya
    local worst
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local r = cur / max
            if not worst or r < worst then worst = r end
        end
    end
    if worst and REPAIR_AT > 0 and worst < REPAIR_AT then
        out[#out + 1] = { kind = "Repair", icon = "Interface\\Icons\\Trade_BlackSmithing",
            text = (L["Repair: your most worn item is at %d%%"]):format(math.floor(worst * 100 + 0.5)) }
    end
    -- hunter: ammo (az ammo slot darabszama)
    if select(2, UnitClass("player")) == "HUNTER" and AMMO_AT > 0 then
        local id = GetInventoryItemID("player", 0)
        local n = id and GetInventoryItemCount("player", 0) or 0
        if n < AMMO_AT then
            out[#out + 1] = { kind = "Ammo", icon = "Interface\\Icons\\INV_Ammo_Arrow_02",
                text = n > 0 and (L["Ammo: only %d left"]):format(n) or L["Ammo: none equipped"] }
        end
    end
    -- XP kaja (Buffs modul): figyeled, de nincs a taskadban
    if NS.FoodCandidates and NS.BuffSlotOff and not NS.BuffSlotOff("food")
        and not (NS.ModuleOn and not NS.ModuleOn("QuestFocus_Buffs")) then
        local ok, xp = pcall(NS.FoodCandidates)
        if ok and type(xp) == "table" and #xp == 0 then
            out[#out + 1] = { kind = "Food", icon = "Interface\\Icons\\INV_Misc_Food_15",
                text = L["XP food: none in your bags"] }
        end
    end
    for _, e in ipairs(out) do
        local ok, p, d = pcall(NS.NearestTownsfolk, e.kind)
        if ok and p then e.point, e.dist = p, d end
    end
    return out
end

local NEED_ROW_H = 18
local needRows = {}
local function NeedRow(i)
    local r = needRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, city)
    r:SetSize(CITY_W - 28, NEED_ROW_H - 1)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("LEFT", 2, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetPoint("RIGHT", -180, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -2, 0)
    r.right:SetWidth(176)
    r.right:SetJustifyH("RIGHT")
    r.right:SetWordWrap(false)
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 0.6, 0.2, 0.10)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    r:SetScript("OnClick", function(self)
        local e = self.data
        if not e then return end
        local ok, p, d = pcall(NS.NearestTownsfolk, e.kind)
        if not (ok and p) then
            NS.Loud(NS.Print, L["No known NPC for this nearby (Questie hasn't loaded its town data yet, or none on this continent)."])
            return
        end
        NS.SetWaypoint(p, p.name)
        NS.Loud(NS.Print, L["Marker: |cffffff00%s|r (%d yd)"], p.name or "?", d or 0)
    end)
    r:SetScript("OnEnter", function(self)
        local e = self.data
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(e.text, 1, 1, 1)
        if e.point then GameTooltip:AddLine((L["Nearest: %s (%d yd)"]):format(e.point.name or "?", e.dist or 0), 0.8, 0.8, 0.8) end
        GameTooltip:AddLine(L["Click: marker on the nearest one"], 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    needRows[i] = r
    return r
end

-- Fejlec gombok (a bezaras mellett, jobbrol balra): Bank, aukcioshaz, class trainer.
-- Kattintasra marker a legkozelebbire (Questie town data, a sajat frakciod).
local function HeadBtn(text, width, kind, tipTitle, tipText, anchor)
    local b = CreateFrame("Button", nil, city, "UIPanelButtonTemplate")
    b:SetSize(width, 20)
    b:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
    b:SetText(text)
    if b:GetFontString() then b:GetFontString():SetFontObject("GameFontNormalSmall") end
    b:SetScript("OnClick", function()
        local ok, p, d = pcall(NS.NearestTownsfolk, kind)
        if not (ok and p) then
            NS.Loud(NS.Print, L["No known %s nearby (Questie may still be loading its town data)."], tipTitle)
            return
        end
        NS.SetWaypoint(p, p.name)
        NS.Loud(NS.Print, L["Marker: |cffffff00%s|r (%d yd)"], p.name or "?", d or 0)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tipTitle, 1, 1, 1)
        local ok, p, d = pcall(NS.NearestTownsfolk, kind)
        if ok and p then GameTooltip:AddLine((L["Nearest: %s (%d yd)"]):format(p.name or "?", d or 0), 0.8, 0.8, 0.8) end
        GameTooltip:AddLine(tipText, 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end
city.bankBtn = HeadBtn(L["Bank"], 46, "Banker", L["Banker"], L["Click: marker on the nearest banker."], cClose)
city.ahBtn = HeadBtn(L["AH"], 36, "Auctioneer", L["Auction House"], L["Click: marker on the nearest auctioneer."], city.bankBtn)
city.trainerBtn = HeadBtn(L["Trainer"], 58, "Class Trainer", L["Class trainer"], L["Click: marker on the nearest trainer of your class."], city.ahBtn)

local function InCity() return IsResting and IsResting() end
NS.InCity = function() return InCity() and not QuestFocusDB.noCityMode end

local function RefreshCityList()
    if QuestFocusDB.noCityMode or not NS.QuestieAvailable() then city:Hide() return end
    local ignored = IgnoredHere()
    if ignored and not city.forced then city:Hide() return end
    city.ignoreBtn:SetText(ignored and L["Stop ignoring here"] or L["Ignore this place"])
    local pc, px, py = NS.PlayerWorldPos()
    if not pc then return end
    local ok, list = pcall(BuildPickups, pc, px, py, CITY_MAX)
    if not ok or not list then return end
    for _, r in ipairs(cityRows) do r:Hide() end
    local y, n = 0, 0
    local anyDungeon = false
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
        -- dungeon / raid quest: halvany voros (raid: lila) hatter a soron + Start dungeon gomb
        local dAbbr, dRaid = NS.QuestDungeon(d.quest, d.qid)
        r.text:SetPoint("RIGHT", dAbbr and -146 or -128, 0)
        if dAbbr then
            r.bg:SetColorTexture(dRaid and 0.55 or 0.75, 0.2, dRaid and 0.85 or 0.1, 0.18)
            r.bg:Show()
            r.dBtn.qid, r.dBtn.dungeon = d.qid, dAbbr
            r.dBtn:Show()
            anyDungeon = true
        else
            r.bg:Hide()
            r.dBtn:Hide()
        end
        if info.chainPos then tags = tags .. ("   %s|cffb48cff%d/%d|r"):format(NS.ChainMarkup(), info.chainPos, info.chainLen) end
        if info.byItem then tags = tags .. " |cffff9933" .. L["item"] .. "|r" end
        r.text:SetText(("%s[%s]|r %s%s%s|r%s  |cff999999%s|r"):format(hex, tostring(d.level or "?"),
            NS.DungeonTag(d.quest, d.qid), hex, d.name or "?", tags, FormatTime(EstimateQuestTime(d.quest))))
        r.right:SetText(("|cffd8c070%s|r  |cff99ccff%d yd|r"):format(XpText(info.xp), d.dist))
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", cContent, "TOPLEFT", 0, y)
        r:Show()
        y = y - CITY_ROW_H
    end
    -- teendok (javitas, ammo, XP kaja) a questek folott
    local needs = CityNeeds()
    for _, r in ipairs(needRows) do r:Hide() end
    for i, e in ipairs(needs) do
        local r = NeedRow(i)
        r.data = e
        r.icon:SetTexture(e.icon)
        r.text:SetText("|cffffb060" .. e.text .. "|r")
        r.right:SetText(e.point and ("%s  |cff99ccff%d yd|r"):format(e.point.name or "?", e.dist or 0)
            or "|cff808080" .. L["no NPC known nearby"] .. "|r")
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", city, "TOPLEFT", 14, -38 - (i - 1) * NEED_ROW_H)
        r:Show()
    end
    if n == 0 and #needs == 0 then city:Hide() return end
    local top = -38 - (#needs > 0 and (#needs * NEED_ROW_H + 6) or 0)
    city.title:SetText(n > 0 and (L["Quests to pick up here (%d)"]):format(n) or L["In town"])
    cContent:SetHeight(math.max(-y, 1))
    local visH = math.min(n, CITY_VISIBLE) * CITY_ROW_H
    -- csuszka csak ha tobb sor van, mint ami kifer
    local needBar = n > CITY_VISIBLE
    cScroll:ClearAllPoints()
    cScroll:SetPoint("TOPLEFT", city, "TOPLEFT", 12, top)
    cScroll:SetPoint("BOTTOMRIGHT", city, "TOPLEFT", CITY_W - (needBar and 34 or 12), top - math.max(visH, 1))
    cScroll:SetShown(n > 0)
    if cScroll.ScrollBar then cScroll.ScrollBar:SetShown(needBar) end
    if not needBar then cScroll:SetVerticalScroll(0) end
    city.foot:ClearAllPoints()
    city.foot:SetPoint("TOPLEFT", city, "TOPLEFT", 14, top - visH - 4)
    city.ignoreBtn:ClearAllPoints()
    city.ignoreBtn:SetPoint("TOPLEFT", city, "TOPLEFT", 12, top - visH - 20)
    city.disableBtn:ClearAllPoints()
    city.disableBtn:SetPoint("LEFT", city.ignoreBtn, "RIGHT", 6, 0)
    -- van dungeon quest a listaban: Start dungeon gomb is
    city.dungeonBtn:SetShown(anyDungeon)
    city:SetHeight(-top + visH + 52)
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
local cityElapsed, cityGen = 0, nil
city:SetScript("OnUpdate", function(_, dt)
    cityElapsed = cityElapsed + dt
    if cityElapsed < 5 then return end
    cityElapsed = 0
    if not InCity() and not city.forced then city:Hide() return end
    -- optimalizalas: csak ha mozogtal (15 yd) vagy valtozott a quest log
    local moved = NS.Moved and NS.Moved("city", 15)
    if NS.Moved and not moved and cityGen == NS.questLogGen then return end
    cityGen = NS.questLogGen
    if not city:IsMouseOver() then RefreshCityList() end
end)
city:HookScript("OnHide", function() city.forced = nil end)
-- /qf city: kezzel is megnyithato (varoson kivul es ignoralt helyen is)
NS.ShowCityList = function()
    city.closedHere = nil
    city.forced = (not InCity() or IgnoredHere()) and true or nil
    RefreshCityList()
end
NS.ResetCityIgnore = function()
    local n = QuestFocusDB.cityIgnore and #QuestFocusDB.cityIgnore or 0
    QuestFocusDB.cityIgnore = {}
    NS.Print(L["City list: ignore list cleared (%d places)."], n)
end

-- Ujraprobalkozas: belepeskor / relog utan a Questie meg toltodhet (vagy a hely meg nem
-- ismert), ilyenkor az elso frissites semmit nem ad. Amig varosban vagyunk es a lista nincs
-- kint (es nem zartuk be / ignoraltuk), 4 mp-enkent ujraprobalja.
local cityRetry, cityRetryElapsed = CreateFrame("Frame"), 0
cityRetry:SetScript("OnUpdate", function(_, dt)
    cityRetryElapsed = cityRetryElapsed + dt
    if cityRetryElapsed < 4 then return end
    cityRetryElapsed = 0
    if city:IsShown() or city.closedHere or QuestFocusDB.noCityMode or not InCity() then return end
    if InCombatLockdown() or IgnoredHere() then return end
    RefreshCityList()
end)

local qpopTicker = CreateFrame("Frame")
local qpopElapsed, qpopGen = 0, nil
qpopTicker:SetScript("OnUpdate", function(_, dt)
    qpopElapsed = qpopElapsed + dt
    if qpopElapsed < 5 then return end
    qpopElapsed = 0
    -- varosban nincs egyenkenti popup (ott a lista van)
    if InCity() and not QuestFocusDB.noCityMode then return end
    if QuestFocusDB.noQuestPopup or InCombatLockdown() or qpop:IsShown() or not NS.QuestieAvailable() then return end
    -- optimalizalas: ha 25 yd-nal kevesebbet mentel es a quest log se valtozott, ugyanaz jonne ki
    local moved = NS.Moved and NS.Moved("qpop", 25)
    if NS.Moved and not moved and qpopGen == NS.questLogGen then return end
    qpopGen = NS.questLogGen
    local pc, px, py = NS.PlayerWorldPos()
    if not pc then return end
    local ok, list = pcall(BuildPickups, pc, px, py, 10)
    if not ok or not list then return end
    for _, d in ipairs(list) do
        if d.dist > NEARBY_RADIUS then break end
        if not announced[d.qid] then
            announced[d.qid] = true
            ShowQuestPopup(d)
            qpopGen = nil -- utana a kovetkezo kozeli quest mozgas nelkul is johet
            return
        end
    end
end)

