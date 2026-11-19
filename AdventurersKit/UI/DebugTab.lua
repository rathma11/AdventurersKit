-- Options > Debug ful: szekcionkent naplo kapcsolo + "Copy debug", "Copy all", es a masolo ablak
-- (kijelolheto szovegmezo: addon nem irhat a vagolapra, Ctrl+C-vel lehet kimasolni).
-- A szekciok, a naplo es a szoveg: Core\DebugLog.lua. A pillanatkepek a modulok fajljaiban.
local ADDON_NAME, NS = ...
local L = NS.L
local S = NS.Style

---------------------------------------------------------------------------
-- Masolo ablak (nagy ablak: DESIGN.md)
---------------------------------------------------------------------------
local copy = CreateFrame("Frame", "QuestFocusCopyFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
copy:SetSize(620, 420)
copy:SetPoint("CENTER")
copy:SetFrameStrata("FULLSCREEN_DIALOG")
copy:SetToplevel(true)
copy:Hide()
S.Backdrop(copy, "window")
S.Draggable(copy, "copyPos")
copy.icon = copy:CreateTexture(nil, "ARTWORK")
copy.icon:SetSize(20, 20)
copy.icon:SetPoint("TOPLEFT", 12, -11)
copy.icon:SetTexture(NS.ICON)
copy.title = copy:CreateFontString(nil, "OVERLAY", "GameFontNormal")
copy.title:SetPoint("LEFT", copy.icon, "RIGHT", 6, 0)
copy.title:SetTextColor(S.TITLE[1], S.TITLE[2], S.TITLE[3])
copy.close = S.CloseButton(copy, true)
copy.hint = copy:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
copy.hint:SetPoint("TOPLEFT", copy.icon, "BOTTOMLEFT", 0, -6)
copy.hint:SetText(L["The text is selected: press Ctrl+C to copy it, then Esc. Paste it into the bug report."])
local div = S.Divider(copy)
div:SetPoint("TOPLEFT", copy.hint, "BOTTOMLEFT", 0, -6)
div:SetPoint("RIGHT", copy, "RIGHT", -12, 0)

local copyScroll = CreateFrame("ScrollFrame", "QuestFocusCopyScroll", copy)
copyScroll:SetPoint("TOPLEFT", div, "BOTTOMLEFT", 0, -6)
copyScroll:SetPoint("BOTTOMRIGHT", copy, "BOTTOMRIGHT", -22, 44)
copyScroll:EnableMouseWheel(true)
local copyBox = CreateFrame("EditBox", nil, copyScroll)
copyBox:SetMultiLine(true)
copyBox:SetFontObject(ChatFontNormal)
copyBox:SetWidth(570)
copyBox:SetAutoFocus(false)
copyBox:SetScript("OnEscapePressed", function() copy:Hide() end)
-- csak olvashato: ha atirnad, visszaallitjuk
copyBox:SetScript("OnTextChanged", function(self, user)
    if user and self.text then self:SetText(self.text); self:HighlightText() end
end)
copyScroll:SetScrollChild(copyBox)
local bar = S.ScrollBar(copyScroll)
copyScroll:SetScript("OnMouseWheel", function(self, d)
    local max = self:GetVerticalScrollRange() or 0
    self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - d * 40)))
    if bar and bar.Update then bar.Update() end
end)
copyBox:SetScript("OnCursorChanged", function(_, _, y, _, h)
    -- a kurzor (billentyuzettel lapozva) mindig latszodjon
    local top, view = copyScroll:GetVerticalScroll() or 0, copyScroll:GetHeight() or 0
    y = -(y or 0)
    if y < top then copyScroll:SetVerticalScroll(y)
    elseif y + (h or 0) > top + view then copyScroll:SetVerticalScroll(y + (h or 0) - view) end
    if bar and bar.Update then bar.Update() end
end)
tinsert(UISpecialFrames, "QuestFocusCopyFrame")

-- gombok alul: frissites (ugyanaz a szekcio ujra), kijeloles ujra, bezaras
local refreshBtn = S.ActionButton(copy, L["Refresh"], "primary", 120)
local selectBtn = S.ActionButton(copy, L["Select all"], nil, 120)
local closeBtn = S.ActionButton(copy, L["Close"], nil, 120)
refreshBtn:SetPoint("BOTTOMLEFT", copy, "BOTTOMLEFT", 12, 12)
selectBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 6, 0)
closeBtn:SetPoint("BOTTOMRIGHT", copy, "BOTTOMRIGHT", -12, 12)
selectBtn:SetScript("OnClick", function() copyBox:SetFocus(); copyBox:HighlightText() end)
closeBtn:SetScript("OnClick", function() copy:Hide() end)

local copyKey -- a mostani tartalom: szekcio kulcs vagy "all"
local function CopyText(key)
    if key == "all" then return NS.DebugTextAll() end
    return NS.DebugText(key)
end

-- key: szekcio kulcs ("target", ...) vagy "all"; nil = targeting (a regi /ak copy)
local function ShowCopy(key)
    key = key or "target"
    copyKey = key
    local s = NS.DebugSection(key)
    copy.title:SetText((L["Adventurer's Kit debug: %s"]):format(key == "all" and L["all sections"] or (s and L[s.title] or key)))
    local text = CopyText(key)
    copyBox.text = text
    copyBox:SetText(text)
    if not S.RestorePos(copy, "copyPos") then copy:ClearAllPoints(); copy:SetPoint("CENTER") end
    copy:Show()
    copyBox:SetFocus()
    copyBox:HighlightText()
    copyScroll:SetVerticalScroll(0)
    if bar and bar.Update then C_Timer.After(0, bar.Update) end
end
refreshBtn:SetScript("OnClick", function() if copyKey then ShowCopy(copyKey) end end)
NS.ShowCopy = ShowCopy
NS.C.ShowCopy = ShowCopy

---------------------------------------------------------------------------
-- 90 Debug ful
---------------------------------------------------------------------------
if not (NS.AddOptionsTab and NS.OptFlow) then return end
local page = NS.AddOptionsTab("Debug", 90)
local o = NS.OptFlow(page)
o:Header(L["Debug sections"])
o:Text(L["Every feature has its own debug section: a snapshot of what it sees now, plus a log of its decisions while "]
    .. L["its switch is on (the last 200 lines, cleared by /reload). A switched off log costs nothing. "]
    .. L["Turn on the part that misbehaves, play until it happens, then Copy debug and paste it into the bug report."], 2)

-- felso gombsor: minden naplo be / ki, Copy all (fo gomb), naplok torlese, hibak torlese
local enableAll = S.ActionButton(page, L["Enable all"], nil, 110)
local copyAll = S.ActionButton(page, L["Copy all"], "primary", 110)
local clearLogs = S.ActionButton(page, L["Clear logs"], nil, 110)
local clearErr = S.ActionButton(page, L["Clear errors"], nil, 110)
o:Place(enableAll, 2, 10)
copyAll:SetPoint("LEFT", enableAll, "RIGHT", 6, 0)
clearLogs:SetPoint("LEFT", copyAll, "RIGHT", 6, 0)
clearErr:SetPoint("LEFT", clearLogs, "RIGHT", 6, 0)
local function Tip(b, title, desc)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(desc, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
Tip(enableAll, L["Enable all"], L["Turns on the log of every section (when all are on, the button turns them all off). Same as /ak debug all on | off."])
Tip(copyAll, L["Copy all"], L["Every section's snapshot and log in one text, ready to copy. Same as /ak copy all."])
Tip(clearLogs, L["Clear logs"], L["Empties the log of every section (the switches stay as they are)."])
Tip(clearErr, L["Clear errors"], L["Empties the Lua error list (General section)."])
copyAll:SetScript("OnClick", function() ShowCopy("all") end)

o:Check(L["Lua error popup for Adventurer's Kit errors"],
    L["Off: our errors don't open the error window, they are only listed in the General section (and one line in chat). "]
    .. L["On: the normal Lua error window shows them too. Other addons are not affected."],
    function() return QuestFocusDB.showErrors end,
    function(v) QuestFocusDB.showErrors = v end)

o:Header(L["Sections"])
local rows = {}
local ROW_W = 470
for _, s in ipairs(NS.DEBUG_SECTIONS) do
    local key = s.key
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(ROW_W, 40)
    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", -2, 0)
    cb:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        NS.SetDebugOn(key, on)
        NS.Debug(key, "log switched on")
        row.refresh()
    end)
    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Log"] .. ": " .. L[s.title], 1, 1, 1)
        GameTooltip:AddLine((L["On: this part writes its decisions into the log (the last %d lines). Same as /ak debug %s on | off."])
            :format(NS.DEBUG_LOG_MAX, key), 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local title = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    title:SetText(L[s.title])
    local keyText = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    keyText:SetPoint("LEFT", title, "RIGHT", 6, 0)
    local desc = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetTextColor(S.DESC[1], S.DESC[2], S.DESC[3])
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    desc:SetWidth(ROW_W - 150)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(false)
    desc:SetText(L[s.desc])
    local btn = S.ActionButton(row, L["Copy debug"], nil, 110, 22)
    btn:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
    btn:SetScript("OnClick", function() ShowCopy(key) end)
    Tip(btn, L["Copy debug"], (L["%s: snapshot + log in the copy window. Same as /ak copy %s."]):format(L[s.title], key))
    row.refresh = function()
        local on = NS.DebugOn(key)
        cb:SetChecked(on)
        local n = NS.DebugCount(key)
        keyText:SetText(("[%s]%s"):format(key, (on or n > 0) and ("  " .. (L["log: %s, %d lines"]):format(on and L["on"] or L["off"], n)) or ""))
    end
    o:Place(row, 2, 6)
    o:OnRefresh(row.refresh)
    rows[#rows + 1] = row
end
o:Text(L["Chat: /ak debug <section> prints a snapshot; /ak debug <section> on | off switches its log; /ak copy <section> | all opens the copy window. Plain /ak debug: targeting."], 2)

-- Enable all: mind be; ha mar mind be van, a gomb "Disable all" (mind ki)
local function RefreshEnableAll()
    enableAll.text:SetText(NS.DebugAllOn() and L["Disable all"] or L["Enable all"])
end
o:OnRefresh(RefreshEnableAll)
enableAll:SetScript("OnClick", function()
    NS.SetDebugAll(not NS.DebugAllOn())
    o:Refresh()
end)

clearLogs:SetScript("OnClick", function()
    for _, s in ipairs(NS.DEBUG_SECTIONS) do NS.DebugClear(s.key) end
    o:Refresh()
end)
clearErr:SetScript("OnClick", function() wipe(NS.errors); o:Refresh() end)

page:HookScript("OnShow", function() o:Refresh() end)
-- a sorok szamlaloja nyitva frissul (masodpercenkent)
local el = 0
page:HookScript("OnUpdate", function(_, dt)
    el = el + dt
    if el < 1 then return end
    el = 0
    for _, r in ipairs(rows) do r.refresh() end
    RefreshEnableAll()
end)
