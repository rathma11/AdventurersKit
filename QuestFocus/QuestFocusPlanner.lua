-- QuestFocus: hatralevo ido becsles es questjavaslat.
--  * ETA: objective-onkent a sajat tempodbol (mikor nott a szamlalo), ennek hianyaban a
--    kill-tempodbol (ket kill kozt eltelt ido) es a Questie drop rate-bol.
--  * Javaslat: ha nincs kijelolt quest, a panel egy utvonalat mutat a quest logbol
--    (mindig a legkozelebbi kovetkezo allomas) es a kozelben felveheto questeket.

local _, NS = ...
local L = NS.L
local state = NS.state

local DEFAULT_KILL_TIME = 45   -- mp/kill, amig nincs sajat meres
local MAX_GAP = 300            -- ennel hosszabb szunet nem szamit bele a tempoba
local ROUTE_LEN = 5
local PICKUP_LEN = 3

---------------------------------------------------------------------------
-- Kill tempo
---------------------------------------------------------------------------
local lastKill, killSeen = nil, {}

local function RecordKill(guid)
    if not guid or killSeen[guid] then return end
    killSeen[guid] = true
    local now = GetTime()
    if lastKill then
        local dt = now - lastKill
        if dt > 1 and dt < MAX_GAP then
            local db = QuestFocusDB
            db.killPace = db.killPace and (db.killPace * 0.75 + dt * 0.25) or dt
            db.killSamples = (db.killSamples or 0) + 1
        end
    end
    lastKill = now
end

local function KillPace()
    local db = QuestFocusDB or {}
    if db.killPace and (db.killSamples or 0) >= 3 then return db.killPace, false end
    return DEFAULT_KILL_TIME, true
end

---------------------------------------------------------------------------
-- Objective tempo (mikor nott a Collected)
---------------------------------------------------------------------------
local progress = {} -- key -> { last = n, hits = { t1, t2, ... } }

local function ObjKey(qid, o)
    return tostring(qid) .. ":" .. tostring(o.Type) .. ":" .. tostring(o.Id or o.Description)
end

local ShowToast -- lent

local function ScanProgress()
    local now = GetTime()
    for i = 1, NS.NumLogEntries() do
        local title, isHeader, qid = NS.GetLogEntry(i)
        if not isHeader and qid then
            local q = NS.GetQuestieQuest(qid)
            if q and type(q.Objectives) == "table" then
                for _, o in pairs(q.Objectives) do
                    local c = type(o) == "table" and tonumber(o.Collected)
                    if c then
                        local key = ObjKey(qid, o)
                        local p = progress[key]
                        if not p then
                            progress[key] = { last = c, hits = {} }
                        elseif c > p.last then
                            for _ = 1, math.min(c - p.last, 10) do p.hits[#p.hits + 1] = now end
                            while #p.hits > 12 do table.remove(p.hits, 1) end
                            p.last = c
                            if ShowToast then ShowToast(qid, title, o) end
                        else
                            p.last = c
                        end
                    end
                end
            end
        end
    end
end

-- Atlagos ido / egyseg a sajat korabbi haladasbol (legalabb 2 ertelmes kozbol)
local function ObjPace(key)
    local p = progress[key]
    if not p or #p.hits < 3 then return end
    local sum, n = 0, 0
    for i = 2, #p.hits do
        local dt = p.hits[i] - p.hits[i - 1]
        if dt < MAX_GAP * 2 then sum, n = sum + dt, n + 1 end
    end
    if n >= 2 then return sum / n, n end
end

local function BestDropRate(o)
    if not o.itemId then return end
    local DB = NS.Module("QuestieDB")
    if not (DB and type(DB.GetItemDroprate) == "function") then return end
    local best
    for _, s in ipairs(o.sources or {}) do
        if s.isNpc then
            local ok, rate = pcall(DB.GetItemDroprate, o.itemId, s.id)
            if ok and type(rate) == "table" then rate = rate[1] end
            rate = tonumber(rate)
            if rate and rate > 0 and (not best or rate > best) then best = rate end
        end
    end
    return best
end

-- Visszaad: mp, info tabla { how = "pace"|"kills", guess = bool, kills, rate, per }
local function EtaSeconds(o)
    if not o or o.completed or o.turnIn or not o.qo then return end
    local c, n = tonumber(o.qo.Collected), tonumber(o.qo.Needed)
    if not (c and n) or n <= c then return end
    local remaining = n - c
    local per = o.qid and ObjPace(ObjKey(o.qid, o.qo))
    if per then
        return remaining * per, { how = "pace", per = per, remaining = remaining }
    end
    local pace, guess = KillPace()
    local t = o.qo.Type
    if t == "monster" or t == "killcredit" then
        return remaining * pace, { how = "kills", kills = remaining, per = pace, guess = guess }
    elseif t == "item" then
        local rate = BestDropRate(o)
        if rate then
            local kills = math.ceil(remaining * 100 / math.min(rate, 100))
            return kills * pace, { how = "kills", kills = kills, rate = rate, per = pace, guess = guess }
        end
    end
end

NS.PaceText = function()
    local pace, guess = KillPace()
    if guess then return "|cff808080" .. L["no data"] .. "|r" end
    return ("%ds / kill"):format(pace + 0.5)
end

local function FormatTime(sec)
    if sec < 60 then return L["<1m"] end
    local m = math.floor(sec / 60 + 0.5)
    if m < 60 then return ("~%dm"):format(m) end
    return ("~%dh %dm"):format(math.floor(m / 60), m % 60)
end

NS.EtaShort = function(o)
    local sec, info = EtaSeconds(o)
    if not sec then return end
    return FormatTime(sec) .. (info.guess and "?" or "")
end

NS.EtaLine = function(o)
    local sec, info = EtaSeconds(o)
    if not sec then return end
    local txt = L["Time left: "] .. FormatTime(sec)
    if info.how == "pace" then
        txt = txt .. (L[" (your pace: 1 per %ds)"]):format(info.per)
    elseif info.rate then
        txt = txt .. (L[" (~%d kills at %s%% drop, %ds/kill)"]):format(info.kills,
            info.rate >= 10 and ("%d"):format(info.rate) or ("%.1f"):format(info.rate), info.per)
    else
        txt = txt .. (L[" (%d kills, %ds/kill)"]):format(info.kills, info.per)
    end
    if info.guess then txt = txt .. L[" - estimated, no kill data yet"] end
    return txt
end

NS.QuestEta = function(objectives)
    local total, any, guess = 0, false, false
    for _, o in ipairs(objectives or {}) do
        local sec, info = EtaSeconds(o)
        if sec then total, any, guess = total + sec, true, guess or info.guess end
    end
    if any then return FormatTime(total) .. (guess and "?" or "") end
end

---------------------------------------------------------------------------
-- Haladas toast: kis felugro ablak a panel folott, ha nott egy objective
---------------------------------------------------------------------------
local toast = CreateFrame("Frame", "QuestFocusToast", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
toast:SetSize(250, 48)
toast:SetFrameStrata("MEDIUM")
toast:Hide()
if toast.SetBackdrop then
    toast:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    toast:SetBackdropColor(0.04, 0.04, 0.06, 0.92)
    toast:SetBackdropBorderColor(0.95, 0.78, 0.40, 0.9)
end
local accent = toast:CreateTexture(nil, "ARTWORK")
accent:SetPoint("TOPLEFT", 4, -4)
accent:SetPoint("BOTTOMLEFT", 4, 4)
accent:SetWidth(2)
accent:SetColorTexture(0.95, 0.78, 0.40, 1)
toast.label = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
toast.label:SetPoint("TOPLEFT", 12, -7)
toast.label:SetTextColor(0.95, 0.78, 0.40)
toast.right = toast:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
toast.right:SetPoint("TOPRIGHT", -9, -7)
toast.icon = toast:CreateTexture(nil, "ARTWORK")
toast.icon:SetSize(18, 18)
toast.icon:SetPoint("BOTTOMLEFT", 12, 7)
toast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
toast.text:SetPoint("LEFT", toast.icon, "RIGHT", 6, 0)
toast.text:SetPoint("RIGHT", -9, 0)
toast.text:SetJustifyH("LEFT")
toast.text:SetWordWrap(false)

local TOAST_HOLD, TOAST_FADE = 3.5, 0.6
NS.ToastFrame = toast -- a buff emlekezteto megvarja, amig ez eltunik
toast:SetScript("OnUpdate", function(self, dt)
    self.t = (self.t or 0) + dt
    if self.t > TOAST_HOLD + TOAST_FADE then
        self:Hide()
    elseif self.t > TOAST_HOLD then
        self:SetAlpha(1 - (self.t - TOAST_HOLD) / TOAST_FADE)
    end
end)

ShowToast = function(qid, title, o)
    if QuestFocusDB.noToast then return end
    -- A kijelolt quest objective-jeiben megvannak a forrasok is (drop rate-hez)
    local entry
    if state.questId == qid then
        for _, e in ipairs(state.objectives or {}) do if e.qo == o then entry = e end end
    end
    entry = entry or { qo = o, qid = qid, itemId = o.Type == "item" and o.Id or nil, sources = {} }
    local c, n = tonumber(o.Collected) or 0, tonumber(o.Needed) or 0
    local desc = tostring(o.Description or o.Text or "?")
    local done = n > 0 and c >= n
    toast.label:SetText(done and L["OBJECTIVE COMPLETE"] or L["QUEST PROGRESS"])
    local sec = not done and EtaSeconds(entry)
    toast.right:SetText(sec and (FormatTime(sec) .. L[" left"]) or (title or ""))
    toast.text:SetText((done and "|cff33ff99" or "|cffffffff") .. desc .. "|r  |cffffd100" .. ("%d/%d"):format(c, n) .. "|r")
    local tex = o.Type == "item" and o.Id and GetItemIcon and GetItemIcon(o.Id)
    toast.icon:SetTexture(tex or "Interface\\Icons\\Ability_Hunter_SniperShot")
    toast:ClearAllPoints()
    if NS.BuffAlertFrame and NS.BuffAlertFrame:IsShown() then
        toast:SetPoint("BOTTOMRIGHT", NS.BuffAlertFrame, "TOPRIGHT", 0, 4)
    elseif NS.panel:IsShown() then
        toast:SetPoint("BOTTOMRIGHT", NS.panel, "TOPRIGHT", 0, 4)
    else
        toast:SetPoint("TOP", UIParent, "TOP", 0, -160)
    end
    toast.t = 0
    toast:SetAlpha(1)
    toast:Show()
end

---------------------------------------------------------------------------
-- Vilagkoordinatak cache-elve (spawnok nem valtoznak)
---------------------------------------------------------------------------
local pointCache = {}

local function SourcePoints(src)
    local key = (src.isNpc and "m" or "o") .. tostring(src.id)
    local pts = pointCache[key]
    if pts then return pts end
    pts = {}
    if type(src.spawns) == "table" then
        for areaId, list in pairs(src.spawns) do
            local uiMap = NS.UiMapFromArea(areaId)
            if uiMap and type(list) == "table" then
                for _, c in ipairs(list) do
                    local x, y = c[1], c[2]
                    if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
                        local wc, wx, wy = NS.WorldPos(uiMap, x / 100, y / 100)
                        if wc and wx then
                            pts[#pts + 1] = { map = uiMap, x = x, y = y, wc = wc, wx = wx, wy = wy, name = src.name }
                        end
                    end
                end
            end
        end
    end
    pointCache[key] = pts
    return pts
end

local function Nearest(sources, c, x, y)
    local best, bestD
    for _, s in ipairs(sources) do
        for _, p in ipairs(SourcePoints(s)) do
            if p.wc == c then
                local d = (p.wx - x) ^ 2 + (p.wy - y) ^ 2
                if not bestD or d < bestD then best, bestD = p, d end
            end
        end
    end
    if best then return best, math.sqrt(bestD) end
end

---------------------------------------------------------------------------
-- Javaslatok
---------------------------------------------------------------------------
-- Quest log: minden questnek egy "kovetkezo allomasa" van (hatralevo objective-ek vagy leadas).
-- Mohó utvonal: mindig a legkozelebbi allomas az elozotol.
local function BuildRoute(pc, px, py)
    local stops = {}
    for i = 1, NS.NumLogEntries() do
        local title, isHeader, qid, done = NS.GetLogEntry(i)
        if not isHeader and qid then
            local q = NS.GetQuestieQuest(qid)
            if q then
                local objs = NS.CollectTargets(q, done)
                local sources = {}
                for _, o in ipairs(objs) do
                    if not o.completed then
                        for _, s in ipairs(o.sources) do sources[#sources + 1] = s end
                    end
                end
                if #sources > 0 then
                    stops[#stops + 1] = { qid = qid, title = title, done = done, sources = sources, objs = objs }
                end
            end
        end
    end
    local route, cx, cy = {}, px, py
    while #route < ROUTE_LEN and #stops > 0 do
        local bi, bp, bd
        for i, s in ipairs(stops) do
            local p, d = Nearest(s.sources, pc, cx, cy)
            if p and (not bd or d < bd) then bi, bp, bd = i, p, d end
        end
        if not bi then break end
        local s = table.remove(stops, bi)
        s.point, s.leg = bp, bd
        route[#route + 1] = s
        cx, cy = bp.wx, bp.wy
    end
    return route
end

local function IsDone(qid)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(qid) then return true end
    if IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(qid) then return true end
    local db = _G.Questie and Questie.db and Questie.db.char
    return db and type(db.complete) == "table" and db.complete[qid] and true or false
end

local starterCache = {} -- qid -> quest giver forrasok

local function BuildPickups(pc, px, py)
    local AQ = NS.Module("AvailableQuests")
    local avail = AQ and AQ.__availableQuests
    if type(avail) ~= "table" then return {} end
    local QP = NS.Module("QuestiePlayer")
    local inLog = QP and QP.currentQuestlog or {}
    local level = UnitLevel("player") or 1
    local green = GetQuestGreenRange and GetQuestGreenRange() or 8
    local list = {}
    for qid in pairs(avail) do
        if not inLog[qid] and not IsDone(qid) then
            local q = NS.GetQuestieQuest(qid)
            if q and type(q.Starts) == "table" and not q.isHidden
                and (q.requiredLevel or 0) <= level
                and not (q.level and q.level > 0 and level - q.level > green) then
                local sources = starterCache[qid]
                if not sources then
                sources = {}
                starterCache[qid] = sources
                for _, id in ipairs(type(q.Starts.NPC) == "table" and q.Starts.NPC or {}) do
                    local npc = NS.GetNPC(id)
                    if npc then sources[#sources + 1] = { id = id, name = npc.name, spawns = npc.spawns, isNpc = true } end
                end
                for _, id in ipairs(type(q.Starts.GameObject) == "table" and q.Starts.GameObject or {}) do
                    local obj = NS.GetObject(id)
                    if obj then sources[#sources + 1] = { id = id, name = obj.name, spawns = obj.spawns, isNpc = false } end
                end
                end
                local p, d = Nearest(sources, pc, px, py)
                if p then list[#list + 1] = { qid = qid, name = q.name, level = q.level, point = p, dist = d } end
            end
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    for i = #list, PICKUP_LEN + 1, -1 do list[i] = nil end
    return list
end

---------------------------------------------------------------------------
-- Panel sorok
---------------------------------------------------------------------------
local panel = NS.panel
local rows = {}

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, panel)
    r:SetSize(276, 16)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetAllPoints()
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    r:SetScript("OnClick", function(self)
        local d = self.data
        if not d then return end
        if d.kind == "route" then
            NS.SelectQuest(d.qid, d.title, d.done, true)
        elseif d.kind == "pickup" then
            NS.SetWaypoint(d.point, d.point.name or d.name)
            if state.waypoint then state.waypoint.giver = d.qid end
            NS.Print(L["Marker: quest giver |cffffff00%s|r for %s"], d.point.name or "?", d.name or "?")
        end
    end)
    r:SetScript("OnEnter", function(self)
        local d = self.data
        if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if d.kind == "route" then
            GameTooltip:SetText(d.title or "?", 1, 1, 1)
            NS.AddQuestTooltip(GameTooltip, d.qid, d.done)
            GameTooltip:AddLine(L["Click: select this quest (marker + QFocus macro)"], 0.5, 0.5, 0.5)
        else
            GameTooltip:SetText(("[%s] %s"):format(tostring(d.level or "?"), d.name or "?"), 1, 1, 1)
            GameTooltip:AddLine((L["Quest giver: %s"]):format(d.point.name or "?"), 1, 0.82, 0)
            GameTooltip:AddLine(("%s %.1f, %.1f"):format(NS.ZoneName(d.point.map), d.point.x, d.point.y), 0.6, 0.8, 1)
            GameTooltip:AddLine(L["Click: marker on the quest giver"], 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

local function Header(text)
    if not panel.sugHeaders then panel.sugHeaders = {} end
    local h = panel.sugHeaders[text]
    if not h then
        h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetJustifyH("LEFT")
        h:SetText(text)
        h:SetTextColor(0.75, 0.65, 0.45)
        panel.sugHeaders[text] = h
    end
    return h
end

NS.HideSuggestions = function()
    for _, r in ipairs(rows) do r:Hide() end
    for _, h in pairs(panel.sugHeaders or {}) do h:Hide() end
end

local function YdText(d)
    return d and ("|cff99ccff%d yd|r"):format(d) or ""
end

NS.ShowSuggestions = function()
    NS.HideSuggestions()
    if QuestFocusDB.noSuggest then return false end
    panel.title:SetText(L["What next?"])
    local y = NS.PanelChrome("list")
    if not NS.QuestieAvailable() then
        panel.sub:SetText("")
        panel.footer:SetText(L["Questie is not loaded."])
        NS.PanelFinish(y)
        return true
    end
    local pc, px, py = NS.PlayerWorldPos()
    local route, pickups = {}, {}
    if pc then
        route = BuildRoute(pc, px, py)
        pickups = BuildPickups(pc, px, py)
    end
    panel.sub:SetText((L["%d on the route, %d to pick up"]):format(#route, #pickups))

    local n = 0
    local function place(fs)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)
        fs:Show()
        y = y - 15
    end

    if #route > 0 then
        place(Header(L["Route (quest log):"]))
        for i, s in ipairs(route) do
            n = n + 1
            local r = Row(n)
            r.data = { kind = "route", qid = s.qid, title = s.title, done = s.done }
            local name = s.done and ("|cffffff00" .. L["Turn in: "] .. "|r" .. (s.title or "?")) or (s.title or "?")
            local leg = (i == 1 and "" or "+") .. YdText(s.leg and math.floor(s.leg + 0.5))
            local eta = not s.done and NS.QuestEta(s.objs)
            r.text:SetText(("%d. %s  %s%s"):format(i, name, leg, eta and ("  |cff999999" .. eta .. "|r") or ""))
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
            r:Show()
            y = y - 16
        end
        y = y - 4
    end
    if #pickups > 0 then
        place(Header(L["Pick up nearby:"]))
        for _, p in ipairs(pickups) do
            n = n + 1
            local r = Row(n)
            r.data = { kind = "pickup", qid = p.qid, name = p.name, level = p.level, point = p.point }
            local col = GetQuestDifficultyColor and p.level and GetQuestDifficultyColor(p.level)
            local hex = col and ("|cff%02x%02x%02x"):format(col.r * 255, col.g * 255, col.b * 255) or "|cffffffff"
            r.text:SetText(("%s[%s] %s|r  %s"):format(hex, tostring(p.level or "?"), p.name or "?",
                YdText(p.dist and math.floor(p.dist + 0.5))))
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
            r:Show()
            y = y - 16
        end
    end

    if n == 0 then
        panel.footer:SetText(pc and L["Nothing nearby. Select a quest in the quest log (L)."]
            or L["Position unknown here (instance?)."])
    else
        panel.footer:SetText(L["Click a row. Pick a quest in the log (L) to focus it."])
    end
    NS.PanelFinish(y)
    return true
end

-- Javaslatok frissitese, amig latszanak (mozgas kozben valtozik a sorrend)
local sugElapsed = 0
panel:HookScript("OnUpdate", function(_, dt)
    if state.questId or QuestFocusDB.noSuggest then return end
    sugElapsed = sugElapsed + dt
    if sugElapsed < 3 then return end
    sugElapsed = 0
    if not panel:IsMouseOver() then NS.ShowSuggestions() end
end)

---------------------------------------------------------------------------
-- Esemenyek
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
-- A combat logra feliratkozas ezen a kliensen tiltott addonoknak (ADDON_ACTION_FORBIDDEN),
-- ezert a killeket az XP uzenetbol szamoljuk ("X dies, you gain N experience").
ev:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:RegisterEvent("QUEST_ACCEPTED")
ev:RegisterEvent("PLAYER_LOGIN")
local scanPending = false
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "CHAT_MSG_COMBAT_XP_GAIN" then
        -- Csak a kill XP szamit (quest leadas / felfedezes XP nem): a szoveg "dies"-t tartalmaz
        pcall(function()
            if type(arg1) == "string" and arg1:find(" dies", 1, true) then RecordKill("xp" .. GetTime()) end
        end)
    elseif event == "QUEST_LOG_UPDATE" then
        -- A Questie a sajat esemenyere frissiti a Collected ertekeket: kicsit kesobb nezzuk
        if scanPending then return end
        scanPending = true
        C_Timer.After(1.5, function()
            scanPending = false
            ScanProgress()
            if not state.questId and NS.panel:IsShown() then NS.ShowSuggestions() end
        end)
    elseif event == "QUEST_ACCEPTED" then
        if state.waypoint and state.waypoint.giver and not state.questId then NS.ClearWaypoint() end
    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(10, ScanProgress)
    end
end)

-- A killSeen ne nojon vegtelenre
C_Timer.NewTicker(600, function() wipe(killSeen) end)

---------------------------------------------------------------------------
-- Kapcsolo a beallitasokban
---------------------------------------------------------------------------
local pagePanel = NS.AddOptionsTab(L["Panel"])
local cbSuggest = NS.OptCheck(L["Suggest quests when none is selected"],
    L["With no quest selected the panel shows a route through your quest log (nearest next stop each time) "]
    .. L["and nearby quests you can pick up."],
    function() return not QuestFocusDB.noSuggest end,
    function(v)
        QuestFocusDB.noSuggest = not v
        NS.Panel_Update()
    end, pagePanel)
cbSuggest:SetPoint("TOPLEFT", pagePanel, "TOPLEFT", -2, 0)

local cbToast = NS.OptCheck(L["Progress popup"],
    L["A small popup above the panel for a few seconds when an objective progresses, with the estimated time left."],
    function() return not QuestFocusDB.noToast end,
    function(v) QuestFocusDB.noToast = not v end, pagePanel)
cbToast:SetPoint("TOPLEFT", cbSuggest, "BOTTOMLEFT", 0, -6)

local etaNote = pagePanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
etaNote:SetPoint("TOPLEFT", cbToast, "BOTTOMLEFT", 2, -14)
etaNote:SetWidth(520)
etaNote:SetJustifyH("LEFT")
etaNote:SetText(L["Time left is learned from your own pace: how fast each objective counter grew, otherwise "]
    .. L["the time between your kills combined with the Questie drop rate. A '?' means there is no kill data yet."])

local resetPace = CreateFrame("Button", nil, pagePanel, "UIPanelButtonTemplate")
resetPace:SetSize(160, 22)
resetPace:SetPoint("TOPLEFT", etaNote, "BOTTOMLEFT", -2, -10)
resetPace:SetText(L["Reset kill pace"])
resetPace:SetScript("OnClick", function()
    QuestFocusDB.killPace, QuestFocusDB.killSamples = nil, nil
    wipe(progress)
    NS.Print(L["Kill pace reset."])
end)
NS.opt:HookScript("OnShow", function() cbSuggest.refresh(); cbToast.refresh() end)
