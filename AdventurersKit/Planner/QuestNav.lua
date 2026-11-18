local ADDON_NAME, NS = ...
local L = NS.L
local state = NS.C.state

---------------------------------------------------------------------------
-- Elozo / kovetkezo quest (a panel cimsoraban a nyilak + Key Bindings)
---------------------------------------------------------------------------
-- Kovetkezo: az utvonal (Route (quest log)) elso allomasa a mostani quest utan. A quest,
-- amirol igy ellepsz, az utvonal vegere kerul ("atugorva"). Karakterenkent mentve
-- (NS.CharDB().deferredQuests = { [qid] = true }), reload / relog utan is megmarad.
-- Mindet feloldja:
--   (a) a quest, amire a nyillal valtottal, kesz lesz (leadhato),
--   (b) barmelyik questet leadod (QUEST_TURNED_IN).
-- Egy questet old fel:
--   - te valasztod ki (quest log kattintas, kovetes, route sor, vissza nyil),
--   - halad (kill / drop: Planner\Pace.lua ScanProgress),
--   - ~150 yd-ra kerulsz a celjatol / leadasi pontjatol (miutan elotte messzebb voltal),
--   - kikerul a logbol.
-- Ha minden mas quest atugrott (vagy nincs mas), az utvonal ezekbol all, legkozelebbi elol,
-- es a kovetkezo nyil ezeken is korbemegy.
-- Elozo: mint a bongeszo "vissza" gombja; a korabban fokuszalt questek verme (csak memoriaban;
-- ami mar nincs a logban, azt kihagyja).

local NEAR_YD = 150     -- ennyire kozel erve a quest celjahoz az atugras megszunik
local REARM_YD = 200    -- ...de csak ha elotte ennel messzebb voltal (kulonben azonnal feloldana)
local HISTORY_MAX = 30

local EMPTY = {}
-- az atugrott questek (karakterenkent); rawget: ne a kozos QuestFocusDB-bol olvasson
local function Deferred(create)
    local c = NS.CharDB and NS.CharDB()
    if not c or not QuestFocusDB then return EMPTY end
    local t = rawget(c, "deferredQuests")
    if not t and create then
        t = {}
        c.deferredQuests = t
    end
    return t or EMPTY
end
NS.DeferredQuests = function() return Deferred(false) end -- Planner\Route.lua (BuildRoute)

-- (a)-hoz: a quest, amire a nyillal valtottal { qid, done } (ez is mentve)
local function Anchor() local c = NS.CharDB and NS.CharDB(); return c and rawget(c, "deferAnchor") end
local function SetAnchor(a) local c = NS.CharDB and NS.CharDB(); if c and QuestFocusDB then c.deferAnchor = a end end

local order = {}    -- qid -> sorszam: a nyil korbejarasahoz (memoriaban; ami nincs benne, az a legregebbi)
local seq = 0
local armed = {}    -- qid -> true: mar voltal messze tole, kozel erve feloldhato
local history = {}
local goingBack = false

local function Refresh()
    if NS.Panel_Update then NS.Panel_Update() end
end

local function Undefer(qid)
    local t = Deferred(false)
    if not qid or not t[qid] then return false end
    t[qid] = nil
    order[qid], armed[qid] = nil, nil
    return true
end

local function ClearDeferred()
    SetAnchor(nil)
    wipe(armed)
    wipe(order)
    local t = Deferred(false)
    if next(t) == nil then return end
    wipe(t)
    Refresh()
end
NS.ClearDeferredQuests = ClearDeferred

-- ami mar nincs a logban, azt eldobjuk (ha a log meg nem toltott be, nem nyulunk hozza)
local function Prune()
    local t = Deferred(false)
    if next(t) == nil or NS.NumLogEntries() == 0 then return end
    for qid in pairs(t) do
        if not NS.FindQuestInLog(qid) then Undefer(qid) end
    end
end

-- Core\Selection.lua hivja, amikor a fokusz egy masik questre valt (vagy torlod)
NS.OnFocusLeave = function(qid)
    if goingBack or not qid then return end
    if history[#history] ~= qid then
        history[#history + 1] = qid
        if #history > HISTORY_MAX then table.remove(history, 1) end
    end
end
-- ...es amikor egy quest fokuszba kerul: mar nincs atugorva
NS.OnFocusEnter = function(qid)
    if Undefer(qid) then Refresh() end
end
-- Planner\Pace.lua: a quest haladt (kill / drop)
NS.OnQuestProgress = function(qid)
    if Undefer(qid) then Refresh() end
end

local function Route()
    if not NS.QuestNavRoute or not NS.QuestieAvailable() then return {} end
    local ok, r = pcall(NS.QuestNavRoute)
    return ok and type(r) == "table" and r or {}
end

-- A kovetkezo allomas. Ha csak atugrottak maradtak, a legregebben atugrott (igy korbemegy).
local function NextStop(route)
    local s = route[1]
    if not s or not s.deferred then return s end
    local best
    for _, r in ipairs(route) do
        if not best or (order[r.qid] or 0) < (order[best.qid] or 0) then best = r end
    end
    return best
end

-- A verem teteje, ami meg a logban van (a tobbit eldobjuk)
-- A farm session (Planner\Farm.lua) is lehet a veremben ("farm"): amig fut es nem az latszik.
local function FarmBackOk()
    return NS.Farm and NS.Farm.IsRunning() and not NS.Farm.Viewing()
end
local function PeekBack()
    while #history > 0 do
        local qid = history[#history]
        if qid == "farm" then
            if FarmBackOk() then return "farm", L["Farm session"], false end
            table.remove(history)
            qid = history[#history]
            if not qid then return end
        end
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

-- Planner\Farm.lua: a farm nezetrol ellepve a "vissza" nyil oda hozzon
NS.QuestNavPushFarm = function()
    if history[#history] ~= "farm" then
        history[#history + 1] = "farm"
        if #history > HISTORY_MAX then table.remove(history, 1) end
    end
end

NS.NextQuest = function()
    Prune()
    -- farm nezetbol: a fokuszalt questre (ha van), kulonben az utvonal elso allomasara
    if NS.FarmViewing and NS.FarmViewing() then
        if state.questId then
            NS.Farm.SetView(false)
            return
        end
        local s = NextStop(Route())
        if not s then NS.Print(L["No other quest on the route."]) return end
        NS.Farm.SetView(false)
        SetAnchor({ qid = s.qid, done = s.done and true or false })
        Select(s.qid, s.title, s.done)
        return
    end
    local s = NextStop(Route())
    if not s then
        NS.Print(L["No other quest on the route."])
        return
    end
    local cur = state.questId
    if cur and cur ~= s.qid then
        Deferred(true)[cur] = true
        seq = seq + 1
        order[cur], armed[cur] = seq, nil
    end
    SetAnchor({ qid = s.qid, done = s.done and true or false })
    Select(s.qid, s.title, s.done) -- az OnFocusEnter feloldja, ha atugrott volt
end

NS.PrevQuest = function()
    local qid, title, done = PeekBack()
    if not qid then
        NS.Print(L["No earlier quest to go back to."])
        return
    end
    table.remove(history)
    if qid == "farm" then
        NS.Farm.SetView(true)
        return
    end
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
        local s = NextStop(route)
        if NS.FarmViewing and NS.FarmViewing() then
            -- farm nezet: a fokuszalt quest (vagy az utvonal eleje); a session fut tovabb
            if state.questId then s = { title = state.title, done = state.isComplete } end
            if s then GameTooltip:AddLine(QuestLine(s.title, s.done, s.dist), 1, 1, 1) end
            GameTooltip:AddLine(L["Back to your quests. The farm session keeps running; the back arrow (or its route row) brings it back."],
                0.8, 0.8, 0.8, true)
        elseif s then
            GameTooltip:AddLine(QuestLine(s.title, s.done, s.dist), 1, 1, 1)
            if s.deferred then
                GameTooltip:AddLine(L["(skipped earlier: every other quest is skipped too)"], 0.6, 0.6, 0.6, true)
            end
            GameTooltip:AddLine(L["Goes to the next stop of the route. This quest moves to the end of the route until the next one is ready to turn in, you turn in a quest, it makes progress, you pick it yourself, or you get near it."],
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
            GameTooltip:AddLine(qid == "farm" and L["Back to the farm session."]
                or L["Back to the quest you focused before (like a browser's back button)."], 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine(L["No earlier quest to go back to."], 0.8, 0.8, 0.8)
        end
        KeyLine("ADVENTURERSKIT_PREVQUEST")
    end
    GameTooltip:Show()
end

-- Az atugrasok feloldasa: leadas, a cel quest kesz lett, quest eltavolitva
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "QUEST_TURNED_IN")
pcall(ev.RegisterEvent, ev, "QUEST_REMOVED")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:SetScript("OnEvent", function(_, event, qid)
    if not QuestFocusDB then return end
    if event == "QUEST_TURNED_IN" then
        ClearDeferred()
        return
    end
    if event == "QUEST_REMOVED" then
        if Undefer(qid) then Refresh() end
        return
    end
    -- (a): a quest, amire valtottal, leadhato lett
    local a = Anchor()
    if not a or NS.NumLogEntries() == 0 then return end
    if next(Deferred(false)) == nil then SetAnchor(nil) return end
    local title, done = NS.FindQuestInLog(a.qid)
    if not title then
        SetAnchor(nil) -- mar nincs a logban (leadtad / eldobtad)
    elseif done and not a.done then
        ClearDeferred()
    end
end)

-- Kozelseg: 5 mp-enkent, ha legalabb 20 yd-ot mentel. Egy atugrott quest akkor oldodik fel, ha
-- ~150 yd-ra kerulsz a hatralevo celjahoz (vagy a leadashoz), de csak ha elotte 200 yd-nal
-- messzebb voltal tole (kulonben ott, ahol atugrottad, azonnal feloldana).
local function StopDistance(qid, done)
    local q = NS.GetQuestieQuest(qid)
    if not q then return end
    local sources = {}
    for _, o in ipairs(NS.CollectTargets(q, done)) do
        if not o.completed then
            for _, s in ipairs(o.sources or EMPTY) do sources[#sources + 1] = s end
        end
    end
    if #sources == 0 then return end
    local pc, px, py = NS.PlayerWorldPos()
    if not pc then return end
    local _, d = NS.P.Nearest(sources, pc, px, py)
    return d
end

local nearElapsed = 0
ev:SetScript("OnUpdate", function(_, dt)
    nearElapsed = nearElapsed + dt
    if nearElapsed < 5 then return end
    nearElapsed = 0
    if not QuestFocusDB or InCombatLockdown() or not NS.QuestieAvailable() then return end
    local t = Deferred(false)
    if next(t) == nil or not NS.Moved("questnav", 20) then return end
    local changed = false
    for qid in pairs(t) do
        local title, done = NS.FindQuestInLog(qid)
        local d = title and StopDistance(qid, done)
        if d then
            if d > REARM_YD then
                armed[qid] = true
            elseif d <= NEAR_YD and armed[qid] then
                t[qid], order[qid], armed[qid] = nil, nil, nil
                changed = true
            end
        else
            armed[qid] = true -- mas kontinensen / nincs pont: ha odaersz, mar feloldhato
        end
    end
    if changed then Refresh() end
end)
