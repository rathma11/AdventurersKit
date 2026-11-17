local ADDON_NAME, NS = ...
local L = NS.L
NS.C = NS.C or {}
local C = NS.C
local GetLogEntry, Module, NumLogEntries, Print, state = C.GetLogEntry, C.Module, C.NumLogEntries, C.Print, C.state

---------------------------------------------------------------------------
-- Slash parancsok
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Zona fokusz: csak az aktualis zona questjei maradnak a trackerben (Questie)
---------------------------------------------------------------------------
local function QuestTracker() return Module("QuestieTracker") end

local function IsTracked(qid, idx)
    local QT = QuestTracker()
    if QT and type(QT.IsTrackedByQuestie) == "function" then
        local ok, r = pcall(QT.IsTrackedByQuestie, qid)
        if ok then return r and true or false end
    end
    if C_QuestLog and C_QuestLog.GetQuestWatchType then return C_QuestLog.GetQuestWatchType(qid) ~= nil end
    if IsQuestWatched and idx then return IsQuestWatched(idx) and true or false end
    return false
end

local function Untrack(qid, idx)
    local QT = QuestTracker()
    if QT and type(QT.UntrackQuestId) == "function" and pcall(QT.UntrackQuestId, QT, qid) then return end
    if C_QuestLog and C_QuestLog.RemoveQuestWatch then C_QuestLog.RemoveQuestWatch(qid)
    elseif RemoveQuestWatch and idx then RemoveQuestWatch(idx) end
end

local function Track(qid, idx)
    if C_QuestLog and C_QuestLog.AddQuestWatch then
        C_QuestLog.AddQuestWatch(qid) -- a Questie erre hookol es frissit
    elseif AddQuestWatch and idx then
        AddQuestWatch(idx)
    end
    -- Biztonsag kedveert a Questie sajat listajat is igazitjuk
    local db = _G.Questie and Questie.db
    if db and db.profile and db.char then
        if db.profile.autoTrackQuests then
            if db.char.AutoUntrackedQuests then db.char.AutoUntrackedQuests[qid] = nil end
        elseif db.char.TrackedQuests then
            db.char.TrackedQuests[qid] = true
        end
        local QT = QuestTracker()
        if QT and QT.Update then pcall(QT.Update, QT) end
    end
end

-- questId -> { index, header } a quest logbol
local function LogQuests()
    local out, header = {}, nil
    for i = 1, NumLogEntries() do
        local title, isHeader, qid = GetLogEntry(i)
        if isHeader then header = title
        elseif qid and qid > 0 then out[qid] = { index = i, header = header } end
    end
    return out
end

local function ZoneFocusOff(silent)
    local zf = QuestFocusDB.zoneFocus
    if not zf then return end
    local log = LogQuests()
    for qid in pairs(zf.removed or {}) do
        if log[qid] and not IsTracked(qid, log[qid].index) then Track(qid, log[qid].index) end
    end
    for qid in pairs(zf.added or {}) do
        if log[qid] and IsTracked(qid, log[qid].index) then Untrack(qid, log[qid].index) end
    end
    QuestFocusDB.zoneFocus = nil
    if not silent then Print(L["Zone focus off: previous quests are back in the tracker."]) end
end

local function ZoneFocusOn()
    if QuestFocusDB.zoneFocus then ZoneFocusOff(true) end
    local zone = GetRealZoneText and GetRealZoneText() or GetZoneText()
    local zf = { zone = zone, removed = {}, added = {} }
    local kept, hidden = 0, 0
    for qid, e in pairs(LogQuests()) do
        local inZone = (e.header == zone) or (qid == state.questId)
        local tracked = IsTracked(qid, e.index)
        if inZone then
            kept = kept + 1
            if not tracked then Track(qid, e.index); zf.added[qid] = true end
        elseif tracked then
            Untrack(qid, e.index); zf.removed[qid] = true
            hidden = hidden + 1
        end
    end
    QuestFocusDB.zoneFocus = zf
    Print(L["Zone focus: |cffffff00%s|r (%d quests kept, %d hidden). Turn off: same button / /qf zone"],
        zone or "?", kept, hidden)
end

local function ToggleZoneFocus()
    if QuestFocusDB.zoneFocus then ZoneFocusOff() else ZoneFocusOn() end
end

-- Zonavaltaskor: ha be van kapcsolva, a fokusz koveti a jatekost; ha nincs, megkerdezzuk
-- (zonankent egyszer egy jatekmenetben, csak ha van questunk abban a zonaban)
local askedZone = {}
StaticPopupDialogs["QUESTFOCUS_ZONEFOCUS"] = {
    text = L["QuestFocus: you have %d quest(s) in |cffffff00%s|r.\nFocus on this zone? The other quests leave the Questie tracker (they come back when you turn it off)."],
    button1 = L["Focus"],
    button2 = L["Not now"],
    button3 = L["Don't ask again"],
    OnAccept = function() ZoneFocusOn() end,
    OnAlt = function()
        QuestFocusDB.noZonePrompt = true
        Print(L["Zone question turned off. Turn it back on: Options > QuestFocus > Ask when entering a new zone."])
    end,
    timeout = 30,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Fokusz be van kapcsolva, es masik zonaba ertel: rakerdezunk, hogy valtson-e
-- (QuestFocusDB.zoneAutoFollow eseten kerdes nelkul valt, mint regen)
local SWITCH_TEXT = L["QuestFocus: you have %d quest(s) in |cffffff00%s|r.\nSwitch the Questie tracker to this zone? (zone focus is now on |cffffff00%s|r)"]
StaticPopupDialogs["QUESTFOCUS_ZONESWITCH"] = {
    text = "",
    button1 = L["Switch"],
    button2 = L["Keep"],
    button3 = L["Turn off focus"],
    OnAccept = function() ZoneFocusOn() end,
    OnAlt = function() ZoneFocusOff() end,
    timeout = 30,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function QuestsHere(zone)
    local here, other = 0, 0
    for _, e in pairs(LogQuests()) do
        if e.header == zone then here = here + 1 else other = other + 1 end
    end
    return here, other
end

local function MaybeAskZone()
    local zone = GetRealZoneText and GetRealZoneText() or GetZoneText()
    if not zone or zone == "" then return end
    local zf = QuestFocusDB.zoneFocus
    if zf then
        -- mar erre a zonara fokuszalunk
        if zf.zone == zone then return end
        local here = QuestsHere(zone)
        -- itt nincs questunk: a fokusz marad (kulonben ures lenne a tracker)
        if here == 0 then return end
        if QuestFocusDB.zoneAutoFollow then ZoneFocusOn() return end
        if askedZone[zone] then return end
        if InCombatLockdown() then state.askZoneAfterCombat = true return end
        askedZone[zone] = true
        StaticPopup_Hide("QUESTFOCUS_ZONEFOCUS")
        -- 3 parameter kell a szovegbe, a StaticPopup csak 2-t ad at: elore formazzuk
        StaticPopupDialogs.QUESTFOCUS_ZONESWITCH.text = SWITCH_TEXT:format(here, zone, zf.zone or "?")
        StaticPopup_Show("QUESTFOCUS_ZONESWITCH")
        return
    end
    if QuestFocusDB.noZonePrompt or askedZone[zone] then return end
    local here, other = QuestsHere(zone)
    -- csak ha van itt quest, es van mas is, amit el lehetne rejteni
    if here == 0 or other == 0 then return end
    if InCombatLockdown() then
        state.askZoneAfterCombat = true
        return
    end
    askedZone[zone] = true
    StaticPopup_Hide("QUESTFOCUS_ZONESWITCH")
    StaticPopup_Show("QUESTFOCUS_ZONEFOCUS", here, zone)
end
NS.MaybeAskZone = MaybeAskZone

local zoneWatcher = CreateFrame("Frame")
zoneWatcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoneWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
zoneWatcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if state.askZoneAfterCombat then state.askZoneAfterCombat = nil; MaybeAskZone() end
        return
    end
    C_Timer.After(1, function()
        if QuestFocusDB then MaybeAskZone() end
    end)
end)


-- belso exportok a tobbi core fajlnak
NS.C.ToggleZoneFocus = ToggleZoneFocus
