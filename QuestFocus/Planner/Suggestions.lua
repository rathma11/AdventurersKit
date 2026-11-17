local ADDON_NAME, NS = ...
local L = NS.L
NS.P = NS.P or {}
local P = NS.P
local BuildPickups, BuildRoute, PICKUP_LEN, ROUTE_LEN, state = P.BuildPickups, P.BuildRoute, P.PICKUP_LEN, P.ROUTE_LEN, P.state

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
    r.text = r:CreateFontString(nil, "OVERLAY", "QuestFocusFontSmall")
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
        local TT = NS.TT
        if d.kind == "route" then
            local objs = d.objs
            if not objs then
                local q = NS.GetQuestieQuest(d.qid)
                objs = q and NS.CollectTargets(q, d.done) or {}
            end
            local tt = TT.Begin(self, "ANCHOR_LEFT", d.title or "?", TT.Progress(objs, d.done))
            TT.Objectives(tt, objs)
            TT.Finish(tt, L["Click: focus this quest (marker + QFocus macro)"])
        else
            TT.Pickup(self, "ANCHOR_LEFT", d)
        end
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

-- Hany sor fer ki a javaslatokbol: a panel huzott magassagabol (QuestFocusDB.panelH)
-- szamoljuk; alapbol 5 utvonal + 3 felveheto. A tobbletnek kb. 60%-a utvonal.
local function ListCounts()
    local h = tonumber(QuestFocusDB.panelH)
    if not h then return ROUTE_LEN, PICKUP_LEN end
    local rowH = NS.RowH()
    local avail = h - 56 - 2 * 15 - 8 - (rowH + 22)
    local n = math.max(ROUTE_LEN + PICKUP_LEN, math.floor(avail / rowH))
    local route = math.max(ROUTE_LEN, math.ceil(n * 0.6))
    return route, math.max(PICKUP_LEN, n - route)
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
        NS.PanelFinish(y, true)
        return true
    end
    local pc, px, py = NS.PlayerWorldPos()
    local route, pickups = {}, {}
    if pc then
        local nRoute, nPick = ListCounts()
        route = BuildRoute(pc, px, py, nRoute)
        pickups = BuildPickups(pc, px, py, nPick)
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
            r.data = { kind = "route", qid = s.qid, title = s.title, done = s.done, objs = s.objs }
            local name = s.done and ("|cffffff00" .. L["Turn in: "] .. "|r" .. (s.title or "?")) or (s.title or "?")
            local leg = (i == 1 and "" or "+") .. YdText(s.leg and math.floor(s.leg + 0.5))
            local eta = not s.done and NS.QuestEta(s.objs)
            r.text:SetText(("%d. %s  %s%s"):format(i, name, leg, eta and ("  |cff999999" .. eta .. "|r") or ""))
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
            r:Show()
            r:SetSize(NS.PW() - 24, NS.RowH())
            y = y - NS.RowH()
        end
        y = y - 4
    end
    if #pickups > 0 then
        place(Header(L["Pick up nearby:"]))
        for _, p in ipairs(pickups) do
            n = n + 1
            local r = Row(n)
            r.data = { kind = "pickup", qid = p.qid, name = p.name, level = p.level, point = p.point,
                dist = p.dist and math.floor(p.dist + 0.5) }
            local col = GetQuestDifficultyColor and p.level and GetQuestDifficultyColor(p.level)
            local hex = col and ("|cff%02x%02x%02x"):format(col.r * 255, col.g * 255, col.b * 255) or "|cffffffff"
            r.text:SetText(("%s[%s] %s|r  %s"):format(hex, tostring(p.level or "?"), p.name or "?",
                YdText(p.dist and math.floor(p.dist + 0.5))))
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
            r:Show()
            r:SetSize(NS.PW() - 24, NS.RowH())
            y = y - NS.RowH()
        end
    end

    if n == 0 then
        panel.footer:SetText(pc and L["Nothing nearby. Select a quest in the quest log (L)."]
            or L["Position unknown here (instance?)."])
    else
        panel.footer:SetText(L["Click a row. Pick a quest in the log (L) to focus it."])
    end
    NS.PanelFinish(y, true)
    return true
end

-- Leadas modban a panel aljan: a quest logod tobbi questje utvonal-sorrendben (max 5),
-- ugyanugy mint a javaslatoknal (kattintas: arra a questre valt).
-- y-tol rajzol, visszaadja az uj y-t. A Panel_Update hivja (UI\Panel.lua).
local TURNIN_ROUTE = 5
local tiRoute, tiKey = {}, ""
local function TurnInRoute()
    local pc, px, py = NS.PlayerWorldPos()
    if not pc then return {} end
    local ok, list = pcall(BuildRoute, pc, px, py, TURNIN_ROUTE + 1)
    if not ok or type(list) ~= "table" then return {} end
    local out = {}
    for _, s in ipairs(list) do
        if s.qid ~= state.questId and #out < TURNIN_ROUTE then out[#out + 1] = s end
    end
    return out
end
local function TurnInKey(list)
    local t = {}
    for i, s in ipairs(list) do t[i] = s.qid .. ":" .. math.floor((s.leg or 0) / 25) end
    return table.concat(t, ",")
end
NS.ShowTurnInPickups = function(y)
    if QuestFocusDB.noSuggest or not NS.QuestieAvailable() then return y end
    tiRoute = TurnInRoute()
    tiKey = TurnInKey(tiRoute)
    if #tiRoute == 0 then return y end
    y = y - 4
    local h = Header(L["Route (quest log):"])
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)
    h:Show()
    y = y - 15
    for i, s in ipairs(tiRoute) do
        local r = Row(i)
        r.data = { kind = "route", qid = s.qid, title = s.title, done = s.done, objs = s.objs }
        local name = s.done and ("|cffffff00" .. L["Turn in: "] .. "|r" .. (s.title or "?")) or (s.title or "?")
        local leg = (i == 1 and "" or "+") .. YdText(s.leg and math.floor(s.leg + 0.5))
        local eta = not s.done and NS.QuestEta(s.objs)
        r.text:SetText(("%d. %s  %s%s"):format(i, name, leg, eta and ("  |cff999999" .. eta .. "|r") or ""))
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
        r:SetSize(NS.PW() - 24, NS.RowH())
        r:Show()
        y = y - NS.RowH()
    end
    return y
end

-- Javaslatok frissitese, amig latszanak (mozgas kozben valtozik a sorrend)
local sugElapsed = 0
panel:HookScript("OnUpdate", function(_, dt)
    if QuestFocusDB.noSuggest then return end
    sugElapsed = sugElapsed + dt
    if sugElapsed < 3 then return end
    sugElapsed = 0
    if panel:IsMouseOver() then return end
    if not state.questId then
        NS.ShowSuggestions()
    elseif state.isComplete and NS.QuestieAvailable() then
        -- leadas mod: csak akkor rajzoljuk ujra, ha a kozeli lista (vagy ~25 yd-os tavolsag) valtozott
        local pc, px, py = NS.PlayerWorldPos()
        if not pc then return end
        if TurnInKey(TurnInRoute()) ~= tiKey and NS.Panel_Update then NS.Panel_Update() end
    end
end)

