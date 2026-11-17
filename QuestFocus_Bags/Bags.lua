-- QuestFocus: quest itemek a taskaban
--  * lista a taska mellett (melyik questhez kell, mennyi felesleges, mi van a bankban)
--  * Bagnon slotok szinezese (kell / kesz / questet indit / felesleges)
--  * hasznalhato quest item gomb a QuestFocus panel mellett (+ billentyu)
--  * nem eladhato, felesleges quest itemek eldobasa (egyenkent rakerdez)

local NS = _G.QuestFocusNS -- a QuestFocus (alap) addon kozos nevtere
if not NS then return end
local L = NS.L
local Print, state = NS.Print, NS.state

local QUEST_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12
local MAX_ROWS = 14
local COLORS = {
    need     = { 1, 0.82, 0 },     -- aktiv questhez kell
    done     = { 0.2, 1, 0.2 },    -- megvan / kesz quest, leadashoz kell
    starts   = { 0.3, 0.9, 1 },    -- questet indit
    leftover = { 0.55, 0.55, 0.55 }, -- nincs hozza aktiv quest
}

BINDING_HEADER_QUESTFOCUS = "QuestFocus"
_G["BINDING_NAME_CLICK QuestFocusUseItem:LeftButton"] = L["Use the selected quest's item"]

---------------------------------------------------------------------------
-- Container API (classic es modern)
---------------------------------------------------------------------------
local function ContainerSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

-- itemID, count, icon, link, noValue
local function ContainerItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local i = C_Container.GetContainerItemInfo(bag, slot)
        if i then return i.itemID, i.stackCount, i.iconFileID, i.hyperlink, i.hasNoValue end
    elseif GetContainerItemInfo then
        local tex, count, _, _, _, _, link, _, noValue, id = GetContainerItemInfo(bag, slot)
        return id, count, tex, link, noValue
    end
end

local function ContainerQuestInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemQuestInfo then
        local i = C_Container.GetContainerItemQuestInfo(bag, slot)
        if i then return i.isQuestItem, i.questID, i.isActive end
    elseif GetContainerItemQuestInfo then
        return GetContainerItemQuestInfo(bag, slot)
    end
end

local function PickupItem(bag, slot)
    if C_Container and C_Container.PickupContainerItem then C_Container.PickupContainerItem(bag, slot)
    elseif PickupContainerItem then PickupContainerItem(bag, slot) end
end

local function SellPriceZero(id, noValue)
    if noValue ~= nil then return noValue and true or false end
    local price = select(11, GetItemInfo(id))
    return price == 0
end

local function Bags()
    local B = _G.BagBrother
    if not (B and B.Frames) then B = _G.Bagnon end
    if B and B.Frames then return B end
end

---------------------------------------------------------------------------
-- Adatgyujtes
---------------------------------------------------------------------------
-- itemId -> { {qid, title, text, needed, done, use}, ... }
local function QuestNeeds()
    local needs = {}
    local function add(itemId, e)
        needs[itemId] = needs[itemId] or {}
        table.insert(needs[itemId], e)
    end
    for i = 1, NS.NumLogEntries() do
        local title, isHeader, qid, done = NS.GetLogEntry(i)
        if not isHeader and qid and qid > 0 then
            local q = NS.GetQuestieQuest(qid)
            if q then
                local objItems = {}
                for _, o in pairs(q.Objectives or {}) do
                    if type(o) == "table" and o.Type == "item" and o.Id then
                        objItems[o.Id] = true
                        add(o.Id, {
                            qid = qid, title = title, done = done or o.Completed,
                            questDone = done and true or false, -- az egesz quest kesz (leadhato)
                            collected = tonumber(o.Collected), needed = tonumber(o.Needed),
                        })
                    end
                end
                local used = {}
                for _, id in pairs(q.requiredSourceItems or {}) do used[id] = true end
                if tonumber(q.sourceItemId) and q.sourceItemId > 0 then used[q.sourceItemId] = true end
                for id in pairs(used) do
                    if not objItems[id] then add(id, { qid = qid, title = title, done = done, questDone = done, use = true }) end
                end
            end
        end
    end
    return needs
end

-- BagBrother cache: a bank tartalma (akkor is, ha nem vagy a banknal)
local function BankCounts()
    local B = Bags()
    local cache = B and B.player and B.player.cache
    local counts = {}
    if type(cache) ~= "table" then return counts end
    local lastInv = B.NumBags or NUM_BAG_SLOTS or 4
    for bag, data in pairs(cache) do
        if type(bag) == "number" and (bag < 0 or bag > lastInv) and type(data) == "table"
            and type(data.items) == "table" and bag ~= -2 then -- -2: kulcstarto
            for _, str in pairs(data.items) do
                if type(str) == "string" then
                    local id = tonumber(str:match("^(%d+)"))
                    if id then counts[id] = (counts[id] or 0) + (tonumber(str:match(";(%d+)$")) or 1) end
                end
            end
        end
    end
    return counts
end

local function ItemHasUse(id)
    if C_Item and C_Item.GetItemSpell then return C_Item.GetItemSpell(id) ~= nil end
    return GetItemSpell and GetItemSpell(id) ~= nil
end

-- Hasznalhato (Use:) item egy meg nem leadhato aktiv queshez: ezek a panel melletti
-- gombokra kerulnek, nem a taska melletti listaba
local function IsPanelUseItem(e)
    if QuestFocusDB.noUseButton or not e.needs or not ItemHasUse(e.id) then return false end
    for _, n in ipairs(e.needs) do if not n.questDone then return true end end
    return false
end

local scan = { items = {}, status = {}, leftovers = {}, bankOnly = {}, usable = {} }

local function Scan()
    local needs, bank = QuestNeeds(), BankCounts()
    local items, seen, status, leftovers = {}, {}, {}, {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, ContainerSlots(bag) do
            local id, count, icon, link, noValue = ContainerItem(bag, slot)
            if id then
                local isQ, startQ, active = ContainerQuestInfo(bag, slot)
                local classID = select(6, GetItemInfoInstant(id))
                local need = needs[id]
                local starts = startQ and startQ > 0 and not active
                if need or starts or isQ or classID == QUEST_CLASS then
                    local e = seen[id]
                    if e then
                        e.count = e.count + (count or 1)
                        e.slots[#e.slots + 1] = { bag, slot }
                    else
                        e = { id = id, count = count or 1, icon = icon, link = link, bag = bag, slot = slot,
                            slots = { { bag, slot } }, needs = need, starts = starts,
                            noValue = SellPriceZero(id, noValue), bank = bank[id] }
                        seen[id] = e
                        items[#items + 1] = e
                    end
                end
            end
        end
    end
    for _, e in ipairs(items) do
        if e.needs then
            local allDone = true
            for _, n in ipairs(e.needs) do if not n.done then allDone = false end end
            e.kind = allDone and "done" or "need"
            local n = e.needs[1]
            if n.needed and e.count > n.needed then e.surplus = e.count - n.needed end
        elseif e.starts then
            e.kind = "starts"
        else
            e.kind = "leftover"
            if e.noValue then leftovers[#leftovers + 1] = e end
        end
        status[e.id] = e.kind
    end
    -- Bankban levo, de aktiv questhez kello itemek, amik nincsenek a taskaban
    local bankOnly = {}
    for id, list in pairs(needs) do
        if not seen[id] and bank[id] then
            local n = list[1]
            if not n.done then
                bankOnly[#bankOnly + 1] = { id = id, count = bank[id], needs = list, kind = "bank",
                    icon = select(5, GetItemInfoInstant(id)) }
            end
        end
    end
    local function rank(e) return e.kind == "need" and 1 or e.kind == "done" and 2 or e.kind == "starts" and 3 or 4 end
    table.sort(items, function(a, b)
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        return (a.needs and a.needs[1].title or "") < (b.needs and b.needs[1].title or "")
    end)
    -- hasznalhato quest itemek: a panelre (a kijelolt quest elol), a listabol kimaradnak
    local usable, listed = {}, {}
    for _, e in ipairs(items) do
        if IsPanelUseItem(e) then usable[#usable + 1] = e else listed[#listed + 1] = e end
    end
    local function forSel(e)
        for _, n in ipairs(e.needs) do if n.qid == state.questId then return 0 end end
        return 1
    end
    table.sort(usable, function(a, b)
        if forSel(a) ~= forSel(b) then return forSel(a) < forSel(b) end
        return (a.needs[1].title or "") < (b.needs[1].title or "")
    end)
    scan.items, scan.status, scan.leftovers, scan.bankOnly = listed, status, leftovers, bankOnly
    scan.usable = usable
    return scan
end

---------------------------------------------------------------------------
-- Bagnon slotok szinezese
---------------------------------------------------------------------------
local lastStatusKey
local function StatusKey(status)
    local t = {}
    for id, k in pairs(status) do t[#t + 1] = id .. k end
    table.sort(t)
    return table.concat(t, ",")
end

-- Kiemelt item (a listaban rakattintottal): erosen pulzalo arany keret, a tobbi elhalvanyul
local bagFocus -- itemID vagy nil

local function ApplyFocus(self, B)
    local id = self.info and self.info.itemID
    if bagFocus then
        if id == bagFocus then
            if not self.qfFocus then
                local t = self:CreateTexture(nil, "OVERLAY", nil, 7)
                t:SetTexture("Interface\\Buttons\\CheckButtonHilight")
                t:SetBlendMode("ADD")
                t:SetAllPoints()
                local ag = t:CreateAnimationGroup()
                ag:SetLooping("BOUNCE")
                local a = ag:CreateAnimation("Alpha")
                a:SetFromAlpha(1)
                a:SetToAlpha(0.25)
                a:SetDuration(0.5)
                self.qfFocus, self.qfFocusAnim = t, ag
            end
            self.qfFocus:SetVertexColor(1, 0.85, 0.1)
            self.qfFocus:Show()
            self.qfFocusAnim:Play()
            if self.IconBorder then self.IconBorder:SetVertexColor(1, 0.85, 0.1); self.IconBorder:Show() end
            if self.IconGlow then self.IconGlow:SetVertexColor(1, 0.85, 0.1, 1); self.IconGlow:Show() end
            self:SetAlpha(1)
        else
            if self.qfFocus then self.qfFocus:Hide(); self.qfFocusAnim:Stop() end
            self:SetAlpha(0.3)
        end
        self.qfDimmed = true
    elseif self.qfDimmed then
        self.qfDimmed = nil
        if self.qfFocus then self.qfFocus:Hide(); self.qfFocusAnim:Stop() end
        self:SetAlpha(1)
    end
end

local function HookOne(B)
    if not (type(B) == "table" and B.Item and B.Item.UpdateBorder) or B.qfItemHooked then return end
    B.qfItemHooked = true
    hooksecurefunc(B.Item, "UpdateBorder", function(self)
        if not QuestFocusDB.noBagGlow then
            local id = self.info and self.info.itemID
            local kind = id and self.searched and scan.status[id]
            if kind then
                local c = COLORS[kind]
                if self.IconBorder then
                    self.IconBorder:SetVertexColor(c[1], c[2], c[3])
                    self.IconBorder:Show()
                end
                if self.IconGlow then
                    self.IconGlow:SetVertexColor(c[1], c[2], c[3], (B.sets and B.sets.glowAlpha) or 0.5)
                    self.IconGlow:Show()
                end
            end
        end
        ApplyFocus(self, B)
    end)
    -- a Bagnon sajat keresese is allit atlatszosagot: utana a mienk ervenyes
    if type(B.Item.UpdateSearch) == "function" then
        hooksecurefunc(B.Item, "UpdateSearch", function(self) ApplyFocus(self, B) end)
    end
end

-- A Bagnon a BagBrother kodjat a sajat nevtereben is betolti: mindkettot hookoljuk
local function HookBagnonItems()
    HookOne(_G.BagBrother)
    HookOne(_G.Bagnon)
end

local function UpdateAllBagFrames()
    for _, B in ipairs({ _G.BagBrother, _G.Bagnon }) do
        if type(B) == "table" then
            if B.Frames and B.Frames.Update then pcall(B.Frames.Update, B.Frames) end
            -- A Bagnon a slotokat a keresesi jelzesre rajzolja ujra (UpdateSearch): ugyanazzal
            -- a keresessel ujrakuldjuk, igy a kiemeles azonnal latszik, a keresesed nem valtozik
            if type(B.SendSignal) == "function" then pcall(B.SendSignal, B, "SEARCH_CHANGED", B.search) end
        end
    end
end

-- Kattintas a listaban: ki/be kapcsolja az item kiemeleset a taskaban
NS.BagFocus = function(itemId)
    if not itemId and not bagFocus then return false end
    HookBagnonItems()
    if itemId then bagFocus = (bagFocus ~= itemId) and itemId or nil else bagFocus = nil end
    UpdateAllBagFrames()
    return bagFocus ~= nil
end

local function MaybeRefreshBagnon()
    local key = StatusKey(scan.status)
    if key == lastStatusKey then return end
    lastStatusKey = key
    UpdateAllBagFrames()
end

---------------------------------------------------------------------------
-- Lista a taska mellett
---------------------------------------------------------------------------
local list = CreateFrame("Frame", "QuestFocusBagList", UIParent, "BackdropTemplate")
list:SetSize(260, 40)
list:SetFrameStrata("HIGH")
list:SetClampedToScreen(true)
list:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
list:SetBackdropColor(0, 0, 0, 0.85)
list:Hide()
list.title = list:CreateFontString(nil, "OVERLAY", "GameFontNormal")
list.title:SetPoint("TOPLEFT", 10, -8)
list.rows = {}
-- taska bezarasakor a kiemeles is megszunik
list:HookScript("OnHide", function() if NS.BagFocus then NS.BagFocus(nil) end end)
local anchorFrame
local RefreshBagList -- lent

-- Osszecsukas: csak a fejlec latszik
local collapseBtn = CreateFrame("Button", nil, list)
collapseBtn:SetSize(18, 18)
collapseBtn:SetPoint("TOPRIGHT", -6, -5)
local function UpdateCollapseIcon()
    local c = QuestFocusDB and QuestFocusDB.bagListCollapsed
    collapseBtn:SetNormalTexture(c and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
    collapseBtn:SetPushedTexture(c and "Interface\\Buttons\\UI-PlusButton-Down" or "Interface\\Buttons\\UI-MinusButton-Down")
end
collapseBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
collapseBtn:SetScript("OnClick", function()
    QuestFocusDB.bagListCollapsed = not QuestFocusDB.bagListCollapsed
    RefreshBagList()
end)
collapseBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(QuestFocusDB.bagListCollapsed and L["Expand list"] or L["Collapse list"], 1, 1, 1)
    GameTooltip:Show()
end)
collapseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Gorgetheto tartalom
local scroll = CreateFrame("ScrollFrame", "QuestFocusBagListScroll", list, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 6, -26)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(220, 10)
scroll:SetScrollChild(content)

local junkBtn = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
junkBtn:SetSize(240, 20)
junkBtn:Hide()

local function GetRow(i)
    local r = list.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, content)
    r:SetSize(218, 30)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(24, 24)
    r.icon:SetPoint("LEFT", 2, 0)
    r.border = r:CreateTexture(nil, "BACKGROUND")
    r.border:SetPoint("TOPLEFT", r.icon, -2, 2)
    r.border:SetPoint("BOTTOMRIGHT", r.icon, 2, -2)
    r.border:SetColorTexture(1, 1, 1, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 0)
    r.name:SetWidth(186)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
    r.sub:SetWidth(186)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    r:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if e.bag then GameTooltip:SetBagItem(e.bag, e.slot) else GameTooltip:SetItemByID(e.id) end
        for _, n in ipairs(e.needs or {}) do
            local prog = n.needed and (" %d/%d"):format(n.collected or 0, n.needed) or ""
            GameTooltip:AddLine(("%s%s%s"):format(n.title or "?", prog, n.done and L[" (complete)"] or ""), 1, 0.82, 0, true)
        end
        if e.surplus then GameTooltip:AddLine((L["%d surplus (you carry more than needed)"]):format(e.surplus), 0.6, 0.6, 0.6) end
        if e.bank then GameTooltip:AddLine((L["Also in the bank: %d"]):format(e.bank), 0.6, 0.8, 1) end
        if e.kind == "leftover" then
            GameTooltip:AddLine(e.noValue and L["Unsellable: /qf junk can destroy it"] or L["Can be sold to a vendor"], 0.6, 0.6, 0.6)
        end
        GameTooltip:AddLine(L["Click: highlight it in the bag; click again: clear"], 0.5, 0.5, 0.5)
        if e.needs then GameTooltip:AddLine(L["...and select the quest (QFocus marker + macro)"], 0.5, 0.5, 0.5) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self)
        local e = self.entry
        -- Kiemeles a taskaban (pulzalo keret, a tobbi elhalvanyul); ujra kattintva ki
        if e and e.id and NS.BagFocus then NS.BagFocus(e.id) end
        local n = e and e.needs and e.needs[1]
        if n then
            local title, done = NS.FindQuestInLog(n.qid)
            NS.SelectQuest(n.qid, title or n.title, done, true)
        end
    end)
    list.rows[i] = r
    return r
end

local function RowText(e)
    local c = COLORS[e.kind] or COLORS.need
    if e.kind == "bank" then
        local n = e.needs[1]
        return (L["|cff99ccffIN BANK|r %s"]):format(n.title or "?"), c
    end
    if e.needs then
        local n = e.needs[1]
        local count = n.needed and ("%d/%d"):format(math.min(n.collected or 0, n.needed), n.needed)
        local prog
        if n.use then
            prog = L["use / carry"]
        elseif n.questDone then
            prog = "|cff33ff99" .. L["quest complete, turn in"] .. "|r"
        elseif n.done then
            -- csak ez az objective kesz, a quest tobbi resze meg hatravan
            prog = "|cff33ff99" .. (count or "") .. " " .. L["done"] .. "|r |cffaaaaaa" .. L["(keep it, quest not finished)"] .. "|r"
        else
            prog = count or L["needed"]
        end
        local extra = ""
        if e.surplus then extra = extra .. (L[" |cffaaaaaa+%d surplus|r"]):format(e.surplus) end
        if #e.needs > 1 then extra = extra .. (" |cffaaaaaa(+%d quest)|r"):format(#e.needs - 1) end
        return ("%s |cffffffff%s|r%s"):format(n.title or "?", prog, extra), COLORS.need
    end
    if e.kind == "starts" then return L["Starts a quest! (right click it in the bag)"], c end
    return e.noValue and L["No active quest, unsellable (/qf junk)"] or L["No active quest, sellable"], c
end

RefreshBagList = function()
    Scan()
    MaybeRefreshBagnon()
    if not (anchorFrame and anchorFrame:IsShown()) or QuestFocusDB.noBagList then list:Hide() return end

    local rows = {}
    for _, e in ipairs(scan.items) do rows[#rows + 1] = e end
    for _, e in ipairs(scan.bankOnly) do rows[#rows + 1] = e end
    if #rows == 0 then list:Hide() return end

    list.title:SetText((L["Quest items (%d)"]):format(#rows))
    UpdateCollapseIcon()
    list:ClearAllPoints()
    list.title:ClearAllPoints()
    collapseBtn:ClearAllPoints()

    if QuestFocusDB.bagListCollapsed then
        -- Osszecsukva: keskeny ful a taska tetejen (nem log a taska mellett)
        list:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 1)
        list:SetSize(170, 22)
        list.title:SetFontObject("GameFontNormalSmall")
        list.title:SetPoint("LEFT", 8, 0)
        collapseBtn:SetSize(14, 14)
        collapseBtn:SetPoint("RIGHT", -4, 0)
        scroll:Hide()
        junkBtn:Hide()
        list:Show()
        return
    end
    list:SetPoint("TOPRIGHT", anchorFrame, "TOPLEFT", -4, 0)
    list:SetWidth(260)
    list.title:SetFontObject("GameFontNormal")
    list.title:SetPoint("TOPLEFT", 10, -8)
    collapseBtn:SetSize(18, 18)
    collapseBtn:SetPoint("TOPRIGHT", -6, -5)
    list:Show()
    scroll:Show()

    local y = 0
    for i, e in ipairs(rows) do
        local r = GetRow(i)
        r.entry = e
        r.icon:SetTexture(e.icon or 134400)
        r.icon:SetDesaturated(e.kind == "bank")
        local c = COLORS[e.kind] or COLORS.need
        r.border:SetColorTexture(c[1], c[2], c[3], 0.9)
        local name = (e.link and e.link:match("%[(.-)%]")) or GetItemInfo(e.id) or ("item " .. e.id)
        local cnt = e.count and e.count > 1 and (" |cffaaaaaax%d|r"):format(e.count) or ""
        local bank = (e.bank and e.kind ~= "bank") and (L[" |cff99ccff+%d bank|r"]):format(e.bank) or ""
        r.name:SetText(name .. cnt .. bank)
        local text, col = RowText(e)
        r.sub:SetText(text)
        r.sub:SetTextColor(col[1], col[2], col[3])
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", content, "TOPLEFT", 2, y)
        r:Show()
        y = y - 32
    end
    for i = #rows + 1, #list.rows do list.rows[i]:Hide() end
    local contentH = -y
    content:SetHeight(math.max(contentH, 1))

    local junkH = 0
    if #scan.leftovers > 0 then
        junkBtn:SetText((L["Destroy unsellable leftovers (%d)"]):format(#scan.leftovers))
        junkBtn:ClearAllPoints()
        junkBtn:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 10, 8)
        junkBtn:Show()
        junkH = 26
    else
        junkBtn:Hide()
    end

    -- A lista nem lehet magasabb a taskanal; ha tobb a sor, gorgetheto
    local maxH = math.max(120, anchorFrame:GetHeight() or 400)
    local fullH = 26 + contentH + junkH + 8
    local h = math.min(fullH, maxH)
    list:SetHeight(h)
    local needScroll = fullH > maxH
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 6, -26)
    scroll:SetPoint("BOTTOMRIGHT", needScroll and -28 or -6, 8 + junkH)
    local bar = scroll.ScrollBar or _G["QuestFocusBagListScrollScrollBar"]
    if bar then bar:SetShown(needScroll) end
    if not needScroll then scroll:SetVerticalScroll(0) end
end

---------------------------------------------------------------------------
-- Felesleges, nem eladhato quest itemek eldobasa (egyenkent megerositessel)
---------------------------------------------------------------------------
local junkQueue
local function NextJunk()
    if not junkQueue or #junkQueue == 0 then
        junkQueue = nil
        return
    end
    local e = table.remove(junkQueue, 1)
    local name = (e.link and e.link:match("%[(.-)%]")) or GetItemInfo(e.id) or ("item " .. e.id)
    StaticPopup_Show("QUESTFOCUS_DISCARD", ("%s x%d"):format(name, e.count), nil, e)
end

StaticPopupDialogs["QUESTFOCUS_DISCARD"] = {
    text = L["Destroy this quest item?\n\n|cffffffff%s|r\n\nNo active quest needs it and it can't be sold. If a quest you haven't picked up yet "]
        .. L["asks for it later, you will have to get it again."],
    button1 = L["Destroy"],
    button2 = L["Skip"],
    OnAccept = function(_, e)
        if InCombatLockdown() then Print(L["Not destroying anything in combat."]) return end
        for _, s in ipairs(e.slots) do
            local id = ContainerItem(s[1], s[2])
            if id == e.id then -- ellenorzes: meg mindig ugyanaz az item van ott
                ClearCursor()
                PickupItem(s[1], s[2])
                if CursorHasItem() then DeleteCursorItem() end
            end
        end
        Print(L["Destroyed: %s"], e.link or e.id)
        C_Timer.After(0.3, NextJunk)
    end,
    OnCancel = function(_, _, reason)
        if reason == "clicked" then C_Timer.After(0.1, NextJunk) else junkQueue = nil end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function DiscardLeftovers()
    Scan()
    if #scan.leftovers == 0 then Print(L["No unsellable leftover quest items."]) return end
    junkQueue = {}
    for _, e in ipairs(scan.leftovers) do junkQueue[#junkQueue + 1] = e end
    Print(L["%d leftover quest items, I'll ask one by one."], #junkQueue)
    NextJunk()
end
NS.DiscardLeftovers = DiscardLeftovers
junkBtn:SetScript("OnClick", DiscardLeftovers)

---------------------------------------------------------------------------
-- Hasznalhato quest itemek a panel bal szelen (egymas alatt, max USE_MAX).
-- Az elso a kijelolt quest itemje (ha van); a tobbi a tobbi aktiv quest hasznalhato itemje.
-- Ezek a taska melletti listabol kimaradnak (Scan: scan.usable).
---------------------------------------------------------------------------
local USE_MAX, USE_SIZE = 4, 36
local useBtns = {}
local function MakeUseButton(i)
    -- az elso neve marad (a keybind erre szol: CLICK QuestFocusUseItem:LeftButton)
    local b = CreateFrame("Button", i == 1 and "QuestFocusUseItem" or ("QuestFocusUseItem" .. i), UIParent,
        "SecureActionButtonTemplate")
    b:SetSize(USE_SIZE, USE_SIZE)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "item")
    b:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetPoint("TOPLEFT", -2, 2)
    b.border:SetPoint("BOTTOMRIGHT", 2, -2)
    b.border:SetColorTexture(0.2, 1, 0.6, 0.5)
    b.border:SetDrawLayer("BACKGROUND")
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    b.key = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    b.key:SetPoint("TOPRIGHT", -2, -2)
    b:SetScript("OnEnter", function(self)
        if not self.itemId then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetItemByID(self.itemId)
        GameTooltip:AddLine(" ")
        for _, n in ipairs(self.needs or {}) do
            local sel = n.qid == state.questId
            GameTooltip:AddLine((sel and "|cff33ff99> " or "|cffffd100") .. (n.title or "?") .. "|r", 1, 1, 1)
        end
        if i == 1 and not GetBindingKey("CLICK QuestFocusUseItem:LeftButton") then
            GameTooltip:AddLine(L["Key: Options > Keybindings > AddOns > QuestFocus"], 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    useBtns[i] = b
    return b
end
for i = 1, USE_MAX do MakeUseButton(i) end

local useGeo
local function UpdateUseButton()
    if InCombatLockdown() then return end
    local panel = NS.panel
    local list = (not QuestFocusDB.noUseButton and panel and panel:IsShown()) and scan.usable or {}
    -- Nem a panelhez horgonyzunk (attol a panel vedett lenne): kepernyo-pozicio alapjan
    local l, t = NS.PanelEdge("left"), NS.PanelEdge("top")
    useGeo = l and t and (math.floor(l) .. ":" .. math.floor(t)) or nil
    local key = GetBindingKey("CLICK QuestFocusUseItem:LeftButton")
    for i, b in ipairs(useBtns) do
        local e = list[i]
        if not e or not l then
            if b:IsShown() then b:Hide() end
            b.itemId, b.needs = nil, nil
        else
            if b.itemId ~= e.id then
                b.itemId = e.id
                b:SetAttribute("item", "item:" .. e.id)
                b.icon:SetTexture(e.icon or select(5, GetItemInfoInstant(e.id)))
            end
            b.needs = e.needs
            local sel = false
            for _, n in ipairs(e.needs or {}) do if n.qid == state.questId then sel = true end end
            b.border:SetShown(sel)
            b:SetAlpha(sel and 1 or 0.8)
            local n = GetItemCount(e.id)
            b.count:SetText(n > 1 and n or "")
            b.key:SetText(i == 1 and key and GetBindingText and GetBindingText(key, true) or "")
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", l - 4, t - (i - 1) * (USE_SIZE + 4))
            b:Show()
        end
    end
end

local cdElapsed = 0
local ticker = CreateFrame("Frame")
local lastQuest, lastPanelShown
ticker:SetScript("OnUpdate", function(_, dt)
    cdElapsed = cdElapsed + dt
    if cdElapsed < 0.5 then return end
    cdElapsed = 0
    local shown = NS.panel and NS.panel:IsShown()
    if state.questId ~= lastQuest or shown ~= lastPanelShown then
        lastQuest, lastPanelShown = state.questId, shown
        if not InCombatLockdown() then Scan() end -- a kijelolt quest itemje kerul elore
        UpdateUseButton()
    elseif useBtns[1]:IsShown() and not InCombatLockdown() then
        -- a panel elmozdult: a gombok kovetik
        local l, t = NS.PanelEdge("left"), NS.PanelEdge("top")
        if l and t and useGeo ~= (math.floor(l) .. ":" .. math.floor(t)) then UpdateUseButton() end
    end
    local getCD = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    for _, b in ipairs(useBtns) do
        if b:IsShown() and b.itemId and getCD then
            local start, dur = getCD(b.itemId)
            if start and dur then b.cd:SetCooldown(start, dur) end
        end
    end
end)

---------------------------------------------------------------------------
-- Taska ablakok figyelese
---------------------------------------------------------------------------
local function Attach(frame)
    if not frame or not frame.HookScript or frame.qfBagHooked then return end
    frame.qfBagHooked = true
    frame:HookScript("OnShow", function(self) anchorFrame = self; RefreshBagList() end)
    frame:HookScript("OnHide", function(self) if anchorFrame == self then list:Hide() end end)
    if frame:IsShown() then anchorFrame = frame; RefreshBagList() end
end

local function HookBags()
    local B = Bags()
    if B then
        hooksecurefunc(B.Frames, "Show", function(self, id)
            if id == "inventory" then Attach(self:Get(id)) end
        end)
        Attach(B.Frames:Get("inventory"))
        HookBagnonItems()
    end
    for _, name in ipairs({ "ContainerFrameCombinedBags", "ContainerFrame1" }) do
        if _G[name] then Attach(_G[name]) end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("UPDATE_BINDINGS")
local pending
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        HookBags()
        C_Timer.After(3, function() Scan(); MaybeRefreshBagnon(); UpdateUseButton() end)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" or event == "UPDATE_BINDINGS" then UpdateUseButton() return end
    if pending then return end
    pending = true
    C_Timer.After(0.3, function()
        pending = false
        RefreshBagList()
        UpdateUseButton()
    end)
end)

NS.ToggleBagList = function()
    QuestFocusDB.noBagList = not QuestFocusDB.noBagList
    RefreshBagList()
    Print(L["Quest item list next to the bags: %s"], QuestFocusDB.noBagList and L["off"] or L["on"])
end

---------------------------------------------------------------------------
-- Kapcsolok a beallitasokban
---------------------------------------------------------------------------
-- a core adja a fult a modul ki/be kapcsolojaval a tetejen
local page, fl = NS.ModulePage("QuestFocus_Bags")
fl:Header(L["Quest items in your bags"])
fl:Check(L["Quest item list next to the bags"],
    L["While your bags are open (Bagnon or Blizzard), lists your quest items next to them: which quest needs them, "]
    .. L["how many are surplus, what is in the bank, which ones start a quest. Click a row to select the quest. Toggle: /qf bags."],
    function() return not QuestFocusDB.noBagList end,
    function(v) QuestFocusDB.noBagList = not v; RefreshBagList() end)
fl:Check(L["Color quest items in Bagnon"],
    L["Yellow: needed for an active quest. Green: you have enough (objective done, keep it for the turn-in). Blue: starts a quest. Grey: no active quest."],
    function() return not QuestFocusDB.noBagGlow end,
    function(v)
        QuestFocusDB.noBagGlow = not v
        lastStatusKey = nil
        local B = Bags()
        if B and B.Frames and B.Frames.Update then pcall(B.Frames.Update, B.Frames) end
    end)
fl:Header(L["Using quest items"])
fl:Check(L["Usable quest items on the panel"],
    L["Quest items you have to use (e.g. throw at a mob) get a button on the left edge of the QuestFocus panel, "]
    .. L["up to 4, the selected quest's item first (green frame). They are left out of the bag list. "]
    .. L["Key for the first one: Options > Keybindings > AddOns > QuestFocus."],
    function() return not QuestFocusDB.noUseButton end,
    function(v) QuestFocusDB.noUseButton = not v; RefreshBagList(); UpdateUseButton() end)
fl:Button(L["Destroy leftover quest items"], 200,
    L["Unsellable quest items no active quest needs any more. Asks one by one before destroying. Same as /qf junk."],
    function() if NS.DiscardLeftovers then NS.DiscardLeftovers() end end, 28)
page:HookScript("OnShow", function() fl:Refresh() end)
