-- QuestFocus: buff emlekezteto gombok (alvozsak / XP kaja / fegyver enchant).
-- A panel alatt egy kis sor: ikon + hatralevo ido. Ha a buff hianyzik vagy kevesebb mint N perc
-- van hatra, a gomb pirosan pulzal, es egyszer szol. Kattintasra hasznalja az itemet
-- (fegyver enchantnal ra is teszi a main hand fegyverre).

local _, NS = ...
local L = NS.L
local Print = NS.Print

local SLOTS = {
    { key = "rest",   label = L["Sleeping bag"], names = { L["Sleeping Bag"] } },
    { key = "food",   label = L["XP food"],      names = {} },
    { key = "weapon", label = L["Weapon enchant"],
      names = { L["Sharpening Stone"], L["Weightstone"], L["Wizard Oil"], L["Mana Oil"] } },
}
local BTN = 30

local function DB()
    QuestFocusDB.buffItems = QuestFocusDB.buffItems or {}
    QuestFocusDB.buffLearn = QuestFocusDB.buffLearn or {}
    return QuestFocusDB
end

local function Minutes()
    return tonumber(QuestFocusDB.buffWarnMin) or 10
end

---------------------------------------------------------------------------
-- Itemek, aurak
---------------------------------------------------------------------------
local GetSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local GetItemID = C_Container and C_Container.GetContainerItemID or GetContainerItemID

-- Beallitott item, vagy nev alapjan az elso talalat a taskakban
local function FindItem(slot)
    local id = DB().buffItems[slot.key]
    if id then return id end
    if #slot.names == 0 then return end
    for bag = 0, 4 do
        for s = 1, (GetSlots(bag) or 0) do
            local iid = GetItemID(bag, s)
            local name = iid and GetItemInfo(iid)
            if name then
                for _, pat in ipairs(slot.names) do
                    if name:find(pat, 1, true) then return iid end
                end
            end
        end
    end
end

local function ItemSpell(id)
    if not id then return end
    -- Ezen a kliensen a GetItemSpell hibat dobhat: vedetten hivjuk
    local fn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not fn then return end
    local ok, name, spellId = pcall(fn, id)
    if ok then return name, spellId end
end

local function HelpfulAuras()
    local out = {}
    for i = 1, 40 do
        local name, _, _, _, duration, expires
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not a then break end
            name, duration, expires = a.name, a.duration, a.expirationTime
        else
            name, _, _, _, duration, expires = UnitAura("player", i, "HELPFUL")
            if not name then break end
        end
        out[name] = { duration = duration or 0, expires = expires or 0 }
    end
    return out
end

-- Hatralevo mp (nil = nincs buff, math.huge = nem jar le)
local function Remaining(slot, itemId, auras)
    if slot.key == "weapon" then
        local has, ms = GetWeaponEnchantInfo()
        if has then return (ms or 0) / 1000 end
        return
    end
    local names = {}
    local learned = itemId and DB().buffLearn[itemId]
    if learned then names[#names + 1] = learned end
    local spell = ItemSpell(itemId)
    if spell then names[#names + 1] = spell end
    if slot.key == "food" then names[#names + 1] = L["Well Fed"] end
    for _, n in ipairs(names) do
        local a = auras[n]
        -- a 30 mp-es "Food" evo aura nem az igazi buff
        if a and not (slot.key == "food" and a.duration > 0 and a.duration <= 60) then
            if a.expires == 0 then return math.huge end
            return a.expires - GetTime()
        end
    end
end

-- Buff tanulas: item hasznalat utan az elso uj, hosszu buff lesz az iteme
local learning
local function StartLearning(itemId)
    learning = { itemId = itemId, untilT = GetTime() + 45, before = HelpfulAuras() }
end

local function CheckLearning()
    if not learning then return end
    if GetTime() > learning.untilT then learning = nil return end
    for name, a in pairs(HelpfulAuras()) do
        if not learning.before[name] and (a.duration == 0 or a.duration >= 300) then
            DB().buffLearn[learning.itemId] = name
            learning = nil
            return
        end
    end
end

---------------------------------------------------------------------------
-- Gombok
---------------------------------------------------------------------------
local bar = CreateFrame("Frame", "QuestFocusBuffBar", UIParent)
bar:SetSize(3 * (BTN + 6), BTN + 14)
bar:Hide()

local buttons = {}
local function FmtLeft(sec)
    if not sec then return "|cffff4444" .. L["none"] .. "|r" end
    if sec == math.huge then return "|cff33ff99on|r" end
    local m = math.floor(sec / 60)
    local txt = m >= 60 and ("%dh"):format(math.floor(m / 60)) or (m >= 1 and ("%dm"):format(m) or ("%ds"):format(math.floor(sec)))
    if sec < Minutes() * 60 then return "|cffff9933" .. txt .. "|r" end
    return "|cffd0d0d0" .. txt .. "|r"
end

for i, slot in ipairs(SLOTS) do
    local b = CreateFrame("Button", "QuestFocusBuff" .. i, bar, "SecureActionButtonTemplate")
    b:SetSize(BTN, BTN)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.slot = slot
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetPoint("TOPLEFT", -2, 2)
    b.border:SetPoint("BOTTOMRIGHT", 2, -2)
    b.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.border:SetBlendMode("ADD")
    b.border:SetTexCoord(0.2, 0.8, 0.2, 0.8)
    b.border:Hide()
    b.warn = b:CreateTexture(nil, "OVERLAY")
    b.warn:SetAllPoints()
    b.warn:SetColorTexture(1, 0.1, 0.1, 0.35)
    b.warn:Hide()
    b.time = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.time:SetPoint("TOP", b, "BOTTOM", 0, -1)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", -1, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        if self.itemId then GameTooltip:SetItemByID(self.itemId) else GameTooltip:SetText(slot.label, 1, 1, 1) end
        GameTooltip:AddLine(" ")
        local left = Remaining(slot, self.itemId, HelpfulAuras())
        GameTooltip:AddLine(slot.label .. ": " .. FmtLeft(left), 1, 0.82, 0)
        GameTooltip:AddLine(slot.key == "weapon" and L["Click: apply to main hand weapon"] or L["Click: use"], 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:HookScript("PreClick", function(self)
        if self.itemId and slot.key ~= "weapon" then StartLearning(self.itemId) end
    end)
    buttons[i] = b
end

-- Secure gombot NEM horgonyzunk a panelhez (attol a panel is vedett lenne, es harcban
-- a meretezese/mozgatasa blokkolva lenne): a panel kepernyo-pozicioja alapjan tesszuk le.
local lastGeo
local function Anchor()
    if InCombatLockdown() then return end
    local p = NS.panel
    local r, b = p:GetRight(), p:GetBottom()
    local geo = p:IsShown() and r and b and (math.floor(r) .. ":" .. math.floor(b)) or "none"
    if geo == lastGeo and bar:GetNumPoints() > 0 then return end
    lastGeo = geo
    bar:ClearAllPoints()
    if geo ~= "none" then
        bar:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", r - 4, b - 2)
    else
        bar:SetPoint("RIGHT", UIParent, "RIGHT", -264, -20)
    end
end

-- Secure attributumok + lathatosag: csak harcon kivul
local function Rebuild()
    if InCombatLockdown() then bar.dirty = true return end
    bar.dirty = nil
    if QuestFocusDB.noBuffBar then bar:Hide() return end
    local x, auras = 0, HelpfulAuras()
    for _, b in ipairs(buttons) do
        local slot = b.slot
        local id = not DB()["noBuff_" .. slot.key] and FindItem(slot) or nil
        local count = id and GetItemCount(id) or 0
        b.itemId = id
        local active = Remaining(slot, id, auras)
        if (id and count > 0) or active then
            b.icon:SetTexture(id and GetItemIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark")
            b.count:SetText(count > 1 and count or "")
            if id and count > 0 then
                b:SetAttribute("type", "macro")
                b:SetAttribute("macrotext", slot.key == "weapon"
                    and ("/use item:%d\n/use 16"):format(id) or ("/use item:%d"):format(id))
            else
                b:SetAttribute("type", nil)
            end
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -x, 0)
            b:Show()
            x = x + BTN + 6
        else
            b:Hide()
        end
    end
    if x == 0 then bar:Hide() return end
    bar:SetWidth(x)
    lastGeo = nil
    Anchor()
    bar:Show()
end
NS.RebuildBuffBar = Rebuild

-- Idok + figyelmeztetes (harcban is mehet, nem secure)
local warned = {}
local function Tick()
    if not bar:IsShown() then return end
    local auras = HelpfulAuras()
    local limit = Minutes() * 60
    local pulse = 0.25 + 0.25 * math.sin(GetTime() * 5)
    for _, b in ipairs(buttons) do
        if b:IsShown() then
            local slot = b.slot
            local left = Remaining(slot, b.itemId, auras)
            b.time:SetText(FmtLeft(left))
            local low = (not left) or (left ~= math.huge and left < limit)
            local canFix = b.itemId and GetItemCount(b.itemId) > 0
            b.warn:SetShown(low and canFix)
            b.warn:SetAlpha(pulse + 0.2)
            b.icon:SetDesaturated(not left)
            -- Egyszer szolunk: amikor a limit ala esik (ha volt buff)
            local key = slot.key
            if left and left ~= math.huge and left < limit and left > 0 then
                if not warned[key] and canFix and not QuestFocusDB.noBuffWarn then
                    warned[key] = true
                    local msg = (L["%s expires in %d min"]):format(slot.label, math.ceil(left / 60))
                    if UIErrorsFrame then UIErrorsFrame:AddMessage("QuestFocus: " .. msg, 1, 0.6, 0.2) end
                    Print(msg)
                end
            elseif left and left >= limit then
                warned[key] = nil
            end
        end
    end
end

local elapsed = 0
bar:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.25 then return end
    elapsed = 0
    Tick()
    Anchor() -- a panel mozgott / atmeretezodott (csak harcon kivul tesz barmit)
end)

---------------------------------------------------------------------------
-- Buff figyelmezteto kisablak (harcon kivul): ikon gombbal, amivel fel is rakhato
---------------------------------------------------------------------------
local alert = CreateFrame("Frame", "QuestFocusBuffAlert", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
alert:SetSize(250, 40)
alert:SetFrameStrata("MEDIUM")
alert:Hide()
if alert.SetBackdrop then
    alert:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    alert:SetBackdropColor(0.06, 0.03, 0.03, 0.93)
    alert:SetBackdropBorderColor(1, 0.55, 0.25, 0.95)
end
local aAccent = alert:CreateTexture(nil, "ARTWORK")
aAccent:SetPoint("TOPLEFT", 4, -4)
aAccent:SetPoint("BOTTOMLEFT", 4, 4)
aAccent:SetWidth(2)
aAccent:SetColorTexture(1, 0.55, 0.25, 1)
alert.label = alert:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
alert.label:SetPoint("TOPLEFT", 12, -7)
alert.label:SetTextColor(1, 0.6, 0.3)
alert.label:SetText(L["BUFF REMINDER"])
alert.hint = alert:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
alert.hint:SetPoint("TOPRIGHT", -26, -7)
alert.hint:SetText(L["click an icon to apply"])
local aClose = CreateFrame("Button", nil, alert, "UIPanelCloseButton")
aClose:SetSize(20, 20)
aClose:SetPoint("TOPRIGHT", -2, -2)

local dismissed = {}   -- slot.key -> true: bezarta, amig a buff fel nem kerul ujra
local alertRows = {}
local ROW_H = 26
for i, slot in ipairs(SLOTS) do
    local b = CreateFrame("Button", "QuestFocusBuffAlertBtn" .. i, alert, "SecureActionButtonTemplate")
    b:SetSize(22, 22)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.slot = slot
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.2)
    b.text = alert:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", b, "RIGHT", 8, 0)
    b.text:SetPoint("RIGHT", alert, "RIGHT", -10, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if self.itemId then GameTooltip:SetItemByID(self.itemId) end
        GameTooltip:AddLine(slot.key == "weapon" and L["Click: apply to main hand weapon"] or L["Click: use"], 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:HookScript("PreClick", function(self)
        if self.itemId and slot.key ~= "weapon" then StartLearning(self.itemId) end
    end)
    b:Hide()
    alertRows[i] = b
end

aClose:SetScript("OnClick", function()
    for _, b in ipairs(alertRows) do if b:IsShown() then dismissed[b.slot.key] = true end end
    if not InCombatLockdown() then alert:Hide() end
end)

local function PlaceAlert()
    alert:ClearAllPoints()
    local p = NS.panel
    local r, t = p:GetRight(), p:GetTop()
    if p:IsShown() and r and t then
        alert:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", r, t + 4)
    else
        alert:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

-- Mely slotok kernek figyelmet: van item, es a buff hianyzik / hamarosan lejar
local lastAlertKey
local function UpdateAlert(auras)
    if InCombatLockdown() then return end
    if QuestFocusDB.noBuffAlert or QuestFocusDB.noBuffBar or UnitIsDeadOrGhost("player") then
        if alert:IsShown() then alert:Hide() end
        lastAlertKey = nil
        return
    end
    local limit = Minutes() * 60
    local need, key = {}, ""
    for _, slot in ipairs(SLOTS) do
        local id = not DB()["noBuff_" .. slot.key] and FindItem(slot) or nil
        local left = Remaining(slot, id, auras)
        if left and (left == math.huge or left >= limit) then dismissed[slot.key] = nil end
        if id and GetItemCount(id) > 0 and not dismissed[slot.key]
            and (not left or (left ~= math.huge and left < limit)) then
            need[#need + 1] = { slot = slot, id = id, left = left }
            key = key .. slot.key .. id .. ";"
        end
    end
    if #need == 0 then
        if alert:IsShown() then alert:Hide() end
        lastAlertKey = nil
        return
    end
    -- Szovegek mindig frissulnek, a secure resz csak ha valtozott a lista
    if key ~= lastAlertKey then
        lastAlertKey = key
        for _, b in ipairs(alertRows) do b:Hide(); b.text:Hide() end
        for i, n in ipairs(need) do
            local b = alertRows[i]
            b.slot, b.itemId = n.slot, n.id
            b.icon:SetTexture(GetItemIcon(n.id))
            b:SetAttribute("type", "macro")
            b:SetAttribute("macrotext", n.slot.key == "weapon"
                and ("/use item:%d\n/use 16"):format(n.id) or ("/use item:%d"):format(n.id))
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", alert, "TOPLEFT", 12, -22 - (i - 1) * ROW_H)
            b:Show()
            b.text:Show()
        end
        alert:SetHeight(26 + #need * ROW_H)
        PlaceAlert()
        if not alert:IsShown() then
            alert:Show()
            if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
        end
    end
    for i, n in ipairs(need) do
        local name = GetItemInfo(n.id) or n.slot.label
        local state = n.left and ((L["%s left"]):format(FmtLeft(n.left))) or ("|cffff4444" .. L["missing"] .. "|r")
        alertRows[i].text:SetText(("|cffffd100%s|r  %s  |cff808080%s|r"):format(n.slot.label, state, name))
    end
end
NS.BuffAlertFrame = alert

local alertElapsed = 0
local alertTicker = CreateFrame("Frame")
alertTicker:SetScript("OnUpdate", function(_, dt)
    alertElapsed = alertElapsed + dt
    if alertElapsed < 1 then return end
    alertElapsed = 0
    UpdateAlert(HelpfulAuras())
    if alert:IsShown() and not InCombatLockdown() then PlaceAlert() end
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("UNIT_AURA")
ev:RegisterEvent("UNIT_INVENTORY_CHANGED")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
local pending = false
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(0.5, function() pending = false; Rebuild() end)
end
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_DISABLED" then
        -- meg a lockdown elott: a secure gombos ablakot harcban nem lehetne eltuntetni
        if alert:IsShown() then alert:Hide() end
        lastAlertKey = nil
    elseif event == "UNIT_AURA" then
        if unit ~= "player" then return end
        CheckLearning()
        Soon()
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if unit == "player" then Soon() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if bar.dirty then Rebuild() end
    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(3, Rebuild)
    else
        Soon()
    end
end)

---------------------------------------------------------------------------
-- Beallitasok: "Buffs" ful
---------------------------------------------------------------------------
local page = NS.AddOptionsTab(L["Buffs"])

local cbBar = NS.OptCheck(L["Buff reminder buttons under the panel"],
    L["Sleeping bag, XP food and weapon enchant buttons with the time left. Click to use the item."],
    function() return not QuestFocusDB.noBuffBar end,
    function(v) QuestFocusDB.noBuffBar = not v; Rebuild() end, page)
cbBar:SetPoint("TOPLEFT", page, "TOPLEFT", -2, 0)

local cbWarn = NS.OptCheck(L["Warn before a buff expires"],
    L["One message (screen + chat) when a buff has less time left than the minutes below."],
    function() return not QuestFocusDB.noBuffWarn end,
    function(v) QuestFocusDB.noBuffWarn = not v end, page)
cbWarn:SetPoint("TOPLEFT", cbBar, "BOTTOMLEFT", 0, -6)

local minBox = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
minBox:SetSize(40, 20)
minBox:SetAutoFocus(false)
minBox:SetNumeric(true)
minBox:SetPoint("TOPLEFT", cbWarn, "BOTTOMLEFT", 32, -6)
local minLabel = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
minLabel:SetPoint("LEFT", minBox, "RIGHT", 8, 0)
minLabel:SetText(L["minutes before it runs out"])
minBox:SetScript("OnEnterPressed", function(self)
    local v = tonumber(self:GetText())
    if v and v > 0 then QuestFocusDB.buffWarnMin = v end
    wipe(warned)
    self:ClearFocus()
end)
minBox:SetScript("OnEscapePressed", function(self) self:SetText(Minutes()); self:ClearFocus() end)

local hint = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
hint:SetPoint("TOPLEFT", minBox, "BOTTOMLEFT", -32, -16)
hint:SetWidth(520)
hint:SetJustifyH("LEFT")
hint:SetText(L["Items: drag one from your bags onto a slot. Right click: automatic / none. "]
    .. L["Sleeping bag and weapon enchant are found by name if no item is set; XP food must be dragged in once. "]
    .. L["The buff an item gives is learned the first time you use it from the button."])

local slotUI = {}
local last = hint
for i, slot in ipairs(SLOTS) do
    local s = CreateFrame("Button", nil, page)
    s:SetSize(34, 34)
    s:SetPoint("TOPLEFT", last, "BOTTOMLEFT", i == 1 and 2 or 0, i == 1 and -14 or -8)
    s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    s.bg = s:CreateTexture(nil, "BACKGROUND")
    s.bg:SetAllPoints()
    s.bg:SetColorTexture(0, 0, 0, 0.5)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetPoint("TOPLEFT", 2, -2)
    s.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    s.text = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    s.text:SetPoint("LEFT", s, "RIGHT", 10, 0)
    s.refresh = function()
        local db = DB()
        local off = db["noBuff_" .. slot.key]
        local set = db.buffItems[slot.key]
        local id = not off and FindItem(slot)
        s.icon:SetTexture(id and GetItemIcon(id) or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
        local name = id and GetItemInfo(id)
        local mode = off and L["off"] or (set and L["set"] or L["automatic"])
        s.text:SetText(("%s: |cffffff00%s|r  |cff808080(%s)|r"):format(slot.label, name or "-", mode))
    end
    local function FromCursor()
        local kind, itemId = GetCursorInfo()
        if kind ~= "item" then return end
        ClearCursor()
        DB().buffItems[slot.key] = itemId
        DB()["noBuff_" .. slot.key] = nil
        s.refresh()
        Rebuild()
    end
    s:SetScript("OnReceiveDrag", FromCursor)
    s:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            local db = DB()
            -- jobb klikk: beallitott -> automatikus -> kikapcsolva -> automatikus
            if db.buffItems[slot.key] then
                db.buffItems[slot.key] = nil
            else
                db["noBuff_" .. slot.key] = not db["noBuff_" .. slot.key] or nil
            end
            s.refresh()
            Rebuild()
        else
            FromCursor()
        end
    end)
    slotUI[i] = s
    last = s
end

local cbAlert = NS.OptCheck(L["Reminder popup out of combat"],
    L["When a buff is missing or about to run out, a small popup above the panel shows the item; click its icon to apply it. "]
    .. L["The X hides it until that buff is applied again."],
    function() return not QuestFocusDB.noBuffAlert end,
    function(v) QuestFocusDB.noBuffAlert = not v; wipe(dismissed); lastAlertKey = nil end, page)
cbAlert:SetPoint("TOPLEFT", last, "BOTTOMLEFT", -2, -14)

page:SetScript("OnShow", function()
    cbBar.refresh(); cbWarn.refresh(); cbAlert.refresh()
    minBox:SetText(Minutes())
    for _, s in ipairs(slotUI) do s.refresh() end
end)
