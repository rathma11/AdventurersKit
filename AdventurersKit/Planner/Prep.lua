-- Dungeon prep mod: egy valasztott dungeonhoz a panel a felveheto (meg nem felvett) questjeit
-- mutatja (quest ado, zona, tavolsag), a mar logban levoket keszkent, a vegen a bejaratot.
-- A marker / nyil a legkozelebbi quest adora mutat, ha mind megvan, a bejaratra (vagy amelyik
-- sorra kattintasz). A macro nem mob-ot targetel: a kozeli quest adot (/targetexact), kulonben
-- inert. Karakterenkent mentve (NS.CharDB().prepDungeon), reload utan is megmarad.
-- Belepes: dungeon lista "Prep" gomb / jobb klikk, /qf dungeon <nev>. Kilepes: a fokusz torles
-- gomb a cim mellett, vagy /qf dungeon off.
local ADDON_NAME, NS = ...
local L = NS.L
local P = NS.P

local panel = NS.panel
local GIVER_NEAR = 60 -- yd: ezen belul a macro a quest adot targeteli
local SKULL = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
local ICON_DONE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t "
local ICON_TODO = "|TInterface\\GossipFrame\\AvailableQuestIcon:12:12|t "
local ICON_FAR = "|TInterface\\COMMON\\Indicator-Gray:12:12|t "
local ICON_SEL = "|TInterface\\COMMON\\Indicator-Green:12:12|t "
local ICON_DOOR = "|T" .. SKULL .. ":12:12|t "

local prep = { dungeon = nil, rows = {}, sel = nil, dirty = true }
local acceptedAt = 0

local function CharDB() return NS.CharDB and NS.CharDB() end
local function Saved()
    local c = CharDB()
    return c and rawget(c, "prepDungeon")
end

NS.PrepActive = function() return prep.dungeon end

---------------------------------------------------------------------------
-- Adatok
---------------------------------------------------------------------------
local function EntrancePoint(name)
    local e = NS.DungeonEntrances and NS.DungeonEntrances[name]
    if not e then
        -- "Scarlet Monastery: Library" -> "Scarlet Monastery" stb.
        local base = name and name:match("^(.-):")
        e = base and NS.DungeonEntrances and NS.DungeonEntrances[base]
    end
    if not e then return end
    local pc, px, py = NS.PlayerWorldPos()
    local best, bestD, first
    for _, t in ipairs(e.pts or {}) do
        local wc, wx, wy = NS.WorldPos(t[1], t[2], t[3])
        local p = { map = t[1], x = t[2] * 100, y = t[3] * 100, wc = wc, wx = wx, wy = wy }
        first = first or p
        if pc and wc == pc and wx then
            local d = math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
            if not bestD or d < bestD then best, bestD = p, d end
        end
    end
    return best or first, bestD, e.detail
end

-- Felveheto-e most: a Questie AvailableQuests listaja (ha ismeri a questet), kulonben a szint
local function Available(qid, q, requires)
    local AQ = NS.Module("AvailableQuests")
    local avail = AQ and type(AQ.__availableQuests) == "table" and AQ.__availableQuests
    if q and avail then return avail[qid] and true or false end
    return (tonumber(requires) or 0) <= (UnitLevel("player") or 1)
end

local function Build()
    prep.dirty = false
    local rows = {}
    local name = prep.dungeon
    if not name then prep.rows = rows return end
    local e = NS.CollectDungeon and NS.CollectDungeon(name)
    prep.info = e
    local pc, px, py = NS.PlayerWorldPos()
    local pickups, have, insideList = {}, {}, {}
    for _, d in ipairs(e and e.quests or {}) do
        local q = NS.GetQuestieQuest(d.qid)
        if d.inLog then
            have[#have + 1] = { kind = "have", qid = d.qid, name = d.name or (q and q.name), level = d.level }
        elseif Available(d.qid, q, d.requires) then
            local r = { kind = "pickup", qid = d.qid, name = d.name or (q and q.name), level = d.level,
                requires = d.requires, note = d.note }
            if q and type(q.Starts) == "table" then
                local sources = P.QuestStarters(d.qid, q)
                r.sources = sources
                r.giver = sources[1] and sources[1].name
                local p, dist
                if pc then p, dist = P.Nearest(sources, pc, px, py) end
                if not p then
                    -- masik kontinensen: az elso ismert pont (a zona neve miatt)
                    for _, s in ipairs(sources) do
                        local pts = P.SourcePoints(s)
                        if pts[1] then p = pts[1] break end
                    end
                end
                r.point, r.dist = p, dist
            end
            r.giver = r.giver or d.note
            -- bent indulo quest (a quest ado csak az instance-ban van, vagy a Journal szerint
            -- "inside"): nem kulon sor, hanem egy "+N bent indul" megjegyzes
            local inside = false
            if not r.point then
                if r.sources and #r.sources > 0 and NS.PrepSpawnsInside then
                    inside = true
                    for _, s in ipairs(r.sources) do
                        if not NS.PrepSpawnsInside(s.spawns) then inside = false break end
                    end
                end
                if not inside and type(d.note) == "string" and d.note:lower():find("inside", 1, true) then inside = true end
            end
            if inside then insideList[#insideList + 1] = r else pickups[#pickups + 1] = r end
        elseif d.qid and not NS.QuestIsDone(d.qid) and q and type(q.Starts) == "table" and type(q.Starts.Item) == "table"
            and type(d.note) == "string" and d.note:lower():find("inside", 1, true) then
            -- itemrol indul a dungeonban (nem "felveheto" a Questie szerint)
            insideList[#insideList + 1] = { kind = "pickup", qid = d.qid, name = d.name or q.name, level = d.level, giver = d.note }
        end
    end
    -- legkozelebbi elol; hely nelkuliek (pl. a dungeonban indulo quest) a vegen
    table.sort(pickups, function(a, b)
        local da = a.dist or (a.point and 1e8) or 2e8
        local db = b.dist or (b.point and 1e8) or 2e8
        if da ~= db then return da < db end
        return (a.name or "") < (b.name or "")
    end)
    table.sort(have, function(a, b) return (a.level or 0) < (b.level or 0) end)
    for _, r in ipairs(pickups) do rows[#rows + 1] = r end
    for _, r in ipairs(have) do rows[#rows + 1] = r end
    if #insideList > 0 then rows[#rows + 1] = { kind = "note", list = insideList } end
    local ep, ed, detail = EntrancePoint(name)
    rows[#rows + 1] = { kind = "entrance", name = name, point = ep, dist = ed, detail = detail }
    prep.rows = rows
end

local function RowKey(r) return r and (r.kind == "entrance" and "entrance" or r.qid) end
local function FindRow(key)
    for i, r in ipairs(prep.rows) do if RowKey(r) == key then return r, i end end
end

-- Automatikus cel: a legkozelebbi felveheto quest adoja (aminek ismert a helye), kulonben a bejarat
local function AutoTarget()
    for _, r in ipairs(prep.rows) do
        if r.kind == "pickup" and r.point then return r end
    end
    return prep.rows[#prep.rows]
end

-- Kijelolt sor, kulonben a mar markerezett (ha meg ugyanolyan: quest ado / bejarat, hogy a
-- marker ne ugraljon, ahogy mozogsz), kulonben az automatikus
local function Target()
    local r = prep.sel and FindRow(prep.sel)
    if r then return r end
    local a = AutoTarget()
    local m = prep.markedKey and FindRow(prep.markedKey)
    if m and a and m.kind == a.kind then return m end
    return a
end

---------------------------------------------------------------------------
-- Marker es macro
---------------------------------------------------------------------------
local function MarkRow(r, quiet)
    if not (r and r.point) then
        if not quiet then
            NS.Loud(NS.Print, r and r.kind == "entrance" and L["No known entrance location for %s."]
                or L["No known location for the quest giver of %s."], r and r.name or "?")
        end
        return
    end
    local title = r.kind == "entrance" and (L["%s entrance"]):format(r.name or "?") or (r.giver or r.name)
    NS.SetWaypoint(r.point, title)
    prep.markedKey = RowKey(r)
    if quiet then return end
    if r.kind == "entrance" then
        NS.Print(L["Marker: |cffffff00%s|r entrance - %s"], r.name or "?", NS.ZoneName(r.point.map))
    else
        NS.Print(L["Marker: quest giver |cffffff00%s|r for %s"], r.giver or "?", r.name or "?")
    end
end

local lastBody
local function PrepMacro()
    if not prep.dungeon or (NS.PrepIsInside and NS.PrepIsInside()) then return end
    local body = '/run UIErrorsFrame:AddMessage("QFocus: dungeon prep - no quest giver nearby",1,.8,.2)'
    local giver
    local t = Target()
    -- a kijelolt (vagy legkozelebbi) quest ado, ha kozel van; kulonben barmelyik kozeli
    local cands = {}
    if t and t.kind == "pickup" then cands[1] = t end
    for _, r in ipairs(prep.rows) do if r.kind == "pickup" and r ~= t then cands[#cands + 1] = r end end
    for _, r in ipairs(cands) do
        if r.point and r.dist and r.dist <= GIVER_NEAR and r.giver and r.sources and r.sources[1]
            and r.sources[1].isNpc then
            giver = r.giver
            break
        end
    end
    if giver then body = "/targetexact " .. giver end
    prep.macroGiver = giver
    if body ~= lastBody or NS.state.pendingBody then
        lastBody = body
        if NS.C.ApplyMacro then NS.C.ApplyMacro(body) end
    end
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local scroll = CreateFrame("ScrollFrame", nil, panel)
local child = CreateFrame("Frame", nil, scroll)
child:SetSize(10, 10)
scroll:SetScrollChild(child)
scroll:EnableMouseWheel(true)
scroll:Hide()
local lines = {}
local function Clip()
    local rh, top, h = NS.RowH() + 1, scroll:GetVerticalScroll(), scroll:GetHeight()
    for i, r in ipairs(lines) do
        local y0 = (i - 1) * rh
        r:SetShown(i <= (scroll.qfCount or 0) and y0 + rh > top + 0.5 and y0 < top + h - 0.5)
    end
    if scroll.qfBar then scroll.qfBar.Update() end
end
scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, child:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * (NS.RowH() + 1))))
    Clip()
end)
if NS.AttachScrollBar then scroll.qfBar = NS.AttachScrollBar(scroll, Clip) end

local function TravelLine(p)
    local r = p and p.wx and NS.TravelAdvice and NS.TravelAdvice(p)
    if not r then return end
    local t = r.bestTime or r.walk
    local how = NS.BestWayText and NS.BestWayText(r)
    if not t then return how and (L["Way: %s"]):format(how) end
    local m = math.floor(t / 60)
    return (L["Way: %s, ~%s"]):format(how or L["walk"], t < 60 and ("%ds"):format(t) or ("%dm %02ds"):format(m, t % 60))
end

local function Line(i)
    local r = lines[i]
    if r then return r end
    r = CreateFrame("Button", nil, child)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.text = r:CreateFontString(nil, "OVERLAY", "QuestFocusFontSmall")
    r.text:SetAllPoints()
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(_, delta) scroll:GetScript("OnMouseWheel")(scroll, delta) end)
    r:SetScript("OnClick", function(self, button)
        local d = self.data
        if not d then return end
        if button == "RightButton" then
            -- vissza az automatikus celra (legkozelebbi quest ado, aztan a bejarat)
            prep.sel, prep.markedKey = nil, nil
            MarkRow(AutoTarget())
        elseif d.kind == "have" or d.kind == "note" then
            -- (a quest logban kijelolni nem lehet: az fokuszt valtana es kilepne a prep modbol)
            return
        else
            prep.sel = RowKey(d)
            MarkRow(d)
        end
        PrepMacro()
        if NS.Panel_Update then NS.Panel_Update() end
    end)
    r:SetScript("OnEnter", function(self)
        local d = self.data
        if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if d.kind == "note" then
            GameTooltip:SetText(L["Quests that start inside the dungeon"], 1, 0.82, 0)
            for _, x in ipairs(d.list) do
                GameTooltip:AddLine(("[%s] %s"):format(tostring(x.level or "?"), x.name or "?"), 1, 1, 1)
                if x.giver then GameTooltip:AddLine("    " .. x.giver, 0.7, 0.7, 0.7, true) end
            end
            GameTooltip:AddLine(L["Inside, the panel lists them where they come in the run."], 0.5, 0.5, 0.5, true)
            GameTooltip:Show()
            return
        elseif d.kind == "entrance" then
            GameTooltip:SetText((L["%s entrance"]):format(d.name or "?"), 1, 0.6, 0.45)
            if d.point then
                GameTooltip:AddLine(("%s %.1f, %.1f"):format(NS.ZoneName(d.point.map), d.point.x, d.point.y), 1, 1, 1)
            else
                GameTooltip:AddLine(L["No known entrance location."], 1, 0.4, 0.4)
            end
            if d.detail then GameTooltip:AddLine(d.detail, 0.8, 0.8, 0.8, true) end
            local tl = TravelLine(d.point)
            if tl then GameTooltip:AddLine(tl, 0.4, 0.8, 1, true) end
            GameTooltip:AddLine(L["Click: marker on the entrance"], 0.5, 0.5, 0.5)
        else
            GameTooltip:SetText(("[%s] %s"):format(tostring(d.level or "?"), d.name or "?"), 1, 1, 1)
            if d.kind == "have" then
                GameTooltip:AddLine(L["Already in your quest log"], 0.4, 1, 0.4)
            else
                if d.requires then GameTooltip:AddLine((L["Requires level %d"]):format(d.requires), 0.8, 0.8, 0.8) end
                if d.giver then GameTooltip:AddLine((L["Quest giver: %s"]):format(d.giver), 0.8, 0.8, 0.8, true) end
                if d.note and d.note ~= d.giver then GameTooltip:AddLine(d.note, 0.6, 0.6, 0.6, true) end
                if d.point then
                    GameTooltip:AddLine(("%s %.1f, %.1f"):format(NS.ZoneName(d.point.map), d.point.x, d.point.y), 1, 1, 1)
                    local tl = TravelLine(d.point)
                    if tl then GameTooltip:AddLine(tl, 0.4, 0.8, 1, true) end
                    GameTooltip:AddLine(L["Click: marker on the quest giver"], 0.5, 0.5, 0.5)
                else
                    GameTooltip:AddLine(L["No known location for the quest giver."], 1, 0.4, 0.4, true)
                end
            end
        end
        GameTooltip:AddLine(L["Right click: back to automatic (nearest quest giver, then the entrance)"], 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    lines[i] = r
    return r
end

local function HideOutside()
    scroll:Hide()
    for _, r in ipairs(lines) do r:Hide() end
end
NS.HidePrep = function()
    HideOutside()
    if NS.HidePrepInside then NS.HidePrepInside() end
end
local function Inside() return NS.PrepIsInside and NS.PrepIsInside() end

local function YdText(d) return d and ("|cff99ccff%d yd|r"):format(d) or nil end

local function FooterText()
    local w = NS.state.waypoint
    local dist
    if w and w.wx then
        local pc, px, py = NS.PlayerWorldPos()
        if pc and pc == w.wc then dist = math.floor(math.sqrt((px - w.wx) ^ 2 + (py - w.wy) ^ 2) + 0.5) end
    end
    local m = prep.macroGiver and (L["|cff33ff99Macro:|r targets %s"]):format(prep.macroGiver)
        or L["Macro: idle (no quest giver nearby)"]
    return m .. (dist and (L[" - marker: "] .. YdText(dist)) or "")
end

-- Panel_Update hivja (UI\Panel.lua), ha a prep mod aktiv
NS.ShowPrep = function()
    -- a dungeonon belul: a beluli fazis listaja (Planner\PrepInside.lua)
    if Inside() and NS.ShowPrepInside then
        HideOutside()
        return NS.ShowPrepInside()
    end
    if NS.HidePrepInside then NS.HidePrepInside() end
    if prep.dirty then Build() end
    local name = prep.dungeon or "?"
    panel.title:SetText((L["Prep: %s"]):format(name))
    panel.title:SetWidth(NS.PW() - 100)
    panel.title:SetWidth(math.min(math.ceil(panel.title:GetStringWidth()) + 2, NS.PW() - 100))
    panel.icon:SetTexture(SKULL)
    local nPick, nHave = 0, 0
    local entrance
    for _, r in ipairs(prep.rows) do
        if r.kind == "pickup" then nPick = nPick + 1 elseif r.kind == "have" then nHave = nHave + 1
        elseif r.kind == "entrance" then entrance = r end
    end
    local ez = entrance and entrance.point and NS.ZoneName(entrance.point.map)
    panel.sub:SetText((L["%d to pick up, %d in log"]):format(nPick, nHave) .. (ez and ("  |cffff9070" .. ez .. "|r") or ""))
    local info = prep.info
    local sect = info and info.lo and (L["DUNGEON PREP (level %d-%d)"]):format(info.lo, info.hi) or L["DUNGEON PREP"]
    local y = NS.PanelChrome("list", sect)
    local rh, w = NS.RowH(), NS.PW() - 24
    local step = rh + 1
    local t = Target()
    local tKey = RowKey(t)
    for i, d in ipairs(prep.rows) do
        local r = Line(i)
        r.data = d
        r:SetSize(w, rh)
        local sel = RowKey(d) == tKey
        local txt
        if d.kind == "entrance" then
            local open = nPick > 0
            txt = (sel and ICON_SEL or ICON_DOOR) .. (open and "|cffd0a080" or "|cffff9070")
                .. (L["Entrance: %s"]):format(ez or L["unknown"]) .. "|r"
                .. (d.dist and ("  " .. YdText(math.floor(d.dist + 0.5))) or "")
        elseif d.kind == "have" then
            txt = ICON_DONE .. ("|cff808080[%s] %s|r  |cff60a060(%s)|r"):format(tostring(d.level or "?"), d.name or "?", L["in log"])
        elseif d.kind == "note" then
            txt = "|TInterface\\GossipFrame\\AvailableQuestIcon:12:12|t |cffffff00"
                .. (L["+%d quests start inside the dungeon"]):format(#d.list) .. "|r"
        else
            local where = d.point and NS.ZoneName(d.point.map)
            local dist = d.dist and YdText(math.floor(d.dist + 0.5))
            local col = sel and "|cff33ff99" or (d.point and "|cffffffff" or "|cffaaaaaa")
            txt = (sel and ICON_SEL or (d.point and ICON_TODO or ICON_FAR)) .. col
                .. ("[%s] %s|r"):format(tostring(d.level or "?"), d.name or "?")
                .. ("  |cffd8c8a0%s|r"):format(d.giver or "?")
                .. (where and (" |cff999999- " .. where .. "|r") or "")
                .. (dist and ("  " .. dist) or "")
        end
        r.text:SetText(txt)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * step)
    end
    for i = #prep.rows + 1, #lines do lines[i]:Hide() end
    -- lathato sorok: a huzott panel magassagabol (javaslat modhoz hasonloan), alapbol max 12
    local maxRows = 12
    local ph = tonumber(QuestFocusDB.panelH)
    if ph then maxRows = math.max(4, math.floor((ph - (-y) - (8 + rh + 12)) / step)) end
    local vis = math.min(#prep.rows, maxRows)
    child:SetSize(w, math.max(1, #prep.rows * step))
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    scroll:SetSize(w, math.max(1, vis * step))
    local maxScroll = math.max(0, (#prep.rows - vis) * step)
    if scroll:GetVerticalScroll() > maxScroll then scroll:SetVerticalScroll(maxScroll) end
    scroll.qfCount = #prep.rows
    scroll:Show()
    Clip()
    y = y - vis * step
    panel.footer:SetText(FooterText())
    NS.PanelFinish(y, true)
    return true
end

---------------------------------------------------------------------------
-- Be / ki
---------------------------------------------------------------------------
local function Resolve(text)
    local names = NS.DungeonNames and NS.DungeonNames() or {}
    local low = text:lower()
    for _, n in ipairs(names) do if n:lower() == low then return n end end
    local hits = {}
    for _, n in ipairs(names) do if n:lower():find(low, 1, true) == 1 then hits[#hits + 1] = n end end
    if #hits == 0 then
        for _, n in ipairs(names) do
            -- "deadmines" -> "The Deadmines", "kroldok" -> "Krol'dok Stronghold"
            local plain = n:lower():gsub("[^%w ]", "")
            if n:lower():find(low, 1, true) or plain:find(low:gsub("[^%w ]", ""), 1, true) then hits[#hits + 1] = n end
        end
    end
    if #hits == 1 then return hits[1] end
    return nil, hits, names
end

-- Quest log valtozas utan: ujraepites; ha a markerezett quest adotol felvetted a questet,
-- a marker a kovetkezore (vegul a bejaratra) lep
local function Refresh()
    if not prep.dungeon then return end
    Build()
    if prep.sel and not FindRow(prep.sel) then prep.sel = nil end
    local t = Target()
    if t and RowKey(t) ~= prep.markedKey then
        MarkRow(t, true)
        if t.kind == "entrance" and t.point then
            NS.Loud(NS.Print, L["All %s quests picked up - marker on the entrance (%s)."], prep.dungeon, NS.ZoneName(t.point.map))
        end
    end
    PrepMacro()
    if NS.Panel_Update then NS.Panel_Update() end
end
-- (Planner\PrepInside.lua: az instance-bol kilepve vissza a prep listahoz, ujra markerrel)
NS.PrepRefresh = function(force)
    if force then prep.markedKey, prep.sel = nil, nil end
    lastBody = nil
    Refresh()
end

NS.StartPrep = function(name, restoring)
    if not name then return end
    -- az elozo allapot (fokuszalt quest + objective) a megszakitashoz (StopPrep restore)
    if not restoring and not prep.dungeon then
        local st = NS.state
        local prev = st.questId and { qid = st.questId, title = st.title, obj = st.objIndex } or nil
        local c0 = CharDB()
        if c0 and QuestFocusDB then c0.prepPrev = prev end
    end
    if NS.C.ClearQuest and NS.state.questId then NS.C.ClearQuest() end
    prep.dungeon, prep.sel, prep.markedKey, prep.dirty = name, nil, nil, true
    local c = CharDB()
    if c and QuestFocusDB then c.prepDungeon = name end
    if not restoring then
        QuestFocusDB.hidePanel = false
        if NS.ReleasePanelHold then NS.ReleasePanelHold() end
    end
    lastBody = nil
    Build()
    MarkRow(Target(), restoring)
    PrepMacro()
    if NS.Panel_Update then NS.Panel_Update() end
    if not restoring then
        local n = 0
        for _, r in ipairs(prep.rows) do if r.kind == "pickup" then n = n + 1 end end
        NS.Loud(NS.Print, L["Dungeon prep: |cffffff00%s|r - %d quests to pick up, then the entrance. Leave: the X next to the title, or /qf dungeon off."],
            name, n)
    end
    -- mar a dungeonban vagy: rogton a beluli fazis
    if NS.PrepCheckInside then NS.PrepCheckInside() end
end

NS.StopPrep = function(quiet, restore)
    if not prep.dungeon then return end
    local old = prep.dungeon
    local c1 = CharDB()
    local prev = c1 and rawget(c1, "prepPrev")
    if c1 and QuestFocusDB then c1.prepPrev = nil end
    prep.dungeon, prep.rows, prep.sel, prep.markedKey, prep.info = nil, {}, nil, nil, nil
    if NS.PrepInsideReset then NS.PrepInsideReset() end
    local c = CharDB()
    if c and QuestFocusDB then c.prepDungeon = nil end
    NS.HidePrep()
    NS.ClearWaypoint()
    lastBody = nil
    if NS.C.ApplyMacro then NS.C.ApplyMacro('/run print("QFocus: no quest selected")') end
    if NS.Panel_Update then NS.Panel_Update() end
    if not quiet then NS.Loud(NS.Print, L["Dungeon prep ended (%s)."], old) end
    -- megszakitas: vissza az elozo questre (ha meg a logban van), kulonben javaslatok
    if restore and prev and prev.qid then
        local title, done = NS.FindQuestInLog(prev.qid)
        if title then
            NS.SelectQuest(prev.qid, title, done, true)
            if prev.obj and NS.state.questId == prev.qid and NS.state.objectives and NS.state.objectives[prev.obj] then
                NS.SelectObjective(prev.obj)
            end
        end
    end
end

-- /qf dungeon <nev> | off
NS.PrepCommand = function(arg)
    arg = (arg or ""):match("^%s*(.-)%s*$")
    local low = arg:lower()
    if low == "off" or low == "stop" or low == "clear" or low == "end" then
        if prep.dungeon then NS.StopPrep(false, true) else NS.Print(L["Dungeon prep is not on."]) end
        return
    end
    local name, hits, all = Resolve(arg)
    if name then NS.StartPrep(name) return end
    if hits and #hits > 1 then
        NS.Print(L["Several dungeons match: %s"], table.concat(hits, ", "))
    else
        NS.Print(L["No dungeon matches \"%s\". Known: %s"], arg, table.concat(all or {}, ", "))
    end
end

-- Kattintott quest (fokusz) a prep modban: ha te valasztottad (nem a quest felvetel utani
-- automatikus kijeloles), a prep mod veget er es a quest jon; kulonben a prep marad.
NS.PrepBlocksSelect = function(mark)
    if not prep.dungeon then return false end
    if mark and GetTime() - acceptedAt > 2 then
        NS.StopPrep(true)
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- Frissites: quest log valtozas, mozgas (tavolsagok, macro), belepes
---------------------------------------------------------------------------
if NS.OnQuestChange then
    NS.OnQuestChange(function(event)
        if event == "QUEST_ACCEPTED" then acceptedAt = GetTime() end
        if not prep.dungeon or Inside() then return end
        C_Timer.After(1.5, function() if not Inside() then Refresh() end end) -- (a Questie quest log listaja kesve frissul)
    end)
end

local ticker = CreateFrame("Frame")
local el, sinceBuild = 0, 0
ticker:SetScript("OnUpdate", function(_, dt)
    el = el + dt
    if el < 1 then return end
    sinceBuild = sinceBuild + el
    el = 0
    if not prep.dungeon or InCombatLockdown() or Inside() then return end
    if (NS.Moved and NS.Moved("prep", 20)) or sinceBuild >= 15 then
        sinceBuild = 0
        Build()
        PrepMacro()
        if NS.Panel_Update and not QuestFocusDB.hidePanel then NS.Panel_Update() end
    elseif panel:IsShown() then
        panel.footer:SetText(FooterText())
    end
end)

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function()
    local name = Saved()
    if not name then return end
    prep.dungeon, prep.dirty = name, true
    -- a Questie adatai (felveheto questek) kesobb allnak be: akkor epitjuk ujra es jelolunk
    C_Timer.After(9, function()
        if prep.dungeon == name then NS.StartPrep(name, true) end
    end)
end)
