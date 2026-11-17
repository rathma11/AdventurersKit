-- QuestFocus: buff emlekezteto gombok (alvozsak / XP kaja / fegyver enchant).
-- A panel alatt egy kis sor: ikon + hatralevo ido. Ha a buff hianyzik vagy kevesebb mint N perc
-- van hatra, a gomb pirosan pulzal, es egyszer szol. Kattintasra hasznalja az itemet
-- (fegyver enchantnal ra is teszi a main hand fegyverre).

local NS = _G.QuestFocusNS -- a QuestFocus (alap) addon kozos nevtere
if not NS then return end
local L = NS.L
local Print = NS.Print

local SLOTS = {
    -- Cozy Sleeping Bag buff: spell 429959, 3 stack kell belole
    { key = "rest",   label = L["Sleeping bag"], names = { L["Sleeping Bag"] }, spellId = 429959, stacks = 3, warn = 10 },
    { key = "food",   label = L["XP food"],      names = {}, warn = 1 },
    -- fegyver enchant itemmel: hand = 16 main hand, 17 off hand (csak ha ott fegyver van)
    { key = "weapon", label = L["Main hand enchant"], hand = 16,
      names = { L["Sharpening Stone"], L["Weightstone"], L["Wizard Oil"], L["Mana Oil"] }, warn = 1 },
    { key = "weapon_off", label = L["Off-hand enchant"], hand = 17,
      names = { L["Sharpening Stone"], L["Weightstone"], L["Wizard Oil"], L["Mana Oil"] }, warn = 1 },
}
-- Rogue: poisonok is (a nev alapjan keressuk a taskaban; kattintasra a fegyverre teszi)
if select(2, UnitClass("player")) == "ROGUE" then
    for _, s in ipairs(SLOTS) do
        if s.hand then
            for _, p in ipairs({ L["Instant Poison"], L["Deadly Poison"], L["Crippling Poison"],
                L["Mind-numbing Poison"], L["Wound Poison"] }) do s.names[#s.names + 1] = p end
            s.label = s.hand == 16 and L["Main hand poison / enchant"] or L["Off-hand poison / enchant"]
        end
    end
end
-- Ezekbol a tipusokbol egyszerre csak egy lehet (Options > Buffs > Add buff); a tobbi
-- ("Other item") barmennyi: QuestFocusDB.customBuffs = { { key = "i_<itemId>", itemId } }
local MAX_CUSTOM = 8

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
        -- fegyver imbue spellel: a main hand enchant idejet nezi (GetWeaponEnchantInfo)
        { key = "c_imbue", label = L["Weapon imbue"], warn = 1, hand = 16,
          spells = { "Windfury Weapon", "Flametongue Weapon", "Frostbrand Weapon", "Rockbiter Weapon" } },
        { key = "c_shield", label = L["Shield"], warn = 1, spells = { "Lightning Shield", "Water Shield", "Earth Shield" } },
    },
}
local _, PLAYER_CLASS = UnitClass("player")
-- Kovetes (tracking): mindenkinek, ha ismer ilyet. Classicban egyszerre csak EGY lehet aktiv
-- (pl. Find Minerals vagy Find Herbs); a nyillal / a "Switch tracking" billentyuvel valthato.
local TRACKING = { key = "c_track", label = L["Tracking"], permanent = true, tracking = true,
    spells = { "Find Minerals", "Find Herbs", "Find Treasure", "Find Fish",
               "Track Beasts", "Track Humanoids", "Track Undead", "Track Demons", "Track Elementals",
               "Track Giants", "Track Dragonkin", "Track Hidden", "Sense Undead", "Sense Demons" } }
CLASS_BUFFS.ALL = { TRACKING }

-- Minden class buff neve (barmelyik classe): ilyen nem lehet egy item "megtanult" buffja
local CLASS_SPELL_SET = {}
for _, list in pairs(CLASS_BUFFS) do
    for _, s in ipairs(list) do for _, n in ipairs(s.spells) do CLASS_SPELL_SET[n] = true end end
end
for _, list in ipairs({ CLASS_BUFFS[PLAYER_CLASS] or {}, CLASS_BUFFS.ALL }) do
    for _, s in ipairs(list) do
        s.names = {}
        s.isClass = true
        SLOTS[#SLOTS + 1] = s
    end
end

local function DB()
    QuestFocusDB.buffItems = QuestFocusDB.buffItems or {}
    QuestFocusDB.buffLearn = QuestFocusDB.buffLearn or {}
    return QuestFocusDB
end

-- Ki van-e kapcsolva a tipus: noBuff_<key> = true (ki) / false (kifejezetten be) / nil (alap:
-- slot.defaultOff, pl. hunter fegyver enchant). slot lehet a slot vagy a kulcsa.
NS.BuffSlotOff = function(slot)
    if type(slot) == "string" then
        for _, s in ipairs(SLOTS) do if s.key == slot then slot = s break end end
        if type(slot) == "string" then return DB()["noBuff_" .. slot] == true end
    end
    local v = DB()["noBuff_" .. slot.key]
    if v == nil then return slot.defaultOff and true or false end
    return v and true or false
end

-- Figyelmeztetesi kuszob percben, buffonkent (alap: slot.warn). 0 = csak ha hianyzik.
local function Minutes(slot)
    local t = QuestFocusDB.buffWarn
    return (t and tonumber(t[slot.key])) or slot.warn or 10
end

-- Sajat item tipusok ("Other item"): barmilyen item, ami buffot ad (elixir, scroll...).
-- A buffot az elso hasznalatkor tanulja meg (vagy az item spell neve alapjan talalja).
local function CustomSlotIndex(key)
    for i, s in ipairs(SLOTS) do if s.key == key then return i end end
end
-- Sajat buff (spell ID / nev alapjan): a buffot nevrol / ID-rol ismerjuk fel; ha a spellt
-- te tudod castolni, az emlekezteto gombja fel is teszi, kulonben csak szol, hogy hianyzik.
local function EnsureCustomBuffs()
    local list = QuestFocusDB.customBuffs or {}
    for _, e in ipairs(list) do
        local i = CustomSlotIndex(e.key)
        if e.itemId then
            local name = GetItemInfo(e.itemId)
            if not i then
                SLOTS[#SLOTS + 1] = { key = e.key, itemId = e.itemId, custom = true, names = {}, warn = 0,
                    label = name or ("item " .. e.itemId) }
            elseif name then
                SLOTS[i].label = name
            end
            DB().buffItems[e.key] = e.itemId
        elseif not i then
            SLOTS[#SLOTS + 1] = { key = e.key, custom = true, customSpell = true, names = {}, warn = 0,
                buffSpellId = e.spellId, buffName = e.name, label = e.name or ("spell " .. tostring(e.spellId)) }
        end
    end
end
NS.EnsureCustomBuffs = EnsureCustomBuffs
local function AddCustomSpellBuff(spellId, name, minutes)
    QuestFocusDB.customBuffs = QuestFocusDB.customBuffs or {}
    local key = "s_" .. tostring(spellId or name)
    if CustomSlotIndex(key) or #QuestFocusDB.customBuffs >= MAX_CUSTOM then return false end
    table.insert(QuestFocusDB.customBuffs, { key = key, spellId = spellId, name = name })
    QuestFocusDB.buffWarn = QuestFocusDB.buffWarn or {}
    QuestFocusDB.buffWarn[key] = minutes or 0
    EnsureCustomBuffs()
    return true
end
local function AddCustomBuff(itemId, minutes)
    QuestFocusDB.customBuffs = QuestFocusDB.customBuffs or {}
    local key = "i_" .. itemId
    if CustomSlotIndex(key) then return false end
    if #QuestFocusDB.customBuffs >= MAX_CUSTOM then return false end
    table.insert(QuestFocusDB.customBuffs, { key = key, itemId = itemId })
    QuestFocusDB.buffWarn = QuestFocusDB.buffWarn or {}
    QuestFocusDB.buffWarn[key] = minutes or 0
    EnsureCustomBuffs()
    return true
end
local function RemoveCustomBuff(key)
    for i, e in ipairs(QuestFocusDB.customBuffs or {}) do
        if e.key == key then table.remove(QuestFocusDB.customBuffs, i) break end
    end
    local i = CustomSlotIndex(key)
    if i then table.remove(SLOTS, i) end
    DB().buffItems[key] = nil
end

---------------------------------------------------------------------------
-- Itemek, aurak
---------------------------------------------------------------------------
local GetSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local GetItemID = C_Container and C_Container.GetContainerItemID or GetContainerItemID

-- Fegyver tipusa a kezben: "edged" (kard, balta, tor, polearm), "blunt" (buzogany, bot),
-- "fist", "ranged" / nil (nincs fegyver). A ko / olaj / poison ehhez kell, hogy illjen.
local EDGED = { [0] = true, [1] = true, [6] = true, [7] = true, [8] = true, [15] = true }
local BLUNT = { [4] = true, [5] = true, [10] = true }
local function WeaponKind(hand)
    local id = GetInventoryItemID("player", hand)
    if not id then return end
    local _, _, _, _, _, classID, subID = GetItemInfoInstant(id)
    if classID ~= 2 then return end
    if EDGED[subID] then return "edged" end
    if BLUNT[subID] then return "blunt" end
    if subID == 13 then return "fist" end
    return "ranged"
end
NS.WeaponKind = WeaponKind

-- Van-e kozelharci fegyver ebben a kezben (ketkezesnel az off hand ures, ranged-nel nincs
-- ideiglenes enchant): ha nincs, a sor nem latszik se az Optionsben, se az emlekeztetoben.
local function HandHasWeapon(hand)
    local k = WeaponKind(hand)
    return k ~= nil and k ~= "ranged"
end
NS.HandHasWeapon = HandHasWeapon

-- Rafer-e ez az item a fegyverre (nev alapjan): Sharpening Stone = eles, Weightstone = tompa,
-- olaj / poison / ismeretlen = barmelyik kozelharci fegyver
local function ItemFitsWeapon(itemId, hand)
    local kind = WeaponKind(hand)
    if not kind or kind == "ranged" then return false end
    local name = GetItemInfo(itemId)
    if not name then return true end -- meg nincs betoltve: ne dobjuk el
    if name:find(L["Sharpening Stone"], 1, true) then return kind == "edged" or kind == "fist" end
    if name:find(L["Weightstone"], 1, true) then return kind == "blunt" or kind == "fist" end
    return true
end
NS.ItemFitsWeapon = ItemFitsWeapon

-- Beallitott item, vagy nev alapjan az elso talalat a taskakban. Fegyvernel csak olyan,
-- ami a mostani fegyverre rafer (fegyvercserenel igy magatol valt kore / olajra).
-- Optimalizalas: a talalat cache-elve, amig nem valtozik a taska / felszereles (itemGen),
-- vagy a beallitott item; a taska bejarasa slotonkent masodpercenkent draga volt.
local itemGen, findCache = 0, {}
-- volt-e meg nem betoltott (nev nelkuli) item a keresesben: csak ekkor erdekel a GET_ITEM_INFO_RECEIVED
local awaitingInfo = false
NS.BumpBuffItems = function() itemGen = itemGen + 1 end
local FindItemRaw
local function FindItem(slot)
    local set = DB().buffItems[slot.key]
    local c = findCache[slot.key]
    if c and c.gen == itemGen and c.set == set then return c.id end
    local id = FindItemRaw(slot)
    findCache[slot.key] = { gen = itemGen, set = set, id = id }
    return id
end
FindItemRaw = function(slot)
    local id = DB().buffItems[slot.key]
    if id and (not slot.hand or ItemFitsWeapon(id, slot.hand)) then return id end
    if #slot.names == 0 then return slot.hand and nil or id end
    for bag = 0, 4 do
        for s = 1, (GetSlots(bag) or 0) do
            local iid = GetItemID(bag, s)
            local name = iid and GetItemInfo(iid)
            if iid and not name then awaitingInfo = true end -- meg nincs betoltve: GET_ITEM_INFO_RECEIVED-re ujra
            if name and (not slot.hand or ItemFitsWeapon(iid, slot.hand)) then
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
    if slot.tracking then
        -- nem buff, hanem a minimap kovetes: lent (NS.TrackingRemaining)
        return NS.TrackingRemaining and NS.TrackingRemaining(slot)
    end
    if slot.customSpell then
        local a = (slot.buffSpellId and auraById[slot.buffSpellId]) or (slot.buffName and auras[slot.buffName])
        if not a then return end
        if a.expires == 0 then return math.huge end
        return a.expires - GetTime()
    end
    if slot.hand then
        -- fegyver enchant / poison / shaman imbue: a fegyveren levo ideiglenes enchant
        -- csak kozelharci fegyverre van ertelme (pajzs / off-hand item / ures / ranged: nem szolunk)
        local wk = WeaponKind(slot.hand)
        if not wk or wk == "ranged" then return math.huge end
        local ok, hasMain, mainMs, _, _, hasOff, offMs = pcall(GetWeaponEnchantInfo)
        if not ok then return end
        local has, ms = hasMain, mainMs
        if slot.hand == 17 then has, ms = hasOff, offMs end
        if has then
            local okN, sec = pcall(function() return (ms or 0) / 1000 end)
            if okN then return sec end
        end
        return
    end
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

-- Aktiv kovetes (tracking) neve vagy ikonja
local function ActiveTracking()
    local tex
    if GetTrackingTexture then
        local ok, t = pcall(GetTrackingTexture)
        if ok then tex = t end
    end
    if not tex and C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
        local ok, n = pcall(C_Minimap.GetNumTrackingTypes)
        for i = 1, (ok and n or 0) do
            local ok2, a, b, c = pcall(C_Minimap.GetTrackingInfo, i)
            if ok2 then
                if type(a) == "table" then
                    if a.active then return a.name, a.texture end
                elseif c then
                    return a, b -- name, texture, active
                end
            end
        end
    end
    return nil, tex
end

-- Aktiv-e valamelyik tracking spellunk (nev szerint). nil = nincs (szolunk), math.huge = van.
-- Elsonek a minimap tracking listat nezzuk (aktiv jelzo): a GetTrackingTexture ezen a
-- kliensen akkor is adhat egy alap ikont, ha semmi sincs bekapcsolva.
NS.TrackingRemaining = function(slot)
    local want = {}
    for _, s in ipairs(slot.spells) do want[s] = true end
    local function seen(s)
        QuestFocusDB.classSeen = QuestFocusDB.classSeen or {}
        QuestFocusDB.classSeen[slot.key] = s
        return math.huge
    end
    if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
        local ok, n = pcall(C_Minimap.GetNumTrackingTypes)
        if ok and n and n > 0 then
            for i = 1, n do
                local ok2, a, b, c = pcall(C_Minimap.GetTrackingInfo, i)
                if ok2 then
                    local name, active
                    if type(a) == "table" then name, active = a.name, a.active else name, active = a, c end
                    if active and name and want[name] then return seen(name) end
                end
            end
            return nil -- a lista mukodik, es egyik tracking spellunk sem aktiv
        end
    end
    -- regi API: az aktiv kovetes ikonja; csak akkor "van", ha egy ismert spellunk ikonja
    if GetTrackingTexture then
        local ok, tex = pcall(GetTrackingTexture)
        if ok and tex then
            for _, s in ipairs(slot.spells) do
                if SpellKnown(s) and SpellIconOf(s) == tex then return seen(s) end
            end
        end
    end
    -- buffkent is lehet (classic hunter track aura)
    local auras = HelpfulAuras()
    for _, s in ipairs(slot.spells) do if auras[s] then return seen(s) end end
    return nil
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
    if NS.BuffSlotOff(slot) then return end
    if slot.customSpell then
        -- csak ha te tudod castolni (kulonben az emlekezteto csak szol, gomb nelkul)
        local known = (slot.buffSpellId and IsPlayerSpell and IsPlayerSpell(slot.buffSpellId))
            or (slot.buffName and SpellKnown(slot.buffName))
        if known and slot.buffName then return { kind = "spell", name = slot.buffName } end
        return
    end
    if slot.isClass then
        local name = SlotSpell(slot)
        if name then return { kind = "spell", name = name } end
        return
    end
    local id = FindItem(slot)
    if id and GetItemCount(id) > 0 then return { kind = "item", id = id } end
    -- a beallitott XP kaja elfogyott: masik XP kaja a taskabol, ha van
    if slot.key == "food" and NS.FoodCandidates then
        local xp = NS.FoodCandidates()
        if xp[1] then return { kind = "item", id = xp[1] } end
    end
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
        b:SetAttribute("macrotext", slot.hand
            and ("/use item:%d\n/use %d"):format(a.id, slot.hand) or ("/use item:%d"):format(a.id))
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
            NS.BuffSlotOff(slot) and " |cff808080(off)|r" or "",
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
-- Segedek az emlekezteto kisablakhoz (a regi "buff gombsor a panel alatt" kikerult)
---------------------------------------------------------------------------
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

-- Modul ki/be (Options > Buffs > Module on): kikapcsolva betoltve marad, de semmit nem csinal
local function On() return not NS.ModuleOn or NS.ModuleOn("QuestFocus_Buffs") end

-- Valtozas utan (item / lista / modul): az emlekezteto azonnal ujraepul (lent allitjuk be)
local refreshAlert
local function Rebuild()
    if QuestFocusDB then EnsureCustomBuffs() end -- item nevek, ha kozben betoltodtek
    if refreshAlert then refreshAlert() end
end
NS.RebuildBuffBar = Rebuild

-- Idok + figyelmeztetes (harcban is mehet, nem secure)
local warned = {}

-- Egyszer szolunk (chat), amikor egy buff a kuszob ala esik. 0 perc: soha (csak a hiany szamit).
local function CheckWarnings(auras)
    if QuestFocusDB.noBuffWarn or not On() then return end
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
                Print(msg) -- csak chat; a kepernyo kozepen nem villogunk (ott az emlekezteto sav)
            end
        elseif left and left >= limit then
            warned[key] = nil
        end
    end
end

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
-- sorok: a beepitett tipusok + MAX_CUSTOM sajat item (a slot futas kozben valtozik: b.slot)
for i = 1, #SLOTS + MAX_CUSTOM do
    local slot = SLOTS[i]
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
    -- Oldalra nyil: alternativak (XP kajak, aurak/blessingek, kovek/olajok) - mint az
    -- inventory slot flyout-ja. Csak akkor latszik, ha tobb lehetoseg van.
    b.arrow = CreateFrame("Button", nil, alert)
    b.arrow:SetSize(12, 22)
    b.arrow:SetPoint("LEFT", b, "RIGHT", 2, 0)
    b.arrow:SetNormalTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    b.arrow:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b.arrow:Hide()
    b.arrow:SetScript("OnClick", function(self)
        if NS.ToggleBuffFlyout then NS.ToggleBuffFlyout(b, self) end
    end)
    b.arrow:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Choose another one"], 1, 1, 1)
        GameTooltip:Show()
    end)
    b.arrow:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- hany darab van meg a taskaban (item alapu buffoknal)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", 1, -1)
    b.text = alert:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", b.arrow, "RIGHT", 4, 0)
    b.text:SetPoint("RIGHT", alert, "RIGHT", -28, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    -- a sor vegen: ezt a tipust ne figyelje tobbet (Options > Buffs: visszapipalhato)
    b.off = CreateFrame("Button", nil, alert)
    b.off:SetSize(14, 14)
    b.off:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    b.off:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
    b.off:Hide()
    b.off:SetScript("OnClick", function()
        local s = b.slot
        if not s then return end
        if s.custom then
            RemoveCustomBuff(s.key) -- sajat item / buff: torlodik a listabol (Add buff-fal visszaveheto)
            NS.Loud(Print, L["%s: removed from the watched buffs."], s.label)
        else
            DB()["noBuff_" .. s.key] = true
            NS.Loud(Print, L["%s: no longer watched. Turn it back on: Options > Buffs."], s.label)
        end
        if NS.RebuildBuffBar then NS.RebuildBuffBar() end
        if NS.RefreshBuffOptions then pcall(NS.RefreshBuffOptions) end
    end)
    b.off:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Don't watch this"], 1, 1, 1)
        GameTooltip:AddLine(L["You can tick it again on the Buffs tab of the options."], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    b.off:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- item / spell huzasa az ikonra: ez lesz a beallitott
    b:SetScript("OnReceiveDrag", function(self)
        local s = self.slot
        if not s or InCombatLockdown() then return end
        local kind, itemId, _, spellID = GetCursorInfo()
        if s.isClass and kind == "spell" then
            local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or (GetSpellInfo and GetSpellInfo(spellID))
            if name then QuestFocusDB.classPref = QuestFocusDB.classPref or {}; QuestFocusDB.classPref[s.key] = name end
        elseif not s.isClass and not s.customSpell and kind == "item" then
            DB().buffItems[s.key] = itemId
            DB()["noBuff_" .. s.key] = false
        else
            return
        end
        ClearCursor()
        if NS.RebuildBuffBar then NS.RebuildBuffBar() end
    end)
    -- info sor (nincs mit hasznalni): kattintasra valasztas (kaja: XP kaja lista, mas: Options > Buffs)
    b:HookScript("PostClick", function(self)
        if self.itemId or self.spellName or InCombatLockdown() then return end
        local s = self.slot
        if not s then return end
        if GetCursorInfo() then
            local h = self:GetScript("OnReceiveDrag")
            if h then h(self) end
            return
        end
        if s.key == "food" and NS.ShowFoodPicker then NS.ShowFoodPicker()
        elseif NS.OpenOptionsTab then NS.OpenOptionsTab(L["Buffs"]) end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local s = self.slot or slot
        if self.info then
            GameTooltip:SetText(s.label, 1, 1, 1)
            GameTooltip:AddLine(self.info, 1, 0.82, 0, true)
            if not s.customSpell then
                GameTooltip:AddLine(L["Click: choose one · or drag an item here"], 0.5, 0.5, 0.5)
            end
        elseif self.spellName then
            GameTooltip:SetText(self.spellName, 1, 1, 1)
            GameTooltip:AddLine(L["Click: cast it on yourself"], 0.5, 0.5, 0.5)
        else
            if self.itemId then GameTooltip:SetItemByID(self.itemId) end
            GameTooltip:AddLine(s.hand == 17 and L["Click: apply to off-hand weapon"]
                or s.hand and L["Click: apply to main hand weapon"] or L["Click: use"], 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:HookScript("PreClick", function(self)
        local s = self.slot or slot
        if self.itemId and not s.hand and not s.isClass then StartLearning(self.itemId) end
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
-- slot kulcs -> true: errol a hianyrol mar villantunk. Csak az elso megjeleneskor villan;
-- ha ignoralod (X / harc) es ujra feljon ugyanazzal, mar nem. Ha megjavitod a buffot, torlodik.
local flashed = {}
local function UpdateAlert(auras)
    if InCombatLockdown() then return end
    if QuestFocusDB.noBuffAlert or not On() or hiddenUntilCombat or UnitIsDeadOrGhost("player") then
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
        if left and (left == math.huge or left >= limit) and not short then
            dismissed[slot.key] = nil
            flashed[slot.key] = nil -- rendben van: legkozelebb ujra villanhat
        end
        if a and not dismissed[slot.key]
            and (not left or (left ~= math.huge and left < limit) or short) then
            need[#need + 1] = { slot = slot, action = a, left = left, stacks = stacks }
            key = key .. slot.key .. tostring(a.id or a.name) .. ";"
        elseif not a and slot.key == "food" and not left and not NS.BuffSlotOff("food") then
            -- nincs XP kaja a taskaban: csak szolunk, gomb nelkul
            need[#need + 1] = { slot = slot, left = nil, info = L["no XP food in your bags - buy some at a vendor, or cook one if you can"] }
            key = key .. "food:none;"
        elseif not a and slot.customSpell and not left and not dismissed[slot.key] then
            -- sajat buff, amit nem te teszel fel (pl. mas classe): csak szolunk
            need[#need + 1] = { slot = slot, left = nil, info = L["ask someone for it"] }
            key = key .. slot.key .. ":none;"
        elseif not a and not left and not slot.isClass and not slot.customSpell and slot.key ~= "food"
            and not NS.BuffSlotOff(slot) and not dismissed[slot.key] then
            -- bepipalt itemes tipus (alvozsak, fegyver enchant, sajat item), de nincs ilyen a taskaban
            local info = L["none in your bags - click to choose, or drag an item here"]
            if slot.hand then
                local wk = WeaponKind(slot.hand)
                info = (wk == "blunt" and L["no weightstone / oil for this weapon in your bags - click to choose, or drag one here"])
                    or (wk == "edged" and L["no sharpening stone / oil for this weapon in your bags - click to choose, or drag one here"])
                    or L["nothing for this weapon in your bags - click to choose, or drag one here"]
            end
            need[#need + 1] = { slot = slot, left = nil, info = info }
            key = key .. slot.key .. ":none;"
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
        for _, b in ipairs(alertRows) do b:Hide(); b.text:Hide(); b.arrow:Hide(); b.off:Hide() end
        if NS.HideBuffFlyout then NS.HideBuffFlyout() end
        for i, n in ipairs(need) do
            local b = alertRows[i]
            if n.action then
                b.slot, b.itemId, b.spellName = n.slot, n.action.id, n.action.name
                b.icon:SetTexture(ActionIcon(n.action))
                SetupSecure(b, n.slot, n.action)
                local alts = NS.BuffAlternatives and NS.BuffAlternatives(n.slot)
                b.alts = alts
                -- fegyver enchant / XP kaja: a nyil mindig ott van (valasztas); masnal csak ha tobb lehetoseg
                b.arrow:SetShown(alts ~= nil and (#alts >= 2 or n.slot.hand ~= nil or n.slot.key == "food"))
            else
                -- csak informacio (pl. nincs XP kaja): nincs kattinthato ikon
                b.slot, b.itemId, b.spellName, b.alts = n.slot, nil, nil, nil
                b:SetAttribute("type", nil)
                local s = n.slot
                -- fegyver enchant / XP kaja: valaszto nyil itt is (ha nincs mibol, megmondja)
                if s.hand or s.key == "food" then
                    b.alts = NS.BuffAlternatives and NS.BuffAlternatives(s) or {}
                    b.arrow:Show()
                end
                b.icon:SetTexture((s.customSpell and s.buffName and SpellIconOf(s.buffName))
                    or (s.custom and s.itemId and GetItemIcon(s.itemId))
                    or (s.hand and "Interface\\Icons\\INV_Stone_SharpeningStone_01")
                    or (s.key == "rest" and "Interface\\Icons\\INV_Misc_Bag_08")
                    or (s.key == "food" and "Interface\\Icons\\INV_Misc_Food_15")
                    or "Interface\\Icons\\INV_Misc_QuestionMark")
            end
            b.info = n.info
            b.icon:SetDesaturated(n.info ~= nil)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", alert, "TOPLEFT", 12, -22 - (i - 1) * ROW_H)
            b:Show()
            b.text:Show()
            b.off:ClearAllPoints()
            b.off:SetPoint("TOPRIGHT", alert, "TOPRIGHT", -8, -26 - (i - 1) * ROW_H)
            b.off:Show()
        end
        alert:SetHeight(26 + #need * ROW_H)
        PlaceAlert()
        alert.onPanel = NS.panel:IsShown()
        if not alert:IsShown() then
            alert:Show()
            -- Hang helyett egy rovid arany felvillanas a saven (csak egy textura animal,
            -- maga az ablak nem, mert secure gombok vannak benne)
            if not alert.flash then
                local f = alert:CreateTexture(nil, "OVERLAY")
                f:SetPoint("TOPLEFT", 4, -4)
                f:SetPoint("BOTTOMRIGHT", -4, 4)
                f:SetColorTexture(1, 0.82, 0.3, 1)
                f:SetBlendMode("ADD")
                f:SetAlpha(0)
                local ag = f:CreateAnimationGroup()
                local a1 = ag:CreateAnimation("Alpha")
                a1:SetFromAlpha(0); a1:SetToAlpha(0.35); a1:SetDuration(0.15); a1:SetOrder(1)
                local a2 = ag:CreateAnimation("Alpha")
                a2:SetFromAlpha(0.35); a2:SetToAlpha(0); a2:SetDuration(0.7); a2:SetOrder(2)
                ag:SetScript("OnFinished", function() f:SetAlpha(0) end)
                alert.flash, alert.flashAnim = f, ag
            end
            local fresh = false
            for _, n in ipairs(need) do
                if not flashed[n.slot.key] then flashed[n.slot.key] = true; fresh = true end
            end
            if fresh then
                alert.flashAnim:Stop()
                alert.flashAnim:Play()
            end
        end
    end
    for i, n in ipairs(need) do
        local cnt = n.action and n.action.kind == "item" and GetItemCount(n.action.id) or nil
        alertRows[i].count:SetText(cnt and cnt > 0 and cnt or "")
        if n.info then
            alertRows[i].text:SetText(("|cffffd100%s|r  |cffff4444%s|r  |cff999999%s|r"):format(
                n.slot.label, L["missing"], n.info))
        else
            local name = ActionName(n.action, n.slot)
            local state = (n.left and ((L["%s left"]):format(FmtLeft(n.left, n.slot))) or ("|cffff4444" .. L["missing"] .. "|r"))
                .. StackText(n.slot, n.stacks)
            -- itemnel: mennyi van meg (1 = az utolso, sarga)
            local have = cnt and ((cnt <= 1 and " |cffffd100x%d|r" or " |cffd0d0d0x%d|r"):format(cnt)) or ""
            alertRows[i].text:SetText(("|cffffd100%s|r  %s  |cff808080%s|r%s"):format(n.slot.label, state, name, have))
        end
    end
end
NS.BuffAlertFrame = alert
refreshAlert = function()
    lastAlertKey = nil
    if not InCombatLockdown() then UpdateAlert(HelpfulAuras()) end
end

local alertElapsed = 0
local alertTicker = CreateFrame("Frame")
alertTicker:SetScript("OnUpdate", function(_, dt)
    alertElapsed = alertElapsed + dt
    if alertElapsed < 1.5 then return end
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
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
local pending = false

-- Fegyvercsere (harcon kivul): a FindItem magatol a rafero kore / olajra / poisonra valt.
-- Ha nincs ilyen a taskaban, a buff emlekezteto soraban latszik (kattintva valaszthatsz).
local weaponCheckPending = false
local function CheckWeapons()
    if InCombatLockdown() then weaponCheckPending = true return end
    weaponCheckPending = false
    -- az uj fegyvernel ujra szolhat (ha a regi miatt X-szel elrejtetted)
    for _, s in ipairs(SLOTS) do if s.hand then dismissed[s.key] = nil end end
    Rebuild()
    -- az Options lista is (off-hand sor eltunik / megjelenik)
    if NS.RefreshBuffList then NS.RefreshBuffList() end
end
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
        Rebuild()
        if weaponCheckPending then C_Timer.After(1, CheckWeapons) end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if unit == 16 or unit == 17 then
            itemGen = itemGen + 1
            Soon()
            C_Timer.After(1, CheckWeapons)
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        itemGen = itemGen + 1
        if NS.ClearFoodCache then NS.ClearFoodCache() end
        Soon()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- mas addonok (pl. AllTheThings) miatt folyamatosan johet: csak ha mi varunk itemre
        if not awaitingInfo then return end
        awaitingInfo = false
        itemGen = itemGen + 1
        Soon()
    elseif event == "PLAYER_LOGIN" then
        NS.EnsureCustomBuffs()
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

local foodCache -- { xp, other }: taska valtozasig (BAG_UPDATE_DELAYED torli)
local function FoodCandidates()
    if foodCache then return foodCache[1], foodCache[2] end
    local xp, other, seen = {}, {}, {}
    for bag = 0, 4 do
        for s = 1, (GetSlots(bag) or 0) do
            local id = GetItemID(bag, s)
            if id and not seen[id] then
                seen[id] = true
                local _, _, _, _, _, classID, subID = GetItemInfoInstant(id)
                -- csak etel / ital: Consumable > Food & Drink, vagy aminek a leirasa evest ir
                -- (a sator, alvozsak, tekercs is "experience"-t ir, de az nem kaja)
                if classID == 0 then
                    local tip = TooltipText(bag, s):lower()
                    local isFood = subID == 5 or tip:find("must remain seated while eating", 1, true)
                        or tip:find("well fed", 1, true)
                    local isXP = tip:find("experience", 1, true) or tip:find("%f[%w]xp%f[%W]")
                    if isFood and isXP then
                        xp[#xp + 1] = id
                    elseif isFood then
                        other[#other + 1] = id
                    end
                end
            end
        end
    end
    foodCache = { xp, other }
    return xp, other
end
NS.FoodCandidates = FoodCandidates
NS.ClearFoodCache = function() foodCache = nil end

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
        DB().noBuff_food = false
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
    -- csak az XP kajak (amiknek a leirasaban experience / XP van); sima kaja nem kell ide.
    -- Ha a felismeres nem talal valamit, az item az ikonra huzva akkor is beallithato.
    for _, id in ipairs(xp) do add(id, true) end
    picker.empty:SetText(L["No XP food in your bags (food whose description mentions experience). You can still drag one onto the XP food icon in Options > Buffs."])
    picker.empty:SetWidth(250)
    picker.empty:SetJustifyH("LEFT")
    picker.empty:SetShown(n == 0)
    if n == 0 then
        picker.empty:ClearAllPoints()
        picker.empty:SetPoint("TOPLEFT", 14, y)
        y = y - 40
    end
    picker:SetHeight(-y + 14)
    picker:Show()
end
NS.ShowFoodPicker = ShowFoodPicker

---------------------------------------------------------------------------
-- Kovetes valto billentyu: /castsequence Find Minerals, Find Herbs - minden nyomasra a masikra
-- valt (harcban is mukodik, mert a sorrendet a jatek viszi, nem az addon)
---------------------------------------------------------------------------
BINDING_HEADER_QUESTFOCUSBUFFS = "Adventurer's Kit - Buffs"
_G["BINDING_NAME_CLICK QuestFocusTrackToggle:LeftButton"] = L["Switch tracking (Find Minerals / Find Herbs)"]
local trackBtn = CreateFrame("Button", "QuestFocusTrackToggle", UIParent, "SecureActionButtonTemplate")
trackBtn:RegisterForClicks("AnyUp", "AnyDown")
local function SetupTrackToggle()
    if InCombatLockdown() then return end
    local known = {}
    for _, s in ipairs({ "Find Minerals", "Find Herbs" }) do
        if SpellKnown(s) then known[#known + 1] = s end
    end
    if #known == 0 then trackBtn:SetAttribute("type", nil) return end
    trackBtn:SetAttribute("type", "macro")
    trackBtn:SetAttribute("macrotext", #known == 2 and ("/castsequence " .. known[1] .. ", " .. known[2])
        or ("/cast " .. known[1]))
end
local trackEv = CreateFrame("Frame")
trackEv:RegisterEvent("PLAYER_LOGIN")
trackEv:RegisterEvent("SPELLS_CHANGED")
trackEv:RegisterEvent("PLAYER_REGEN_ENABLED")
trackEv:SetScript("OnEvent", function() C_Timer.After(2, SetupTrackToggle) end)

---------------------------------------------------------------------------
-- Flyout (oldalra nyilo ikonsor) a buff emlekezteto soraihoz: alternativak
---------------------------------------------------------------------------
-- Egy slot lehetosegei: { kind = "item", id } / { kind = "spell", name }
NS.BuffAlternatives = function(slot)
    local out, seen = {}, {}
    if slot.isClass then
        for _, c in ipairs(slot.cast or slot.spells) do
            if SpellKnown(c) and not seen[c] then seen[c] = true; out[#out + 1] = { kind = "spell", name = c } end
        end
    elseif slot.key == "food" then
        -- csak a valodi XP kajak (sima etel nem kell ide)
        local xp = FoodCandidates()
        for _, id in ipairs(xp) do out[#out + 1] = { kind = "item", id = id } end
    elseif #slot.names > 0 then
        for bag = 0, 4 do
            for s = 1, (GetSlots(bag) or 0) do
                local iid = GetItemID(bag, s)
                local name = iid and not seen[iid] and GetItemInfo(iid)
                if name and (not slot.hand or ItemFitsWeapon(iid, slot.hand)) then
                    for _, pat in ipairs(slot.names) do
                        if name:find(pat, 1, true) then seen[iid] = true; out[#out + 1] = { kind = "item", id = iid } break end
                    end
                end
            end
        end
    end
    return out
end

local flyout = CreateFrame("Frame", "QuestFocusBuffFlyout", alert, BackdropTemplateMixin and "BackdropTemplate" or nil)
flyout:SetFrameStrata("DIALOG")
flyout:SetHeight(32)
flyout:Hide()
if flyout.SetBackdrop then
    flyout:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    flyout:SetBackdropColor(0, 0, 0, 0.9)
    flyout:SetBackdropBorderColor(0.95, 0.78, 0.40, 0.9)
end
local flyBtns = {}
local function FlyBtn(i)
    local f = flyBtns[i]
    if f then return f end
    f = CreateFrame("Button", "QuestFocusBuffFlyoutBtn" .. i, flyout, "SecureActionButtonTemplate")
    f:SetSize(24, 24)
    f:RegisterForClicks("AnyUp", "AnyDown")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.25)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if self.act.kind == "spell" then GameTooltip:SetText(self.act.name, 1, 1, 1)
        else GameTooltip:SetItemByID(self.act.id) end
        GameTooltip:AddLine(L["Click: use it and make it the default"], 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Kattintas elott: ez lesz az alapertelmezett; utana a flyout bezarul
    f:HookScript("PreClick", function(self)
        local s, a = self.slot, self.act
        if s.isClass then
            QuestFocusDB.classPref = QuestFocusDB.classPref or {}
            QuestFocusDB.classPref[s.key] = a.name
        else
            DB().buffItems[s.key] = a.id
            DB()["noBuff_" .. s.key] = false
            if s.key == "food" then StartLearning(a.id) end
        end
    end)
    f:HookScript("PostClick", function()
        if not InCombatLockdown() then flyout:Hide() end
        lastAlertKey = nil -- a sor az uj valasztassal epul ujra
    end)
    flyBtns[i] = f
    return f
end

NS.HideBuffFlyout = function() if not InCombatLockdown() then flyout:Hide() end end

NS.ToggleBuffFlyout = function(row, arrow)
    if InCombatLockdown() then return end
    if flyout:IsShown() and flyout.row == row then flyout:Hide() return end
    local alts = row.alts or {}
    for _, f in ipairs(flyBtns) do f:Hide() end
    local n = 0
    for _, a in ipairs(alts) do
        if n >= 10 then break end
        n = n + 1
        local f = FlyBtn(n)
        f.slot, f.act = row.slot, a
        f.icon:SetTexture(ActionIcon(a))
        SetupSecure(f, row.slot, a)
        f:ClearAllPoints()
        f:SetPoint("LEFT", flyout, "LEFT", 4 + (n - 1) * 26, 0)
        f:Show()
    end
    if n == 0 then
        -- nincs mibol valasztani (pl. nincs a fegyverre illo ko / olaj a taskaban)
        local s = row.slot
        NS.Loud(Print, s and s.hand and L["Nothing for this weapon in your bags (%s). Buy one, or drag an item onto the icon."]
            or L["Nothing to choose from in your bags (%s)."], s and s.label or "?")
        return
    end
    flyout.row = row
    flyout:SetWidth(8 + n * 26)
    flyout:ClearAllPoints()
    flyout:SetPoint("LEFT", arrow, "RIGHT", 2, 0)
    flyout:Show()
end

-- Elso bejelentkezeskor (karakterenkent egyszer): ha egy bepipalt itemes tipushoz (XP kaja,
-- alvozsak, fegyver enchant) nem talalunk semmit a taskaban, megkerdezzuk, beallitja-e.
-- Amit talalunk (XP kaja a leirasbol, ko / olaj / poison nev alapjan, class spell), az
-- automatikus, azzal nem zavarunk.
local function CharKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?") end
local function MissingSetup()
    local out = {}
    for _, s in ipairs(SLOTS) do
        if not s.isClass and not s.custom and not NS.BuffSlotOff(s) and not Action(s) then
            -- fegyver enchant: csak ha abban a kezben kozelharci fegyver van
            if not s.hand or HandHasWeapon(s.hand) then out[#out + 1] = s.label end
        end
    end
    return out
end
StaticPopupDialogs["QUESTFOCUS_BUFFSETUP"] = {
    text = "",
    button1 = L["Set up"],
    button2 = L["Later"],
    button3 = L["Don't ask again"],
    OnAccept = function() if NS.OpenOptionsTab then NS.OpenOptionsTab(L["Buffs"]) end end,
    OnAlt = function()
        QuestFocusDB.buffSetupDone = QuestFocusDB.buffSetupDone or {}
        QuestFocusDB.buffSetupDone[CharKey()] = true
    end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}
local function MaybePromptFood()
    if InCombatLockdown() or not On() or QuestFocusDB.noFoodPrompt then return end
    local done = QuestFocusDB.buffSetupDone and QuestFocusDB.buffSetupDone[CharKey()]
    if done then return end
    local missing = MissingSetup()
    if #missing == 0 then
        -- minden megvan (automatikusan): nem kerdezunk tobbet ezen a karakteren
        QuestFocusDB.buffSetupDone = QuestFocusDB.buffSetupDone or {}
        QuestFocusDB.buffSetupDone[CharKey()] = true
        return
    end
    StaticPopupDialogs.QUESTFOCUS_BUFFSETUP.text =
        (L["Adventurer's Kit - buff reminder: nothing found in your bags for: %s.\nChoose the items now? (Options > Buffs: click the icon, or drag an item onto it)"])
        :format(table.concat(missing, ", "))
    StaticPopup_Show("QUESTFOCUS_BUFFSETUP")
end
NS.MaybePromptFood = MaybePromptFood

---------------------------------------------------------------------------
-- Beallitasok: "Buffs" ful
---------------------------------------------------------------------------
-- a core adja a fult a modul ki/be kapcsolojaval a tetejen
local page, fl = NS.ModulePage("QuestFocus_Buffs", function(on)
    lastAlertKey = nil
    if not on and not InCombatLockdown() then alert:Hide() end
    Rebuild()
end)

fl:Header(L["Reminder"])
fl:Check(L["Reminder popup out of combat"],
    L["When a watched buff is missing or about to run out, a small popup above the panel shows the item; click its icon to apply it. "]
    .. L["The X hides it until that buff is applied again."],
    function() return not QuestFocusDB.noBuffAlert end,
    function(v) QuestFocusDB.noBuffAlert = not v; wipe(dismissed); lastAlertKey = nil end)
fl:Check(L["Warn before a buff expires"],
    L["One chat message when a buff has less time left than its minutes in the list (needs chat messages on, General tab)."],
    function() return not QuestFocusDB.noBuffWarn end,
    function(v) QuestFocusDB.noBuffWarn = not v end)
fl:Check(L["Ask to set up missing buffs"],
    L["Once per character after login: if nothing is found in your bags for a ticked item buff (XP food, sleeping bag, weapon enchant), "]
    .. L["it asks whether to choose the items. What can be found (XP food, stones / oils / poisons, class spells) is set automatically."],
    function() return not QuestFocusDB.noFoodPrompt end,
    function(v) QuestFocusDB.noFoodPrompt = not v end)

---------------------------------------------------------------------------
-- Figyelt buffok listaja: sorok [ikon] nev / item  [perc] min  [X]
---------------------------------------------------------------------------
fl:Header(L["Watched buffs"])
fl:Text(L["Tick what you want watched. Icon: click to choose (food, stone / oil / poison, spell), or drag an item / spell onto it; "]
    .. L["right click: automatic. Minutes: remind this long before it runs out, 0 = only when it's missing. "]
    .. L["Other buffs (elixirs, scrolls...): Add item below."], 2)

local function Watched(slot)
    if slot.custom then return true end
    return not NS.BuffSlotOff(slot)
end

local function AfterChange()
    wipe(warned)
    wipe(dismissed)
    lastAlertKey = nil
    Rebuild()
end

-- Valaszto (nem secure): az ikonra kattintva a lehetosegek; kattintasra az lesz a beallitott
local chooser = CreateFrame("Frame", nil, NS.opt, BackdropTemplateMixin and "BackdropTemplate" or nil)
chooser:SetFrameStrata("DIALOG")
chooser:EnableMouse(true)
chooser:Hide()
if chooser.SetBackdrop then
    chooser:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    chooser:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
    chooser:SetBackdropBorderColor(0.95, 0.78, 0.40, 1)
end
chooser.btns = {}
local RefreshList -- lent
local function OpenChooser(anchor, slot)
    if chooser:IsShown() and chooser.slot == slot then chooser:Hide() return end
    local alts = NS.BuffAlternatives(slot)
    if #alts == 0 then
        NS.Loud(Print, slot.isClass and L["No known spell for %s."] or L["Nothing for %s in your bags. Drag an item onto the icon."], slot.label)
        return
    end
    chooser.slot = slot
    for _, b in ipairs(chooser.btns) do b:Hide() end
    for i, a in ipairs(alts) do
        local b = chooser.btns[i]
        if not b then
            b = CreateFrame("Button", nil, chooser)
            b:SetSize(26, 26)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetAllPoints()
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                if self.act.kind == "spell" then GameTooltip:SetText(self.act.name, 1, 1, 1)
                else GameTooltip:SetItemByID(self.act.id) end
                GameTooltip:AddLine(L["Click: use this one"], 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnClick", function(self)
                local s, act = chooser.slot, self.act
                if act.kind == "spell" then
                    QuestFocusDB.classPref = QuestFocusDB.classPref or {}
                    QuestFocusDB.classPref[s.key] = act.name
                else
                    DB().buffItems[s.key] = act.id
                end
                chooser:Hide()
                AfterChange()
                RefreshList()
            end)
            chooser.btns[i] = b
        end
        b.act = a
        b.icon:SetTexture(ActionIcon(a))
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 6 + ((i - 1) % 8) * 28, -6 - math.floor((i - 1) / 8) * 28)
        b:Show()
    end
    local cols = math.min(#alts, 8)
    chooser:SetSize(12 + cols * 28, 12 + math.ceil(#alts / 8) * 28)
    chooser:ClearAllPoints()
    chooser:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 4)
    chooser:Show()
end
page:HookScript("OnHide", function() chooser:Hide() end)

local listFrame = CreateFrame("Frame", nil, page)
listFrame:SetSize(430, 10)
fl:Place(listFrame, 4, 10)
local ROW = 38
local rows = {}

local function SlotIconAndName(slot)
    local db = DB()
    if slot.customSpell then
        local tex = slot.buffName and SpellIconOf(slot.buffName)
        if (not tex or tex:find("QuestionMark")) and slot.buffSpellId and GetSpellTexture then
            tex = GetSpellTexture(slot.buffSpellId) or tex
        end
        local castable = Action(slot) ~= nil
        return tex or "Interface\\Icons\\INV_Misc_QuestionMark",
            (slot.buffSpellId and ("spell " .. slot.buffSpellId .. "  ") or "")
            .. "|cff808080(" .. (castable and L["you can cast it"] or L["reminder only"]) .. ")|r"
    end
    if slot.isClass then
        local pref = db.classPref and db.classPref[slot.key]
        local name = SlotSpell(slot)
        return name and SpellIconOf(name) or "Interface\\Icons\\INV_Misc_QuestionMark",
            (name or L["not known"]) .. "  |cff808080(" .. (pref and L["set"] or L["automatic"]) .. ")|r"
    end
    local set = db.buffItems[slot.key]
    local id = FindItem(slot)
    if slot.key == "food" and not id and NS.FoodCandidates then id = NS.FoodCandidates()[1] end
    local name = id and GetItemInfo(id)
    return id and GetItemIcon(id) or "Interface\\PaperDoll\\UI-Backpack-EmptySlot",
        (name or (slot.key == "food" and L["no XP food set"] or "-"))
        .. ((set and not slot.custom) and ("  |cff808080(" .. L["set"] .. ")|r") or "")
end

local function GetRow(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, listFrame)
    r:SetSize(430, ROW - 4)
    -- pipa: kered / nem kered (beepitett tipusok); sajat itemnel helyette X a sor vegen
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(24, 24)
    r.check:SetPoint("LEFT", 0, 0)
    r.check:SetScript("OnClick", function(self)
        local s = r.slot
        if not s or s.custom then return end
        DB()["noBuff_" .. s.key] = not self:GetChecked()
        chooser:Hide()
        AfterChange()
        RefreshList()
    end)
    r.check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Watch this buff"], 1, 1, 1)
        GameTooltip:Show()
    end)
    r.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.icon = CreateFrame("Button", nil, r)
    r.icon:SetSize(30, 30)
    r.icon:SetPoint("LEFT", 28, 0)
    r.icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.icon.bg = r.icon:CreateTexture(nil, "BACKGROUND")
    r.icon.bg:SetAllPoints()
    r.icon.bg:SetColorTexture(0, 0, 0, 0.5)
    r.icon.tex = r.icon:CreateTexture(nil, "ARTWORK")
    r.icon.tex:SetPoint("TOPLEFT", 2, -2)
    r.icon.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    r.icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    r.label = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    r.label:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1)
    r.sub = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    r.sub:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -3)
    r.sub:SetWidth(250)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)
    r.close = CreateFrame("Button", nil, r, "UIPanelCloseButton")
    r.close:SetSize(22, 22)
    r.close:SetPoint("RIGHT", 0, 0)
    r.minLabel = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    r.minLabel:SetPoint("RIGHT", r.close, "LEFT", -8, 0)
    r.minLabel:SetText(L["min"])
    r.min = CreateFrame("EditBox", nil, r, "InputBoxTemplate")
    r.min:SetSize(30, 20)
    r.min:SetAutoFocus(false)
    r.min:SetNumeric(true)
    r.min:SetPoint("RIGHT", r.minLabel, "LEFT", -4, 0)
    r.onlyMissing = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    r.onlyMissing:SetPoint("RIGHT", r.close, "LEFT", -8, 0)
    r.onlyMissing:SetText(L["when missing"])
    r.min:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v and v >= 0 and r.slot then
            QuestFocusDB.buffWarn = QuestFocusDB.buffWarn or {}
            QuestFocusDB.buffWarn[r.slot.key] = v
            AfterChange()
        end
        self:SetText(r.slot and Minutes(r.slot) or "")
        self:ClearFocus()
    end)
    r.min:SetScript("OnEscapePressed", function(self) self:SetText(r.slot and Minutes(r.slot) or ""); self:ClearFocus() end)
    r.min:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Remind this many minutes before it runs out"], 1, 1, 1)
        GameTooltip:AddLine(L["0 = only when the buff is missing. Enter to save."], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    r.min:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.close:SetScript("OnClick", function()
        local s = r.slot
        if not s or not s.custom then return end
        RemoveCustomBuff(s.key)
        chooser:Hide()
        AfterChange()
        RefreshList()
    end)
    r.close:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Remove this item"], 1, 1, 1)
        GameTooltip:Show()
    end)
    r.close:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- ikon: kattintas = valaszto, jobb klikk = automatikus, huzas = item / spell beallitasa
    local function FromCursor()
        local s = r.slot
        local kind, itemId, _, spellID = GetCursorInfo()
        if not s then return end
        if s.isClass then
            if kind ~= "spell" then return end
            local ok, name = pcall(function()
                if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
                return (GetSpellInfo(spellID))
            end)
            ClearCursor()
            if ok and name then
                QuestFocusDB.classPref = QuestFocusDB.classPref or {}
                QuestFocusDB.classPref[s.key] = name
            end
        elseif not s.custom then
            if kind ~= "item" then return end
            ClearCursor()
            DB().buffItems[s.key] = itemId
        else
            return
        end
        AfterChange()
        RefreshList()
        return true
    end
    r.icon:SetScript("OnReceiveDrag", FromCursor)
    r.icon:SetScript("OnClick", function(self, button)
        local s = r.slot
        if not s then return end
        if button == "RightButton" then
            if s.isClass and QuestFocusDB.classPref then QuestFocusDB.classPref[s.key] = nil
            elseif not s.custom then DB().buffItems[s.key] = nil end
            AfterChange()
            RefreshList()
            return
        end
        if GetCursorInfo() and FromCursor() then return end
        if s.custom then return end
        if s.key == "food" then ShowFoodPicker() return end
        OpenChooser(self, s)
    end)
    r.icon:SetScript("OnEnter", function(self)
        local s = r.slot
        if not s then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(s.label, 1, 1, 1)
        if s.stacks then
            GameTooltip:AddLine((L["Needs %d stacks of the buff (spell %d)."]):format(s.stacks, s.spellId), 0.7, 0.7, 0.7)
        end
        if s.custom then
            GameTooltip:AddLine(L["The buff is learned the first time you use the item from the reminder."], 0.7, 0.7, 0.7, true)
        else
            GameTooltip:AddLine(s.key == "food" and L["Click: choose food from your bags"]
                or L["Click: choose · Drag: set · Right click: automatic"], 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    r.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

RefreshList = function()
    for _, r in ipairs(rows) do r:Hide(); r.slot = nil end
    local n = 0
    -- harom szegmens: itemek (alvozsak, XP kaja, fegyver), class buffok, egyeb (Add buff)
    local GROUPS = {
        { title = L["Items: sleeping bag, XP food, weapon enchants"], test = function(s) return not s.custom and not s.isClass end },
        { title = L["Class buffs"], test = function(s) return s.isClass and not s.custom end },
        { title = L["Other (added by you)"], test = function(s) return s.custom end },
    }
    listFrame.headers = listFrame.headers or {}
    local y = 0
    for gi, g in ipairs(GROUPS) do
        local h = listFrame.headers[gi]
        if not h then
            h = listFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            h:SetTextColor(1, 0.82, 0)
            listFrame.headers[gi] = h
        end
        local any = false
        for _, slot in ipairs(SLOTS) do if g.test(slot) then any = true break end end
        h:SetShown(any)
        if any then
            h:SetText(g.title)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 2, y - (gi > 1 and 6 or 0))
            y = y - (gi > 1 and 6 or 0) - 16
            for _, slot in ipairs(SLOTS) do
                if g.test(slot) and (not slot.hand or HandHasWeapon(slot.hand)) then
                    n = n + 1
                    local r = GetRow(n)
                    r.slot = slot
                    local on = Watched(slot)
                    local tex, sub = SlotIconAndName(slot)
                    r.icon.tex:SetTexture(tex)
                    r.icon.tex:SetDesaturated(not on)
                    r.label:SetText(slot.label)
                    r.label:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
                    r.sub:SetText(sub)
                    r.check:SetShown(not slot.custom)
                    r.check:SetChecked(on)
                    r.close:SetShown(slot.custom and true or false)
                    local perm = slot.permanent
                    r.min:SetShown(on and not perm)
                    r.minLabel:SetShown(on and not perm)
                    r.onlyMissing:SetShown(on and perm and true or false)
                    -- ha nincs X, a perc mezo a sor vegere csuszik
                    r.minLabel:ClearAllPoints()
                    r.onlyMissing:ClearAllPoints()
                    if slot.custom then
                        r.minLabel:SetPoint("RIGHT", r.close, "LEFT", -8, 0)
                        r.onlyMissing:SetPoint("RIGHT", r.close, "LEFT", -8, 0)
                    else
                        r.minLabel:SetPoint("RIGHT", r, "RIGHT", -4, 0)
                        r.onlyMissing:SetPoint("RIGHT", r, "RIGHT", -4, 0)
                    end
                    if on and not perm and not r.min:HasFocus() then r.min:SetText(Minutes(slot)) end
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, y)
                    r:Show()
                    y = y - ROW
                end
            end
        end
    end
    if listFrame.customHeader then listFrame.customHeader:Hide() end
    listFrame:SetHeight(math.max(-y, 20))
    if page.Remeasure then page.Remeasure() end
end
NS.RefreshBuffOptions = RefreshList
fl:OnRefresh(RefreshList)
NS.RefreshBuffList = function() if page:IsVisible() then RefreshList() end end

---------------------------------------------------------------------------
-- Add item: egyeb, specialis buffok (elixir, scroll...): ide huzott item + perc
---------------------------------------------------------------------------
local add = CreateFrame("Frame", nil, NS.opt, BackdropTemplateMixin and "BackdropTemplate" or nil)
add:SetFrameStrata("DIALOG")
add:EnableMouse(true)
add:SetSize(300, 290)
add:Hide()
if add.SetBackdrop then
    add:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    add:SetBackdropColor(0.04, 0.04, 0.06, 0.98)
    add:SetBackdropBorderColor(0.95, 0.78, 0.40, 1)
end
add.title = add:CreateFontString(nil, "OVERLAY", "GameFontNormal")
add.title:SetPoint("TOPLEFT", 12, -10)
add.title:SetText(L["Add buff"])

local itemSlot = CreateFrame("Button", nil, add)
itemSlot:SetSize(30, 30)
itemSlot:SetPoint("TOPLEFT", 14, -32)
itemSlot.bg = itemSlot:CreateTexture(nil, "BACKGROUND")
itemSlot.bg:SetAllPoints()
itemSlot.bg:SetColorTexture(0, 0, 0, 0.6)
itemSlot.tex = itemSlot:CreateTexture(nil, "ARTWORK")
itemSlot.tex:SetPoint("TOPLEFT", 2, -2)
itemSlot.tex:SetPoint("BOTTOMRIGHT", -2, 2)
itemSlot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
local itemText = add:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
itemText:SetPoint("LEFT", itemSlot, "RIGHT", 8, 0)
itemText:SetWidth(230)
itemText:SetJustifyH("LEFT")

-- ...vagy egy buff: spell ID vagy nev, a most rajtad levo buffok kozul kattintva is
local buffLabel = add:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
buffLabel:SetPoint("TOPLEFT", itemSlot, "BOTTOMLEFT", 0, -12)
buffLabel:SetText(L["...or a buff: spell ID or name (search)"])
local buffBox = CreateFrame("EditBox", nil, add, "InputBoxTemplate")
buffBox:SetSize(150, 18)
buffBox:SetAutoFocus(false)
buffBox:SetPoint("TOPLEFT", buffLabel, "BOTTOMLEFT", 6, -4)
local buffMatch = add:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
buffMatch:SetPoint("LEFT", buffBox, "RIGHT", 8, 0)
buffMatch:SetWidth(110)
buffMatch:SetJustifyH("LEFT")
buffMatch:SetWordWrap(false)
local auraHint = add:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
auraHint:SetPoint("TOPLEFT", buffBox, "BOTTOMLEFT", -6, -6)
auraHint:SetText(L["Buffs on you now (click one):"])
local auraBtns = {}

local function SpellNameOf(id)
    if not id then return end
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id)) or nil
end
local function SpellTexOf(id, name)
    local t = id and GetSpellTexture and GetSpellTexture(id)
    return t or (name and SpellIconOf(name)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local okBtn -- lent
local function UpdateOk() if okBtn then okBtn:SetEnabled(add.itemId ~= nil or add.buffName ~= nil) end end

local function RefreshAuraButtons(filter)
    for _, b in ipairs(auraBtns) do b:Hide() end
    local list = {}
    for name, a in pairs(HelpfulAuras()) do
        if not filter or filter == "" or tonumber(filter) or name:lower():find(filter:lower(), 1, true) then
            list[#list + 1] = { name = name, id = a.spellId }
        end
    end
    table.sort(list, function(x, y) return x.name < y.name end)
    for i = 1, math.min(#list, 20) do
        local b = auraBtns[i]
        if not b then
            b = CreateFrame("Button", nil, add)
            b:SetSize(22, 22)
            b.tex = b:CreateTexture(nil, "ARTWORK")
            b.tex:SetAllPoints()
            b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(self.aura.name, 1, 1, 1)
                if self.aura.id then GameTooltip:AddLine("spell " .. self.aura.id, 0.6, 0.6, 0.6) end
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnClick", function(self)
                add.pickingAura = true
                buffBox:SetText(self.aura.name)
                add.pickingAura = nil
                add.buffName, add.buffId = self.aura.name, self.aura.id
                buffMatch:SetText("|cff33ff99" .. self.aura.name .. "|r")
                add.itemId = nil
                itemSlot.tex:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
                UpdateOk()
            end)
            auraBtns[i] = b
        end
        b.aura = list[i]
        b.tex:SetTexture(SpellTexOf(list[i].id, list[i].name))
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", auraHint, "BOTTOMLEFT", ((i - 1) % 10) * 24, -4 - math.floor((i - 1) / 10) * 24)
        b:Show()
    end
end

buffBox:SetScript("OnTextChanged", function(self)
    if add.pickingAura then return end
    local text = self:GetText():match("^%s*(.-)%s*$")
    add.buffName, add.buffId = nil, nil
    if text ~= "" then
        local id = tonumber(text)
        if id then
            add.buffId, add.buffName = id, SpellNameOf(id)
        else
            add.buffName = text
            -- pontos nev a rajtad levo buffok kozul (helyes kis/nagybetu + spell ID)
            for name, a in pairs(HelpfulAuras()) do
                if name:lower() == text:lower() then add.buffName, add.buffId = name, a.spellId end
            end
        end
        if add.buffName then add.itemId = nil end
    end
    buffMatch:SetText(add.buffName and ("|cff33ff99" .. add.buffName .. "|r")
        or (text ~= "" and ("|cffff4444" .. L["unknown spell ID"] .. "|r") or ""))
    RefreshAuraButtons(text)
    UpdateOk()
end)
buffBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
buffBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

local minLabel = add:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
minLabel:SetPoint("TOPLEFT", auraHint, "BOTTOMLEFT", 0, -60)
minLabel:SetText(L["Remind before it runs out:"])
local minBox = CreateFrame("EditBox", nil, add, "InputBoxTemplate")
minBox:SetSize(30, 18)
minBox:SetAutoFocus(false)
minBox:SetNumeric(true)
minBox:SetPoint("LEFT", minLabel, "RIGHT", 8, 0)
local minSuffix = add:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
minSuffix:SetPoint("LEFT", minBox, "RIGHT", 4, 0)
minSuffix:SetText(L["min (0 = only when missing)"])
okBtn = CreateFrame("Button", nil, add, "UIPanelButtonTemplate")
okBtn:SetSize(90, 22)
okBtn:SetPoint("BOTTOMLEFT", 12, 12)
okBtn:SetText(L["Add"])
local cancelBtn = CreateFrame("Button", nil, add, "UIPanelButtonTemplate")
cancelBtn:SetSize(90, 22)
cancelBtn:SetText(CANCEL or "Cancel")
cancelBtn:SetPoint("LEFT", okBtn, "RIGHT", 8, 0)
cancelBtn:SetScript("OnClick", function() add:Hide() end)
page:HookScript("OnHide", function() add:Hide() end)

local function SetAddItem(id)
    add.itemId = id
    itemSlot.tex:SetTexture(id and GetItemIcon(id) or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    itemText:SetText(id and (GetItemInfo(id) or ("item " .. id))
        or L["Drag an item here from your bags (flask, elixir, scroll, juju...)."])
    if id then
        add.buffName, add.buffId = nil, nil
        add.pickingAura = true
        buffBox:SetText("")
        add.pickingAura = nil
        buffMatch:SetText("")
    end
    UpdateOk()
end
local function ItemFromCursor()
    local kind, itemId = GetCursorInfo()
    if kind ~= "item" then return end
    ClearCursor()
    SetAddItem(itemId)
end
itemSlot:SetScript("OnReceiveDrag", ItemFromCursor)
itemSlot:SetScript("OnClick", ItemFromCursor)

local function OpenAdd(anchor)
    if add:IsShown() then add:Hide() return end
    add.buffName, add.buffId = nil, nil
    add.pickingAura = true
    buffBox:SetText("")
    add.pickingAura = nil
    buffMatch:SetText("")
    SetAddItem(nil)
    RefreshAuraButtons(nil)
    minBox:SetText(0)
    add:ClearAllPoints()
    add:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 10, 0)
    add:Show()
end

okBtn:SetScript("OnClick", function()
    local minutes = tonumber(minBox:GetText()) or 0
    local ok
    if add.itemId then
        ok = AddCustomBuff(add.itemId, minutes)
    elseif add.buffName then
        ok = AddCustomSpellBuff(add.buffId, add.buffName, minutes)
    else
        return
    end
    if not ok then
        NS.Loud(Print, L["Already watched, or too many items (max %d)."], MAX_CUSTOM)
        return
    end
    add:Hide()
    AfterChange()
    RefreshList()
end)

fl:Button(L["Add buff"], 140,
    L["Anything else: an item (flask, elixir, scroll, juju - its buff is learned the first time you use it from the reminder) "]
    .. L["or any buff by spell ID / name, or picked from the buffs on you now. If you can cast it, the reminder casts it; otherwise it only tells you it's missing."],
    function(self) OpenAdd(self) end, 4)

fl:Header(L["Other"])
fl:Button(L["Forget learned buffs"], 200,
    L["Forget which buff each item gives; learned again the next time you use it from the reminder. Same as /qf buffreset."],
    function() if NS.ResetBuffLearn then NS.ResetBuffLearn() end end, 4)
fl:Text(L["Tracking (Find Minerals / Find Herbs) can be switched with a key: Options > Keybindings > AddOns > Adventurer's Kit - Buffs."], 2)

page:HookScript("OnShow", function() fl:Refresh() end)
