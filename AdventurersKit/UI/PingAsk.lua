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

-- Kerdo ablak: ugyanaz a kinezet, mint a panel / buff reminder (sotet hatter, arany keret,
-- narancs csik balra, kis nagybetus fejlec), harom tagolt resz: kerdes, valasz, "legkozelebb".
local GOLD = { 0.95, 0.78, 0.40 }
local f = CreateFrame("Frame", "AdventurersKitPingAsk", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
f:SetSize(300, 164)
f:SetPoint("TOP", UIParent, "TOP", 0, -160)
f:SetFrameStrata("DIALOG")
f:EnableMouse(true)
f:SetMovable(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:Hide()
if f.SetBackdrop then
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.04, 0.04, 0.06, 0.94)
    f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
end
local accent = f:CreateTexture(nil, "ARTWORK")
accent:SetPoint("TOPLEFT", 4, -4)
accent:SetPoint("BOTTOMLEFT", 4, 4)
accent:SetWidth(2)
accent:SetColorTexture(1, 0.55, 0.25, 1)

local head = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
head:SetPoint("TOPLEFT", 12, -8)
head:SetTextColor(1, 0.6, 0.3)
head:SetText(L["AKIT PING"])
local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
close:SetSize(20, 20)
close:SetPoint("TOPRIGHT", -2, -2)

local question = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
question:SetPoint("TOPLEFT", 12, -26)
question:SetText(L["Ping your target in this group?"])
local sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
sub:SetPoint("TOPLEFT", question, "BOTTOMLEFT", 0, -3)
sub:SetWidth(276)
sub:SetJustifyH("LEFT")
sub:SetText(L["You joined a group: they see the AKit macro's pings. Solo it always pings."])

-- lapos gomb (mint a city listen): sotet hatter, vekony arany keret, hoverre vilagosabb
-- (parent: masik ablakhoz is, pl. a dungeon quest megosztas: NS.FlatButton)
local function Flat(text, w, h, parent)
    local b = CreateFrame("Button", nil, parent or f)
    b:SetSize(w, h or 22)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.08, 0.06, 0.03, 0.9)
    local function edge(p1, p2, ww, hh)
        local t = b:CreateTexture(nil, "BORDER")
        t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
        t:SetPoint(p1); t:SetPoint(p2)
        if ww then t:SetWidth(ww) else t:SetHeight(hh) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1); edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1); edge("TOPRIGHT", "BOTTOMRIGHT", 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(1, 0.82, 0, 0.15)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    return b
end
NS.FlatButton = function(parent, text, w, h) return Flat(text, w, h, parent) end

-- 1) valasz erre a csapatra
local yes = Flat(L["Ping in this group"], 136, 24)
yes:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -10)
yes.text:SetFontObject("GameFontNormal")
local no = Flat(L["No ping"], 136, 24)
no:SetPoint("LEFT", yes, "RIGHT", 6, 0)
no.text:SetFontObject("GameFontNormal")

-- elvalaszto vonal
local line = f:CreateTexture(nil, "ARTWORK")
line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
line:SetHeight(1)
line:SetPoint("TOPLEFT", yes, "BOTTOMLEFT", 0, -10)
line:SetPoint("RIGHT", f, "RIGHT", -12, 0)

-- 2) legkozelebb: harom reszes valaszto (egyszerre egy)
local nextLbl = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
nextLbl:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -7)
nextLbl:SetText(L["NEXT TIME I JOIN A GROUP"])
local SHORT = { ask = L["Ask"], on = L["Always ping"], off = L["Never ping"] }
local radios = {}
local function Select(mode)
    for _, r in ipairs(radios) do
        local on = r.mode == mode
        r.bg:SetColorTexture(on and 0.30 or 0.08, on and 0.22 or 0.06, on and 0.05 or 0.03, 0.9)
        r.text:SetFontObject(on and "GameFontHighlightSmall" or "GameFontDisableSmall")
    end
end
for i, m in ipairs(MODES) do
    local r = Flat(SHORT[m[1]] or m[2], 90, 18)
    r:SetPoint("TOPLEFT", nextLbl, "BOTTOMLEFT", (i - 1) * 93, -4)
    r.mode = m[1]
    r:SetScript("OnClick", function(self)
        QuestFocusDB.pingMode = self.mode
        QuestFocusDB.noPing = (self.mode == "off") or nil
        Select(self.mode)
        if NS.RefreshPingUI then NS.RefreshPingUI() end
    end)
    r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(m[2], 1, 1, 1)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    radios[#radios + 1] = r
end

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
