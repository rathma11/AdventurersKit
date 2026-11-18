local ADDON_NAME, NS = ...
local L = NS.L
NS.C = NS.C or {}
local C = NS.C
local arrow, DebugLines, ICON_HUNT, Panel_Update, Print, state, ToggleZoneFocus, UpdateMacro = C.arrow, C.DebugLines, C.ICON_HUNT, C.Panel_Update, C.Print, C.state, C.ToggleZoneFocus, C.UpdateMacro
local UseOwnArrow = C.UseOwnArrow
local ApplyMacro, BuildMacroBody, IconId = C.ApplyMacro, C.BuildMacroBody, C.IconId

---------------------------------------------------------------------------
-- Beallitasok (Options > AddOns > QuestFocus)
-- Bal oldalon fuggoleges fulek feature-onkent (sorrend: order), jobb oldalon a
-- gorgetheto oldal. Minden kapcsolo alatt rovid, szurke leiras.
-- Oldal sorrend:  10 General · 20 Macro & marker · 30 Route & progress · 40 Quest pickup · 45 City list
--                 50 Zone focus · 60 Bags (modul) · 70 Buffs (modul) · 90 Debug
---------------------------------------------------------------------------
local function RebuildMacro()
    state.lastBody = nil
    if state.questId then UpdateMacro() Panel_Update() end
end

local function SpellNameById(id)
    if not id then return end
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function SpellIcon(name)
    if not name or name == "" then return end
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(name) end
    if GetSpellTexture then return GetSpellTexture(name) end
end

local opt = CreateFrame("Frame")
opt.name = "Adventurer's Kit"
local optCategory

local TAB_W, DESC_W = 130, 420

local function OptLabel(parent, text, template)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

local optTitle = OptLabel(opt, "Adventurer's Kit", "GameFontNormalLarge")
optTitle:SetPoint("TOPLEFT", 16, -16)
-- verzioszam kicsiben a nev utan (a .toc Version sorabol)
do
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local ok, ver = pcall(getMeta, ADDON_NAME, "Version")
    local v = opt:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    v:SetPoint("BOTTOMLEFT", optTitle, "BOTTOMRIGHT", 6, 1)
    v:SetText(ok and ver and ("v" .. ver) or "")
end
local optSub = OptLabel(opt, L["Settings grouped by feature. Every option has a short description; hover it for a tooltip too."],
    "GameFontHighlightSmall")
optSub:SetPoint("TOPLEFT", optTitle, "BOTTOMLEFT", 0, -6)

---------------------------------------------------------------------------
-- Fulek (fuggoleges lista bal oldalon)
---------------------------------------------------------------------------
local tabs, selectedKey = {}, nil
local tabBg = opt:CreateTexture(nil, "BACKGROUND")
tabBg:SetPoint("TOPLEFT", optSub, "BOTTOMLEFT", -4, -10)
tabBg:SetPoint("BOTTOMLEFT", opt, "BOTTOMLEFT", 12, 12)
tabBg:SetWidth(TAB_W + 8)
tabBg:SetColorTexture(0, 0, 0, 0.25)

local function SelectTab(key)
    if not key and tabs[1] then key = tabs[1].key end
    selectedKey = key
    for _, t in ipairs(tabs) do
        local on = t.key == key
        t.page:SetShown(on)
        t.sel:SetShown(on)
        t.text:SetTextColor(on and 1 or 0.85, on and 0.82 or 0.85, on and 0 or 0.85)
    end
end

local function LayoutTabs()
    table.sort(tabs, function(a, b) return a.order < b.order end)
    for i, t in ipairs(tabs) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", optSub, "BOTTOMLEFT", 0, -14 - (i - 1) * 24)
    end
end

-- Uj oldal. order: hely a listaban; opts.noScroll: sima frame (sajat gorgetessel, pl. Debug).
-- Visszaad: a tartalom frame (erre kell epiteni).
local function AddOptionsTab(label, order, opts)
    opts = opts or {}
    local key = label
    local holder = CreateFrame("Frame", nil, opt)
    holder:SetPoint("TOPLEFT", optSub, "BOTTOMLEFT", TAB_W + 18, -14)
    holder:SetPoint("BOTTOMRIGHT", opt, "BOTTOMRIGHT", -12, 12)
    holder:Hide()
    local content = holder
    if not opts.noScroll then
        local scroll = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT")
        scroll:SetPoint("BOTTOMRIGHT", -24, 0)
        content = CreateFrame("Frame", nil, scroll)
        content:SetSize(DESC_W + 60, 10)
        scroll:SetScrollChild(content)
        -- tartalom magassaga: a legalso elem alja (megjeleneskor, es ha az oldal keri: Remeasure)
        local function Remeasure()
            C_Timer.After(0, function()
                local top, low = content:GetTop(), nil
                if not top then return end
                local function scan(...)
                    for i = 1, select("#", ...) do
                        local r = select(i, ...)
                        if r:IsShown() and not r.qfNoMeasure and r:GetBottom() then
                            local b = r:GetBottom()
                            if not low or b < low then low = b end
                        end
                    end
                end
                scan(content:GetChildren())
                scan(content:GetRegions())
                content:SetWidth(math.max(DESC_W + 60, scroll:GetWidth()))
                content:SetHeight(low and (top - low + 16) or 10)
            end)
        end
        content.Remeasure = Remeasure
        holder:SetScript("OnShow", Remeasure)
    end

    local t = CreateFrame("Button", nil, opt)
    t:SetSize(TAB_W, 22)
    t.key, t.order, t.page = key, order or (#tabs + 1) * 10, holder
    t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t.text:SetPoint("LEFT", 8, 0)
    t.text:SetPoint("RIGHT", -4, 0)
    t.text:SetJustifyH("LEFT")
    t.text:SetText(label)
    t.sel = t:CreateTexture(nil, "BACKGROUND")
    t.sel:SetAllPoints()
    t.sel:SetColorTexture(1, 0.82, 0, 0.15)
    t.sel:Hide()
    local hl = t:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    t:SetScript("OnClick", function() SelectTab(key) end)
    tabs[#tabs + 1] = t
    LayoutTabs()
    if opt:IsShown() then SelectTab(selectedKey) end
    return content
end
NS.AddOptionsTab = AddOptionsTab

---------------------------------------------------------------------------
-- Elemek
---------------------------------------------------------------------------
local function Desc(parent, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetTextColor(0.62, 0.62, 0.62)
    fs:SetJustifyH("LEFT")
    fs:SetWidth(DESC_W)
    fs:SetText(text or "")
    return fs
end

-- Kapcsolo + leiras alatta (es ugyanez tooltipben)
local function OptCheck(label, tip, get, set, parent)
    parent = parent or opt
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb.label = OptLabel(cb, label)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    cb.desc = Desc(parent, tip)
    cb.desc:SetPoint("TOPLEFT", cb.label, "BOTTOMLEFT", 0, -3)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        if tip then GameTooltip:AddLine(tip, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cb.refresh = function() cb:SetChecked(get()) end
    return cb
end
NS.OptCheck = OptCheck

-- Egymas ala rakott elemek egy oldalon. A "last" mindig az elem legalso resze
-- (kapcsolonal a leiras), lastX annak bal szele az oldalhoz kepest.
local function OptFlow(page)
    local f = { page = page, refreshers = {} }
    function f:Place(frame, x, gap, bottom, bottomX)
        x = x or 0
        frame:ClearAllPoints()
        if self.last then
            frame:SetPoint("TOPLEFT", self.last, "BOTTOMLEFT", x - self.lastX, -(gap or 10))
        else
            frame:SetPoint("TOPLEFT", page, "TOPLEFT", x, -(gap or 2))
        end
        self.last, self.lastX = bottom or frame, bottomX or x
        return frame
    end
    function f:OnRefresh(fn) self.refreshers[#self.refreshers + 1] = fn end
    function f:Refresh() for _, fn in ipairs(self.refreshers) do pcall(fn) end end
    function f:Header(text)
        local fs = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        fs:SetText(text)
        self:Place(fs, 0, self.last and 20 or 2)
        local line = page:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 0.82, 0, 0.25)
        line:SetHeight(1)
        line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
        line:SetWidth(DESC_W - 60)
        return fs
    end
    function f:Text(text, x)
        local fs = Desc(page, text)
        self:Place(fs, x or 2, 8)
        return fs
    end
    function f:Check(label, desc, get, set, x)
        local cb = OptCheck(label, desc, get, set, page)
        x = x or -2
        self:Place(cb, x, 8, cb.desc, x + 30)
        self:OnRefresh(cb.refresh)
        return cb
    end
    -- Szam mezo: "cimke [box] utotag" + leiras alatta. get() -> szam, set(szam)
    function f:Number(label, desc, get, set, suffix, x)
        x = x or 28
        local fs = OptLabel(page, label, "GameFontHighlightSmall")
        local box = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
        box:SetSize(36, 18)
        box:SetAutoFocus(false)
        box:SetNumeric(true)
        box:SetPoint("LEFT", fs, "RIGHT", 10, 0)
        local suf
        if suffix then
            suf = OptLabel(page, suffix, "GameFontHighlightSmall")
            suf:SetPoint("LEFT", box, "RIGHT", 4, 0)
        end
        local d = Desc(page, desc)
        d:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -6)
        box.refresh = function() box:SetText(tostring(get() or "")) end
        box:SetScript("OnEnterPressed", function(self)
            local v = tonumber(self:GetText())
            if v then set(v) end
            self.refresh()
            self:ClearFocus()
        end)
        box:SetScript("OnEscapePressed", function(self) self.refresh(); self:ClearFocus() end)
        box:SetScript("OnEditFocusLost", function(self) self.refresh() end)
        self:Place(fs, x, 12, d, x)
        self:OnRefresh(box.refresh)
        box.label, box.desc = fs, d
        return box
    end
    -- Gomb + leiras alatta
    function f:Button(text, width, desc, onClick, x)
        x = x or 28
        local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        b:SetSize(width or 160, 22)
        b:SetText(text)
        -- gombra kattintas: a visszajelzes akkor is kikerul a chatre, ha a chat ki van kapcsolva
        b:SetScript("OnClick", function(...) NS.Loud(onClick, ...) end)
        local d
        if desc then
            d = Desc(page, desc)
            d:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -4)
        end
        self:Place(b, x, 12, d or b, x)
        b.desc = d
        return b
    end
    return f
end
NS.OptFlow = OptFlow

---------------------------------------------------------------------------
-- Modulok (QuestFocus_Bags, QuestFocus_Buffs): az oldaluk tetejen egy "Module on" kapcsolo.
-- Sima igaz/hamis ertek (QuestFocusDB.modules[addon], alap: be): az addon betoltve marad,
-- kikapcsolva csak nem csinal semmit. Nem kell hozza reload.
---------------------------------------------------------------------------
local MODULES = {
    QuestFocus_Bags = { label = L["Bags"], order = 60,
        desc = L["Quest item list next to the bags, Bagnon coloring, usable quest item buttons on the panel."] },
    QuestFocus_Buffs = { label = L["Buffs"], order = 70,
        desc = L["Buff reminder (sleeping bag, XP food, weapon enchant, class buffs, tracking) and buff buttons."] },
}

local function ModuleOn(addon)
    local m = QuestFocusDB and QuestFocusDB.modules
    return not (m and m[addon] == false)
end
NS.ModuleOn = ModuleOn

-- Modul oldal: tab + "Module on" kapcsolo a tetejen. onToggle(on): a modul azonnal
-- elrejti / visszahozza a sajat dolgait. Visszaad: page, flow.
local function ModulePage(addon, onToggle)
    local def = MODULES[addon]
    if not def then return end
    local page = AddOptionsTab(def.label, def.order)
    local fl = OptFlow(page)
    local cb
    -- Kikapcsolt modul: a tobbi beallitas szurke es nem kattinthato (gorgetni lehet)
    local blocker = CreateFrame("Frame", nil, page)
    blocker.qfNoMeasure = true -- az oldal aljaig er: a magassag meresebol kimarad
    blocker:EnableMouse(true)
    blocker:Hide()
    local function ApplyGrey()
        local on = ModuleOn(addon)
        local a = on and 1 or 0.35
        for _, c in ipairs({ page:GetChildren() }) do
            if c ~= cb and c ~= blocker then c:SetAlpha(a) end
        end
        for _, r in ipairs({ page:GetRegions() }) do
            if r ~= cb.desc then r:SetAlpha(a) end
        end
        blocker:SetFrameLevel(page:GetFrameLevel() + 60)
        blocker:SetShown(not on)
    end
    cb = fl:Check(L["Module on"],
        def.desc .. " " .. L["Off: the module stays loaded but does nothing (its settings below are kept)."],
        function() return ModuleOn(addon) end,
        function(v)
            QuestFocusDB.modules = QuestFocusDB.modules or {}
            QuestFocusDB.modules[addon] = v and true or false
            if onToggle then pcall(onToggle, v) end
            ApplyGrey()
        end)
    blocker:SetPoint("TOPLEFT", cb.desc, "BOTTOMLEFT", -40, -4)
    blocker:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    -- a modul sajat elemei kesobb jonnek letre: megjeleneskor (es frissiteskor) szurkitunk
    page:HookScript("OnShow", function() fl:Refresh(); ApplyGrey() end)
    return page, fl
end
NS.ModulePage = ModulePage

---------------------------------------------------------------------------
-- Minimap gomb (bal klikk: beallitasok, jobb klikk: zona fokusz, huzhato)
---------------------------------------------------------------------------
local OpenOptions -- lent
local mmBtn = CreateFrame("Button", "QuestFocusMinimapButton", Minimap)
mmBtn:SetSize(31, 31)
mmBtn:SetFrameStrata("MEDIUM")
mmBtn:SetFrameLevel(8)
mmBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mmBtn:RegisterForDrag("LeftButton")
mmBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
do
    local bg = mmBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = mmBtn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\" .. ICON_HUNT)
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    mmBtn.icon = icon
    local border = mmBtn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
end

local function MinimapButtonPos()
    local angle = math.rad(QuestFocusDB.minimapAngle or 200)
    local r = (Minimap:GetWidth() / 2) + 10
    mmBtn:ClearAllPoints()
    mmBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function UpdateMinimapButton()
    if not QuestFocusDB then return end
    mmBtn:SetShown(not QuestFocusDB.hideMinimap)
    MinimapButtonPos()
end

mmBtn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local s = Minimap:GetEffectiveScale()
        QuestFocusDB.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
        MinimapButtonPos()
    end)
end)
mmBtn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mmBtn:RegisterEvent("PLAYER_LOGIN")
mmBtn:SetScript("OnEvent", function() UpdateMinimapButton() end)
local function MinimapTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Adventurer's Kit", 0.2, 1, 0.6)
    if state.title then GameTooltip:AddLine("Quest: " .. state.title, 1, 1, 1) end
    local zf = QuestFocusDB and QuestFocusDB.zoneFocus
    GameTooltip:AddLine(L["Zone focus: "] .. (zf and (zf.zone or "?") or L["off"]), 1, 0.82, 0)
    GameTooltip:AddLine(L["Left click: settings"], 0.6, 0.6, 0.6)
    GameTooltip:AddLine(L["Right click: zone focus on/off"], 0.6, 0.6, 0.6)
    GameTooltip:AddLine(L["Drag: move"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end
mmBtn:SetScript("OnEnter", MinimapTooltip)
mmBtn:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
        ToggleZoneFocus()
        -- a tooltip azonnal mutassa az uj allapotot (ne kelljen le-fel vinni az egeret)
        if GameTooltip:IsOwned(self) then MinimapTooltip(self) end
        C_Timer.After(0.2, function()
            if GameTooltip:IsOwned(self) and self:IsMouseOver() then MinimapTooltip(self) end
        end)
    else
        OpenOptions()
    end
end)
mmBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- 10 General
---------------------------------------------------------------------------
local pageGen = AddOptionsTab(L["General"], 10)
local gen = OptFlow(pageGen)
gen:Header(L["Panel"])
gen:Check(L["Show the panel"],
    L["The panel with the selected quest, its objectives and the time left. Same as typing /ak."],
    function() return not QuestFocusDB.hidePanel end,
    function(v) QuestFocusDB.hidePanel = not v; Panel_Update() end)
gen:Number(L["Font size"],
    L["Text size on the panel (8-20, default 10). The panel's width and height follow it. Press Enter to apply."],
    function() return NS.FontSize and NS.FontSize() or 10 end,
    function(v)
        QuestFocusDB.fontSize = math.max(8, math.min(20, v))
        if NS.ApplyFontSize then NS.ApplyFontSize() end
        if NS.ApplyPanelWidth then NS.ApplyPanelWidth() end
        Panel_Update()
    end)
gen:Header(L["Chat"])
gen:Check(L["Chat messages"],
    L["Status messages in chat (marker moved, quest complete, buff warnings, ...). Off: only one line at login "]
    .. L["and the replies to your own /ak commands and button clicks. Toggle: /ak chat."],
    function() return not QuestFocusDB.quietChat end,
    function(v) QuestFocusDB.quietChat = not v end)
gen:Header(L["Minimap"])
gen:Check(L["Minimap button"],
    L["Left click: settings, right click: zone focus on/off. Drag it around the minimap."],
    function() return not QuestFocusDB.hideMinimap end,
    function(v) QuestFocusDB.hideMinimap = not v; UpdateMinimapButton() end)
pageGen:HookScript("OnShow", function() gen:Refresh() end)

---------------------------------------------------------------------------
-- 20 Macro & marker
---------------------------------------------------------------------------
local pageMac = AddOptionsTab(L["Macro & marker"], 20)
local mac = OptFlow(pageMac)
mac:Text(L["The AKit macro targets the mobs of the selected objective. Put it on your bars once; it updates itself. "]
    .. L["The macro can't be changed in combat; changes apply after combat."], 2)
mac:Header(L["AKit macro"])
local cbSpell = mac:Check(L["Spell in the macro (tagging)"],
    L["After targeting the mob the macro also casts this spell (e.g. a ranged pull). Not at turn-in (friendly NPC)."],
    function() return QuestFocusDB.useSpell end,
    function(v) QuestFocusDB.useSpell = v; RebuildMacro() end)

local spellSlot = CreateFrame("Button", nil, pageMac)
spellSlot:SetSize(36, 36)
spellSlot.bg = spellSlot:CreateTexture(nil, "BACKGROUND")
spellSlot.bg:SetAllPoints()
spellSlot.bg:SetColorTexture(0, 0, 0, 0.5)
spellSlot.icon = spellSlot:CreateTexture(nil, "ARTWORK")
spellSlot.icon:SetPoint("TOPLEFT", 2, -2)
spellSlot.icon:SetPoint("BOTTOMRIGHT", -2, 2)
spellSlot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
local spellBox = CreateFrame("EditBox", nil, pageMac, "InputBoxTemplate")
spellBox:SetSize(200, 20)
spellBox:SetAutoFocus(false)
spellBox:SetPoint("LEFT", spellSlot, "RIGHT", 14, 6)
local spellHint = Desc(pageMac, L["Drag a spell here from your spellbook (P), or type its name + Enter. Right click: clear."])
spellHint:SetPoint("TOPLEFT", spellBox, "BOTTOMLEFT", -4, -4)
spellHint:SetWidth(DESC_W - 60)
mac:Place(spellSlot, 28, 8)

local function RefreshSpellUI()
    local s = QuestFocusDB.spell
    spellBox:SetText(s or "")
    spellSlot.icon:SetTexture(SpellIcon(s) or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
end
mac:OnRefresh(RefreshSpellUI)

local function SetSpell(name)
    if name then name = name:match("^%s*(.-)%s*$") end
    if name == "" then name = nil end
    QuestFocusDB.spell = name
    if name and not QuestFocusDB.useSpell then QuestFocusDB.useSpell = true; cbSpell.refresh() end
    RefreshSpellUI()
    RebuildMacro()
    Print(name and (L["Tag spell: |cffffff00%s|r"]):format(name) or L["Tag spell cleared."])
end

local function SpellFromCursor()
    local kind, a, b, c = GetCursorInfo()
    if kind ~= "spell" then return end
    local name = SpellNameById(c)
    if not name and GetSpellBookItemName and a then name = GetSpellBookItemName(a, b) end
    ClearCursor()
    if name then SetSpell(name) end
end

spellSlot:SetScript("OnReceiveDrag", SpellFromCursor)
spellSlot:SetScript("OnClick", function(_, button)
    if button == "RightButton" then SetSpell(nil) else SpellFromCursor() end
end)
spellSlot:SetScript("OnEnter", function(self)
    if not QuestFocusDB.spell then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(QuestFocusDB.spell, 1, 1, 1)
    GameTooltip:Show()
end)
spellSlot:SetScript("OnLeave", function() GameTooltip:Hide() end)
spellBox:SetScript("OnEnterPressed", function(self) SetSpell(self:GetText()); self:ClearFocus() end)
spellBox:SetScript("OnEscapePressed", function(self) RefreshSpellUI(); self:ClearFocus() end)

mac:Check(L["Auto attack (/startattack)"],
    L["Also starts auto attack after targeting (melee / wand / bow)."],
    function() return QuestFocusDB.startAttack end,
    function(v) QuestFocusDB.startAttack = v; RebuildMacro() end)
-- Ping: harom valasztas (egyszerre egy): kerdezze csapatba lepeskor / mindig / soha
do
    local PING_DESC = {
        ask = L["When you join a group, a small window asks whether to ping in that group (you can change this setting there too). Solo it always pings."],
        on = L["The macro always pings the target at the end (ping system); party members see it too."],
        off = L["The macro never pings."],
    }
    local PING_LABEL = { ask = L["Ping: ask when I join a group"], on = L["Ping: always"], off = L["Ping: never"] }
    for _, m in ipairs({ "ask", "on", "off" }) do
        mac:Check(PING_LABEL[m], PING_DESC[m],
            function() return NS.PingMode() == m end,
            function()
                if NS.SetPingMode then NS.SetPingMode(m) else QuestFocusDB.pingMode = m end
                mac:Refresh()
            end)
    end
    NS.RefreshPingUI = function() mac:Refresh() end
end
mac:Check(L["Also target mobs of other nearby quests"],
    L["Mobs of other quests in your log within ~200 yards are added to the macro too, "]
    .. L["and listed on the panel under ALSO NEARBY (click one to focus that quest)."],
    function() return not QuestFocusDB.noNearbyQuests end,
    function(v)
        QuestFocusDB.noNearbyQuests = not v
        if not v then state.extra = nil end
        Panel_Update()
    end)

---------------------------------------------------------------------------
-- Makro ikonok allapotonkent + oldalra nyilo ikonvalaszto
---------------------------------------------------------------------------
-- Valaszthato ikonok (Interface\Icons\...). A nem letezo a valasztoban "?"-kent latszik.
local ICON_CHOICES = {
    -- vadaszat / celzas
    "Ability_Hunter_SniperShot", "Ability_Hunter_AimedShot", "Ability_Marksmanship", "Ability_Hunter_EagleEye",
    "Ability_Tracking", "Ability_DualWield", "Ability_Warrior_Charge", "Ability_Rogue_Ambush",
    "Ability_Warrior_BattleShout", "INV_Sword_04", "INV_Axe_02", "INV_Weapon_Bow_02",
    "INV_Misc_Bone_HumanSkull_01", "INV_Misc_Head_Dragon_01", "INV_Misc_Pelt_Wolf_01", "Ability_Hunter_Pet_Wolf",
    -- gyujtes
    "INV_Misc_Bag_08", "INV_Misc_Herb_10", "INV_Ore_Copper_01", "INV_Misc_Gear_01",
    -- leadas / quest
    "INV_Misc_Note_01", "INV_Misc_Note_02", "INV_Scroll_03", "INV_Letter_01",
    "INV_Misc_Book_09", "INV_Misc_Coin_01", "INV_Misc_Bag_10", "Spell_Holy_Restoration",
    -- terkep / keszenlet
    "INV_Misc_Map_01", "INV_Misc_Spyglass_02", "INV_Misc_Spyglass_03", "INV_Misc_QuestionMark",
}

local function RefreshMacroIcon()
    state.lastIcon = nil
    if not InCombatLockdown() and ApplyMacro then
        local body = state.lastBody
        if not body and state.questId then
            local ok, b = pcall(BuildMacroBody, state.objectives, state.objIndex)
            body = ok and b or nil
        end
        if body then ApplyMacro(body) end
    end
    Panel_Update()
end

-- name = nil: alap ikon. noApply: tobbet allitunk egymas utan (a hivo frissit)
local function SetMacroIcon(kind, name, noApply)
    QuestFocusDB.macroIcons = QuestFocusDB.macroIcons or {}
    if name == NS.MacroIconDefaults[kind] then name = nil end
    QuestFocusDB.macroIcons[kind] = name
    if not noApply then RefreshMacroIcon() end
end
NS.SetMacroIcon = function(kind, name, noApply)
    SetMacroIcon(kind, name, true)
    if noApply then
        -- a /ak icon az utolso hivas utan frissit
        C_Timer.After(0, RefreshMacroIcon)
    else
        RefreshMacroIcon()
    end
end

local function IconTexPath(name)
    return name and (name:find("[/\\]") and name or ("Interface\\Icons\\" .. name)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Oldalra nyilo valaszto (egy kozos az osszes slotnak)
local FLY_COLS, FLY_SIZE = 8, 26
-- az opt-hoz kotve (nem a gorgetett oldalhoz), hogy a scroll ne vagja le
local fly = CreateFrame("Frame", nil, opt, BackdropTemplateMixin and "BackdropTemplate" or nil)
fly:SetFrameStrata("DIALOG")
fly:EnableMouse(true)
fly:Hide()
if fly.SetBackdrop then
    fly:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    fly:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
    fly:SetBackdropBorderColor(0.95, 0.78, 0.40, 1)
end
fly.buttons = {}
for i, name in ipairs(ICON_CHOICES) do
    local b = CreateFrame("Button", nil, fly)
    b:SetSize(FLY_SIZE - 2, FLY_SIZE - 2)
    local col, row = (i - 1) % FLY_COLS, math.floor((i - 1) / FLY_COLS)
    b:SetPoint("TOPLEFT", 8 + col * FLY_SIZE, -8 - row * FLY_SIZE)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexture(IconTexPath(name))
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.sel = b:CreateTexture(nil, "OVERLAY")
    b.sel:SetPoint("TOPLEFT", -2, 2)
    b.sel:SetPoint("BOTTOMRIGHT", 2, -2)
    b.sel:SetColorTexture(0.2, 1, 0.6, 0.45)
    b.sel:SetDrawLayer("BACKGROUND")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.name = name
    b:SetScript("OnClick", function()
        if fly.kind then SetMacroIcon(fly.kind, name) end
        fly:Hide()
        mac:Refresh()
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(name, 1, 1, 1)
        if fly.kind and NS.MacroIconDefaults[fly.kind] == name then
            GameTooltip:AddLine(L["default for this state"], 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    fly.buttons[i] = b
end
local flyRows = math.ceil(#ICON_CHOICES / FLY_COLS)
-- sajat ikon nev (barmely Interface\Icons fajl)
local flyBox = CreateFrame("EditBox", nil, fly, "InputBoxTemplate")
flyBox:SetSize(FLY_COLS * FLY_SIZE - 70, 18)
flyBox:SetAutoFocus(false)
flyBox:SetPoint("TOPLEFT", 14, -12 - flyRows * FLY_SIZE)
local flyBoxHint = fly:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
flyBoxHint:SetPoint("LEFT", flyBox, "RIGHT", 6, 0)
flyBoxHint:SetText(L["other + Enter"])
flyBox:SetScript("OnEnterPressed", function(self)
    local v = self:GetText():match("^%s*(.-)%s*$")
    self:ClearFocus()
    if v == "" or not fly.kind then return end
    if IconId(v) == C.ICON_FALLBACK then
        NS.Loud(Print, L["Icon not found: %s (e.g. ability_hunter_snipershot)"], v)
        return
    end
    SetMacroIcon(fly.kind, v)
    fly:Hide()
    mac:Refresh()
end)
flyBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); fly:Hide() end)
local flyReset = CreateFrame("Button", nil, fly, "UIPanelButtonTemplate")
flyReset:SetSize(FLY_COLS * FLY_SIZE, 20)
flyReset:SetPoint("TOPLEFT", 8, -36 - flyRows * FLY_SIZE)
flyReset:SetText(L["Default"])
flyReset:SetScript("OnClick", function()
    if fly.kind then SetMacroIcon(fly.kind, nil) end
    fly:Hide()
    mac:Refresh()
end)
fly:SetSize(16 + FLY_COLS * FLY_SIZE, 66 + flyRows * FLY_SIZE)

local function OpenFly(slot)
    if fly:IsShown() and fly.kind == slot.kind then fly:Hide() return end
    fly.kind = slot.kind
    local cur = NS.MacroIconName(slot.kind)
    for _, b in ipairs(fly.buttons) do b.sel:SetShown(b.name:lower() == cur:lower()) end
    flyBox:SetText("")
    fly:ClearAllPoints()
    fly:SetPoint("TOPLEFT", slot, "TOPRIGHT", 8, 4)
    fly:Show()
end
pageMac:HookScript("OnHide", function() fly:Hide() end)

mac:Header(L["Macro icons"])
mac:Text(L["The AKit macro (and the panel) changes its icon by state. Click an icon to choose another one from the list "]
    .. L["opening to the side; right click: default."], 2)
local ICON_KINDS = {
    { kind = "hunt", label = L["Hunting: mobs / items to collect"] },
    { kind = "turnin", label = L["Turn-in: quest complete, go to the NPC"] },
    { kind = "idle", label = L["No quest selected"] },
}
for _, k in ipairs(ICON_KINDS) do
    local s = CreateFrame("Button", nil, pageMac)
    s:SetSize(30, 30)
    s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    s.kind = k.kind
    s.bg = s:CreateTexture(nil, "BACKGROUND")
    s.bg:SetAllPoints()
    s.bg:SetColorTexture(0, 0, 0, 0.5)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetPoint("TOPLEFT", 2, -2)
    s.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    s.label = OptLabel(pageMac, k.label, "GameFontHighlight")
    s.label:SetPoint("TOPLEFT", s, "TOPRIGHT", 10, -2)
    s.name = OptLabel(pageMac, "", "GameFontDisableSmall")
    s.name:SetPoint("TOPLEFT", s.label, "BOTTOMLEFT", 0, -3)
    s:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            SetMacroIcon(self.kind, nil)
            fly:Hide()
            mac:Refresh()
        else
            OpenFly(self)
        end
    end)
    s:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(k.label, 1, 1, 1)
        GameTooltip:AddLine(NS.MacroIconName(self.kind), 0.6, 0.6, 0.6)
        GameTooltip:AddLine(L["Click: choose · Right click: default"], 0.45, 0.45, 0.45)
        GameTooltip:Show()
    end)
    s:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mac:Place(s, 28, 8)
    mac:OnRefresh(function()
        local n = NS.MacroIconName(s.kind)
        s.icon:SetTexture(IconTexPath(n))
        local isDef = n == NS.MacroIconDefaults[s.kind]
        s.name:SetText(n .. (isDef and (" |cff808080(" .. L["default"] .. ")|r") or ""))
    end)
end

mac:Header(L["Marker"])
mac:Check(L["Own arrow"],
    L["An arrow pointing to the marker. Hidden when TomTom is installed: TomTom's arrow is used instead."],
    function() return not QuestFocusDB.noArrow end,
    function(v)
        QuestFocusDB.noArrow = not v
        if not v then arrow:Hide() elseif state.waypoint and UseOwnArrow() then arrow:Show() end
    end)
mac:Check(L["Star raid icon on the escorted NPC"],
    L["On an escort quest, puts a star raid icon on the NPC you escort when you target or mouse over it. Works solo and in a party; in a raid only as leader or assist. An icon that is already there is left alone."],
    function() return not QuestFocusDB.noEscortIcon end,
    function(v) QuestFocusDB.noEscortIcon = (not v) or nil end)
pageMac:HookScript("OnShow", function() mac:Refresh() end)

---------------------------------------------------------------------------
-- 50 Zone focus
---------------------------------------------------------------------------
local pageZone = AddOptionsTab(L["Zone focus"], 50)
local zon = OptFlow(pageZone)
zon:Text(L["Only quests of the current zone stay in the Questie tracker (plus the selected AKit quest). "]
    .. L["When you change zones it asks whether to switch to the new zone; turning it off restores everything. Minimap: right click."], 2)
local zoneBtn = zon:Button("", 220, nil, function() end, 2)
local zoneState = OptLabel(pageZone, "", "GameFontHighlightSmall")
zoneState:SetPoint("LEFT", zoneBtn, "RIGHT", 10, 0)
local function RefreshZoneBtn()
    local zf = QuestFocusDB.zoneFocus
    local here = GetRealZoneText and GetRealZoneText() or GetZoneText() or "?"
    if zf then
        zoneBtn:SetText(L["Turn off zone focus"])
        zoneState:SetText((L["Zone focus is |cff33ff99ON|r: %s"]):format(zf.zone or "?"))
    else
        zoneBtn:SetText((L["Focus on %s"]):format(here))
        zoneState:SetText(L["Zone focus is |cff808080off|r (all quests in the tracker)"])
    end
end
zoneBtn:SetScript("OnClick", function() ToggleZoneFocus(); RefreshZoneBtn() end)
zon:OnRefresh(RefreshZoneBtn)
zon:Check(L["Ask when entering a new zone (focus off)"],
    L["Zone focus is off and you enter a zone where you have quests: a popup asks whether to focus on that zone."],
    function() return not QuestFocusDB.noZonePrompt end,
    function(v) QuestFocusDB.noZonePrompt = not v end)
zon:Check(L["Switch without asking (focus on)"],
    L["Zone focus is on and you enter another zone where you have quests. Off: a popup asks Switch / Keep / Turn off focus. "]
    .. L["On: the tracker switches to the new zone right away. Zones without your quests never change the focus."],
    function() return QuestFocusDB.zoneAutoFollow end,
    function(v) QuestFocusDB.zoneAutoFollow = v end)
pageZone:HookScript("OnShow", function() zon:Refresh() end)

---------------------------------------------------------------------------
-- 90 Debug (sajat gorgetes)
---------------------------------------------------------------------------
local pageDebug = AddOptionsTab("Debug", 90, { noScroll = true })
local dbgScroll = CreateFrame("ScrollFrame", nil, pageDebug, "UIPanelScrollFrameTemplate")
dbgScroll:SetPoint("TOPLEFT", 0, -128)
dbgScroll:SetPoint("BOTTOMRIGHT", -26, 0)
local dbgChild = CreateFrame("Frame", nil, dbgScroll)
dbgChild:SetSize(460, 400)
dbgScroll:SetScrollChild(dbgChild)
local dbgText = dbgChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
dbgText:SetPoint("TOPLEFT")
dbgText:SetWidth(460)
dbgText:SetJustifyH("LEFT")
dbgText:SetJustifyV("TOP")
local function RefreshDebug()
    dbgText:SetText(table.concat(DebugLines(), "\n"))
    dbgChild:SetHeight(math.max(400, dbgText:GetStringHeight() + 10))
end
local dbgRefresh = CreateFrame("Button", nil, pageDebug, "UIPanelButtonTemplate")
dbgRefresh:SetSize(90, 22)
dbgRefresh:SetPoint("TOPLEFT")
dbgRefresh:SetText(L["Refresh"])
dbgRefresh:SetScript("OnClick", RefreshDebug)
local dbgChat = CreateFrame("Button", nil, pageDebug, "UIPanelButtonTemplate")
dbgChat:SetSize(110, 22)
dbgChat:SetPoint("LEFT", dbgRefresh, "RIGHT", 6, 0)
dbgChat:SetText(L["Print to chat"])
dbgChat:SetScript("OnClick", function() for _, l in ipairs(DebugLines()) do Print(l) end end)
-- Masolas: addon nem irhat a vagolapra, ezert egy kijelolheto szovegmezobe tesszuk
-- (mar kijelolve), amibol Ctrl+C-vel ki lehet masolni
local copyFrame = CreateFrame("Frame", "QuestFocusCopyFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
copyFrame:SetSize(560, 380)
copyFrame:SetPoint("CENTER")
copyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
copyFrame:EnableMouse(true)
copyFrame:SetMovable(true)
copyFrame:RegisterForDrag("LeftButton")
copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
copyFrame:Hide()
if copyFrame.SetBackdrop then
    copyFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 20,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    copyFrame:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
    copyFrame:SetBackdropBorderColor(0.95, 0.78, 0.40, 1)
end
local copyTitle = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
copyTitle:SetPoint("TOPLEFT", 14, -12)
copyTitle:SetText(L["Adventurer's Kit debug - press Ctrl+C to copy, then Esc"])
local copyClose = CreateFrame("Button", nil, copyFrame, "UIPanelCloseButton")
copyClose:SetPoint("TOPRIGHT", -4, -4)
local copyScroll = CreateFrame("ScrollFrame", "QuestFocusCopyScroll", copyFrame, "UIPanelScrollFrameTemplate")
copyScroll:SetPoint("TOPLEFT", 14, -36)
copyScroll:SetPoint("BOTTOMRIGHT", -32, 14)
local copyBox = CreateFrame("EditBox", nil, copyScroll)
copyBox:SetMultiLine(true)
copyBox:SetFontObject(ChatFontNormal)
copyBox:SetWidth(500)
copyBox:SetAutoFocus(false)
copyBox:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
-- csak olvashato: ha atirnad, visszaallitjuk
copyBox:SetScript("OnTextChanged", function(self, user)
    if user and self.text then self:SetText(self.text); self:HighlightText() end
end)
copyScroll:SetScrollChild(copyBox)

local function PlainText(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end

local function ShowCopy()
    local lines = {}
    for _, l in ipairs(DebugLines()) do lines[#lines + 1] = PlainText(l) end
    local text = table.concat(lines, "\n")
    copyBox.text = text
    copyBox:SetText(text)
    copyFrame:Show()
    copyBox:SetFocus()
    copyBox:HighlightText()
    copyScroll:SetVerticalScroll(0)
end
NS.ShowCopy = ShowCopy

local dbgCopy = CreateFrame("Button", nil, pageDebug, "UIPanelButtonTemplate")
dbgCopy:SetSize(70, 22)
dbgCopy:SetPoint("LEFT", dbgChat, "RIGHT", 6, 0)
dbgCopy:SetText(L["Copy"])
dbgCopy:SetScript("OnClick", ShowCopy)
local dbgClear = CreateFrame("Button", nil, pageDebug, "UIPanelButtonTemplate")
dbgClear:SetSize(100, 22)
dbgClear:SetPoint("LEFT", dbgCopy, "RIGHT", 6, 0)
dbgClear:SetText(L["Clear errors"])
dbgClear:SetScript("OnClick", function() wipe(NS.errors); RefreshDebug() end)

local cbErrors = OptCheck(L["Lua error popup for Adventurer's Kit errors"],
    L["Off: our errors don't open the error window, they are only listed here (and one line in chat). "]
    .. L["On: the normal Lua error window shows them too. Other addons are not affected."],
    function() return QuestFocusDB.showErrors end,
    function(v) QuestFocusDB.showErrors = v end, pageDebug)
cbErrors:SetPoint("TOPLEFT", dbgRefresh, "BOTTOMLEFT", -2, -6)
local dbgLive = Desc(pageDebug, L["Live: refreshes every 0.5 s while open. Copy: select all text for Ctrl+C."])
dbgLive:SetPoint("BOTTOMLEFT", dbgScroll, "TOPLEFT", 0, 8)
local dbgElapsed = 0
pageDebug:SetScript("OnShow", function() cbErrors.refresh(); RefreshDebug() end)
pageDebug:SetScript("OnUpdate", function(_, dt)
    dbgElapsed = dbgElapsed + dt
    if dbgElapsed > 0.5 then dbgElapsed = 0; RefreshDebug() end
end)

opt:SetScript("OnShow", function()
    LayoutTabs()
    SelectTab(selectedKey)
end)

if Settings and Settings.RegisterCanvasLayoutCategory then
    optCategory = Settings.RegisterCanvasLayoutCategory(opt, "Adventurer's Kit")
    Settings.RegisterAddOnCategory(optCategory)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(opt)
end

OpenOptions = function()
    if InCombatLockdown() then Print(L["Open it after combat."]) return end
    if optCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(optCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(opt)
        InterfaceOptionsFrame_OpenToCategory(opt)
    end
end

-- Megnyitas egy adott fulon (pl. /ak notes)
NS.OpenOptionsTab = function(label)
    selectedKey = label
    OpenOptions()
    if opt:IsShown() then SelectTab(label) end
end

-- belso exportok a tobbi core fajlnak
NS.opt = opt
NS.C.OpenOptions, NS.C.OptCheck, NS.C.RebuildMacro, NS.C.SetSpell, NS.C.ShowCopy, NS.C.UpdateMinimapButton, NS.C.opt, NS.C.optNote = OpenOptions, OptCheck, RebuildMacro, SetSpell, ShowCopy, UpdateMinimapButton, opt, nil
