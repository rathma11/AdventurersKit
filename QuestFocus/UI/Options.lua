local ADDON_NAME, NS = ...
local L = NS.L
NS.C = NS.C or {}
local C = NS.C
local arrow, DebugLines, ICON_HUNT, Panel_Update, Print, state, ToggleZoneFocus, UpdateMacro = C.arrow, C.DebugLines, C.ICON_HUNT, C.Panel_Update, C.Print, C.state, C.ToggleZoneFocus, C.UpdateMacro
local UseOwnArrow = C.UseOwnArrow

---------------------------------------------------------------------------
-- Beallitasok (Options > AddOns > QuestFocus)
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

local function OptLabel(parent, text, template)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

local function OptCheck(label, tip, get, set, parent)
    local cb = CreateFrame("CheckButton", nil, parent or opt.pageMain, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb.label = OptLabel(cb, label)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine(tip, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cb.refresh = function() cb:SetChecked(get()) end
    return cb
end

local optTitle = OptLabel(opt, "QuestFocus", "GameFontNormalLarge")
optTitle:SetPoint("TOPLEFT", 16, -16)
local optSub = OptLabel(opt, L["QFocus macro and marker settings. Everything is optional."], "GameFontHighlightSmall")
optSub:SetPoint("TOPLEFT", optTitle, "BOTTOMLEFT", 0, -6)

-- Fulek: Beallitasok / Debug
local pageMain = CreateFrame("Frame", nil, opt)
pageMain:SetPoint("TOPLEFT", optSub, "BOTTOMLEFT", 0, -40)
pageMain:SetPoint("BOTTOMRIGHT", opt, "BOTTOMRIGHT", -16, 16)
local pageDebug = CreateFrame("Frame", nil, opt)
pageDebug:SetAllPoints(pageMain)
pageDebug:Hide()

local tabs = {}
local function SelectTab(i)
    for n, t in ipairs(tabs) do
        if n == i then t:Disable() else t:Enable() end
        t.page:SetShown(n == i)
    end
end
for i, def in ipairs({ { L["Settings"], pageMain }, { "Debug", pageDebug } }) do
    local t = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate")
    t:SetSize(110, 22)
    t:SetText(def[1])
    t.page = def[2]
    t:SetPoint("TOPLEFT", optSub, "BOTTOMLEFT", (i - 1) * 114, -10)
    t:SetScript("OnClick", function() SelectTab(i) end)
    tabs[i] = t
end
opt.pageMain = pageMain

-- Uj ful a tobbi fajlnak (QuestFocusPlanner.lua, QuestFocusBuffs.lua)
NS.AddOptionsTab = function(label)
    local page = CreateFrame("Frame", nil, opt)
    page:SetAllPoints(pageMain)
    page:Hide()
    local i = #tabs + 1
    local t = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate")
    t:SetSize(110, 22)
    t:SetText(label)
    t.page = page
    t:SetPoint("TOPLEFT", optSub, "BOTTOMLEFT", (i - 1) * 114, -10)
    t:SetScript("OnClick", function() SelectTab(i) end)
    tabs[i] = t
    return page
end

-- Spell a tapeleshez
local cbSpell = OptCheck(L["Spell in the macro (tagging)"],
    L["When enabled, the QFocus macro also casts the chosen spell on the mob after targeting it. "]
    .. L["It does not cast at turn-in (friendly NPC)."],
    function() return QuestFocusDB.useSpell end,
    function(v) QuestFocusDB.useSpell = v; RebuildMacro() end)
cbSpell:SetPoint("TOPLEFT", pageMain, "TOPLEFT", -2, 0)

local spellSlot = CreateFrame("Button", nil, pageMain)
spellSlot:SetSize(36, 36)
spellSlot:SetPoint("TOPLEFT", cbSpell, "BOTTOMLEFT", 26, -8)
spellSlot.bg = spellSlot:CreateTexture(nil, "BACKGROUND")
spellSlot.bg:SetAllPoints()
spellSlot.bg:SetColorTexture(0, 0, 0, 0.5)
spellSlot.icon = spellSlot:CreateTexture(nil, "ARTWORK")
spellSlot.icon:SetPoint("TOPLEFT", 2, -2)
spellSlot.icon:SetPoint("BOTTOMRIGHT", -2, 2)
spellSlot:RegisterForClicks("LeftButtonUp", "RightButtonUp")

local spellBox = CreateFrame("EditBox", nil, pageMain, "InputBoxTemplate")
spellBox:SetSize(200, 20)
spellBox:SetAutoFocus(false)
spellBox:SetPoint("LEFT", spellSlot, "RIGHT", 14, 6)
local spellHint = OptLabel(pageMain,L["Drag a spell here from your spellbook (P), or type its name + Enter. Right click: clear."],
    "GameFontDisableSmall")
spellHint:SetPoint("TOPLEFT", spellBox, "BOTTOMLEFT", -4, -4)
spellHint:SetWidth(360)

local function RefreshSpellUI()
    local s = QuestFocusDB.spell
    spellBox:SetText(s or "")
    spellSlot.icon:SetTexture(SpellIcon(s) or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
end

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

local cbAttack = OptCheck("Autoattack (/startattack)",
    L["Also starts auto attack after targeting (melee / wand / bow)."],
    function() return QuestFocusDB.startAttack end,
    function(v) QuestFocusDB.startAttack = v; RebuildMacro() end)
cbAttack:SetPoint("TOPLEFT", spellSlot, "BOTTOMLEFT", -26, -28)

local cbPing = OptCheck(L["Ping the target"],
    L["The macro pings the target at the end (ping system); party members see it too."],
    function() return not QuestFocusDB.noPing end,
    function(v) QuestFocusDB.noPing = not v; RebuildMacro() end)
cbPing:SetPoint("TOPLEFT", cbAttack, "BOTTOMLEFT", 0, -6)

local cbArrow = OptCheck(L["Own arrow"],
    L["Arrow pointing to the marker (hidden when TomTom is installed, TomTom's arrow is used instead)."],
    function() return not QuestFocusDB.noArrow end,
    function(v)
        QuestFocusDB.noArrow = not v
        if not v then arrow:Hide() elseif state.waypoint and UseOwnArrow() then arrow:Show() end
    end)
cbArrow:SetPoint("TOPLEFT", cbPing, "BOTTOMLEFT", 0, -6)

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
mmBtn:SetScript("OnClick", function(_, button)
    if button == "RightButton" then ToggleZoneFocus() else OpenOptions() end
end)
mmBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("QuestFocus", 0.2, 1, 0.6)
    if state.title then GameTooltip:AddLine("Quest: " .. state.title, 1, 1, 1) end
    local zf = QuestFocusDB and QuestFocusDB.zoneFocus
    GameTooltip:AddLine(L["Zone focus: "] .. (zf and (zf.zone or "?") or L["off"]), 1, 0.82, 0)
    GameTooltip:AddLine(L["Left click: settings"], 0.6, 0.6, 0.6)
    GameTooltip:AddLine(L["Right click: zone focus on/off"], 0.6, 0.6, 0.6)
    GameTooltip:AddLine(L["Drag: move"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
mmBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Zona fokusz gomb a beallitasokban
local zoneBtn = CreateFrame("Button", nil, pageMain, "UIPanelButtonTemplate")
zoneBtn:SetSize(220, 24)
zoneBtn:SetPoint("TOPLEFT", cbArrow, "BOTTOMLEFT", 4, -14)
local zoneHint = OptLabel(pageMain, L["Only quests of the current zone stay in the Questie tracker (plus the selected QFocus quest). "]
    .. L["Follows you when you change zones; turning it off restores everything. Minimap: right click."], "GameFontDisableSmall")
zoneHint:SetPoint("TOPLEFT", zoneBtn, "BOTTOMLEFT", 0, -4)
zoneHint:SetWidth(420)
-- Allapot a gomb mellett, hogy egyertelmu legyen: be van-e kapcsolva, es melyik zonara
local zoneState = OptLabel(pageMain, "", "GameFontHighlightSmall")
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

local cbZoneAsk = OptCheck(L["Ask when entering a new zone"],
    L["When you enter a zone where you have quests, a popup asks whether to focus on that zone."],
    function() return not QuestFocusDB.noZonePrompt end,
    function(v) QuestFocusDB.noZonePrompt = not v end)
cbZoneAsk:SetPoint("TOPLEFT", zoneHint, "BOTTOMLEFT", -6, -8)

local cbMinimap = OptCheck(L["Minimap button"],
    L["Left click: settings, right click: zone focus. Drag to move."],
    function() return not QuestFocusDB.hideMinimap end,
    function(v) QuestFocusDB.hideMinimap = not v; UpdateMinimapButton() end)
cbMinimap:SetPoint("TOPLEFT", cbZoneAsk, "BOTTOMLEFT", 0, -6)

local optNote = OptLabel(pageMain, L["The macro can't be changed in combat; changes apply after combat."],
    "GameFontDisableSmall")
optNote:SetPoint("TOPLEFT", cbMinimap, "BOTTOMLEFT", 2, -16)

-- Debug ful
local dbgScroll = CreateFrame("ScrollFrame", nil, pageDebug, "UIPanelScrollFrameTemplate")
dbgScroll:SetPoint("TOPLEFT", 0, -60)
dbgScroll:SetPoint("BOTTOMRIGHT", -26, 0)
local dbgChild = CreateFrame("Frame", nil, dbgScroll)
dbgChild:SetSize(560, 400)
dbgScroll:SetScrollChild(dbgChild)
local dbgText = dbgChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
dbgText:SetPoint("TOPLEFT")
dbgText:SetWidth(560)
dbgText:SetJustifyH("LEFT")
dbgText:SetJustifyV("TOP")
local function RefreshDebug()
    dbgText:SetText(table.concat(DebugLines(), "\n"))
    dbgChild:SetHeight(math.max(400, dbgText:GetStringHeight() + 10))
end
local dbgRefresh = CreateFrame("Button", nil, pageDebug, "UIPanelButtonTemplate")
dbgRefresh:SetSize(100, 22)
dbgRefresh:SetPoint("TOPLEFT")
dbgRefresh:SetText(L["Refresh"])
dbgRefresh:SetScript("OnClick", RefreshDebug)
local dbgChat = CreateFrame("Button", nil, pageDebug, "UIPanelButtonTemplate")
dbgChat:SetSize(120, 22)
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
dbgCopy:SetSize(80, 22)
dbgCopy:SetPoint("LEFT", dbgChat, "RIGHT", 6, 0)
dbgCopy:SetText(L["Copy"])
dbgCopy:SetScript("OnClick", ShowCopy)

local dbgLive = OptLabel(pageDebug, L["Live: refreshes every 0.5 s while open."], "GameFontDisableSmall")
dbgLive:SetPoint("LEFT", dbgCopy, "RIGHT", 10, 0)

local cbErrors = OptCheck(L["Lua error popup for QuestFocus errors"],
    L["Off: QuestFocus errors don't open the error window, they are only listed here (and one line in chat). "]
    .. L["On: the normal Lua error window shows them too. Other addons are not affected."],
    function() return QuestFocusDB.showErrors end,
    function(v) QuestFocusDB.showErrors = v end, pageDebug)
cbErrors:SetPoint("TOPLEFT", dbgRefresh, "BOTTOMLEFT", -2, -4)
local dbgClear = CreateFrame("Button", nil, pageDebug, "UIPanelButtonTemplate")
dbgClear:SetSize(110, 22)
dbgClear:SetPoint("LEFT", cbErrors.label, "RIGHT", 16, 0)
dbgClear:SetText(L["Clear errors"])
dbgClear:SetScript("OnClick", function() wipe(NS.errors); RefreshDebug() end)
local dbgElapsed = 0
pageDebug:SetScript("OnShow", function() cbErrors.refresh(); RefreshDebug() end)
pageDebug:SetScript("OnUpdate", function(_, dt)
    dbgElapsed = dbgElapsed + dt
    if dbgElapsed > 0.5 then dbgElapsed = 0; RefreshDebug() end
end)

opt:SetScript("OnShow", function()
    for _, cb in ipairs({ cbSpell, cbAttack, cbPing, cbArrow, cbMinimap, cbZoneAsk }) do cb.refresh() end
    RefreshSpellUI()
    RefreshZoneBtn()
    SelectTab(1)
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


-- belso exportok a tobbi core fajlnak
NS.C.OpenOptions, NS.C.OptCheck, NS.C.RebuildMacro, NS.C.SetSpell, NS.C.ShowCopy, NS.C.UpdateMinimapButton, NS.C.opt, NS.C.optNote = OpenOptions, OptCheck, RebuildMacro, SetSpell, ShowCopy, UpdateMinimapButton, opt, optNote
