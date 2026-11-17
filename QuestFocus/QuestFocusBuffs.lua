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

-- Class buffok: 'spells' = a buff nevei (barmelyik eleg, a "Greater ..." is), 'cast' = amit
-- feltehetunk magunkra. 'permanent': nem jar le (aura / aspect), csak a hianya szamit.
-- Alapbol azt teszi fel, amit legutobb rajtad latott, kulonben az elso ismert spellt.
local CLASS_BUFFS = {
    PALADIN = {
        { key = "c_blessing", label = L["Blessing"], warn = 1,
          cast = { "Blessing of Might", "Blessing of Wisdom", "Blessing of Kings", "Blessing of Sanctuary",
                   "Blessing of Salvation", "Blessing of Light" },
          spells = { "Blessing of Might", "Blessing of Wisdom", "Blessing of Kings", "Blessing of Sanctuary",
                     "Blessing of Salvation", "Blessing of Light", "Greater Blessing of Might",
                     "Greater Blessing of Wisdom", "Greater Blessing of Kings", "Greater Blessing of Sanctuary",
                     "Greater Blessing of Salvation", "Greater Blessing of Light" } },
        { key = "c_aura", label = L["Aura"], permanent = true,
          spells = { "Devotion Aura", "Retribution Aura", "Concentration Aura", "Sanctity Aura",
                     "Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura" } },
    },
    MAGE = {
        { key = "c_int", label = L["Arcane Intellect"], warn = 1, cast = { "Arcane Intellect" },
          spells = { "Arcane Intellect", "Arcane Brilliance" } },
        { key = "c_armor", label = L["Armor"], warn = 1,
          spells = { "Ice Armor", "Frost Armor", "Mage Armor", "Molten Armor" } },
    },
    PRIEST = {
        { key = "c_fort", label = L["Fortitude"], warn = 1, cast = { "Power Word: Fortitude" },
          spells = { "Power Word: Fortitude", "Prayer of Fortitude" } },
        { key = "c_inner", label = L["Inner Fire"], warn = 1, spells = { "Inner Fire" } },
    },
    DRUID = {
        { key = "c_motw", label = L["Mark of the Wild"], warn = 1, cast = { "Mark of the Wild" },
          spells = { "Mark of the Wild", "Gift of the Wild" } },
        { key = "c_thorns", label = L["Thorns"], warn = 1, spells = { "Thorns" } },
    },
    WARLOCK = {
        { key = "c_armor", label = L["Demon Armor"], warn = 1, spells = { "Fel Armor", "Demon Armor", "Demon Skin" } },
    },
    HUNTER = {
        { key = "c_aspect", label = L["Aspect"], permanent = true,
          spells = { "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Cheetah", "Aspect of the Pack",
                     "Aspect of the Wild", "Aspect of the Beast", "Aspect of the Viper", "Aspect of the Dragonhawk" } },
        { key = "c_trueshot", label = L["Trueshot Aura"], permanent = true, spells = { "Trueshot Aura" } },
    },
    SHAMAN = {
        { key = "c_shield", label = L["Shield"], warn = 1, spells = { "Lightning Shield", "Water Shield", "Earth Shield" } },
    },
}
local _, PLAYER_CLASS = UnitClass("player")
-- Minden class buff neve (barmelyik classe): ilyen nem lehet egy item "megtanult" buffja
local CLASS_SPELL_SET = {}
for _, list in pairs(CLASS_BUFFS) do
    for _, s in ipairs(list) do for _, n in ipairs(s.spells) do CLASS_SPELL_SET[n] = true end end
end
for _, s in ipairs(CLASS_BUFFS[PLAYER_CLASS] or {}) do
    s.names = {}
    s.isClass = true
    SLOTS[#SLOTS + 1] = s
end

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
            local a = { duration = tonumber(duration) or 0, expires = tonumber(expires) or 0, count = tonumber(count) or 0,
                        index = i, spellId = tonumber(spellId), name = name }
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

-- XP buff felismerese: a buff leirasaban "experience" szerepel (spellId-nkent egyszer nezzuk,
-- csak harcon kivul). Az alvozsak rested buffja (429959) nem szamit.
local auraTip = CreateFrame("GameTooltip", "QuestFocusAuraTip", nil, "GameTooltipTemplate")
local xpAuraCache = {}
local function IsXPAura(a)
    if not a or not a.spellId or a.spellId == 429959 then return false end
    local cached = xpAuraCache[a.spellId]
    if cached ~= nil then return cached end
    if InCombatLockdown() or not a.index then return false end
    local text = ""
    local ok = pcall(function()
        auraTip:SetOwner(WorldFrame, "ANCHOR_NONE")
        auraTip:ClearLines()
        auraTip:SetUnitBuff("player", a.index)
        for i = 1, auraTip:NumLines() do
            local fs = _G["QuestFocusAuraTipTextLeft" .. i]
            local t = fs and fs:GetText()
            if t then text = text .. "\n" .. t end
        end
        auraTip:Hide()
    end)
    if not ok then return false end
    local lower = text:lower()
    local isXP = lower:find("experience", 1, true) ~= nil or lower:find("%f[%w]xp%f[%W]") ~= nil
    xpAuraCache[a.spellId] = isXP
    return isXP
end

-- Hatralevo mp (nil = nincs buff, math.huge = nem jar le), masodik ertek: stackek szama
local function Remaining(slot, itemId, auras)
    if slot.isClass then
        for _, name in ipairs(slot.spells) do
            local a = auras[name]
            if a then
                -- megjegyezzuk, melyiket hasznalod (ezt tesszuk fel legkozelebb)
                QuestFocusDB.classSeen = QuestFocusDB.classSeen or {}
                QuestFocusDB.classSeen[slot.key] = name
                if slot.permanent or a.expires == 0 then return math.huge end
                return a.expires - GetTime()
            end
        end
        return
    end
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
    if learned and (CLASS_SPELL_SET[learned] or (slot.key == "food" and learned == L["Well Fed"])) then
        -- rosszul tanult (pl. kozben kapott Blessing): eldobjuk
        DB().buffLearn[itemId] = nil
        learned = nil
    end
    if learned then names[#names + 1] = learned end
    local spell = ItemSpell(itemId)
    if spell then names[#names + 1] = spell end
    -- XP kaja: a sima "Well Fed" NEM szamit (az nem az XP buff); helyette barmelyik buff,
    -- aminek a leirasaban experience/XP van
    if slot.key == "food" then
        for _, a in pairs(auras) do
            if a.duration > 60 and IsXPAura(a) then
                if not learned and itemId then DB().buffLearn[itemId] = a.name end
                if a.expires == 0 then return math.huge end
                return a.expires - GetTime()
            end
        end
    end
    for _, n in ipairs(names) do
        if slot.key == "food" and n == L["Well Fed"] then n = nil end
        local a = auras[n]
        -- a 30 mp-es "Food" evo aura nem az igazi buff
        if a and not (slot.key == "food" and a.duration > 0 and a.duration <= 60) then
            if a.expires == 0 then return math.huge end
            return a.expires - GetTime()
        end
    end
end

-- Class spell: ismeri-e a karakter (a spellbookban van-e)
local function SpellKnown(name)
    if not name then return false end
    local ok, info = pcall(function()
        if C_Spell and C_Spell.GetSpellInfo then return C_Spell.GetSpellInfo(name) end
        return (GetSpellInfo(name))
    end)
    return ok and info ~= nil
end

local function SpellIconOf(name)
    local ok, tex = pcall(function()
        if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(name) end
        return GetSpellTexture(name)
    end)
    return ok and tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Melyik spellt tegyuk fel: beallitott > legutobb rajtad latott > az elso ismert
local function SlotSpell(slot)
    local castable = slot.cast or slot.spells
    local function ok(name)
        if not name or not SpellKnown(name) then return false end
        for _, c in ipairs(castable) do if c == name then return true end end
        return false
    end
    local pref = QuestFocusDB.classPref and QuestFocusDB.classPref[slot.key]
    if ok(pref) then return pref end
    local seen = QuestFocusDB.classSeen and QuestFocusDB.classSeen[slot.key]
    if seen then seen = seen:gsub("^Greater ", "") end
    if ok(seen) then return seen end
    for _, c in ipairs(castable) do if SpellKnown(c) then return c end end
end

-- Mivel lehet "megjavitani" a slotot: { kind = "item", id } vagy { kind = "spell", name }
local function Action(slot)
    if DB()["noBuff_" .. slot.key] then return end
    if slot.isClass then
        local name = SlotSpell(slot)
        if name then return { kind = "spell", name = name } end
        return
    end
    local id = FindItem(slot)
    if id and GetItemCount(id) > 0 then return { kind = "item", id = id } end
end

local function ActionIcon(a)
    if a.kind == "spell" then return SpellIconOf(a.name) end
    return GetItemIcon(a.id)
end

local function ActionName(a, slot)
    if a.kind == "spell" then return a.name end
    return GetItemInfo(a.id) or slot.label
end

-- Secure gomb beallitasa (csak harcon kivul hivjuk)
local function SetupSecure(b, slot, a)
    if a.kind == "spell" then
        b:SetAttribute("type", "spell")
        b:SetAttribute("spell", a.name)
        b:SetAttribute("unit", "player")
        b:SetAttribute("macrotext", nil)
    else
        b:SetAttribute("type", "macro")
        b:SetAttribute("spell", nil)
        b:SetAttribute("unit", nil)
        b:SetAttribute("macrotext", slot.key == "weapon"
            and ("/use item:%d\n/use 16"):format(a.id) or ("/use item:%d"):format(a.id))
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
    -- Nem lehet a buff: class buffok (blessing, aura...), mas itemek mar megtanult buffjai,
    -- vegtelen aurak. Igy egy kozben kapott Blessing nem "tanulodik meg" kajanak.
    local skip = {}
    for _, s in ipairs(SLOTS) do
        for _, n in ipairs(s.spells or {}) do skip[n] = true end
    end
    for id, n in pairs(DB().buffLearn) do if id ~= learning.itemId then skip[n] = true end end
    for name, a in pairs(HelpfulAuras()) do
        if not learning.before[name] and not skip[name] and a.duration >= 300 then
            DB().buffLearn[learning.itemId] = name
            learning = nil
            return
        end
    end
end

-- Debug: mit lat a buff figyelo (Debug ful / /qf debug)
NS.BuffDebugLines = function()
    local out = { L["Buffs:"] }
    local auras = HelpfulAuras()
    for _, slot in ipairs(SLOTS) do
        local a = Action(slot)
        local id = a and a.id or FindItem(slot)
        local left, stacks = Remaining(slot, id, auras)
        local what = a and (a.kind == "spell" and a.name or (GetItemInfo(a.id) or ("item " .. a.id)))
            or (id and ((GetItemInfo(id) or ("item " .. id)) .. " (0 in bags)")) or "-"
        local learned = id and DB().buffLearn[id]
        out[#out + 1] = ("  %s: %s | buff: %s | left: %s%s%s%s"):format(slot.label, what,
            learned or (slot.isClass and "class" or "-"),
            left and (left == math.huge and "on" or ("%ds"):format(left)) or "|cffff4444none|r",
            slot.stacks and (" stacks " .. tostring(stacks or 0) .. "/" .. slot.stacks) or "",
            DB()["noBuff_" .. slot.key] and " |cff808080(off)|r" or "",
            NS.buffDismissed and NS.buffDismissed[slot.key] and " |cff808080(closed with X)|r" or "")
    end
    return out
end

-- Megtanult buff torlese (ha rosszat tanult): /qf buffreset
NS.ResetBuffLearn = function()
    wipe(DB().buffLearn)
    NS.Print(L["Learned item buffs cleared; they are learned again on next use."])
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
    local r, b = NS.PanelEdge("right"), NS.PanelEdge("bottom")
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
        if slot.isClass then
            b:Hide() -- a gombsorban csak az itemek; class buff a kisablakban
        elseif (id and count > 0) or active then
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
        local a = Action(slot)
        local canFix = a ~= nil
        local limit = Minutes(slot) * 60
        local left = Remaining(slot, a and a.id, auras)
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
NS.buffDismissed = dismissed
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
        local s = self.slot or slot
        if self.spellName then
            GameTooltip:SetText(self.spellName, 1, 1, 1)
            GameTooltip:AddLine(L["Click: cast it on yourself"], 0.5, 0.5, 0.5)
        else
            if self.itemId then GameTooltip:SetItemByID(self.itemId) end
            GameTooltip:AddLine(s.key == "weapon" and L["Click: apply to main hand weapon"] or L["Click: use"], 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:HookScript("PreClick", function(self)
        local s = self.slot or slot
        if self.itemId and s.key ~= "weapon" and not s.isClass then StartLearning(self.itemId) end
    end)
    b:Hide()
    alertRows[i] = b
end

-- X: a kovetkezo harcig nem mutatjuk (harc utan, ha meg kell, visszajon)
local hiddenUntilCombat = false
aClose:SetScript("OnClick", function()
    hiddenUntilCombat = true
    if not InCombatLockdown() then alert:Hide() end
end)

-- Harcon kivul a panel tetejere tapad (sav, ugyanolyan szeles es meretaranyu), igy
-- egyutt mozog vele. Harc elott (PLAYER_REGEN_DISABLED) leválasztjuk, kulonben a panel
-- is vedett lenne es harcban nem lehetne mozgatni.
local function PlaceAlert()
    if InCombatLockdown() then return end
    alert:ClearAllPoints()
    local p = NS.panel
    if p:IsShown() then
        alert:SetScale(p:GetScale())
        alert:SetWidth(p:GetWidth())
        alert:SetPoint("BOTTOMLEFT", p, "TOPLEFT", 0, -3)
    else
        alert:SetScale(1)
        alert:SetWidth(250)
        alert:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

local function DetachAlert()
    alert:Hide()
    alert:ClearAllPoints()
    alert:SetPoint("TOP", UIParent, "TOP", 0, -120)
end

-- Mely slotok kernek figyelmet: van item, es a buff hianyzik / hamarosan lejar
local lastAlertKey
local function UpdateAlert(auras)
    if InCombatLockdown() then return end
    if QuestFocusDB.noBuffAlert or hiddenUntilCombat or UnitIsDeadOrGhost("player") then
        if alert:IsShown() then alert:Hide() end
        lastAlertKey = nil
        return
    end
    local need, key = {}, ""
    for _, slot in ipairs(SLOTS) do
        local limit = Minutes(slot) * 60
        local a = Action(slot)
        local left, stacks = Remaining(slot, a and a.id, auras)
        local short = ShortStacks(slot, stacks)
        if left and (left == math.huge or left >= limit) and not short then dismissed[slot.key] = nil end
        if a and not dismissed[slot.key]
            and (not left or (left ~= math.huge and left < limit) or short) then
            need[#need + 1] = { slot = slot, action = a, left = left, stacks = stacks }
            key = key .. slot.key .. tostring(a.id or a.name) .. ";"
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
            b.slot, b.itemId, b.spellName = n.slot, n.action.id, n.action.name
            b.icon:SetTexture(ActionIcon(n.action))
            SetupSecure(b, n.slot, n.action)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", alert, "TOPLEFT", 12, -22 - (i - 1) * ROW_H)
            b:Show()
            b.text:Show()
        end
        alert:SetHeight(26 + #need * ROW_H)
        PlaceAlert()
        alert.onPanel = NS.panel:IsShown()
        if not alert:IsShown() then
            alert:Show()
            if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
        end
    end
    for i, n in ipairs(need) do
        local name = ActionName(n.action, n.slot)
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
    -- a panel ki/be: ujrahelyezes (a mozgatast az anchor magatol koveti)
    if alert:IsShown() and not InCombatLockdown() and (alert.onPanel ~= NS.panel:IsShown()
        or (NS.panel:IsShown() and math.abs(alert:GetScale() - NS.panel:GetScale()) > 0.01)) then
        alert.onPanel = NS.panel:IsShown()
        PlaceAlert()
    end
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
        -- meg a lockdown elott: elrejtjuk es levalasztjuk a panelrol (harcban a secure
        -- gombos ablakot nem lehetne eltuntetni, es a panel se lenne mozgathato)
        DetachAlert()
        hiddenUntilCombat = false -- az X csak a kovetkezo harcig szolt
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
        -- XP kaja valaszto: ha nincs beallitva (a panel betoltese utan)
        C_Timer.After(12, function() if NS.MaybePromptFood then NS.MaybePromptFood() end end)
    else
        Soon()
    end
end)

---------------------------------------------------------------------------
-- XP kaja valaszto: ha nincs beallitva, listazza a taskaban levo jelolteket
-- (amiknek a leirasaban "experience" / "XP" van elol, utana a tobbi etel/ital)
---------------------------------------------------------------------------
local scanTip = CreateFrame("GameTooltip", "QuestFocusScanTip", nil, "GameTooltipTemplate")
local function TooltipText(bag, slot)
    local ok = pcall(function()
        scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
        scanTip:ClearLines()
        scanTip:SetBagItem(bag, slot)
    end)
    if not ok then return "" end
    local parts = {}
    for i = 1, scanTip:NumLines() do
        local fs = _G["QuestFocusScanTipTextLeft" .. i]
        local txt = fs and fs:GetText()
        if txt then parts[#parts + 1] = txt end
    end
    scanTip:Hide()
    return table.concat(parts, "\n")
end

local function FoodCandidates()
    local xp, other, seen = {}, {}, {}
    for bag = 0, 4 do
        for s = 1, (GetSlots(bag) or 0) do
            local id = GetItemID(bag, s)
            if id and not seen[id] then
                seen[id] = true
                local _, _, _, _, _, classID, subID = GetItemInfoInstant(id)
                local tip = TooltipText(bag, s):lower()
                local isXP = tip:find("experience", 1, true) or tip:find("%f[%w]xp%f[%W]")
                if isXP and classID == 0 then
                    xp[#xp + 1] = id
                elseif classID == 0 and subID == 5 then -- Consumable > Food & Drink
                    other[#other + 1] = id
                end
            end
        end
    end
    return xp, other
end

local picker = CreateFrame("Frame", "QuestFocusFoodPicker", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
picker:SetSize(280, 80)
picker:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
picker:SetFrameStrata("DIALOG")
picker:EnableMouse(true)
picker:SetMovable(true)
picker:RegisterForDrag("LeftButton")
picker:SetScript("OnDragStart", picker.StartMoving)
picker:SetScript("OnDragStop", picker.StopMovingOrSizing)
picker:Hide()
if picker.SetBackdrop then
    picker:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 20,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    picker:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
    picker:SetBackdropBorderColor(0.95, 0.78, 0.40, 1)
end
picker.title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
picker.title:SetPoint("TOPLEFT", 14, -12)
picker.title:SetText(L["Choose your XP food"])
picker.sub = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
picker.sub:SetPoint("TOPLEFT", picker.title, "BOTTOMLEFT", 0, -3)
picker.sub:SetText(L["Click the one that gives the XP buff."])
local pClose = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
pClose:SetSize(24, 24)
pClose:SetPoint("TOPRIGHT", -4, -4)
pClose:SetScript("OnClick", function() picker:Hide() end)
local pNever = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
pNever:SetSize(110, 20)
pNever:SetText(L["Don't ask again"])
pNever:SetScript("OnClick", function() QuestFocusDB.noFoodPrompt = true; picker:Hide() end)
picker.empty = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
picker.empty:SetText(L["No food found in your bags."])

local pickRows = {}
local function PickRow(i)
    local r = pickRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, picker)
    r:SetSize(250, 22)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("LEFT")
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetPoint("RIGHT")
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.1)
    r:SetScript("OnClick", function(self)
        DB().buffItems.food = self.itemId
        DB().noBuff_food = nil
        picker:Hide()
        Print((L["XP food set: %s"]):format(GetItemInfo(self.itemId) or self.itemId))
        lastAlertKey = nil
        Rebuild()
        if NS.RefreshBuffOptions then NS.RefreshBuffOptions() end
    end)
    r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemId)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pickRows[i] = r
    return r
end

local function ShowFoodPicker()
    local xp, other = FoodCandidates()
    for _, r in ipairs(pickRows) do r:Hide() end
    local y, n = -44, 0
    local function add(id, isXP)
        if n >= 10 then return end
        n = n + 1
        local r = PickRow(n)
        r.itemId = id
        r.icon:SetTexture(GetItemIcon(id))
        local count = GetItemCount(id)
        r.text:SetText(((isXP and "|cff33ff99XP|r  " or "") .. (GetItemInfo(id) or ("item " .. id)))
            .. (count > 1 and ("  |cff808080x" .. count .. "|r") or ""))
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", picker, "TOPLEFT", 14, y)
        r:Show()
        y = y - 24
    end
    for _, id in ipairs(xp) do add(id, true) end
    for _, id in ipairs(other) do add(id, false) end
    picker.empty:SetShown(n == 0)
    if n == 0 then
        picker.empty:ClearAllPoints()
        picker.empty:SetPoint("TOPLEFT", 14, y)
        y = y - 20
    end
    pNever:ClearAllPoints()
    pNever:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -14, y - 6)
    picker:SetHeight(-y + 40)
    picker:Show()
end
NS.ShowFoodPicker = ShowFoodPicker

-- Bejelentkezes utan egyszer felajanljuk, ha nincs XP kaja beallitva, de van etel a taskaban
local function MaybePromptFood()
    if InCombatLockdown() or QuestFocusDB.noFoodPrompt or DB().buffItems.food or DB().noBuff_food then return end
    local xp, other = FoodCandidates()
    if #xp + #other == 0 then return end
    ShowFoodPicker()
end
NS.MaybePromptFood = MaybePromptFood

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
    .. L["The number box: warn this many minutes before the buff runs out (Enter to save). "]
    .. L["Class buffs: by default the one you last had on is cast; drag a spell from your spellbook (P) onto the slot to choose."])

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
        if slot.isClass then
            local pref = db.classPref and db.classPref[slot.key]
            local name = not off and SlotSpell(slot)
            s.icon:SetTexture(name and SpellIconOf(name) or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
            local mode = off and L["off"] or (pref and L["set"] or L["automatic"])
            s.text:SetText(("%s: |cffffff00%s|r  |cff808080(%s)|r"):format(slot.label,
                name or (off and "-" or L["not known"]), mode))
            return
        end
        local set = db.buffItems[slot.key]
        local id = not off and FindItem(slot)
        s.icon:SetTexture(id and GetItemIcon(id) or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
        local name = id and GetItemInfo(id)
        local mode = off and L["off"] or (set and L["set"] or L["automatic"])
        s.text:SetText(("%s: |cffffff00%s|r  |cff808080(%s)|r"):format(slot.label, name or "-", mode))
    end
    local function FromCursor()
        local kind, itemId, _, spellID = GetCursorInfo()
        if slot.isClass then
            -- class slotra spellt huzhatsz a spellbookbol (P): azt teszi fel
            if kind ~= "spell" then return end
            local ok, name = pcall(function()
                if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
                return (GetSpellInfo(spellID))
            end)
            ClearCursor()
            if ok and name then
                QuestFocusDB.classPref = QuestFocusDB.classPref or {}
                QuestFocusDB.classPref[slot.key] = name
                DB()["noBuff_" .. slot.key] = nil
                lastAlertKey = nil
            end
            s.refresh()
            return
        end
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
            lastAlertKey = nil
            if slot.isClass and db.classPref and db.classPref[slot.key] then
                db.classPref[slot.key] = nil
            elseif db.buffItems[slot.key] then
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

local pickBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
pickBtn:SetSize(170, 22)
pickBtn:SetPoint("TOPLEFT", cbAlert, "BOTTOMLEFT", 2, -10)
pickBtn:SetText(L["Choose XP food from bags"])
pickBtn:SetScript("OnClick", ShowFoodPicker)

NS.RefreshBuffOptions = function()
    for _, s in ipairs(slotUI) do s.refresh() end
end

page:SetScript("OnShow", function()
    cbBar.refresh(); cbWarn.refresh(); cbAlert.refresh()
    for _, s in ipairs(slotUI) do s.refresh() end
end)
