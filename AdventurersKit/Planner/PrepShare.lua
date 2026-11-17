-- Dungeon prep: csapatban a dungeonba lepve megkerdezi, megosszuk-e a dungeon questjeit a
-- csapattal (QuestLogPushQuest). Ugyanaz a kinezet, mint a ping kerdes (UI\PingAsk.lua): sotet
-- hatter, arany keret, narancs csik, kis nagybetus fejlec, lapos gombok (NS.FlatButton).
-- Csak harcon kivul (harcban a harc utanra marad), belepesenkent egyszer, csak csapatban es
-- ha van megoszthato quest. Kikapcsolhato: Options > Route & progress (QuestFocusDB.noShareAsk).
local ADDON_NAME, NS = ...
local L = NS.L

local GOLD = { 0.95, 0.78, 0.40 }
local W = 320
local f = CreateFrame("Frame", "AdventurersKitShareAsk", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
f:SetSize(W, 120)
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
head:SetText(L["SHARE DUNGEON QUESTS"])
local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
close:SetSize(20, 20)
close:SetPoint("TOPRIGHT", -2, -2)

local question = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
question:SetPoint("TOPLEFT", 12, -26)
question:SetText(L["Share your dungeon quests with the party?"])

local checks = {}
local function Check(i)
    local c = checks[i]
    if c then return c end
    c = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    c:SetSize(20, 20)
    c.label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
    c.label:SetWidth(W - 60)
    c.label:SetJustifyH("LEFT")
    c.label:SetWordWrap(false)
    checks[i] = c
    return c
end

local Flat = NS.FlatButton
local share = Flat and Flat(f, L["Share"], 136, 24)
local notNow = Flat and Flat(f, L["Not now"], 136, 24)
if share then share.text:SetFontObject("GameFontNormal") end
if notNow then notNow.text:SetFontObject("GameFontNormal") end

---------------------------------------------------------------------------
-- Quest log
---------------------------------------------------------------------------
local function LogIndex(qid)
    if not (GetNumQuestLogEntries and GetQuestLogTitle) then return end
    for i = 1, (GetNumQuestLogEntries()) do
        if select(8, GetQuestLogTitle(i)) == qid then return i end
    end
end

-- Megoszthato-e (a kijelolt questre mukodik: kijeloljuk, aztan vissza az eredetire)
local function Pushables(list)
    local out = {}
    if not (SelectQuestLogEntry and GetQuestLogPushable and GetQuestLogSelection) then return out end
    local prev = GetQuestLogSelection()
    for _, q in ipairs(list) do
        local idx = LogIndex(q.qid)
        if idx then
            SelectQuestLogEntry(idx)
            if GetQuestLogPushable() then out[#out + 1] = q end
        end
    end
    if prev and prev > 0 then SelectQuestLogEntry(prev) end
    return out
end

local function PushAll(list)
    local prev = GetQuestLogSelection and GetQuestLogSelection() or 0
    local n = 0
    local function step(i)
        local q = list[i]
        if not q then
            if prev and prev > 0 and SelectQuestLogEntry then SelectQuestLogEntry(prev) end
            if QuestLog_Update and QuestLogFrame and QuestLogFrame:IsShown() then pcall(QuestLog_Update) end
            NS.Loud(NS.Print, L["Shared %d dungeon quests with the party."], n)
            return
        end
        local idx = LogIndex(q.qid)
        if idx and not InCombatLockdown() then
            SelectQuestLogEntry(idx)
            if GetQuestLogPushable() then
                QuestLogPushQuest()
                n = n + 1
            end
        end
        C_Timer.After(0.3, function() step(i + 1) end)
    end
    step(1)
end

---------------------------------------------------------------------------
-- Ablak
---------------------------------------------------------------------------
local current = {}
local function Show(list)
    current = list
    local y = -46
    for i, q in ipairs(list) do
        local c = Check(i)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", f, "TOPLEFT", 10, y)
        c:SetChecked(true)
        c.label:SetText(("[%s] %s"):format(tostring(q.level or "?"), q.title or "?"))
        c:Show()
        y = y - 20
    end
    for i = #list + 1, #checks do checks[i]:Hide() end
    y = y - 8
    if share then
        share:ClearAllPoints()
        share:SetPoint("TOPLEFT", f, "TOPLEFT", 12, y)
        notNow:ClearAllPoints()
        notNow:SetPoint("LEFT", share, "RIGHT", 6, 0)
    end
    f:SetHeight(-y + 24 + 12)
    f:Show()
end

if share then
    share:SetScript("OnClick", function()
        local sel = {}
        for i, q in ipairs(current) do
            if checks[i] and checks[i]:GetChecked() then sel[#sel + 1] = q end
        end
        f:Hide()
        if #sel > 0 then PushAll(sel) end
    end)
    notNow:SetScript("OnClick", function() f:Hide() end)
end

local pending = false
local function TryAsk()
    if QuestFocusDB.noShareAsk or not (IsInGroup and IsInGroup()) then return end
    if not (NS.PrepIsInside and NS.PrepIsInside() and NS.PrepInsideQuests) then return end
    if InCombatLockdown() then pending = true return end
    local list = Pushables(NS.PrepInsideQuests())
    if #list > 0 then Show(list) end
end

-- Planner\PrepInside.lua hivja belepeskor (belepesenkent egyszer)
NS.PrepShareAsk = function()
    pending = false
    f:Hide()
    TryAsk()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function()
    if pending then
        pending = false
        TryAsk()
    end
end)
NS.PrepShareHide = function()
    pending = false
    f:Hide()
end
