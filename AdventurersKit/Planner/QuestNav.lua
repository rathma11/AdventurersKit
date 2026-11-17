local ADDON_NAME, NS = ...
local L = NS.L
local state = NS.C.state

---------------------------------------------------------------------------
-- Elozo / kovetkezo quest (a panel cimsoraban a nyilak + Key Bindings)
---------------------------------------------------------------------------
-- Kovetkezo: az utvonal (Route (quest log)) elso allomasa a mostani quest utan. A quest,
-- amirol igy ellepsz, az utvonal vegere kerul ("atugorva"), amig:
--   (a) a quest, amire valtottal, kesz lesz (leadhato),
--   (b) barmelyik questet leadod (QUEST_TURNED_IN),
--   (c) toltokepernyo jon (PLAYER_ENTERING_WORLD: zona/instance valtas, reload).
-- Csak memoriaban (nem SavedVariables).
-- Elozo: mint a bongeszo "vissza" gombja; a korabban fokuszalt questek verme (ami mar nincs
-- a logban, azt kihagyja).

local deferred = {} -- qid -> sorszam (az atugras sorrendje)
NS.deferredQuests = deferred -- Planner\Route.lua (BuildRoute) olvassa
local deferSeq = 0
local anchor -- { qid, done }: a quest, amire a kovetkezo nyillal valtottal
local history = {}
local HISTORY_MAX = 30
local goingBack = false

local function Refresh()
    if NS.Panel_Update then NS.Panel_Update() end
end

local function ClearDeferred()
    anchor = nil
    if next(deferred) == nil then return end
    wipe(deferred)
    Refresh()
end
NS.ClearDeferredQuests = ClearDeferred

-- Core\Selection.lua hivja, amikor a fokusz egy masik questre valt (vagy torlod)
NS.OnFocusLeave = function(qid)
    if goingBack or not qid then return end
    if history[#history] ~= qid then
        history[#history + 1] = qid
        if #history > HISTORY_MAX then table.remove(history, 1) end
    end
end

local function Route()
    if not NS.QuestNavRoute or not NS.QuestieAvailable() then return {} end
    local ok, r = pcall(NS.QuestNavRoute)
    return ok and type(r) == "table" and r or {}
end

-- A verem teteje, ami meg a logban van (a tobbit eldobjuk)
local function PeekBack()
    while #history > 0 do
        local qid = history[#history]
        local title, done = NS.FindQuestInLog(qid)
        if title and qid ~= state.questId then return qid, title, done end
        table.remove(history)
    end
end

NS.HasQuestHistory = function() return PeekBack() ~= nil end

local function Select(qid, title, done)
    local ok, err = pcall(NS.SelectQuest, qid, title, done, true)
    if not ok then
        local h = geterrorhandler and geterrorhandler()
        if h then h(err) end
    end
end

NS.NextQuest = function()
    local s = Route()[1]
    if not s then
        NS.Print(L["No other quest on the route."])
        return
    end
    local cur = state.questId
    if cur and cur ~= s.qid then
        deferSeq = deferSeq + 1
        deferred[cur] = deferSeq
    end
    deferred[s.qid] = nil
    anchor = { qid = s.qid, done = s.done and true or false }
    Select(s.qid, s.title, s.done)
end

NS.PrevQuest = function()
    local qid, title, done = PeekBack()
    if not qid then
        NS.Print(L["No earlier quest to go back to."])
        return
    end
    table.remove(history)
    deferred[qid] = nil -- szandekosan visszajottel ra: mar nincs atugorva
    goingBack = true
    Select(qid, title, done)
    goingBack = false
end

-- Key Bindings (Bindings.xml az addon gyokereben). A fejlec (QUESTFOCUS) kozos a Bags modul
-- "Use item" kotesevel: az a mieink utan toltodik, igy ugyanazon "Adventurer's Kit" alatt latszik.
_G.AdventurersKit_NextQuest = function() NS.NextQuest() end
_G.AdventurersKit_PrevQuest = function() NS.PrevQuest() end
_G.BINDING_HEADER_QUESTFOCUS = "Adventurer's Kit"
_G.BINDING_NAME_ADVENTURERSKIT_NEXTQUEST = L["Next quest"]
_G.BINDING_NAME_ADVENTURERSKIT_PREVQUEST = L["Previous quest"]

local function YdText(d)
    return d and ("  |cff99ccff%d yd|r"):format(math.floor(d + 0.5)) or ""
end
local function QuestLine(title, done, dist)
    return (done and ("|cffffff00" .. L["Turn in: "] .. "|r") or "") .. "|cffffffff" .. (title or "?") .. "|r" .. YdText(dist)
end
local function KeyLine(binding)
    local key = GetBindingKey and GetBindingKey(binding)
    if key then
        GameTooltip:AddLine((L["Key: %s"]):format(GetBindingText and GetBindingText(key, "KEY_") or key), 0.5, 0.5, 0.5)
    else
        GameTooltip:AddLine(L["You can set a key for it in Key Bindings (Adventurer's Kit)."], 0.5, 0.5, 0.5, true)
    end
end

-- Tooltip a panel nyilainak: dir = "next" / "prev"
NS.QuestNavTooltip = function(owner, dir)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
    local route = Route()
    if dir == "next" then
        GameTooltip:SetText(L["Next quest"], 1, 1, 1)
        local s = route[1]
        if s then
            GameTooltip:AddLine(QuestLine(s.title, s.done, s.dist), 1, 1, 1)
            if s.deferred then
                GameTooltip:AddLine(L["(skipped earlier: every other quest is skipped too)"], 0.6, 0.6, 0.6, true)
            end
            GameTooltip:AddLine(L["Goes to the next stop of the route. This quest moves to the end of the route until the next one is ready to turn in, you turn in a quest, or a loading screen comes."],
                0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine(L["No other quest on the route."], 0.8, 0.8, 0.8)
        end
        KeyLine("ADVENTURERSKIT_NEXTQUEST")
    else
        GameTooltip:SetText(L["Previous quest"], 1, 1, 1)
        local qid, title, done = PeekBack()
        if qid then
            local dist
            for _, s in ipairs(route) do
                if s.qid == qid then dist = s.dist break end
            end
            GameTooltip:AddLine(QuestLine(title, done, dist), 1, 1, 1)
            GameTooltip:AddLine(L["Back to the quest you focused before (like a browser's back button)."], 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine(L["No earlier quest to go back to."], 0.8, 0.8, 0.8)
        end
        KeyLine("ADVENTURERSKIT_PREVQUEST")
    end
    GameTooltip:Show()
end

-- Az atugrasok feloldasa
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(ev.RegisterEvent, ev, "QUEST_TURNED_IN")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" or event == "QUEST_TURNED_IN" then
        ClearDeferred()
        return
    end
    -- (a): a quest, amire valtottal, leadhato lett
    if not anchor or next(deferred) == nil then return end
    local title, done = NS.FindQuestInLog(anchor.qid)
    if not title then
        anchor = nil -- mar nincs a logban (leadtad / eldobtad)
    elseif done and not anchor.done then
        ClearDeferred()
    end
end)
