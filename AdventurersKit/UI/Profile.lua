-- Beallitasok exportja / importja (Options > Share settings, /qf export, /qf import).
-- Szoveg: "AK1:" + sajat, hossz-prefixes formatum. Importnal SAJAT parser olvassa (nincs
-- loadstring), igy egy kapott szoveg nem futtathat kodot.
-- Ami nem megy at: allapot (panel helye, ignore lista, tempo statisztika, utolso quest...).
-- Karakterfuggo reszek ellenorizve: item valasztasok csak ha a taskadban megvan,
-- class beallitasok csak azonos classnal.
local ADDON_NAME, NS = ...
local L = NS.L
local GetItemCount, GetItemInfoInstant, GetItemInfo, GetItemIcon, GetItemSpell = NS.SafeItem.GetItemCount, NS.SafeItem.GetItemInfoInstant, NS.SafeItem.GetItemInfo, NS.SafeItem.GetItemIcon, NS.SafeItem.GetItemSpell -- biztonsagos item API (CoreInit.lua)

local PREFIX = "AK1:"

-- Exportalt kulcsok (a tobbi allapot / karakterhez kotott, nem visszuk at)
local PLAIN = {
    "quietChat", "showErrors", "hideMinimap", "fontSize", "panelW", "panelH", "panelScale",
    "macroIcons", "startAttack", "noPing", "noArrow", "nearbyRadius", "noNearbyQuests",
    "noSuggest", "noToast", "noQuestPopup", "noCityMode", "pickupAbove", "pickupBelow",
    "zoneFocus", "noZonePrompt", "zoneAutoFollow", "modules",
    "noBagGlow", "noBagList", "noUseButton",
    "noBuffAlert", "noBuffWarn", "noFoodPrompt", "buffWarn",
}
local CLASS_ONLY = { "spell", "useSpell", "classPref" } -- csak azonos classnal

---------------------------------------------------------------------------
-- Szerializalas: T / F / N<szam>; / S<hossz>:<bajtok> / { kulcs ertek ... }
---------------------------------------------------------------------------
local function Ser(v, out, depth)
    local t = type(v)
    if t == "boolean" then out[#out + 1] = v and "T" or "F"
    elseif t == "number" then out[#out + 1] = "N" .. tostring(v) .. ";"
    elseif t == "string" then out[#out + 1] = "S" .. #v .. ":" .. v
    elseif t == "table" and depth < 8 then
        out[#out + 1] = "{"
        for k, val in pairs(v) do
            local kt, vt = type(k), type(val)
            if (kt == "string" or kt == "number")
                and (vt == "boolean" or vt == "number" or vt == "string" or vt == "table") then
                Ser(k, out, depth + 1)
                Ser(val, out, depth + 1)
            end
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "F"
    end
end

-- Visszaolvasas: (ertek, uj pozicio) vagy hiba eseten nil
local function Des(s, i, depth)
    if depth > 10 then return end
    local c = s:sub(i, i)
    if c == "T" then return true, i + 1 end
    if c == "F" then return false, i + 1 end
    if c == "N" then
        local j = s:find(";", i + 1, true)
        local n = j and tonumber(s:sub(i + 1, j - 1))
        if not n then return end
        return n, j + 1
    end
    if c == "S" then
        local j = s:find(":", i + 1, true)
        local len = j and tonumber(s:sub(i + 1, j - 1))
        if not len or len < 0 or j + len > #s then return end
        return s:sub(j + 1, j + len), j + len + 1
    end
    if c == "{" then
        local t, n = {}, 0
        i = i + 1
        while true do
            if i > #s then return end
            if s:sub(i, i) == "}" then return t, i + 1 end
            local k, v
            k, i = Des(s, i, depth + 1)
            if k == nil or (type(k) ~= "string" and type(k) ~= "number") then return end
            v, i = Des(s, i, depth + 1)
            if v == nil then return end
            t[k] = v
            n = n + 1
            if n > 2000 then return end
        end
    end
end

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

local function Export()
    local db = QuestFocusDB
    local data = { v = NS.Version and NS.Version() or "?", class = select(2, UnitClass("player")), s = {} }
    for _, k in ipairs(PLAIN) do if db[k] ~= nil then data.s[k] = Copy(db[k]) end end
    for _, k in ipairs(CLASS_ONLY) do if db[k] ~= nil then data.s[k] = Copy(db[k]) end end
    for k, v in pairs(db) do
        if type(k) == "string" and k:find("^noBuff_") then data.s[k] = v end
    end
    -- item valasztasok: itemID + nev (a nev a jelentesbe, ha a masiknal nincs meg)
    if type(db.buffItems) == "table" then
        data.items = {}
        for key, id in pairs(db.buffItems) do
            data.items[key] = { id = id, name = GetItemInfo(id) or ("item " .. tostring(id)) }
        end
    end
    if type(db.customBuffs) == "table" then
        data.custom = {}
        for _, cb in ipairs(db.customBuffs) do
            local e = Copy(cb)
            if e.itemId then e.itemName = GetItemInfo(e.itemId) or ("item " .. tostring(e.itemId)) end
            data.custom[#data.custom + 1] = e
        end
    end
    local out = {}
    Ser(data, out, 0)
    return PREFIX .. table.concat(out)
end
NS.ExportSettings = Export

local function Have(id) return tonumber(id) and GetItemCount(tonumber(id)) > 0 end

-- Visszaadja: ok, uzenet sorok
local function Import(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text:sub(1, #PREFIX) ~= PREFIX then return false, { L["Not an Adventurer's Kit settings text (it should start with AK1:)."] } end
    local ok, data = pcall(Des, text, #PREFIX + 1, 0)
    if not ok or type(data) ~= "table" or type(data.s) ~= "table" then
        return false, { L["The settings text is damaged (copy it again, all of it)."] }
    end
    local db, report = QuestFocusDB, {}
    local myClass = select(2, UnitClass("player"))
    local allowed = {}
    for _, k in ipairs(PLAIN) do allowed[k] = true end
    local n = 0
    for k, v in pairs(data.s) do
        if type(k) == "string" and (allowed[k] or k:find("^noBuff_")) then
            db[k] = Copy(v)
            n = n + 1
        end
    end
    -- class beallitasok
    if data.class == myClass then
        for _, k in ipairs(CLASS_ONLY) do
            if data.s[k] ~= nil then db[k] = Copy(data.s[k]); n = n + 1 end
        end
    elseif data.class then
        report[#report + 1] = (L["Class settings (macro spell, class buff choices) skipped: they are for %s."]):format(
            (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[data.class]) or tostring(data.class))
    end
    -- item valasztasok: csak ami nalad is megvan; a tobbi automatikus marad
    local missing = {}
    if type(data.items) == "table" then
        db.buffItems = db.buffItems or {}
        for key, e in pairs(data.items) do
            if type(e) == "table" and Have(e.id) then
                db.buffItems[key] = tonumber(e.id)
            elseif type(e) == "table" then
                missing[#missing + 1] = tostring(e.name or e.id)
            end
        end
    end
    -- sajat buffok: spell / buff mindig; item csak ha megvan (kulonben folyton szolna erte)
    if type(data.custom) == "table" then
        db.customBuffs = db.customBuffs or {}
        local have = {}
        for _, cb in ipairs(db.customBuffs) do if cb.key then have[cb.key] = true end end
        for _, cb in ipairs(data.custom) do
            if type(cb) == "table" and type(cb.key) == "string" and not have[cb.key] and #db.customBuffs < 8 then
                if cb.itemId and not Have(cb.itemId) then
                    missing[#missing + 1] = tostring(cb.itemName or cb.itemId)
                else
                    cb.itemName = nil
                    db.customBuffs[#db.customBuffs + 1] = cb
                    have[cb.key] = true
                end
            end
        end
    end
    table.insert(report, 1, (L["Imported %d settings (from v%s)."]):format(n, tostring(data.v or "?")))
    if #missing > 0 then
        report[#report + 1] = L["Not in your bags, left automatic / not added (add them later on the Buffs tab): "]
            .. table.concat(missing, ", ")
    end
    return true, report
end
NS.ImportSettings = Import

---------------------------------------------------------------------------
-- Ablak: tobbsoros szovegmezo (export: kijelolve masolhato; import: ide masold)
---------------------------------------------------------------------------
local win = CreateFrame("Frame", "QuestFocusShareFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
win:SetSize(460, 260)
win:SetPoint("CENTER")
win:SetFrameStrata("DIALOG")
win:EnableMouse(true)
win:SetMovable(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
win:Hide()
tinsert(UISpecialFrames, "QuestFocusShareFrame")
if win.SetBackdrop then
    win:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 20,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    win:SetBackdropColor(0.04, 0.04, 0.06, 0.96)
    win:SetBackdropBorderColor(0.95, 0.78, 0.40, 1)
end
win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
win.title:SetPoint("TOPLEFT", 14, -12)
win.hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
win.hint:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -4)
win.hint:SetWidth(430)
win.hint:SetJustifyH("LEFT")
local wClose = CreateFrame("Button", nil, win, "UIPanelCloseButton")
wClose:SetPoint("TOPRIGHT", -4, -4)

local sc = CreateFrame("ScrollFrame", "QuestFocusShareScroll", win, "UIPanelScrollFrameTemplate")
sc:SetPoint("TOPLEFT", 14, -52)
sc:SetPoint("BOTTOMRIGHT", -34, 42)
local box = CreateFrame("EditBox", nil, sc)
box:SetMultiLine(true)
box:SetAutoFocus(false)
box:SetFontObject(ChatFontSmall or GameFontHighlightSmall)
box:SetWidth(400)
box:SetMaxLetters(0)
box:SetScript("OnEscapePressed", function() win:Hide() end)
sc:SetScrollChild(box)
-- export modban a szoveg nem szerkesztheto: barmi gepeles visszaallitja
box:SetScript("OnTextChanged", function(self, user)
    if user and win.mode == "export" and self:GetText() ~= win.text then
        self:SetText(win.text)
        self:HighlightText()
    end
end)

local action = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
action:SetSize(120, 22)
action:SetPoint("BOTTOMRIGHT", -14, 12)

StaticPopupDialogs["QUESTFOCUS_IMPORT_RELOAD"] = {
    text = "%s",
    button1 = RELOADUI or "Reload UI",
    button2 = L["Later"],
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

action:SetScript("OnClick", function()
    if win.mode == "export" then
        box:SetFocus()
        box:HighlightText()
        return
    end
    local ok, report = Import(box:GetText())
    for _, line in ipairs(report) do NS.PrintAlways(line) end
    if ok then
        win:Hide()
        StaticPopup_Show("QUESTFOCUS_IMPORT_RELOAD",
            L["Adventurer's Kit: settings imported. Reload the UI so every module picks them up?"])
    end
end)

local function Open(mode)
    win.mode = mode
    if mode == "export" then
        win.text = Export()
        win.title:SetText(L["Export settings"])
        win.hint:SetText(L["Ctrl+C to copy, then send it to anyone (whisper, Discord...). Item choices go with item names; class settings only apply to the same class."])
        action:SetText(L["Select all"])
        box:SetText(win.text)
        win:Show()
        box:SetFocus()
        box:HighlightText()
    else
        win.text = nil
        win.title:SetText(L["Import settings"])
        win.hint:SetText(L["Paste the text with Ctrl+V, then Import. Items you don't have stay automatic; it does not change your panel position or ignore list."])
        action:SetText(L["Import"])
        box:SetText("")
        win:Show()
        box:SetFocus()
    end
    sc:SetVerticalScroll(0)
end
NS.OpenShareSettings = Open

---------------------------------------------------------------------------
-- Options ful (Release notes ele)
---------------------------------------------------------------------------
local page = NS.AddOptionsTab(L["Share settings"], 75)
local fl = NS.OptFlow(page)
fl:Header(L["Share settings"])
fl:Text(L["Send your Adventurer's Kit settings to someone else, or load theirs. Not shared: panel position, city ignore list, your kill pace and other personal data."], 2)
fl:Button(L["Export"], 140,
    L["Shows your settings as text; copy it (Ctrl+C) and send it. Also: /qf export"],
    function() Open("export") end)
fl:Button(L["Import"], 140,
    L["Paste someone's settings text. XP food, sleeping bag, stones / oils and your own item buffs are only taken if you have that item in your bags; "]
    .. L["class settings (macro spell, class buffs) only from the same class. Also: /qf import"],
    function() Open("import") end)
