local ADDON_NAME, NS = ...
local L = NS.L

---------------------------------------------------------------------------
-- Ping a AKit makroban: mod beallitasa (on / off / ask) es a csapatba lepeskori kerdes.
-- A kerdo ablakban is atallithato, mi legyen legkozelebb (mindig / soha / kerdezze).
---------------------------------------------------------------------------
local function RefreshMacro()
    local state = NS.C.state
    if state then state.lastBody = nil end
    if state and state.questId and NS.C.UpdateMacro then NS.C.UpdateMacro() end
    if NS.Panel_Update then NS.Panel_Update() end
end

NS.SetPingMode = function(m)
    if m ~= "on" and m ~= "off" and m ~= "ask" then return end
    QuestFocusDB.pingMode = m
    QuestFocusDB.noPing = (m == "off") or nil -- regi kulcs (export / regi verzio)
    RefreshMacro()
    if NS.RefreshPingUI then NS.RefreshPingUI() end
end

local MODES = {
    { "ask", L["Ask when I join a group"] },
    { "on", L["Always ping"] },
    { "off", L["Never ping"] },
}
NS.PING_MODES = MODES

-- Kerdo ablak (NS.Style, DESIGN.md): box hatter, narancs csik, kis nagybetus fejlec, X.
-- Nagy kerdes sor, alatta ket egyforma szeles valasz gomb (Ping = primary), szurke magyarazat,
-- majd "NEXT TIME I JOIN A GROUP" szekcio egy egyforma szeles, harom reszes valasztoval.
local S = NS.Style
local W, PAD = 300, 12
local f = S.Box("AdventurersKitPingAsk", W, 200, L["AKIT PING"], "DIALOG")
f:SetPoint("TOP", UIParent, "TOP", 0, -160)
f:SetBackdropColor(S.BOX_BG[1], S.BOX_BG[2], S.BOX_BG[3], 0.94) -- dialog: kicsit tomorebb
f:EnableMouse(true)
f:SetMovable(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)

local question = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
question:SetPoint("TOPLEFT", PAD, -28)
question:SetWidth(W - 2 * PAD)
question:SetJustifyH("LEFT")
question:SetText(L["Ping your target in this group?"])

-- (masik ablakokhoz is: pl. a dungeon quest megosztas; ugyanaz, mint S.FlatButton)
NS.FlatButton = function(parent, text, w, h) return S.FlatButton(parent, text, w, h) end

-- 1) valasz erre a csapatra: ket egyforma gomb, a ping a fo valasz
local yes = S.ActionButton(f, L["Ping in this group"], "primary")
local no = S.ActionButton(f, L["No ping"], "secondary")
S.ButtonRow(f, { yes, no }, question, -10, 6)

local sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
sub:SetPoint("TOPLEFT", yes, "BOTTOMLEFT", 0, -6)
sub:SetWidth(W - 2 * PAD)
sub:SetJustifyH("LEFT")
sub:SetText(L["You joined a group: they see the AKit macro's pings. Solo it always pings."])

local line = S.Divider(f)
line:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -10)
line:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)

-- 2) legkozelebb: harom reszes, egyforma szeles valaszto (egyszerre egy)
local nextLbl = S.Section(f, L["NEXT TIME I JOIN A GROUP"])
nextLbl:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -8)
local SHORT = { ask = L["Ask"], on = L["Always ping"], off = L["Never ping"] }
local items, DESC = {}, {}
for _, m in ipairs(MODES) do
    items[#items + 1] = { m[1], SHORT[m[1]] or m[2] }
    DESC[m[1]] = m[2]
end
local seg = S.Segmented(f, items, 90, 22, 4)
S.ButtonRow(f, seg.buttons, nextLbl, -5, 4)
local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("TOPLEFT", seg.buttons[1], "BOTTOMLEFT", 0, -6)
hint:SetWidth(W - 2 * PAD)
hint:SetJustifyH("LEFT")
local HINT = {
    ask = L["Asks like this every time you join a group."],
    on = L["Always pings in groups, no question."],
    off = L["Never pings in groups, no question."],
}
local function Select(mode)
    seg:Select(mode)
    hint:SetText(HINT[mode] or "")
end
seg.onSelect = function(mode)
    QuestFocusDB.pingMode = mode
    QuestFocusDB.noPing = (mode == "off") or nil
    Select(mode)
    if NS.RefreshPingUI then NS.RefreshPingUI() end
end
for _, b in ipairs(seg.buttons) do
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(DESC[self.value] or "", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
-- magassag: fejlec 28 + kerdes ~18 + 10 + gomb 24 + 6 + magyarazat 2 sor ~22 + 10 + 1
-- + 8 + szekcio 10 + 5 + valaszto 22 + 6 + hint 10 + also 12
f:SetHeight(194)

local function Answer(v)
    NS.pingSession = v
    QuestFocusDB.pingAnswer = v -- /reload utan is erre a csapatra
    f:Hide()
    RefreshMacro()
    NS.Loud(NS.Print, v and L["Ping on for this group."] or L["No ping for this group."])
end
yes:SetScript("OnClick", function() Answer(true) end)
no:SetScript("OnClick", function() Answer(false) end)

local function ShowAsk()
    Select(NS.PingMode())
    f:Show()
end
NS.ShowPingAsk = ShowAsk
f.yes, f.no, f.seg = yes, no, seg
NS.PingAskFrame = f -- tesztekhez / debughoz


-- Csapatba lepes figyelese
local wasInGroup, pendingAsk = false, false
local ev = CreateFrame("Frame")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingAsk and IsInGroup() and NS.PingMode() == "ask" and NS.pingSession == nil then ShowAsk() end
        pendingAsk = false
        return
    end
    local inGroup = IsInGroup and IsInGroup() or false
    if inGroup and not wasInGroup then
        -- /reload csapatban: a korabbi valasz marad
        if event == "PLAYER_ENTERING_WORLD" and NS.pingSession == nil and QuestFocusDB.pingAnswer ~= nil then
            NS.pingSession = QuestFocusDB.pingAnswer
        end
        if NS.PingMode() == "ask" and NS.pingSession == nil then
            if InCombatLockdown() then pendingAsk = true else ShowAsk() end
        end
        RefreshMacro()
    elseif not inGroup and wasInGroup then
        NS.pingSession = nil -- kovetkezo csapatnal ujra kerdez
        QuestFocusDB.pingAnswer = nil
        f:Hide()
        RefreshMacro()
    end
    wasInGroup = inGroup
end)
