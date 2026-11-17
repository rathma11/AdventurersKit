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

BINDING_HEADER_QUESTFOCUS = "Adventurer's Kit"
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

-- Modul ki/be (Options > Bags > Module on): kikapcsolva betoltve marad, de semmit nem csinal
local function On() return not NS.ModuleOn or NS.ModuleOn("QuestFocus_Bags") end

local function ItemHasUse(id)
    if C_Item and C_Item.GetItemSpell then return C_Item.GetItemSpell(id) ~= nil end
    return GetItemSpell and GetItemSpell(id) ~= nil
end

-- Hasznalhato (Use:) item egy meg nem leadhato aktiv queshez: ezek a panel melletti
-- gombokra kerulnek, nem a taska melletti listaba
-- Csak az, amit HASZNALNI kell a queshez: a quest altal adott / megkovetelt item (n.use:
-- sourceItemId, requiredSourceItems), vagy egy meg nem kesz objective quest-tipusu itemje.
-- Gyujtendo fogyaszthato (pl. ital, kaja) NEM kerul ide, akkor sem, ha van Use: hatasa.
-- Most ez a gombkent a panel egy objective soraban van (lent: UpdateUseButton)
local function IsPanelUseItem(e)
    return On() and NS.panelUseShown and NS.panelUseShown[e.id] and true or false
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

local anchorFrame -- a nyitott taska ablak (lent allitjuk: Attach)

local function ApplyFocus(self, B, idOverride)
    local id = idOverride or (self.info and (self.info.itemID or self.info.id))
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
        if not QuestFocusDB.noBagGlow and On() then
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

---------------------------------------------------------------------------
-- Kiemeles kozvetlenul: a nyitott taska ablak(ok) item gombjait magunk keressuk meg
-- (Bagnon / BagBrother / Blizzard), es amig a kiemeles aktiv, felfrissitjuk (a Bagnon
-- ujrarajzolaskor visszaallitja az atlatszosagot). Nem fugg a Bagnon belso metodusaitol.
---------------------------------------------------------------------------
local touched = setmetatable({}, { __mode = "k" }) -- gombok, amikhez hozzanyultunk
local GetBagItemID = C_Container and C_Container.GetContainerItemID or GetContainerItemID

local function IsItemButton(b)
    if b.IsObjectType and b:IsObjectType("ItemButton") then return true end
    return b.IconBorder ~= nil or (b.GetName and b:GetName() and b:GetName():find("Item%d+$") ~= nil)
end

local function ButtonItemID(b)
    local info = b.info
    if type(info) == "table" and (info.itemID or info.id) then return info.itemID or info.id end
    local slot = b.GetID and b:GetID()
    if not slot or slot <= 0 then return end
    local okB, bag = pcall(function() return (b.GetBag and b:GetBag()) or b.bag end)
    if not okB then bag = nil end
    if not bag then
        local p = b:GetParent()
        bag = p and p.GetID and p:GetID()
    end
    if type(bag) ~= "number" then return end
    local ok, id = pcall(GetBagItemID, bag, slot)
    return ok and id or nil
end

local function CollectItemButtons(frame, out, depth)
    if not frame or depth > 7 then return end
    for _, c in ipairs({ frame:GetChildren() }) do
        if c:IsShown() then
            if c:IsObjectType("Button") and IsItemButton(c) then
                out[#out + 1] = c
            else
                CollectItemButtons(c, out, depth + 1)
            end
        end
    end
end

local function BagRoots()
    local roots = {}
    if anchorFrame and anchorFrame:IsShown() then roots[#roots + 1] = anchorFrame end
    for _, name in ipairs({ "ContainerFrameCombinedBags" }) do
        local f = _G[name]
        if f and f:IsShown() and f ~= anchorFrame then roots[#roots + 1] = f end
    end
    for i = 1, 13 do
        local f = _G["ContainerFrame" .. i]
        if f and f:IsShown() and f ~= anchorFrame then roots[#roots + 1] = f end
    end
    return roots
end

local function ApplyFocusAll()
    local found = 0
    for _, root in ipairs(BagRoots()) do
        local btns = {}
        CollectItemButtons(root, btns, 0)
        for _, b in ipairs(btns) do
            local id = ButtonItemID(b)
            ApplyFocus(b, nil, id or -1) -- -1: ures slot (elhalvanyul)
            touched[b] = true
            if id == bagFocus then found = found + 1 end
        end
    end
    return found
end

-- ha a kiemelest kikapcsoljuk, minden erintett gombot visszaallitunk (zart taskaban is)
local function ClearFocusAll()
    for b in pairs(touched) do
        if b.qfDimmed then
            b.qfDimmed = nil
            if b.qfFocus then b.qfFocus:Hide(); b.qfFocusAnim:Stop() end
            b:SetAlpha(1)
        end
    end
end

local focusTicker = CreateFrame("Frame")
focusTicker:Hide()
local focusElapsed = 0
focusTicker:SetScript("OnUpdate", function(self, dt)
    focusElapsed = focusElapsed + dt
    if focusElapsed < 0.3 then return end
    focusElapsed = 0
    if not bagFocus then self:Hide() return end
    ApplyFocusAll()
end)

-- Kattintas a listaban: ki/be kapcsolja az item kiemeleset a taskaban
NS.BagFocus = function(itemId)
    if not itemId and not bagFocus then return false end
    HookBagnonItems()
    if itemId then bagFocus = (bagFocus ~= itemId) and itemId or nil else bagFocus = nil end
    if bagFocus then
        local found = ApplyFocusAll()
        focusTicker:Show()
        NS.bagFocusDebug = ("item %d, %d button(s) found"):format(bagFocus, found)
    else
        ClearFocusAll()
        focusTicker:Hide()
    end
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
    -- Optimalizalas: csak nyitott taskanal es kinyitott quest item listanal szkennelunk;
    -- osszecsukva a ful a legutobbi szamot mutatja.
    if not (anchorFrame and anchorFrame:IsShown()) or QuestFocusDB.noBagList or not On() then list:Hide() return end
    if not QuestFocusDB.bagListCollapsed then
        Scan()
        scan.done = true
        MaybeRefreshBagnon()
    end

    local rows = {}
    for _, e in ipairs(scan.items) do rows[#rows + 1] = e end
    for _, e in ipairs(scan.bankOnly) do rows[#rows + 1] = e end
    -- osszecsukva, meg szkenneles nelkul: a ful latszik (kinyitni ezzel lehet), szam nelkul
    local unknown = QuestFocusDB.bagListCollapsed and not scan.done
    if #rows == 0 and not unknown then list:Hide() return end

    list.title:SetText(unknown and L["Quest items"] or (L["Quest items (%d)"]):format(#rows))
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
-- Hasznalhato quest item a panel objective soraban (a sor jobb szelen egy kis gomb):
--  - a kijelolt quest objective-jei, es az ALSO NEARBY (kozeli) objective-ek;
--  - az objective sajat itemje, ha quest-tipusu es hasznalhato, vagy a quest altal adott /
--    megkovetelt item (sourceItemId, requiredSourceItems) - ez a kijelolt / elso nyitott sorba.
-- A secure gombot nem horgonyozzuk a panelhez (attol a panel vedett lenne): kepernyo-pozicio.
-- Ami itt latszik, az a taska melletti listabol kimarad (NS.panelUseShown).
---------------------------------------------------------------------------
local USE_MAX = 6
NS.panelUseShown = {}

-- Optimalizalas: az eredmeny csak taska / quest log valtozaskor (useGen) szamolodik ujra,
-- nem minden 0.4 mp-es tick-ben (a Questie lekerdezes draga).
local useGen, useCache = 0, {}
local ObjectiveUseItemRaw
local function ObjectiveUseItem(qid, o, questLevel)
    if not On() or QuestFocusDB.noUseButton or not o or o.completed or o.turnIn then return end
    local key = tostring(qid) .. "|" .. tostring(o.desc) .. "|" .. tostring(questLevel and true or false)
    local c = useCache[key]
    if c and c.gen == useGen then return c.id end
    local id = ObjectiveUseItemRaw(qid, o, questLevel)
    useCache[key] = { gen = useGen, id = id }
    return id
end
ObjectiveUseItemRaw = function(qid, o, questLevel)
    if o.itemId and GetItemCount(o.itemId) > 0 and ItemHasUse(o.itemId)
        and select(6, GetItemInfoInstant(o.itemId)) == QUEST_CLASS then
        return o.itemId
    end
    if not questLevel then return end
    local q = qid and NS.GetQuestieQuest(qid)
    if not q then return end
    local cands = {}
    if tonumber(q.sourceItemId) and q.sourceItemId > 0 then cands[#cands + 1] = q.sourceItemId end
    for _, id in pairs(q.requiredSourceItems or {}) do cands[#cands + 1] = id end
    for _, id in ipairs(cands) do
        if GetItemCount(id) > 0 and ItemHasUse(id) then return id end
    end
end
NS.ObjectiveUseItem = ObjectiveUseItem

local useBtns = {}
local function MakeUseButton(i)
    -- az elso neve marad (a keybind erre szol: CLICK QuestFocusUseItem:LeftButton)
    local b = CreateFrame("Button", i == 1 and "QuestFocusUseItem" or ("QuestFocusUseItem" .. i), UIParent,
        "SecureActionButtonTemplate")
    b:SetSize(18, 18)
    b:SetFrameStrata("MEDIUM")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "item")
    b:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", 2, -2)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    b:SetScript("OnEnter", function(self)
        if not self.itemId then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemId)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click: use it"], 0.5, 0.5, 0.5)
        if i == 1 then
            local key = GetBindingKey("CLICK QuestFocusUseItem:LeftButton")
            GameTooltip:AddLine(key and ((L["Key: %s"]):format(GetBindingText and GetBindingText(key) or key))
                or L["Key: Options > Keybindings > AddOns > Adventurer's Kit"], 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    useBtns[i] = b
    return b
end
for i = 1, USE_MAX do MakeUseButton(i) end

-- Mely sorokhoz kell gomb: { row, id }
local function UseRows()
    local out, seen = {}, {}
    local panel = NS.panel
    if not (panel and panel:IsShown()) then return out end
    local function add(list)
        for _, r in ipairs(list or {}) do
            if r:IsShown() and r.useObj and #out < USE_MAX then
                local id = ObjectiveUseItem(r.useQid, r.useObj, r.useQuestItem)
                if id and not seen[id] then
                    seen[id] = true
                    out[#out + 1] = { row = r, id = id }
                end
            end
        end
    end
    add(panel.lines)
    add(panel.extraRows)
    return out
end

local function RowRect(r)
    local s = r:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local right, top, h = r:GetRight(), r:GetTop(), r:GetHeight()
    if not (right and top) then return end
    -- a panel objective sor vegen terkep gomb van (qfMapInset): az item gomb ele kerul
    right = right - (r.qfMapInset or 0)
    return right * s, top * s, h * s
end

local useKey = ""
local function UpdateUseButton()
    if InCombatLockdown() then return end
    local rows = UseRows()
    local key, shown = {}, {}
    -- sorszoveg: ahol gomb van, ott a szoveg ne fusson ala
    local panel = NS.panel
    for _, list in ipairs({ panel and panel.lines or {}, panel and panel.extraRows or {} }) do
        for _, r in ipairs(list) do
            if r.text and r.qfUseInset then
                r.text:ClearAllPoints()
                r.text:SetPoint("TOPLEFT")
                r.text:SetPoint("BOTTOMRIGHT", -(r.qfMapInset or 0), 0)
                r.qfUseInset = nil
            end
        end
    end
    for i, b in ipairs(useBtns) do
        local e = rows[i]
        local rx, ry, rh = nil, nil, nil
        if e then rx, ry, rh = RowRect(e.row) end
        if not e or not rx then
            if b:IsShown() then b:Hide() end
            b.itemId = nil
        else
            if b.itemId ~= e.id then
                b.itemId = e.id
                b:SetAttribute("item", "item:" .. e.id)
                b.icon:SetTexture(select(5, GetItemInfoInstant(e.id)))
            end
            local n = GetItemCount(e.id)
            b.count:SetText(n > 1 and n or "")
            local size = math.max(14, math.floor(rh + 0.5))
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", rx, ry)
            b:Show()
            if e.row.text then
                e.row.text:ClearAllPoints()
                e.row.text:SetPoint("TOPLEFT")
                e.row.text:SetPoint("BOTTOMRIGHT", -(size + 4 + (e.row.qfMapInset or 0)), 0)
                e.row.qfUseInset = true
            end
            shown[e.id] = true
            key[#key + 1] = e.id .. "@" .. math.floor(rx) .. ":" .. math.floor(ry)
        end
    end
    useKey = table.concat(key, ",")
    -- ami a panelen van, az a taska melletti listabol kimarad
    local changed = false
    for id in pairs(shown) do if not NS.panelUseShown[id] then changed = true end end
    for id in pairs(NS.panelUseShown) do if not shown[id] then changed = true end end
    NS.panelUseShown = shown
    if changed and list and list:IsShown() then RefreshBagList() end
end

local cdElapsed = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, dt)
    cdElapsed = cdElapsed + dt
    if cdElapsed < 0.4 then return end
    cdElapsed = 0
    if not InCombatLockdown() then
        -- sorok / panel elmozdult, uj item, masik quest: ujrarakjuk
        local rows, k = UseRows(), {}
        for _, e in ipairs(rows) do
            local rx, ry = RowRect(e.row)
            k[#k + 1] = e.id .. "@" .. math.floor(rx or 0) .. ":" .. math.floor(ry or 0)
        end
        if table.concat(k, ",") ~= useKey then UpdateUseButton() end
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
-- quest valtozas: a core szuri (felvetel / leadas / haladas), nem minden QUEST_LOG_UPDATE
if NS.OnQuestChange then
    NS.OnQuestChange(function() local h = ev:GetScript("OnEvent"); if h then h(ev, "QUEST_CHANGED") end end)
else
    ev:RegisterEvent("QUEST_LOG_UPDATE")
end
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("UPDATE_BINDINGS")
local pending
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        HookBags()
        C_Timer.After(3, function() RefreshBagList(); UpdateUseButton() end)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" or event == "UPDATE_BINDINGS" then UpdateUseButton() return end
    -- taska / quest log valtozott: a hasznalhato item cache ujraszamolodik
    useGen = useGen + 1
    if useGen % 50 == 0 then wipe(useCache) end
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
local page, fl = NS.ModulePage("QuestFocus_Bags", function()
    bagFocus = nil
    lastStatusKey = nil
    RefreshBagList()
    UpdateUseButton()
    local B = Bags()
    if B and B.Frames and B.Frames.Update then pcall(B.Frames.Update, B.Frames) end
end)
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
    L["A quest item you have to use (e.g. throw at a mob) gets a small button at the end of its objective row on the panel: "]
    .. L["for the selected quest and for the nearby (ALSO NEARBY) objectives. Those are left out of the bag list. "]
    .. L["Key for the first one: Options > Keybindings > AddOns > Adventurer's Kit."],
    function() return not QuestFocusDB.noUseButton end,
    function(v) QuestFocusDB.noUseButton = not v; RefreshBagList(); UpdateUseButton() end)
fl:Button(L["Destroy leftover quest items"], 200,
    L["Unsellable quest items no active quest needs any more. Asks one by one before destroying. Same as /qf junk."],
    function() if NS.DiscardLeftovers then NS.DiscardLeftovers() end end, 28)
page:HookScript("OnShow", function() fl:Refresh() end)
