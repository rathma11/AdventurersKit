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

local MakeRow
local function Row(i)
    local r = rows[i]
    if r then return r end
    r = MakeRow(panel)
    rows[i] = r
    return r
end

-- Gorgetheto sorlista (ScrollFrame + gyerek frame + sorok); a sorokon is mukodik a gorgo
local function ScrollList()
    local sc = CreateFrame("ScrollFrame", nil, panel)
    local ch = CreateFrame("Frame", nil, sc)
    ch:SetSize(10, 10)
    sc:SetScrollChild(ch)
    sc:EnableMouseWheel(true)
    sc:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, ch:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * NS.RowH() * 2)))
        self.qfClip()
    end)
    sc:Hide()
    -- A ScrollFrame csak a rajzolast vagja le, az egeret nem: a kilogo (nem lathato) sorok a
    -- panel alja alatt elkaptak a kattintast (pl. a meretezo fogantyu elol). Ezert csak a
    -- lathato ablakba eso sorok latszanak (qfCount: hany sor ervenyes).
    sc.qfClip = function()
        local rh, top, h = NS.RowH(), sc:GetVerticalScroll(), sc:GetHeight()
        for i, r in ipairs(sc.qfList) do
            local y0 = (i - 1) * rh
            r:SetShown(i <= (sc.qfCount or 0) and y0 + rh > top + 0.5 and y0 < top + h - 0.5)
        end
        if sc.qfBar then sc.qfBar.Update() end
    end
    -- vekony arany gorgetosav a jobb szelen (UI\Panel.lua), csak ha nem fer ki minden
    if NS.AttachScrollBar then sc.qfBar = NS.AttachScrollBar(sc, sc.qfClip) end
    ch.qfScroll = sc
    local list = {}
    sc.qfList = list
    local function get(i)
        local r = list[i]
        if r then return r end
        r = MakeRow(ch)
        list[i] = r
        return r
    end
    return sc, ch, list, get
end

-- Utvonal (quest log): gorgetheto lista, az osszes allomassal; ListCounts-nyi sor latszik
local ROUTE_ALL = 40
local routeScroll, routeChild, routeRows, RouteRow = ScrollList()
-- Quest modban ugyanez a panel aljan (a quest log tobbi questje), fix magassagu teruleten
local tiScroll, tiChild, tiRows, TiRow = ScrollList()

MakeRow = function(parent)
    local r = CreateFrame("Button", nil, parent)
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
        elseif d.kind == "zone" then
            local z = d.zone
            NS.SetWaypoint(z.point, z.point.name or z.zone)
            local how = z.steps and #z.steps > 0 and NS.TransportStepsText(z.steps) or L["walk"]
            NS.Loud(NS.Print, L["Marker: |cffffff00%s|r (%s) - %s, ~%s"], z.zone or "?", z.point.name or "?", how,
                P.FormatTime(z.time or 0))
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
            if d.deferred then
                tt:AddLine(L["Skipped with the next-quest arrow: at the end of the route for now."], 0.6, 0.6, 0.6, true)
            end
            TT.Finish(tt, L["Click: focus this quest (marker + QFocus macro)"])
        elseif d.kind == "zone" then
            local z = d.zone
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(z.zone or "?", 1, 0.82, 0)
            GameTooltip:AddLine(z.kind == "log" and (L["%d quests from your log are here"]):format(z.count)
                or (L["%d quests to pick up here for your level"]):format(z.count), 1, 1, 1)
            for i, q in ipairs(z.quests) do
                if i > 8 then GameTooltip:AddLine("...", 0.6, 0.6, 0.6) break end
                GameTooltip:AddLine("  " .. (q.level and ("[" .. q.level .. "] ") or "") .. (q.title or "?"), 0.8, 0.8, 0.8)
            end
            local how = z.steps and #z.steps > 0 and NS.TransportStepsText(z.steps) or L["walk"]
            GameTooltip:AddLine((L["Way: %s, ~%s"]):format(how, P.FormatTime(z.time or 0)), 0.4, 0.8, 1, true)
            GameTooltip:AddLine(L["Click: marker there"], 0.5, 0.5, 0.5)
            GameTooltip:Show()
        else
            TT.Pickup(self, "ANCHOR_LEFT", d)
        end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- gorgetes a soron is (a sor elkapja az egeret, a gorgo a listanak szol)
    local sc = parent.qfScroll
    if sc then
        r:EnableMouseWheel(true)
        r:SetScript("OnMouseWheel", function(_, delta) sc:GetScript("OnMouseWheel")(sc, delta) end)
    end
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
    routeScroll:Hide()
    tiScroll:Hide()
    if panel.tiToggle then panel.tiToggle:Hide() end
    for _, h in pairs(panel.sugHeaders or {}) do h:Hide() end
end

local function YdText(d)
    return d and ("|cff99ccff%d yd|r"):format(d) or ""
end

-- Dungeon prep modban (Planner\Prep.lua) a panel a prep listaje: a javaslatok sajat frissitoi
-- (az alabbi OnUpdate, a QUEST_LOG_UPDATE a Planner\Events.lua-ban) nem rajzolhatnak rea.
local function PrepOwnsPanel()
    return not state.questId and NS.PrepActive and NS.PrepActive() and NS.ShowPrep and true or false
end

NS.ShowSuggestions = function()
    NS.HideSuggestions()
    if PrepOwnsPanel() then return true end
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
    local nRoute = ROUTE_LEN
    if pc then
        local nPick
        nRoute, nPick = ListCounts()
        route = BuildRoute(pc, px, py, ROUTE_ALL) -- mind (gorgetheto), nRoute sor latszik
        pickups = BuildPickups(pc, px, py, nPick)
    end
    panel.sub:SetText((L["%d on the route, %d to pick up"]):format(#route, #pickups))

    local n = 0
    local shownRoute = 0
    local function place(fs)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)
        fs:Show()
        y = y - 15
    end

    -- zona ajanlas (masik zona sok questtel / kovetkezo zona felveheto questekkel)
    local zs = pc and NS.ZoneSuggestion and NS.ZoneSuggestion()
    if zs then
        place(Header(L["Next zone:"]))
        n = n + 1
        local r = Row(n)
        r.data = { kind = "zone", zone = zs }
        local hs = zs.steps and zs.steps[1] and zs.steps[1].kind == "hs"
        local via = ""
        if zs.steps and #zs.steps > 0 then
            via = hs and ("  |cff33ff99" .. L["Hearth"] .. "|r") or ("  |cff33ff99" .. NS.TransportStepsText({ zs.steps[1] }):match("^[^:]+") .. "|r")
        end
        local what = zs.kind == "log" and (L["%d in your log"]):format(zs.count) or (L["%d to pick up"]):format(zs.count)
        r.text:SetText(("|cffffd100%s %s|r  |cffcccccc%s|r  |cff999999~%s|r%s"):format(
            hs and L["Hearth back to"] or L["Go to"], zs.zone or "?", what, P.FormatTime(zs.time or 0), via))
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
        r:Show()
        r:SetSize(NS.PW() - 24, NS.RowH())
        y = y - NS.RowH() - 4
    end

    if #route > 0 then
        -- fejlec: hany allomas; ha tobb, mint ami latszik, gorgetheto
        local more = #route > nRoute
        local h = Header(L["Route (quest log):"])
        h:SetText(more and (L["Route (quest log, %d):"]):format(#route) or L["Route (quest log):"])
        place(h)
        local rowH, w = NS.RowH(), NS.PW() - 24
        for _, r in ipairs(routeRows) do r:Hide() end
        for i, s in ipairs(route) do
            local r = RouteRow(i)
            r.data = { kind = "route", qid = s.qid, title = s.title, done = s.done, objs = s.objs, deferred = s.deferred }
            local name = s.done and ("|cffffff00" .. L["Turn in: "] .. "|r" .. (s.title or "?")) or (s.title or "?")
            local leg = YdText(s.dist and math.floor(s.dist + 0.5)) -- tolad legvonalban
            local eta = not s.done and NS.QuestEta(s.objs)
            r.text:SetText(("%d. %s  %s%s"):format(i, name, leg, eta and ("  |cff999999" .. eta .. "|r") or ""))
            r.text:SetAlpha(s.deferred and 0.45 or 1) -- atugorva (kovetkezo nyil): halvanyan, a vegen
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", routeChild, "TOPLEFT", 0, -(i - 1) * rowH)
            r:SetSize(w, rowH)
            r:Show()
        end
        local visible = math.min(#route, nRoute)
        routeChild:SetSize(w, #route * rowH)
        routeScroll:ClearAllPoints()
        routeScroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
        routeScroll:SetSize(w, visible * rowH)
        local maxScroll = math.max(0, #route * rowH - visible * rowH)
        if routeScroll:GetVerticalScroll() > maxScroll then routeScroll:SetVerticalScroll(maxScroll) end
        routeScroll.qfCount = #route
        routeScroll:Show()
        routeScroll.qfClip()
        shownRoute = #route
        y = y - visible * rowH - 4
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

    if n == 0 and shownRoute == 0 then
        panel.footer:SetText(pc and L["Nothing nearby. Select a quest in the quest log (L)."]
            or L["Position unknown here (instance?)."])
    else
        panel.footer:SetText(L["Click a row. Pick a quest in the log (L) to focus it."])
    end
    NS.PanelFinish(y, true)
    return true
end

-- Quest modban a panel aljan: a quest logod tobbi questje utvonal-sorrendben, ugyanugy mint a
-- javaslatoknal (kattintas: arra a questre valt). A panel fix magas: maxRows sor latszik
-- (UI\Panel.lua osztja el a helyet), a tobbi gorgetheto. Ha 0 sor fer ki, csak a fejlec
-- marad; arra az egeret vive tooltipben a lista.
-- y-tol rajzol, visszaadja az uj y-t. A Panel_Update hivja (UI\Panel.lua).
local TURNIN_ROUTE = 5
local tiRoute, tiKey = {}, ""
local function TurnInRoute()
    local pc, px, py = NS.PlayerWorldPos()
    if not pc then return {} end
    local ok, list = pcall(BuildRoute, pc, px, py, ROUTE_ALL + 1)
    if not ok or type(list) ~= "table" then return {} end
    local out = {}
    for _, s in ipairs(list) do
        if s.qid ~= state.questId and #out < ROUTE_ALL then out[#out + 1] = s end
    end
    return out
end
-- Az elozo / kovetkezo quest nyilaknak (Planner\QuestNav.lua): a tobbi quest utvonal-sorrendben
NS.QuestNavRoute = TurnInRoute
-- csak az elso par allomas (+ a darabszam) szamit: ha ez valtozik, ujrarajzolunk
local function TurnInKey(list)
    local t = { #list }
    for i, s in ipairs(list) do
        if i > TURNIN_ROUTE then break end
        t[#t + 1] = s.qid .. ":" .. math.floor((s.dist or 0) / 25) .. (s.deferred and "d" or "")
    end
    return table.concat(t, ",")
end

local function RouteText(i, s)
    local name = s.done and ("|cffffff00" .. L["Turn in: "] .. "|r" .. (s.title or "?")) or (s.title or "?")
    local leg = YdText(s.dist and math.floor(s.dist + 0.5)) -- tolad legvonalban
    local eta = not s.done and NS.QuestEta(s.objs)
    return ("%d. %s  %s%s"):format(i, name, leg, eta and ("  |cff999999" .. eta .. "|r") or "")
end

-- Fejlec: gomb, hogy tooltipben mutathassa a listat, ha nem latszik (vagy nem latszik mind)
local function RouteHeader()
    local b = panel.tiToggle
    if b then return b end
    b = CreateFrame("Button", nil, panel)
    b:SetSize(200, 14)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("LEFT")
    b.text:SetJustifyH("LEFT")
    b.text:SetTextColor(0.75, 0.65, 0.45)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["Route (quest log)"], 1, 0.86, 0.5)
        for i, s in ipairs(tiRoute) do
            if i > 15 then GameTooltip:AddLine("...", 0.6, 0.6, 0.6) break end
            local a = s.deferred and 0.5 or 1
            GameTooltip:AddLine(RouteText(i, s), a, a, a)
        end
        if (self.visible or 0) > 0 and #tiRoute > self.visible then
            GameTooltip:AddLine(L["Scroll the list with the mouse wheel."], 0.45, 0.45, 0.45, true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.tiToggle = b
    return b
end

-- Az utvonal elore kiszamolasa (a Panel_Update ebbol osztja el a helyet); visszaadja a hosszat
NS.PrepareTurnInRoute = function()
    if QuestFocusDB.noSuggest or not NS.QuestieAvailable() then tiRoute = {} return 0 end
    tiRoute = TurnInRoute()
    tiKey = TurnInKey(tiRoute)
    return #tiRoute
end

-- prepared: a PrepareTurnInRoute ebben a frissitesben mar lefutott (nem szamoljuk ujra)
NS.ShowTurnInPickups = function(y, maxRows, prepared)
    if QuestFocusDB.noSuggest or not NS.QuestieAvailable() then return y end
    if not prepared then
        tiRoute = TurnInRoute()
        tiKey = TurnInKey(tiRoute)
    end
    if #tiRoute == 0 then return y end
    local rowH, w = NS.RowH(), NS.PW() - 24
    local visible = math.max(0, math.min(#tiRoute, maxRows or TURNIN_ROUTE))
    y = y - 4
    local h = RouteHeader()
    h.visible = visible
    local hidden = #tiRoute - visible
    h.text:SetText(hidden > 0
        and (L["Route (quest log):"] .. "  |cff999999" .. (visible > 0 and (L["%d stops"]):format(#tiRoute)
            or (L["%d stops - hover"]):format(#tiRoute)) .. "|r")
        or L["Route (quest log):"])
    h:SetSize(math.min(w, math.ceil(h.text:GetStringWidth()) + 4), 14)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y + 1)
    h:Show()
    y = y - 15
    if visible == 0 then return y end
    for i, s in ipairs(tiRoute) do
        local r = TiRow(i)
        r.data = { kind = "route", qid = s.qid, title = s.title, done = s.done, objs = s.objs, deferred = s.deferred }
        r.text:SetText(RouteText(i, s))
        r.text:SetAlpha(s.deferred and 0.45 or 1) -- atugorva (kovetkezo nyil): halvanyan, a vegen
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", tiChild, "TOPLEFT", 0, -(i - 1) * rowH)
        r:SetSize(w, rowH)
    end
    tiChild:SetSize(w, #tiRoute * rowH)
    tiScroll:ClearAllPoints()
    tiScroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    tiScroll:SetSize(w, visible * rowH)
    local maxScroll = math.max(0, (#tiRoute - visible) * rowH)
    if tiScroll:GetVerticalScroll() > maxScroll then tiScroll:SetVerticalScroll(maxScroll) end
    tiScroll.qfCount = #tiRoute
    tiScroll:Show()
    tiScroll.qfClip()
    return y - visible * rowH
end

-- Javaslatok frissitese, amig latszanak (mozgas kozben valtozik a sorrend)
local sugElapsed = 0
panel:HookScript("OnUpdate", function(_, dt)
    if QuestFocusDB.noSuggest then return end
    sugElapsed = sugElapsed + dt
    if sugElapsed < 3 then return end
    sugElapsed = 0
    if panel:IsMouseOver() or PrepOwnsPanel() then return end
    if not state.questId then
        NS.ShowSuggestions()
    elseif NS.QuestieAvailable() then
        -- quest mod: csak akkor rajzoljuk ujra, ha az utvonal eleje (vagy ~25 yd-os tavolsag) valtozott
        local pc, px, py = NS.PlayerWorldPos()
        if not pc then return end
        if TurnInKey(TurnInRoute()) ~= tiKey and NS.Panel_Update then NS.Panel_Update() end
    end
end)

