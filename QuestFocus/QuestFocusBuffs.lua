-- QuestFocus: buff emlekezteto gombok (alvozsak / XP kaja / fegyver enchant).
-- A panel alatt egy kis sor: ikon + hatralevo ido. Ha a buff hianyzik vagy kevesebb mint N perc
-- van hatra, a gomb pirosan pulzal, es egyszer szol. Kattintasra hasznalja az itemet
-- (fegyver enchantnal ra is teszi a main hand fegyverre).

local _, NS = ...
local L = NS.L
local Print = NS.Print

local SLOTS = {
    -- Cozy Sleeping Bag buff: spell 429959, 3 stack kell belole
    { key = "rest",   label = L["Sleeping bag"], names = { L["Sleeping Bag"] }, spellId = 429959, stacks = 3, warn = 10 },
    { key = "food",   label = L["XP food"],      names = {}, warn = 1 },
    { key = "weapon", label = L["Weapon enchant"],
      names = { L["Sharpening Stone"], L["Weightstone"], L["Wizard Oil"], L["Mana Oil"] }, warn = 1 },
}
local BTN = 30

local function DB()
    QuestFocusDB.buffItems = QuestFocusDB.buffItems or {}
    QuestFocusDB.buffLearn = QuestFocusDB.buffLearn or {}
    return QuestFocusDB
end

-- Figyelmeztetesi kuszob percben, buffonkent (alap: slot.warn)
local function Minutes(slot)
    local t = QuestFocusDB.buffWarn
    return (t and tonumber(t[slot.key])) or slot.warn or 10
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

-- Ezen a kliensen harcban az aurak "secret" ertekek: addon nem olvashatja (hibat dob).
-- Ezert csak harcon kivul olvasunk, harcban a legutobbi eredmeny (abszolut lejarati idok) megy.
local auraCache, auraById = {}, {}
local function ReadAuras()
    local out, byId = {}, {}
    for i = 1, 40 do
        local ok, name, count, duration, expires, spellId, _
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a
            ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok then return nil end
            if not a then break end
            ok = pcall(function()
                name, count, duration, expires, spellId = a.name, a.applications, a.duration, a.expirationTime, a.spellId
            end)
            if not ok then return nil end
        else
            ok, name, _, count, _, duration, expires, _, _, _, spellId = pcall(UnitAura, "player", i, "HELPFUL")
            if not ok then return nil end
            if not name then break end
        end
        if type(name) == "string" then
            local a = { duration = tonumber(duration) or 0, expires = tonumber(expires) or 0, count = tonumber(count) or 0 }
            out[name] = a
            if tonumber(spellId) then byId[tonumber(spellId)] = a end
        end
    end
    return out, byId
end

local function HelpfulAuras()
    if InCombatLockdown() then return auraCache end
    local ok, fresh, byId = pcall(ReadAuras)
    if ok and fresh then auraCache, auraById = fresh, byId end
    return auraCache
end

-- Hatralevo mp (nil = nincs buff, math.huge = nem jar le), masodik ertek: stackek szama
local function Remaining(slot, itemId, auras)
    if slot.spellId then
        local a = auraById[slot.spellId]
        if a then
            local stacks = math.max(a.count or 0, 1)
            if a.expires == 0 then return math.huge, stacks end
            return a.expires - GetTime(), stacks
        end
        return nil, 0
    end
    if slot.key == "weapon" then
        local ok, has, ms = pcall(GetWeaponEnchantInfo)
        if ok and has then
            local okN, sec = pcall(function() return (ms or 0) / 1000 end)
            if okN then return sec end
        end
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

-- Stack kovetelmeny (alvozsak: 3 stack kell)
local function ShortStacks(slot, stacks)
    return slot.stacks and (stacks or 0) < slot.stacks
end
local function StackText(slot, stacks)
    if not slot.stacks then return "" end
    local c = ShortStacks(slot, stacks) and "|cffff9933" or "|cff33ff99"
    return (" %s%d/%d|r"):format(c, stacks or 0, slot.stacks)
end

local function FmtLeft(sec, slot)
    if not sec then return "|cffff4444" .. L["none"] .. "|r" end
    if sec == math.huge then return "|cff33ff99on|r" end
    local m = math.floor(sec / 60)
    local txt = m >= 60 and ("%dh"):format(math.floor(m / 60)) or (m >= 1 and ("%dm"):format(m) or ("%ds"):format(math.floor(sec)))
    if slot and sec < Minutes(slot) * 60 then return "|cffff9933" .. txt .. "|r" end
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
        local left, stacks = Remaining(slot, self.itemId, HelpfulAuras())
        GameTooltip:AddLine(slot.label .. ": " .. FmtLeft(left, slot) .. StackText(slot, stacks), 1, 0.82, 0)
        if slot.stacks then
            GameTooltip:AddLine((L["Needs %d stacks of the buff (spell %d)."]):format(slot.stacks, slot.spellId), 0.7, 0.7, 0.7)
        end
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
    -- A gombsor alapbol ki van kapcsolva (a buff idok ugyis latszanak a buff kereten)
    if not QuestFocusDB.showBuffBar then bar:Hide() return end
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

-- Egyszer szolunk (kepernyo + chat), amikor egy buff a kuszob ala esik. A gombsortol fuggetlen.
local function CheckWarnings(auras)
    if QuestFocusDB.noBuffWarn then return end
    for _, slot in ipairs(SLOTS) do
        local id = not DB()["noBuff_" .. slot.key] and FindItem(slot) or nil
        local canFix = id and GetItemCount(id) > 0
        local limit = Minutes(slot) * 60
        local left = Remaining(slot, id, auras)
        local key = slot.key
        if left and left ~= math.huge and left < limit and left > 0 then
            if not warned[key] and canFix then
                warned[key] = true
                local msg = (L["%s expires in %d min"]):format(slot.label, math.max(1, math.ceil(left / 60)))
                if UIErrorsFrame then UIErrorsFrame:AddMessage("QuestFocus: " .. msg, 1, 0.6, 0.2) end
                Print(msg)
            end
        elseif left and left >= limit then
            warned[key] = nil
        end
    end
end

-- Gombsor idok + pulzalas (csak ha be van kapcsolva es latszik)
local function Tick()
    if not bar:IsShown() then return end
    local auras = HelpfulAuras()
    local pulse = 0.25 + 0.25 * math.sin(GetTime() * 5)
    for _, b in ipairs(buttons) do
        if b:IsShown() then
            local slot = b.slot
            local limit = Minutes(slot) * 60
            local left, stacks = Remaining(slot, b.itemId, auras)
            b.time:SetText(FmtLeft(left, slot) .. StackText(slot, stacks))
            local low = (not left) or (left ~= math.huge and left < limit) or ShortStacks(slot, stacks)
            local canFix = b.itemId and GetItemCount(b.itemId) > 0
            b.warn:SetShown(low and canFix)
            b.warn:SetAlpha(pulse + 0.2)
            b.icon:SetDesaturated(not left)
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
    -- ugyanaz a kinezet, mint a progress kisablake
    alert:SetBackdropColor(0.04, 0.04, 0.06, 0.92)
    alert:SetBackdropBorderColor(0.95, 0.78, 0.40, 0.9)
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
    if QuestFocusDB.noBuffAlert or UnitIsDeadOrGhost("player") then
        if alert:IsShown() then alert:Hide() end
        lastAlertKey = nil
        return
    end
    local need, key = {}, ""
    for _, slot in ipairs(SLOTS) do
        local limit = Minutes(slot) * 60
        local id = not DB()["noBuff_" .. slot.key] and FindItem(slot) or nil
        local left, stacks = Remaining(slot, id, auras)
        local short = ShortStacks(slot, stacks)
        if left and (left == math.huge or left >= limit) and not short then dismissed[slot.key] = nil end
        if id and GetItemCount(id) > 0 and not dismissed[slot.key]
            and (not left or (left ~= math.huge and left < limit) or short) then
            need[#need + 1] = { slot = slot, id = id, left = left, stacks = stacks }
            key = key .. slot.key .. id .. ";"
        end
    end
    if #need == 0 then
        if alert:IsShown() then alert:Hide() end
        lastAlertKey = nil
        return
    end
    -- Ugyanazon a helyen jelenik meg, mint a progress kisablak: ha az eppen kint van
    -- (pl. harc vegen), megvarjuk, amig eltunik, es utana jon a buff emlekezteto
    -- Betolteskor a panel csak par mp mulva jon fel (Questie): addig varunk, hogy a
    -- kisablak a panel folott jelenjen meg, ne magaban a kepernyo tetejen.
    -- (Ha a panelt bezartad, nem varunk ra.)
    if not alert:IsShown() and not NS.panel:IsShown() and not QuestFocusDB.hidePanel then
        lastAlertKey = nil
        return
    end
    if not alert:IsShown() and NS.ToastFrame and NS.ToastFrame:IsShown() then
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
        local state = (n.left and ((L["%s left"]):format(FmtLeft(n.left, n.slot))) or ("|cffff4444" .. L["missing"] .. "|r"))
            .. StackText(n.slot, n.stacks)
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
    local auras = HelpfulAuras()
    CheckWarnings(auras)
    UpdateAlert(auras)
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

local cbBar = NS.OptCheck(L["Buff buttons under the panel (off by default)"],
    L["Sleeping bag, XP food and weapon enchant buttons with the time left. Click to use the item. "]
    .. L["Off by default: the buff frame already shows the timers; the reminder popup works without these."],
    function() return QuestFocusDB.showBuffBar end,
    function(v) QuestFocusDB.showBuffBar = v; Rebuild() end, page)
cbBar:SetPoint("TOPLEFT", page, "TOPLEFT", -2, 0)

local cbWarn = NS.OptCheck(L["Warn before a buff expires"],
    L["One message (screen + chat) when a buff has less time left than the minutes below."],
    function() return not QuestFocusDB.noBuffWarn end,
    function(v) QuestFocusDB.noBuffWarn = not v end, page)
cbWarn:SetPoint("TOPLEFT", cbBar, "BOTTOMLEFT", 0, -6)

local hint = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
hint:SetPoint("TOPLEFT", cbWarn, "BOTTOMLEFT", 2, -12)
hint:SetWidth(520)
hint:SetJustifyH("LEFT")
hint:SetText(L["Items: drag one from your bags onto a slot. Right click: automatic / none. "]
    .. L["Sleeping bag and weapon enchant are found by name if no item is set; XP food must be dragged in once. "]
    .. L["The buff an item gives is learned the first time you use it from the button. "]
    .. L["The number box: warn this many minutes before the buff runs out (Enter to save)."])

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
    -- Figyelmeztetes kuszob ehhez a buffhoz (perc)
    s.min = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    s.min:SetSize(34, 20)
    s.min:SetAutoFocus(false)
    s.min:SetNumeric(true)
    s.min:SetPoint("LEFT", s, "RIGHT", 14, 0)
    s.minLabel = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    s.minLabel:SetPoint("LEFT", s.min, "RIGHT", 4, 0)
    s.minLabel:SetText(L["min"])
    s.min:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v and v >= 0 then
            QuestFocusDB.buffWarn = QuestFocusDB.buffWarn or {}
            QuestFocusDB.buffWarn[slot.key] = v
        end
        wipe(warned)
        wipe(dismissed)
        lastAlertKey = nil
        self:SetText(Minutes(slot))
        self:ClearFocus()
    end)
    s.min:SetScript("OnEscapePressed", function(self) self:SetText(Minutes(slot)); self:ClearFocus() end)
    s.text = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    s.text:SetPoint("LEFT", s.minLabel, "RIGHT", 12, 0)
    s.refresh = function()
        s.min:SetText(Minutes(slot))
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
    for _, s in ipairs(slotUI) do s.refresh() end
end)
