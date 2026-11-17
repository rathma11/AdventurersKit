local ADDON_NAME, NS = ...
local L = NS.L
NS.C = NS.C or {}
local C = NS.C
local arrow, DebugLines, ICON_HUNT, Panel_Update, Print, state, ToggleZoneFocus, UpdateMacro = C.arrow, C.DebugLines, C.ICON_HUNT, C.Panel_Update, C.Print, C.state, C.ToggleZoneFocus, C.UpdateMacro
local UseOwnArrow = C.UseOwnArrow

---------------------------------------------------------------------------
-- Beallitasok (Options > AddOns > QuestFocus)
-- Bal oldalon fuggoleges fulek feature-onkent (sorrend: order), jobb oldalon a
-- gorgetheto oldal. Minden kapcsolo alatt rovid, szurke leiras.
-- Oldal sorrend:  10 General · 20 Macro & marker · 30 Route & progress · 40 Quest pickup
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
opt.name = "QuestFocus"
local optCategory

local TAB_W, DESC_W = 130, 420

local function OptLabel(parent, text, template)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

local optTitle = OptLabel(opt, "QuestFocus", "GameFontNormalLarge")
optTitle:SetPoint("TOPLEFT", 16, -16)
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
        -- tartalom magassaga: a legalso elem alja (megjeleneskor merjuk)
        holder:SetScript("OnShow", function()
            C_Timer.After(0, function()
                local top, low = content:GetTop(), nil
                if not top then return end
                local function scan(...)
                    for i = 1, select("#", ...) do
                        local r = select(i, ...)
                        if r:IsShown() and r:GetBottom() then
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
        end)
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
    GameTooltip:SetText("QuestFocus", 0.2, 1, 0.6)
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
    L["The QuestFocus panel with the selected quest, its objectives and the time left. Same as typing /qf."],
    function() return not QuestFocusDB.hidePanel end,
    function(v) QuestFocusDB.hidePanel = not v; Panel_Update() end)
gen:Number(L["Font size"],
    L["Text size on the panel (8-20, default 10). Resizing the panel does not change it. Press Enter to apply."],
    function() return NS.FontSize and NS.FontSize() or 10 end,
    function(v)
        QuestFocusDB.fontSize = math.max(8, math.min(20, v))
        if NS.ApplyFontSize then NS.ApplyFontSize() end
        Panel_Update()
    end)
gen:Header(L["Chat"])
gen:Check(L["Chat messages"],
    L["Status messages in chat (marker moved, quest complete, buff warnings, ...). Off: only one line at login "]
    .. L["and the replies to your own /qf commands and button clicks. Toggle: /qf chat."],
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
mac:Text(L["The QFocus macro targets the mobs of the selected objective. Put it on your bars once; it updates itself. "]
    .. L["The macro can't be changed in combat; changes apply after combat."], 2)
mac:Header(L["QFocus macro"])
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
mac:Check(L["Ping the target"],
    L["The macro pings the target at the end (ping system); party members see it too."],
    function() return not QuestFocusDB.noPing end,
    function(v) QuestFocusDB.noPing = not v; RebuildMacro() end)
mac:Check(L["Also target mobs of other nearby quests"],
    L["Mobs of other quests in your log within ~200 yards are added to the macro too, "]
    .. L["and listed on the panel under ALSO NEARBY (click one to focus that quest)."],
    function() return not QuestFocusDB.noNearbyQuests end,
    function(v)
        QuestFocusDB.noNearbyQuests = not v
        if not v then state.extra = nil end
        Panel_Update()
    end)

-- Makro ikon (ugyanaz, mint /qf icon)
local iconLabel = OptLabel(pageMac, L["Macro icon"], "GameFontHighlightSmall")
local iconBox = CreateFrame("EditBox", nil, pageMac, "InputBoxTemplate")
iconBox:SetSize(200, 18)
iconBox:SetAutoFocus(false)
iconBox:SetPoint("LEFT", iconLabel, "RIGHT", 10, 0)
local iconDesc = Desc(pageMac, L["Icon file name, e.g. ability_hunter_snipershot. Empty + Enter: automatic (crosshair, letter at turn-in)."])
iconDesc:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", 0, -6)
mac:Place(iconLabel, 28, 12, iconDesc, 28)
iconBox:SetScript("OnEnterPressed", function(self)
    local v = self:GetText():match("^%s*(.-)%s*$")
    SlashCmdList.QUESTFOCUS(v ~= "" and ("icon " .. v) or "icon")
    self:SetText(QuestFocusDB.icon or "")
    self:ClearFocus()
end)
iconBox:SetScript("OnEscapePressed", function(self) self:SetText(QuestFocusDB.icon or ""); self:ClearFocus() end)
mac:OnRefresh(function() iconBox:SetText(QuestFocusDB.icon or "") end)

mac:Header(L["Marker"])
mac:Check(L["Own arrow"],
    L["An arrow pointing to the marker. Hidden when TomTom is installed: TomTom's arrow is used instead."],
    function() return not QuestFocusDB.noArrow end,
    function(v)
        QuestFocusDB.noArrow = not v
        if not v then arrow:Hide() elseif state.waypoint and UseOwnArrow() then arrow:Show() end
    end)
pageMac:HookScript("OnShow", function() mac:Refresh() end)

---------------------------------------------------------------------------
-- 50 Zone focus
---------------------------------------------------------------------------
local pageZone = AddOptionsTab(L["Zone focus"], 50)
local zon = OptFlow(pageZone)
zon:Text(L["Only quests of the current zone stay in the Questie tracker (plus the selected QFocus quest). "]
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
copyTitle:SetText(L["QuestFocus debug - press Ctrl+C to copy, then Esc"])
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

local cbErrors = OptCheck(L["Lua error popup for QuestFocus errors"],
    L["Off: QuestFocus errors don't open the error window, they are only listed here (and one line in chat). "]
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
    optCategory = Settings.RegisterCanvasLayoutCategory(opt, "QuestFocus")
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

-- Megnyitas egy adott fulon (pl. /qf notes)
NS.OpenOptionsTab = function(label)
    selectedKey = label
    OpenOptions()
    if opt:IsShown() then SelectTab(label) end
end

-- belso exportok a tobbi core fajlnak
NS.opt = opt
NS.C.OpenOptions, NS.C.OptCheck, NS.C.RebuildMacro, NS.C.SetSpell, NS.C.ShowCopy, NS.C.UpdateMinimapButton, NS.C.opt, NS.C.optNote = OpenOptions, OptCheck, RebuildMacro, SetSpell, ShowCopy, UpdateMinimapButton, opt, nil
