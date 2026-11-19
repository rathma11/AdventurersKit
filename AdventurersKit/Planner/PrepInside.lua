-- Dungeon prep: a dungeonon beluli fazis. Ha prep modban belepsz a dungeon instance-ba, a panel
-- a dungeon logban levo questjeit mutatja (boss sorrendben, ha van boss adat: Planner\DungeonBosses.lua,
-- kulonben a quest log sorrendjeben), alattuk minden objective-et (oles, loot, object, hasznalando
-- item: a Bags modul gombja a sorra kerul), es a bent felveheto questeket ("!" sor).
-- Pozicio: a Questie a dungeon spawnokat csak {-1,-1} jelolessel tarolja, es a classic kliens
-- instance-ban altalaban nem ad terkep poziciot: ilyenkor nincs nyil, csak a "kovetkezo"
-- szoveges tipp (boss neve / object). Ha megis van pozicio es koordinata, marker / nyil is jon.
-- Ha minden kesz (es nincs bent felveheto quest), a mod veget er, mint a megszakitas.
local ADDON_NAME, NS = ...
local L = NS.L
local P = NS.P
local panel = NS.panel

local ins = { on = false, rows = {}, areaId = nil, hadWork = false }

local ICON_DONE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t "
local ICON_TODO = "|TInterface\\COMMON\\Indicator-Gray:12:12|t "
local ICON_NEXT = "|TInterface\\COMMON\\Indicator-Green:12:12|t "
local ICON_PICK = "|TInterface\\GossipFrame\\AvailableQuestIcon:12:12|t "
local ICON_TI = "|TInterface\\GossipFrame\\ActiveQuestIcon:12:12|t "

NS.PrepIsInside = function() return ins.on end

---------------------------------------------------------------------------
-- Instance felismeres
---------------------------------------------------------------------------
local function Norm(s)
    s = tostring(s or ""):lower():gsub("^the ", "")
    return (s:gsub("[^%w]", ""))
end
local ALIAS = { sunkentemple = "templeofatalhakkar", templeofatalhakkar = "sunkentemple" }

local function InstanceMatches(dungeon)
    if not (IsInInstance and IsInInstance()) then return false end
    local iname, _, _, _, _, _, _, instId = GetInstanceInfo()
    if not iname or not dungeon then return false end
    local a, b = Norm(dungeon:match("^(.-):") or dungeon), Norm(iname)
    if a == "" or b == "" then return false end
    if a == b or a:find(b, 1, true) or b:find(a, 1, true) or ALIAS[a] == b then return true, instId end
    -- Questie: instance ID -> dungeon area -> dungeon nev
    local ZoneDB = NS.Module("ZoneDB")
    local area = ZoneDB and type(ZoneDB.instanceIdToAreaId) == "table" and ZoneDB.instanceIdToAreaId[instId]
    if area then
        local dn = NS.QuestDungeon and NS.QuestDungeon({ zoneOrSort = area })
        if dn and (Norm(dn) == a or Norm(dn):find(a, 1, true) or a:find(Norm(dn), 1, true)) then return true, instId end
    end
    return false
end

local function AreaOfInstance()
    local instId = select(8, GetInstanceInfo())
    local ZoneDB = NS.Module("ZoneDB")
    return ZoneDB and type(ZoneDB.instanceIdToAreaId) == "table" and ZoneDB.instanceIdToAreaId[instId] or nil
end

-- Bent van-e egy forras: a spawnjai ennek az instance-nak az area-jaban vannak, vagy csak
-- instance jeloles ({-1,-1}) van rola
local function SpawnsInside(spawns, area)
    if type(spawns) ~= "table" then return false end
    if area and spawns[area] then return true end
    local any = false
    for _, list in pairs(spawns) do
        for _, c in ipairs(type(list) == "table" and list or {}) do
            if type(c[1]) == "number" then
                if c[1] >= 0 then return false end
                any = true
            end
        end
    end
    return any
end
NS.PrepSpawnsInside = SpawnsInside

---------------------------------------------------------------------------
-- Lista
---------------------------------------------------------------------------
local function Bosses(dungeon)
    local B = NS.DungeonBosses or {}
    return B[dungeon] or B[dungeon:match("^(.-):") or ""] or (dungeon == "Blackrock Spire" and B["Lower Blackrock Spire"])
        or (dungeon == "Stratholme" and B["Stratholme: Living"]) or {}
end

local function BossIndex(bosses, src)
    if not (src and src.isNpc ~= false) then return end
    for i, b in ipairs(bosses) do
        if (b[2] and src.id == b[2]) or (src.name and src.name == b[1]) then return i end
    end
end

local function Inside(dungeon)
    return NS.PrepActive and NS.PrepActive() == dungeon and ins.on
end

-- Az objective: boss kapcsolat + szoveges tipp
local function ObjInfo(o, bosses, area)
    local idx
    local objNames, npcInside = {}, false
    for _, s in ipairs(o.sources or {}) do
        local bi = BossIndex(bosses, s)
        if bi and (not idx or bi < idx) then idx = bi end
        if s.isNpc == false and s.name then objNames[#objNames + 1] = s.name end
        if SpawnsInside(s.spawns, area) then npcInside = true end
    end
    local hint
    if o.turnIn then
        local n = o.sources and o.sources[1] and o.sources[1].name
        hint = npcInside and (L["turn in here: %s"]):format(n or "?") or (L["turn in outside: %s"]):format(n or "?")
    elseif idx then
        hint = (L["boss %d/%d: %s"]):format(idx, #bosses, bosses[idx][1])
    elseif #objNames > 0 then
        hint = (L["object: %s"]):format(table.concat(objNames, ", "))
    elseif #(o.sources or {}) == 0 then
        hint = L["location unknown"]
    end
    return idx, hint, npcInside
end

local function DungeonQuestIds(dungeon)
    local set = {}
    local e = NS.CollectDungeon and NS.CollectDungeon(dungeon)
    for _, d in ipairs(e and e.quests or {}) do set[d.qid] = d end
    return set, e
end

local function Build()
    local dungeon = NS.PrepActive and NS.PrepActive()
    ins.rows = {}
    if not dungeon then return end
    local area = ins.areaId
    local bosses = Bosses(dungeon)
    local known, e = DungeonQuestIds(dungeon)
    local groups = {}
    local active = false
    -- 1) a logban levo questek: a dungeon questjei, plusz minden quest, aminek nyitott
    --    objective-je ide (az instance-ba) mutat (semmi ne maradjon ki)
    for i = 1, NS.NumLogEntries() do
        local title, isHeader, qid, done = NS.GetLogEntry(i)
        if not isHeader and qid then
            local q = NS.GetQuestieQuest(qid)
            local objs = q and NS.CollectTargets(q, done) or {}
            local mine = known[qid] ~= nil or (q and NS.QuestDungeon and NS.QuestDungeon(q, qid) == dungeon)
                or (q and area and tonumber(q.zoneOrSort) == area)
            if not mine and area then
                for _, o in ipairs(objs) do
                    if not o.completed and not o.turnIn then
                        for _, s in ipairs(o.sources or {}) do
                            if type(s.spawns) == "table" and s.spawns[area] then mine = true break end
                        end
                    end
                    if mine then break end
                end
            end
            if mine then
                local g = { kind = "q", qid = qid, title = title, done = done, level = q and q.level, objs = {}, order = i }
                local key
                local turnInside = false
                for _, o in ipairs(objs) do
                    local idx, hint, inside = ObjInfo(o, bosses, area)
                    if o.turnIn and inside then turnInside = true end
                    if not o.completed and idx and (not key or idx < key) then key = idx end
                    g.objs[#g.objs + 1] = { kind = "o", qid = qid, o = o, hint = hint, idx = idx, order = #g.objs, inside = inside }
                end
                if #objs == 0 then
                    g.objs[1] = { kind = "o", qid = qid, o = { desc = L["No objective data for this quest."], completed = done },
                        hint = known[qid] and known[qid].note or nil, order = 0 }
                end
                -- objective-ek: boss sorrend (kapcsolat nelkuliek elol: ut kozben), aztan eredeti
                table.sort(g.objs, function(a, b)
                    local ka, kb = a.idx or 0, b.idx or 0
                    if ka ~= kb then return ka < kb end
                    return a.order < b.order
                end)
                g.open = not done or turnInside
                if g.open then active = true end
                g.key = g.open and (key or 0) or 1000
                groups[#groups + 1] = g
            end
        end
    end
    -- 2) bent felveheto questek (NPC bent, vagy itemrol / objectrol indul)
    local AQ = NS.Module("AvailableQuests")
    local avail = AQ and type(AQ.__availableQuests) == "table" and AQ.__availableQuests or {}
    local QP = NS.Module("QuestiePlayer")
    local inLog = QP and type(QP.currentQuestlog) == "table" and QP.currentQuestlog or {}
    local level = UnitLevel("player") or 1
    local cand, missed = {}, {}
    for qid in pairs(known) do cand[qid] = true end
    for qid in pairs(avail) do cand[qid] = true end
    for qid in pairs(cand) do
        local q = NS.GetQuestieQuest(qid)
        local d = known[qid]
        if not inLog[qid] and not (d and d.inLog) and not NS.QuestIsDone(qid) and q and type(q.Starts) == "table" then
            local sources = P.QuestStarters(qid, q)
            local inside, giverSrc = false, nil
            for _, s in ipairs(sources) do
                if SpawnsInside(s.spawns, area) then inside, giverSrc = true, s break end
            end
            local item = type(q.Starts.Item) == "table" and q.Starts.Item[1]
            local ok
            if inside then
                ok = avail[qid] or P.PickupOk(qid, q, inLog, level, 10, 10)
            elseif item and known[qid] then
                ok = P.PickupOk(qid, q, inLog, level, 10, 10)
            end
            if ok then
                local key, hint
                if giverSrc then
                    key = BossIndex(Bosses(dungeon), giverSrc)
                    hint = (L["quest giver: %s"]):format(giverSrc.name or "?")
                elseif item then
                    local iname = GetItemInfo and GetItemInfo(item)
                    do
                        local DB = NS.Module("QuestieDB")
                        local ok2, it = false, nil
                        if DB and type(DB.GetItem) == "function" then ok2, it = pcall(DB.GetItem, DB, item) end
                        iname = iname or (ok2 and type(it) == "table" and it.name) or nil
                        -- az itemet dobo boss
                        for _, src in ipairs(ok2 and type(it) == "table" and type(it.Sources) == "table" and it.Sources or {}) do
                            if src.Type == "monster" then
                                local bi = BossIndex(bosses, { id = src.Id, isNpc = true })
                                if bi and (not key or bi < key) then key = bi end
                            end
                        end
                    end
                    hint = (L["starts from an item: %s"]):format(iname or ("item " .. item))
                end
                if key and bosses[key] then hint = hint .. "  |cff999999(" .. (L["boss %d/%d: %s"]):format(key, #bosses, bosses[key][1]) .. ")|r" end
                if d and d.note then hint = hint or d.note end
                groups[#groups + 1] = { kind = "pick", qid = qid, name = (d and d.name) or q.name, level = q.level,
                    hint = hint, giver = giverSrc and giverSrc.name, key = key or 0, order = 0, note = d and d.note }
                active = true
            elseif d and not inside and (avail[qid] or (q and not item)) then
                -- kint kellett volna felvenni: itt mar nem teendo, csak egy halvany sor a vegen
                missed[#missed + 1] = { name = d.name or q.name, level = q.level or d.level, giver = d.note }
            end
        end
    end
    table.sort(groups, function(a, b)
        if a.key ~= b.key then return a.key < b.key end
        if a.kind ~= b.kind then return a.kind == "pick" end
        return (a.order or 0) < (b.order or 0)
    end)
    local rows = {}
    for _, g in ipairs(groups) do
        rows[#rows + 1] = g
        if g.kind == "q" then for _, o in ipairs(g.objs) do rows[#rows + 1] = o end end
    end
    if #missed > 0 then rows[#rows + 1] = { kind = "missed", list = missed } end
    ins.rows = rows
    ins.active = active
    if active then ins.hadWork = true end
    ins.info = e
end

-- A kovetkezo teendo: az elso nyitott objective (vagy bent felveheto quest) a sorrendben
local function NextRow()
    for _, r in ipairs(ins.rows) do
        if r.kind == "pick" then return r end
        if r.kind == "o" and not r.o.completed then
            -- kesz quest leadasa csak, ha bent van a leado
            if not r.o.turnIn or r.inside then return r end
        end
    end
end

---------------------------------------------------------------------------
-- Marker (ha van pozicio) es macro
---------------------------------------------------------------------------
local function InsideSources(sources, area)
    local out = {}
    if not area then return out end
    for _, s in ipairs(sources or {}) do
        local list = type(s.spawns) == "table" and s.spawns[area]
        if list then out[#out + 1] = { id = s.id, name = s.name, isNpc = s.isNpc, spawns = { [area] = list } } end
    end
    return out
end

local function UpdateMarker(nx)
    ins.hasArrow = false
    local pc = NS.PlayerWorldPos()
    if not (nx and pc and nx.kind == "o") then
        -- bent nincs pozicio: a kint lerakott marker (bejarat) se maradjon
        if ins.ownMarker or NS.state.waypoint then NS.ClearWaypoint(); ins.ownMarker, ins.markKey = nil, nil end
        return
    end
    local srcs = InsideSources(nx.o.sources, ins.areaId)
    local p = #srcs > 0 and NS.C.FindSpawnTarget(srcs, true) or nil
    if p and p.wc == pc and p.wx then
        local key = ("%s:%d:%d"):format(tostring(p.map), p.x, p.y)
        if key ~= ins.markKey then
            NS.SetWaypoint(p, p.name or nx.o.desc)
            ins.markKey, ins.ownMarker = key, true
        end
        ins.hasArrow = true
    elseif ins.ownMarker or NS.state.waypoint then
        NS.ClearWaypoint(); ins.ownMarker, ins.markKey = nil, nil
    end
end

local lastBody
local function Macro(nx)
    local MAX = 255
    local lines, seen, len = {}, {}, 0
    local function add(line)
        if len + #line + 1 > MAX then return end
        lines[#lines + 1] = line
        len = len + #line + 1
    end
    local names = {}
    local function addName(n) if n and not seen[n] then seen[n] = true; names[#names + 1] = n end end
    local friendly
    if nx then
        if nx.kind == "pick" then
            friendly = nx.giver
        elseif nx.o.turnIn then
            friendly = nx.o.sources and nx.o.sources[1] and nx.o.sources[1].name
        else
            for _, s in ipairs(nx.o.sources or {}) do if s.isNpc then addName(s.name) end end
        end
    end
    -- a tobbi nyitott oles / drop objective mobjai is (a kovetkezo utan)
    for _, r in ipairs(ins.rows) do
        if r.kind == "o" and not r.o.completed and not r.o.turnIn then
            for _, s in ipairs(r.o.sources or {}) do if s.isNpc then addName(s.name) end end
        end
    end
    local body
    if friendly then
        body = "/targetexact " .. friendly
    elseif #names > 0 then
        add("/cleartarget [noharm][dead]")
        for _, n in ipairs(names) do add("/targetexact [noexists] " .. n); add("/cleartarget [dead]") end
        if QuestFocusDB.startAttack then add("/startattack [@target,harm,nodead]") end
        body = table.concat(lines, "\n")
    else
        body = '/run UIErrorsFrame:AddMessage("AKit: dungeon - nothing to target",1,.8,.2)'
    end
    ins.macroWhat = friendly or names[1]
    if body ~= lastBody or NS.state.pendingBody then
        lastBody = body
        if NS.C.ApplyMacro then NS.C.ApplyMacro(body) end
    end
end

---------------------------------------------------------------------------
-- Panel sorok (a Bags modul a hasznalando item gombot ezekre is teszi: panel.prepLines)
---------------------------------------------------------------------------
local scroll = CreateFrame("ScrollFrame", nil, panel)
local child = CreateFrame("Frame", nil, scroll)
child:SetSize(10, 10)
scroll:SetScrollChild(child)
scroll:EnableMouseWheel(true)
scroll:Hide()
local lines = {}
panel.prepLines = lines
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

local function Line(i)
    local r = lines[i]
    if r then return r end
    r = CreateFrame("Button", nil, child)
    r.text = r:CreateFontString(nil, "OVERLAY", "QuestFocusFontSmall")
    r.text:SetPoint("TOPLEFT")
    r.text:SetPoint("BOTTOMRIGHT")
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(_, delta) scroll:GetScript("OnMouseWheel")(scroll, delta) end)
    r:SetScript("OnEnter", function(self)
        local d = self.data
        if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if d.kind == "q" then
            GameTooltip:SetText(("[%s] %s"):format(tostring(d.level or "?"), d.title or "?"), 1, 1, 1)
            local kd = ins.info and ins.info.quests
            for _, x in ipairs(kd or {}) do
                if x.qid == d.qid and x.note then GameTooltip:AddLine(x.note, 0.7, 0.7, 0.7, true) end
            end
            if d.done then GameTooltip:AddLine(L["Ready to turn in"], 0.4, 1, 0.4) end
        elseif d.kind == "pick" then
            GameTooltip:SetText(("[%s] %s"):format(tostring(d.level or "?"), d.name or "?"), 1, 0.82, 0)
            GameTooltip:AddLine(L["Pick up inside the dungeon"], 1, 1, 0.4)
            if d.hint then GameTooltip:AddLine(d.hint, 0.8, 0.8, 0.8, true) end
            if d.note and d.note ~= d.hint then GameTooltip:AddLine(d.note, 0.7, 0.7, 0.7, true) end
        elseif d.kind == "missed" then
            GameTooltip:SetText(L["Missed outside"], 0.7, 0.7, 0.7)
            GameTooltip:AddLine(L["These start outside the dungeon; pick them up next time."], 0.6, 0.6, 0.6, true)
            for _, x in ipairs(d.list) do
                GameTooltip:AddLine(("[%s] %s"):format(tostring(x.level or "?"), x.name or "?")
                    .. (x.giver and ("  |cff888888" .. x.giver .. "|r") or ""), 0.9, 0.9, 0.9, true)
            end
        else
            local TT = NS.TT
            if TT and TT.Objective then
                GameTooltip:SetText(d.o.desc or "?", 1, 1, 1, true)
                pcall(TT.Objective, GameTooltip, d.o, { sources = 6 })
            else
                GameTooltip:SetText(d.o.desc or "?", 1, 1, 1, true)
            end
            if d.hint then GameTooltip:AddLine(d.hint, 1, 0.82, 0.4, true) end
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    lines[i] = r
    return r
end

-- A dungeon questjei a logban (a megosztas ablaknak: Planner\PrepShare.lua)
NS.PrepInsideQuests = function()
    local out = {}
    for _, r in ipairs(ins.rows) do
        if r.kind == "q" then out[#out + 1] = { qid = r.qid, title = r.title, level = r.level } end
    end
    return out
end

NS.HidePrepInside = function()
    scroll:Hide()
    for _, r in ipairs(lines) do r:Hide(); r.useObj = nil end
end

local function FooterText(nx)
    if not nx then return L["Nothing left to do here."] end
    local what = nx.kind == "pick" and ((L["pick up %s"]):format(nx.name or "?")) or (nx.o.desc or "?")
    local s = (L["|cff33ff99Next:|r %s"]):format(what) .. (nx.hint and ("  |cff999999" .. nx.hint .. "|r") or "")
    if not ins.hasArrow then s = s .. "  |cff777777(" .. L["no arrow inside"] .. ")|r" end
    return s
end

NS.ShowPrepInside = function()
    local dungeon = NS.PrepActive() or "?"
    panel.title:SetText((L["Dungeon: %s"]):format(dungeon))
    panel.title:SetWidth(NS.PW() - 100)
    panel.title:SetWidth(math.min(math.ceil(panel.title:GetStringWidth()) + 2, NS.PW() - 100))
    panel.icon:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
    local nq, nopen, npick = 0, 0, 0
    for _, r in ipairs(ins.rows) do
        if r.kind == "q" then nq = nq + 1; if r.open then nopen = nopen + 1 end
        elseif r.kind == "pick" then npick = npick + 1 end
    end
    panel.sub:SetText((L["%d quests, %d open, %d to pick up inside"]):format(nq, nopen, npick))
    local nb = #Bosses(dungeon)
    local y = NS.PanelChrome("list", nb > 0 and L["IN THE DUNGEON (boss order)"] or L["IN THE DUNGEON (quest log order)"])
    local rh, w = NS.RowH(), NS.PW() - 24
    local step = rh + 1
    local nx = NextRow()
    for i, d in ipairs(ins.rows) do
        local r = Line(i)
        r.data = d
        r:SetSize(w, rh)
        r.useQid, r.useObj, r.useQuestItem = nil, nil, nil
        local txt
        if d.kind == "q" then
            local col = d.open and "|cffffd100" or "|cff808080"
            txt = (d.open and "" or ICON_DONE) .. col .. ("[%s] %s|r"):format(tostring(d.level or "?"), d.title or "?")
                .. (d.done and ("  |cff60ff60(" .. L["ready"] .. ")|r") or "")
        elseif d.kind == "pick" then
            txt = (d == nx and ICON_NEXT or ICON_PICK) .. ("|cffffff00! [%s] %s|r"):format(tostring(d.level or "?"), d.name or "?")
                .. (d.hint and ("  |cff999999" .. d.hint .. "|r") or "")
        elseif d.kind == "missed" then
            txt = "|cff666666" .. (L["Missed outside: %d"]):format(#d.list) .. "|r"
        else
            local o = d.o
            local icon = o.completed and ICON_DONE or (d == nx and ICON_NEXT) or (o.turnIn and ICON_TI) or ICON_TODO
            local col = o.completed and "|cff808080" or (d == nx and "|cff33ff99") or "|cffffffff"
            txt = "    " .. icon .. col .. (o.desc or "?") .. "|r" .. (d.hint and not o.completed and ("  |cff999999" .. d.hint .. "|r") or "")
            -- hasznalando item gomb (Bags): az elso nyitott objective soran a quest iteme is
            if not o.completed and not o.turnIn then
                local first = true
                for _, x in ipairs(ins.rows) do
                    if x.kind == "o" and x.qid == d.qid and not x.o.completed and not x.o.turnIn then first = (x == d) break end
                end
                r.useQid, r.useObj, r.useQuestItem = d.qid, o, first
            end
        end
        r.text:SetText(txt)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * step)
    end
    for i = #ins.rows + 1, #lines do lines[i]:Hide(); lines[i].useObj = nil end
    if #ins.rows == 0 then
        local r = Line(1)
        r.data, r.useObj = nil, nil
        r:SetSize(w, rh)
        r.text:SetText("|cff999999" .. L["No quests for this dungeon in your log."] .. "|r")
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    end
    local n = math.max(1, #ins.rows)
    local maxRows = 14
    local ph = tonumber(QuestFocusDB.panelH)
    if ph then maxRows = math.max(4, math.floor((ph - (-y) - (8 + rh + 12)) / step)) end
    local vis = math.min(n, maxRows)
    child:SetSize(w, n * step)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    scroll:SetSize(w, vis * step)
    local maxScroll = math.max(0, (n - vis) * step)
    if scroll:GetVerticalScroll() > maxScroll then scroll:SetVerticalScroll(maxScroll) end
    scroll.qfCount = n
    scroll:Show()
    Clip()
    y = y - vis * step
    panel.footer:SetText(FooterText(nx))
    NS.PanelFinish(y, true)
    return true
end

---------------------------------------------------------------------------
-- Be / ki, frissites
---------------------------------------------------------------------------
local function Update()
    if not ins.on then return end
    Build()
    -- minden kesz: vege, vissza az elozo allapotba
    if ins.hadWork and not ins.active then
        NS.Loud(NS.Print, L["All %s quests done here - dungeon prep finished."], NS.PrepActive() or "?")
        ins.on = false
        NS.HidePrepInside()
        NS.StopPrep(true, true)
        return
    end
    local nx = NextRow()
    UpdateMarker(nx)
    Macro(nx)
    if NS.Panel_Update then NS.Panel_Update() end
end
NS.PrepInsideUpdate = Update

local function Enter()
    ins.on, ins.hadWork, ins.markKey, ins.ownMarker = true, false, nil, nil
    ins.areaId = AreaOfInstance()
    lastBody = nil
    NS.ClearWaypoint() -- a bejarat markere itt mar nem kell
    Build()
    local nx = NextRow()
    NS.Debug("prep", "entered the instance (area %s): %d quest row(s), map arrow: %s", tostring(ins.areaId), #ins.rows,
        tostring(ins.hasArrow and true or false))
    UpdateMarker(nx)
    NS.Loud(NS.Print, L["In %s: %d quest rows. %s"], NS.PrepActive() or "?", #ins.rows,
        ins.hasArrow and "" or L["No map position inside the instance: no arrow, follow the Next hint."])
    Update()
    -- csapatban: megosszuk-e a dungeon questjeit (Planner\PrepShare.lua), belepesenkent egyszer
    if ins.on and NS.PrepShareAsk then NS.PrepShareAsk() end
end

-- Kilepes az instance-bol: ha minden kesz, vege (elozo allapot); kulonben vissza a prep listahoz
local function Leave()
    ins.on = false
    if NS.PrepShareHide then NS.PrepShareHide() end
    NS.HidePrepInside()
    NS.Debug("prep", "left the instance: %s", (ins.hadWork and not ins.active) and "all done, prep ends" or "back to the prep list")
    if ins.hadWork and not ins.active then
        NS.StopPrep(true, true)
    elseif NS.PrepRefresh then
        NS.PrepRefresh(true)
    end
end

NS.PrepCheckInside = function()
    local d = NS.PrepActive and NS.PrepActive()
    local now = d and InstanceMatches(d) or false
    if now and not ins.on then Enter()
    elseif now then Update()
    elseif ins.on then Leave() end
end
NS.PrepInsideReset = function()
    ins.on, ins.rows, ins.hadWork = false, {}, false
    NS.HidePrepInside()
    lastBody = nil
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:SetScript("OnEvent", function()
    C_Timer.After(1, function() if NS.PrepCheckInside then NS.PrepCheckInside() end end)
end)

-- harcon kivul 2 mp-enkent (a quest log valtozast is az OnQuestChange hozza)
local tick = CreateFrame("Frame")
local el = 0
tick:SetScript("OnUpdate", function(_, dt)
    el = el + dt
    if el < 2 then return end
    el = 0
    if ins.on and not InCombatLockdown() and panel:IsShown() then
        local nx = NextRow()
        UpdateMarker(nx)
        panel.footer:SetText(FooterText(nx))
    end
end)
if NS.OnQuestChange then
    NS.OnQuestChange(function()
        if ins.on then C_Timer.After(1.5, Update) end
    end)
end

-- Debug: dungeon prep belso fazis (Core\DebugLog.lua; a kulso resz: Planner\Prep.lua)
NS.DebugSnapshot("prep", function(out)
    if not (NS.PrepActive and NS.PrepActive()) then return end
    out[#out + 1] = ("Inside: %s | area %s | rows %d | map arrow %s | had work %s | work left %s"):format(tostring(ins.on),
        tostring(ins.areaId), #(ins.rows or {}), tostring(ins.hasArrow and true or false), tostring(ins.hadWork),
        tostring(ins.active and true or false))
end)
