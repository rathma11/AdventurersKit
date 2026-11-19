local ADDON_NAME, NS = ...
local L = NS.L
NS.P = NS.P or {}
local P = NS.P
local announced, BuildPickups, EstimateQuestTime, FormatTime, NEARBY_RADIUS, qpop, ShowQuestPopup, state = P.announced, P.BuildPickups, P.EstimateQuestTime, P.FormatTime, P.NEARBY_RADIUS, P.qpop, P.ShowQuestPopup, P.state

local CITY_RADIUS, CITY_MAX, CITY_VISIBLE, CITY_ROW_H = 600, 40, 12, 19
local CITY_W = 500 -- alap; a felhasznalo atmeretezheti (QuestFocusDB.citySize = { w, rows })
local CITY_MIN_W, CITY_MAX_W, CITY_MIN_ROWS, CITY_MAX_ROWS = 430, 900, 3, 30
local function CityW()
    local s = QuestFocusDB and QuestFocusDB.citySize
    return math.max(CITY_MIN_W, math.min(CITY_MAX_W, tonumber(s and s.w) or CITY_W))
end
local function CityRows()
    local s = QuestFocusDB and QuestFocusDB.citySize
    return math.max(CITY_MIN_ROWS, math.min(CITY_MAX_ROWS, tonumber(s and s.rows) or CITY_VISIBLE))
end

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
    local ids = { qid } -- a lanc osszes questje (a questlogban levo kereseshez)
    for _ = 1, 30 do
        local pre = q(cur, "preQuestSingle")
        local p = type(pre) == "table" and pre[1] or nil
        if not p or seen[p] then break end
        seen[p] = true
        ids[#ids + 1] = p
        before, cur = before + 1, p
    end
    local after, nxt = 0, q(qid, "nextQuestInChain")
    for _ = 1, 30 do
        if not nxt or nxt == 0 or seen[nxt] then break end
        seen[nxt] = true
        ids[#ids + 1] = nxt
        after = after + 1
        nxt = q(nxt, "nextQuestInChain")
    end
    if before + after == 0 then return end
    return before + 1, before + 1 + after, ids
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
    c.chainPos, c.chainLen, c.chainIds = ChainOf(qid)
    quest = quest or NS.GetQuestieQuest(qid)
    c.byItem = quest and type(quest.Starts) == "table" and type(quest.Starts.Item) == "table"
        and #quest.Starts.Item > 0 or nil
    infoCache[qid] = c
    return c
end
NS.QuestExtraInfo = QuestExtraInfo

-- A lanc questlogban levo questje (amit mar csinalsz): ezt nyitja meg a quest logban.
local function ChainQuestInLog(info)
    if not (info and info.chainIds) then return end
    local QP = NS.Module("QuestiePlayer")
    local inLog = QP and QP.currentQuestlog or {}
    for _, id in ipairs(info.chainIds) do
        if inLog[id] then return id end
    end
    if GetQuestLogIndexByID then
        for _, id in ipairs(info.chainIds) do
            local ok, idx = pcall(GetQuestLogIndexByID, id)
            if ok and idx and idx > 0 then return id end
        end
    end
end

local function OpenQuestInLog(qid)
    if InCombatLockdown() then return end
    local idx = NS.FocusInQuestLog and NS.FocusInQuestLog(qid)
    local qlf = _G.QuestLogFrame
    if qlf then
        if not qlf:IsShown() then
            if ToggleQuestLog then ToggleQuestLog() else ShowUIPanel(qlf) end
        end
        if idx and QuestLog_SetSelection then pcall(QuestLog_SetSelection, idx) end
        if QuestLog_Update then pcall(QuestLog_Update) end
        return true
    end
    -- terkep melletti quest panel (ujabb kliens)
    local wm = WorldMapFrame
    if wm and not wm:IsShown() then
        if ToggleWorldMap then ToggleWorldMap() else ShowUIPanel(wm) end
    end
    if _G.QuestMapFrame_OpenToQuestDetails then pcall(_G.QuestMapFrame_OpenToQuestDetails, qid) end
    return true
end

local function OpenChainInLog(info)
    local qid = ChainQuestInLog(info)
    if not qid then
        NS.Loud(NS.Print, L["None of this chain's quests is in your quest log yet."])
        return
    end
    OpenQuestInLog(qid)
end
NS.ChainQuestInLog, NS.OpenChainInLog = ChainQuestInLog, OpenChainInLog

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
-- valaszto vonal az also gombsor folott
city.sep = city:CreateTexture(nil, "ARTWORK")
city.sep:SetHeight(1)
city.sep:SetColorTexture(1, 0.82, 0, 0.3)

-- Lapos gomb a lista stilusahoz (a piros UIPanelButton helyett): sotet hatter, vekony arany
-- keret, hoverre vilagosabb; opcionalis kis ikon a szoveg elott. Szelesseg a szoveghez igazodik.
local function FlatBtn(text, icon, coords)
    local b = CreateFrame("Button", nil, city)
    b:SetHeight(18)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.06, 0.03, 0.85)
    local function edge(p1, p2, w, h)
        local t = b:CreateTexture(nil, "BORDER")
        t:SetColorTexture(1, 0.82, 0, 0.35)
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) else t:SetHeight(h) end
        return t
    end
    b.edges = { edge("TOPLEFT", "TOPRIGHT", nil, 1), edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1),
        edge("TOPLEFT", "BOTTOMLEFT", 1), edge("TOPRIGHT", "BOTTOMRIGHT", 1) }
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(1, 0.82, 0, 0.15)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if icon then
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(13, 13)
        b.icon:SetPoint("LEFT", 4, 0)
        b.icon:SetTexture(icon)
        if coords then b.icon:SetTexCoord(unpack(coords)) else b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        b.text:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
    else
        b.text:SetPoint("CENTER", 0, 0)
    end
    function b:SetText(t)
        self.text:SetText(t)
        self:SetWidth(math.ceil(self.text:GetStringWidth()) + (self.icon and 25 or 16))
    end
    b:SetScript("OnEnable", function(self) self.text:SetFontObject("GameFontNormalSmall") end)
    b:SetScript("OnDisable", function(self) self.text:SetFontObject("GameFontDisableSmall") end)
    b:SetText(text)
    return b
end
city.dungeonBtn = FlatBtn(L["Dungeon quests"], NS.DUNGEON_ICON)
city.dungeonBtn:SetPoint("BOTTOMRIGHT", city, "BOTTOMRIGHT", -22, 12)
city.dungeonBtn:SetScript("OnClick", function() if NS.ToggleDungeonList then NS.ToggleDungeonList() end end)
city.dungeonBtn:SetScript("OnEnter", function(self)
    local tt = NS.TT.Begin(self, "ANCHOR_TOP", L["Dungeon quests"])
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
    r.text:SetPoint("RIGHT", -96, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT")
    r.right:SetWidth(94)
    r.right:SetJustifyH("RIGHT")
    -- dungeon quest: kis "Start dungeon" gomb a sor jobb oldalan (az XP / tavolsag elott)
    r.dBtn = NS.MakeDungeonButton(r, 14)
    r.dBtn:SetPoint("RIGHT", r, "RIGHT", -96, 0)
    -- quest lanc (lanc ikon + 2/5): kattintasra a quest log a lanc nalad levo questjenel
    r.chain = CreateFrame("Button", nil, r)
    r.chain:SetHeight(CITY_ROW_H - 3)
    r.chain.label = r.chain:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.chain.label:SetPoint("LEFT")
    local chl = r.chain:CreateTexture(nil, "HIGHLIGHT")
    chl:SetAllPoints()
    chl:SetColorTexture(0.7, 0.55, 1, 0.2)
    r.chain:SetScript("OnClick", function(self)
        local d = self:GetParent().data
        if d then OpenChainInLog(QuestExtraInfo(d.qid, d.quest)) end
    end)
    r.chain:SetScript("OnEnter", function(self)
        local d = self:GetParent().data
        if not d then return end
        local info = QuestExtraInfo(d.qid, d.quest)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((L["Quest chain: part %d of %d"]):format(info.chainPos or 0, info.chainLen or 0), 0.7, 0.55, 1)
        local cur = ChainQuestInLog(info)
        local q = cur and NS.GetQuestieQuest(cur)
        if cur then
            GameTooltip:AddLine((L["In your log: %s"]):format(q and q.name or ("#" .. cur)), 1, 1, 1)
            GameTooltip:AddLine(L["Click: open it in the quest log"], 0.5, 0.5, 0.5)
        else
            GameTooltip:AddLine(L["None of this chain's quests is in your quest log yet."], 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    r.chain:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.chain:Hide()
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
-- Kuszobok (Options > City list > City to-do); 0 = az a sor ki van kapcsolva
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

NS.CityBagSlots = BagSlots

local function CityNeeds()
    local out = {}
    -- tele taska: szazalek VAGY kevés szabad hely (barmelyik)
    local free, total = BagSlots()
    local pctLimit, freeLimit = NS.CityLimit("bagPct"), NS.CityLimit("bagFree")
    if total > 0 then
        local used = math.floor((total - free) / total * 100 + 0.5)
        if (pctLimit > 0 and used >= pctLimit) or (freeLimit > 0 and free <= freeLimit) then
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

---------------------------------------------------------------------------
-- Directions: egy lenyilo menu a fejlecben, mint a varosi or utbaigazitasa. Minden sor a
-- legkozelebbi ilyen NPC-t mutatja tavolsaggal; kattintasra marker. Szakma trainerek almenuben.
---------------------------------------------------------------------------
local TRK = "Interface\\Minimap\\Tracking\\"
local GUIDE = {
    { kind = "Auctioneer", label = L["Auction House"], icon = TRK .. "Auctioneer" },
    { kind = "Banker", label = L["Bank"], icon = TRK .. "Banker" },
    { kind = "Flight Master", label = L["Flight Master"], icon = TRK .. "FlightMaster" },
    { kind = "Innkeeper", label = L["Inn"], icon = TRK .. "Innkeeper" },
    { kind = "Class Trainer", label = L["Class Trainer"], icon = TRK .. "Class" },
    { sub = "prof", label = L["Profession Trainer"], icon = TRK .. "Profession" },
    { kind = "Weapon Master", label = L["Weapons Trainer"], icon = "Interface\\Icons\\INV_Sword_04" },
    { kind = "Stable Master", label = L["Stable Master"], icon = TRK .. "StableMaster", class = "HUNTER" },
    { kind = "Repair", label = L["Repair"], icon = TRK .. "Repair" },
    { kind = "Food", label = L["Food & Drink"], icon = TRK .. "Food" },
    { kind = "Ammo", label = L["Ammo"], icon = TRK .. "Ammunition", class = "HUNTER" },
    { kind = "Battlemaster", label = L["Battlemaster"], icon = TRK .. "BattleMaster" },
}
local IC = "Interface\\Icons\\"
local PROFS = {
    { 171, L["Alchemy"], IC .. "Trade_Alchemy" }, { 164, L["Blacksmithing"], IC .. "Trade_BlackSmithing" },
    { 185, L["Cooking"], IC .. "INV_Misc_Food_15" }, { 333, L["Enchanting"], IC .. "Trade_Engraving" },
    { 202, L["Engineering"], IC .. "Trade_Engineering" }, { 129, L["First Aid"], IC .. "Spell_Holy_SealOfSacrifice" },
    { 356, L["Fishing"], IC .. "Trade_Fishing" }, { 182, L["Herbalism"], IC .. "Spell_Nature_NatureTouchGrow" },
    { 165, L["Leatherworking"], IC .. "INV_Misc_ArmorKit_17" }, { 186, L["Mining"], IC .. "Trade_Mining" },
    { 393, L["Skinning"], IC .. "INV_Misc_Pelt_Wolf_01" }, { 197, L["Tailoring"], IC .. "Trade_Tailoring" },
    { 762, L["Riding"], IC .. "Spell_Nature_Swiftness" },
}

local MENU_W, MENU_ROW = 170, 18
local function MakeMenu(name)
    local m = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    m:SetFrameStrata("DIALOG")
    m:SetWidth(MENU_W)
    m:EnableMouse(true)
    m:Hide()
    if m.SetBackdrop then
        m:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        m:SetBackdropColor(0.06, 0.05, 0.03, 0.96)
        m:SetBackdropBorderColor(0.95, 0.78, 0.40, 1)
    end
    m.rows = {}
    return m
end
local menu, subMenu = MakeMenu("AdventurersKitGuideMenu"), MakeMenu("AdventurersKitGuideSubMenu")

local function MenuRow(m, i)
    local r = m.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, m)
    r:SetSize(MENU_W - 12, MENU_ROW)
    r:SetPoint("TOPLEFT", 6, -6 - (i - 1) * MENU_ROW)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("LEFT", 2, 0)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetJustifyH("LEFT")
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -4, 0)
    r.right:SetJustifyH("RIGHT")
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.15)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    m.rows[i] = r
    return r
end

local function GoTo(e)
    if not e.point then
        NS.Loud(NS.Print, L["No known %s nearby (Questie may still be loading its town data)."], e.label)
        return
    end
    NS.SetWaypoint(e.point, e.point.name)
    NS.Loud(NS.Print, L["Marker: |cffffff00%s|r (%d yd)"], e.point.name or "?", e.dist or 0)
    menu:Hide(); subMenu:Hide()
end

-- sorok kitoltese: entries = { label, icon, point, dist, sub, mine }
local function FillMenu(m, entries, onSub)
    for _, r in ipairs(m.rows) do r:Hide() end
    for i, e in ipairs(entries) do
        local r = MenuRow(m, i)
        r.icon:SetTexture(e.icon)
        if e.crop then r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else r.icon:SetTexCoord(0, 1, 0, 1) end
        r.icon:SetShown(e.icon ~= nil)
        local col = (e.sub or e.point) and (e.mine and "|cff40ff40" or "|cffffd100") or "|cff808080"
        r.text:SetText(col .. e.label .. "|r")
        if e.sub then
            r.right:SetText("|cffffd100>|r")
        else
            r.right:SetText("") -- tavolsag: a tooltipben (folevive)
        end
        r:SetScript("OnClick", function(self)
            if e.sub then onSub(self, e) else GoTo(e) end
        end)
        r:SetScript("OnEnter", function(self)
            if e.sub then onSub(self, e) return end
            subMenu:SetShown(subMenu:IsShown() and m == subMenu)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(e.label, 1, 1, 1)
            if e.point then
                GameTooltip:AddLine((L["Nearest: %s (%d yd)"]):format(e.point.name or "?", e.dist or 0), 0.8, 0.8, 0.8)
                GameTooltip:AddLine(L["Click: marker on the nearest one"], 0.5, 0.5, 0.5)
            else
                GameTooltip:AddLine(L["None known on this continent for your faction."], 0.6, 0.6, 0.6, true)
            end
            GameTooltip:Show()
        end)
        r:Show()
    end
    m:SetHeight(12 + #entries * MENU_ROW)
end

local function Nearest(kind)
    local ok, p, d = pcall(NS.NearestTownsfolk, kind)
    if ok and p then return p, d end
end

-- Csak ami itt, a telepulesen elerheto (GUIDE_R yardon belul): kis faluban nincs AH, bank...
local GUIDE_R = 700
-- telepulesen kivul (ikonnal / /ak city nyitva): a legkozelebbi, barmilyen messze
local function GuideR() return (NS.InTown and NS.InTown()) and GUIDE_R or math.huge end
local function ProfList()
    local mine = {}
    local QP = NS.Module("QuestieProfessions")
    if QP and QP.GetPlayerProfessions then
        local ok, t = pcall(QP.GetPlayerProfessions, QP)
        if ok and type(t) == "table" then mine = t end
    end
    local list = {}
    for _, pr in ipairs(PROFS) do
        local p, d = Nearest("Prof:" .. pr[1])
        if p and d and d <= GuideR() then
            list[#list + 1] = { label = pr[2], icon = pr[3], crop = true, point = p, dist = d, mine = mine[pr[1]] ~= nil }
        end
    end
    -- a sajat szakmaid elol
    table.sort(list, function(a, b)
        if a.mine ~= b.mine then return a.mine end
        return a.label < b.label
    end)
    return list
end

local function ShowProfMenu(anchorRow)
    local list = ProfList()
    if #list == 0 then subMenu:Hide() return end
    FillMenu(subMenu, list)
    subMenu:ClearAllPoints()
    subMenu:SetPoint("TOPLEFT", anchorRow, "TOPRIGHT", 8, 6)
    subMenu:Show()
end

local function ShowGuideMenu(anchor)
    local cls = select(2, UnitClass("player"))
    local list = {}
    for _, g in ipairs(GUIDE) do
        if not g.class or g.class == cls then
            local e = { label = g.label, icon = g.icon, sub = g.sub }
            if g.sub then
                if #ProfList() > 0 then list[#list + 1] = e end
            else
                e.point, e.dist = Nearest(g.kind)
                if e.point and e.dist and e.dist <= GuideR() then list[#list + 1] = e end
            end
        end
    end
    if #list == 0 then
        NS.Loud(NS.Print, L["Directions: nothing known around here."])
        return
    end
    FillMenu(menu, list, function(row) ShowProfMenu(row) end)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", city, "TOPRIGHT", 4, 0) -- a lista mellett, oldalt
    subMenu:Hide()
    menu:Show()
end
-- kattintas mashova / ESC: bezar
menu:SetScript("OnHide", function() subMenu:Hide() end)
tinsert(UISpecialFrames, "AdventurersKitGuideMenu")
city:HookScript("OnHide", function() menu:Hide() end)

city.guideBtn = FlatBtn(L["Directions"], TRK .. "None")
city.guideBtn.icon:SetTexture("Interface\\GossipFrame\\GossipGossipIcon")
city.guideBtn.icon:SetTexCoord(0, 1, 0, 1)
do -- kis lefele nyil a szoveg utan
    local b = city.guideBtn
    b.arrow = b:CreateTexture(nil, "ARTWORK")
    b.arrow:SetSize(10, 10)
    b.arrow:SetPoint("LEFT", b.text, "RIGHT", 3, -1)
    b.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    b:SetWidth(b:GetWidth() + 12)
end
city.guideBtn:SetPoint("RIGHT", cClose, "LEFT", -4, 0)
city.guideBtn:SetScript("OnClick", function(self)
    if menu:IsShown() then menu:Hide() else ShowGuideMenu(self) end
end)
city.guideBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L["Directions"], 1, 1, 1)
    GameTooltip:AddLine(L["Like asking a guard: bank, auction house, trainers, inn, flight master... with the distance to the nearest one. Click one for a marker."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
city.guideBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- Atmeretezes: jobb also sarok fogantyu. Szelesseg szabadon (CITY_MIN_W..CITY_MAX_W),
-- magassag sorokra kerekitve (ennyi quest sor latszik gorgetes nelkul). Mentve: citySize.
---------------------------------------------------------------------------
city:SetResizable(true)
if city.SetResizeBounds then
    city:SetResizeBounds(CITY_MIN_W, 120, CITY_MAX_W, 900)
elseif city.SetMinResize then
    city:SetMinResize(CITY_MIN_W, 120)
    city:SetMaxResize(CITY_MAX_W, 900)
end
-- szelesseg fuggo elemek (sorok, gorgeto) - atmeretezes kozben elo frissites
function city.ApplyWidth(w)
    w = w or CityW()
    if not city.sizing then city:SetWidth(w) end
    cContent:SetWidth(w - 48)
    for _, r in ipairs(cityRows) do r:SetWidth(w - 48) end
    for _, r in ipairs(needRows) do r:SetWidth(w - 28) end
    if city.lastTop then
        cScroll:ClearAllPoints()
        cScroll:SetPoint("TOPLEFT", city, "TOPLEFT", 12, city.lastTop)
        cScroll:SetPoint("BOTTOMRIGHT", city, "TOPLEFT", w - (city.lastBar and 34 or 12),
            city.lastTop - math.max(city.lastVisH or 0, 1))
    end
end
local grip = CreateFrame("Button", nil, city)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -5, 5)
grip:SetFrameLevel(city:GetFrameLevel() + 5)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", function(_, btn)
    if btn ~= "LeftButton" then return end
    city.sizing = true
    city:StartSizing("BOTTOMRIGHT")
end)
grip:SetScript("OnMouseUp", function()
    if not city.sizing then return end
    city:StopMovingOrSizing()
    city.sizing = nil
    local fixed = -(city.lastTop or -38) + (city.lastBottom or 59)
    local rows = math.floor((city:GetHeight() - fixed) / CITY_ROW_H + 0.5)
    QuestFocusDB.citySize = {
        w = math.floor(math.max(CITY_MIN_W, math.min(CITY_MAX_W, city:GetWidth())) + 0.5),
        rows = math.max(CITY_MIN_ROWS, math.min(CITY_MAX_ROWS, rows)),
    }
    NS.RefreshCityList()
end)
grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Drag to resize"], 1, 1, 1)
    GameTooltip:AddLine(L["Width, and how many quests are shown without scrolling. Right-click: default size."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
grip:RegisterForClicks("RightButtonUp")
grip:SetScript("OnClick", function(_, btn)
    if btn ~= "RightButton" then return end
    QuestFocusDB.citySize = nil
    NS.RefreshCityList()
end)
city:HookScript("OnSizeChanged", function(self, w)
    if self.sizing then self.ApplyWidth(w) end
end)

-- Telepules: pihenes (varos / fogado epulete), vagy egy innkeeper INN_R yardon belul (kis
-- falvak: ott csak a fogadoban pihensz, de a falu mar "varos"). Taxi repules kozben nem.
local INN_R = 250
local nearInn, nearInnAt = false, -10
local function NearInn()
    if GetTime() - nearInnAt < 3 then return nearInn end
    nearInnAt = GetTime()
    local ok, p, d = pcall(NS.NearestTownsfolk, "Innkeeper")
    nearInn = (ok and p and d and d <= INN_R) and true or false
    return nearInn
end
-- Alvozsak (Cozy Sleeping Bag, buff 429959): kint a vilagban is "resting"-et ad, az nem varos.
-- Harcban az aurak secret ertekek: ott a legutobbi (harcon kivuli) eredmeny marad.
local SLEEP_BAG_ID = 429959
local bagRest, bagRestAt, bagRestWas = false, -10, nil
local function SleepingBagRest()
    if InCombatLockdown() then return bagRest end
    -- pihenes allapot valtozott (lefekudtel / felalltal): ne a regi cache-bol valaszoljon
    local resting = IsResting and IsResting() or false
    if resting == bagRestWas and GetTime() - bagRestAt < 2 then return bagRest end
    bagRestWas = resting
    bagRestAt = GetTime()
    local found = false
    pcall(function()
        for i = 1, 40 do
            local name, spellId
            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
                if not a then break end
                name, spellId = a.name, a.spellId
            else
                local _
                name, _, _, _, _, _, _, _, _, spellId = UnitAura("player", i, "HELPFUL")
                if not name then break end
            end
            if spellId == SLEEP_BAG_ID or (type(name) == "string" and name:find("Sleeping Bag", 1, true)) then
                found = true
                break
            end
        end
    end)
    bagRest = found
    return bagRest
end
local function InCity()
    if UnitOnTaxi and UnitOnTaxi("player") then return false end
    if NearInn() then return true end
    return (IsResting and IsResting() and not SleepingBagRest()) and true or false
end
NS.InCity = function() return InCity() and not QuestFocusDB.noCityMode end
NS.InTown = InCity -- telepulesen vagy-e (a city list kapcsolotol fuggetlenul)

-- Magatol nyilik-e (Options > City list): a lista be van kapcsolva es "Open automatically in
-- towns" is. Kulonben csak a panel ikonja / a /ak city nyitja (city.forced).
-- "Hide for 20 min": eddig (time()) magatol nem nyilik; karakterenkent, /reload utan is el.
local HIDE_SECS = 20 * 60
local function HiddenUntil()
    local t = tonumber(NS.CharDB().cityHideUntil)
    if t and t > time() then return t end
end
NS.CityHiddenUntil = HiddenUntil
local function AutoOpen()
    return not QuestFocusDB.noCityMode and not QuestFocusDB.cityNoAuto and not HiddenUntil()
end
NS.CityAutoOpen = AutoOpen

-- also sor bal oldalan: elrejtes 20 percre (a panel ikonja / /ak city kozben is megnyitja)
city.hideBtn = NS.Style.FlatButton(city, L["Hide for 20 min"], 110, 18)
city.hideBtn:SetPoint("BOTTOMLEFT", city, "BOTTOMLEFT", 12, 12)
city.hideBtn:SetScript("OnClick", function()
    NS.CharDB().cityHideUntil = time() + HIDE_SECS
    city.closedHere = true
    city.hideWhy = "hidden for 20 min"
    city:Hide()
    NS.Loud(NS.Print, L["City list hidden for 20 minutes. The town icon on the panel or /ak city still opens it."])
end)
city.hideBtn:SetScript("OnEnter", function(self)
    local tt = NS.TT.Begin(self, "ANCHOR_TOP", L["Hide for 20 min"])
    NS.TT.Note(tt, L["Closes the list and it won't open by itself for 20 minutes, not even in the next town (also after /reload). The town icon on the panel or /ak city still opens it."])
    NS.TT.Finish(tt)
end)
city.hideBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ures lista (kezzel nyitva, nincs quest es teendo): egy sor szoveg a questek helyen
city.empty = city:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
city.empty:SetJustifyH("LEFT")
city.empty:SetWordWrap(false)
city.empty:Hide()

local function RefreshCityList()
    if not NS.QuestieAvailable() then city:Hide() return end
    -- kikapcsolt city list: csak a kezzel nyitott (ikon, /ak city) marad kint
    if QuestFocusDB.noCityMode and not city.forced then city:Hide() return end
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
        r.text:SetPoint("RIGHT", dAbbr and -114 or -96, 0)
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
        if info.byItem then tags = tags .. " |cffff9933" .. L["item"] .. "|r" end
        -- lanc: kulon kattinthato gomb a nev utan (helyet hagyunk neki a szoveg vegen)
        local chainW = 0
        if info.chainPos then
            r.chain.label:SetText(("%s|cffb48cff%d/%d|r"):format(NS.ChainMarkup(), info.chainPos, info.chainLen))
            chainW = math.ceil(r.chain.label:GetStringWidth()) + 4
            r.chain:SetWidth(chainW)
        end
        r.text:SetPoint("RIGHT", (dAbbr and -114 or -96) - (chainW > 0 and chainW + 8 or 0), 0)
        r.text:SetText(("%s[%s]|r %s%s%s|r%s"):format(hex, tostring(d.level or "?"),
            NS.DungeonTag(d.quest, d.qid), hex, d.name or "?", tags))
        if chainW > 0 then
            local maxW = r.text:GetWidth()
            local w = r.text:GetStringWidth()
            if maxW and maxW > 0 then w = math.min(w, maxW) end
            r.chain:ClearAllPoints()
            r.chain:SetPoint("LEFT", r.text, "LEFT", math.ceil(w) + 8, 0)
            r.chain:Show()
        else
            r.chain:Hide()
        end
        r.right:SetText(("|cffd8c070%s|r |cff99ccff%d yd|r"):format(XpText(info.xp), d.dist))
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
    local empty = n == 0 and #needs == 0
    if empty and not city.forced then city:Hide() return end
    local town = InCity()
    local top = -38 - (#needs > 0 and (#needs * NEED_ROW_H + 6) or 0)
    if n > 0 then
        city.title:SetText((town and L["Quests to pick up here (%d)"] or L["Quests to pick up nearby (%d)"]):format(n))
    else
        city.title:SetText(town and L["In town"] or L["Not in town"])
    end
    city.empty:ClearAllPoints()
    city.empty:SetPoint("TOPLEFT", city, "TOPLEFT", 14, top - 3)
    city.empty:SetPoint("RIGHT", city, "RIGHT", -14, 0)
    city.empty:SetText(town and L["Nothing to do here: no quests to pick up nearby, no errands."]
        or L["No quests to pick up nearby, no errands. Directions: the nearest bank, trainers..."])
    city.empty:SetShown(empty)
    cContent:SetHeight(math.max(-y, 1))
    local rowsMax = CityRows()
    local visH = empty and CITY_ROW_H or math.min(n, rowsMax) * CITY_ROW_H
    -- csuszka csak ha tobb sor van, mint ami kifer
    local needBar = n > rowsMax
    city.lastTop, city.lastN, city.lastVisH, city.lastBar = top, n, visH, needBar
    city.ApplyWidth()
    cScroll:ClearAllPoints()
    cScroll:SetPoint("TOPLEFT", city, "TOPLEFT", 12, top)
    cScroll:SetPoint("BOTTOMRIGHT", city, "TOPLEFT", CityW() - (needBar and 34 or 12), top - math.max(visH, 1))
    cScroll:SetShown(n > 0)
    if cScroll.ScrollBar then cScroll.ScrollBar:SetShown(needBar) end
    if not needBar then cScroll:SetVerticalScroll(0) end
    city.foot:ClearAllPoints()
    city.foot:SetPoint("TOPLEFT", city, "TOPLEFT", 14, top - visH - 4)
    city.foot:SetShown(n > 0)
    -- also sor: vonal + Hide for 20 min (bal) + Dungeon quests (jobb, ha van dungeon quest)
    city.sep:ClearAllPoints()
    city.sep:SetPoint("TOPLEFT", city, "TOPLEFT", 12, top - visH - 20)
    city.sep:SetPoint("TOPRIGHT", city, "TOPRIGHT", -12, top - visH - 20)
    city.dungeonBtn:SetShown(anyDungeon)
    city.lastBottom = 59
    city:SetHeight(-top + visH + city.lastBottom)
    if not city:IsShown() and (city.forced or (town and AutoOpen() and not city.closedHere)) then city:Show() end
end

NS.RefreshCityList = RefreshCityList

local cityEv = CreateFrame("Frame")
cityEv:RegisterEvent("PLAYER_UPDATE_RESTING")
cityEv:RegisterEvent("PLAYER_ENTERING_WORLD")
cityEv:SetScript("OnEvent", function()
    C_Timer.After(2, function()
        if InCity() then
            if city:IsShown() or AutoOpen() then RefreshCityList() end
        else
            city.closedHere = nil -- kovetkezo varosban ujra feljon
            if not city.forced then city:Hide() end
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
    if not InCity() and not city.forced then city.hideWhy = "left town"; city:Hide() return end
    -- optimalizalas: csak ha mozogtal (15 yd) vagy valtozott a quest log
    local moved = NS.Moved and NS.Moved("city", 15)
    if NS.Moved and not moved and cityGen == NS.questLogGen then return end
    cityGen = NS.questLogGen
    if not city:IsMouseOver() then RefreshCityList() end
end)
city:HookScript("OnHide", function()
    NS.Debug("city", "city list closed: %s", city.hideWhy or "closed (X / Esc / no Questie / no data)")
    city.hideWhy = nil
    city.forced = nil
end)
city:HookScript("OnShow", function()
    NS.Debug("city", "city list opened: %s", city.forced and "by you (panel icon / /ak city)" or "automatically in town")
end)
-- miert vagy (nem) telepulesen: debug szoveg
local function InCityWhy()
    if UnitOnTaxi and UnitOnTaxi("player") then return "no (on a taxi)" end
    if NearInn() then return ("yes (innkeeper within %d yd)"):format(INN_R) end
    if IsResting and IsResting() then
        return SleepingBagRest() and "no (resting from a sleeping bag)" or "yes (resting area)"
    end
    return "no (not resting, no innkeeper nearby)"
end
-- Panel ikon / /ak city: kezzel nyitva (telepulesen kivul is, es akkor is, ha magatol nem
-- nyilik). Kezzel nyitva kint marad, amig be nem zarod (a telepulest elhagyva is).
NS.ShowCityList = function()
    if not NS.QuestieAvailable() then
        NS.Loud(NS.Print, L["The city list needs Questie."])
        return
    end
    city.closedHere = nil
    city.forced = true
    RefreshCityList()
end
NS.CityListShown = function() return city:IsShown() end
NS.ToggleCityList = function()
    if city:IsShown() then
        city.closedHere = true
        city.hideWhy = "toggled off by you"
        city:Hide()
    else
        NS.ShowCityList()
    end
end

-- 0.7.9: a "Don't open here again" helyek megszuntek; a regi mentett listakat egyszer toroljuk
local cleanEv = CreateFrame("Frame")
cleanEv:RegisterEvent("PLAYER_LOGIN")
cleanEv:SetScript("OnEvent", function()
    local db = QuestFocusDB
    if type(db) ~= "table" then return end
    db.cityIgnore = nil
    for _, c in pairs(type(db.chars) == "table" and db.chars or {}) do
        if type(c) == "table" then rawset(c, "cityIgnore", nil) end
    end
end)

-- Ujraprobalkozas: belepeskor / relog utan a Questie meg toltodhet (vagy a hely meg nem
-- ismert), ilyenkor az elso frissites semmit nem ad. Amig varosban vagyunk es a lista nincs
-- kint (es nem zartuk be), 4 mp-enkent ujraprobalja.
local cityRetry, cityRetryElapsed = CreateFrame("Frame"), 0
cityRetry:SetScript("OnUpdate", function(_, dt)
    cityRetryElapsed = cityRetryElapsed + dt
    if cityRetryElapsed < 4 then return end
    cityRetryElapsed = 0
    -- falu (innkeeper kozelseg) be / ki: nincs ra esemeny, itt figyeljuk
    local inNow = InCity() and true or false
    if inNow ~= city.wasIn then
        city.wasIn = inNow
        if NS.DebugOn("city") then
            NS.Debug("city", "in town: %s%s", InCityWhy(), inNow and (AutoOpen() and ", auto open on"
                or (", auto open off (%s)"):format(QuestFocusDB.noCityMode and "city list off" or QuestFocusDB.cityNoAuto
                    and "auto open setting off" or "hidden for 20 min")) or "")
        end
        if not inNow then
            city.closedHere = nil -- kovetkezo telepulesen ujra feljon
            if not city.forced then city.hideWhy = "left town"; city:Hide() end
        end
        NS.Panel_Update()
    end
    if city:IsShown() or city.closedHere or not AutoOpen() or not inNow then return end
    if InCombatLockdown() then return end
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
    -- taxi repules kozben ne (ott ugysem tudsz leszallni a questert)
    if UnitOnTaxi and UnitOnTaxi("player") then return end
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

-- Debug: varos lista pillanatkep (Core\DebugLog.lua)
NS.DebugSnapshot("city", function(out)
    out[#out + 1] = "In town: " .. InCityWhy()
    local hu = HiddenUntil()
    out[#out + 1] = ("City list: %s | shown %s | opened by you %s | closed here %s | auto open %s%s"):format(
        QuestFocusDB.noCityMode and "off" or "on", tostring(city:IsShown()), tostring(city.forced == true),
        tostring(city.closedHere == true), tostring(AutoOpen() and true or false),
        hu and (" | hidden for %d more min"):format(math.ceil((hu - time()) / 60)) or "")
    local free, total = BagSlots()
    out[#out + 1] = ("Bags: %d free of %d | limits: bag %d%% / %d free, repair %d%%, ammo %d"):format(free, total,
        NS.CityLimit("bagPct"), NS.CityLimit("bagFree"), NS.CityLimit("repair"), NS.CityLimit("ammo"))
    local ok, needs = pcall(CityNeeds)
    if ok then
        out[#out + 1] = ("Errands: %d"):format(#needs)
        for _, e in ipairs(needs) do
            out[#out + 1] = ("  %s: %s%s"):format(e.kind, e.text, e.dist and (" | nearest %d yd"):format(e.dist) or " | no NPC known")
        end
    else
        out[#out + 1] = "Errands: error " .. tostring(needs)
    end
end)
