-- QuestFocus
-- Quest kijelolesre: QFocus target macro, marker (waypoint + nyil), tooltip.
-- Az adatokat (mobok, itemek, spawn helyek, leado NPC) a Questie-bol veszi.

local ADDON_NAME = ...
local MACRO_NAME = "QFocus"
local ICON_FALLBACK = 134400 -- INV_Misc_QuestionMark
local ICON_HUNT = "Ability_Hunter_SniperShot"   -- celkereszt: mobok
local ICON_TURNIN = "INV_Misc_Note_01"          -- level: leadas
local ICON_IDLE = "INV_Misc_Map_01"             -- nincs kijelolt quest
local MACRO_MAX = 255
local PREFIX = "|cff33ff99QuestFocus|r: "

local QF = CreateFrame("Frame", "QuestFocusEventFrame")
local state = {
    questId = nil,      -- kijelolt quest
    title = nil,
    isComplete = false,
    objectives = nil,   -- CollectTargets eredmenye
    objIndex = nil,     -- ha egy konkret objective van kivalasztva
    lastBody = nil,
    pendingBody = nil,
    macroCount = 0,
    waypoint = nil,
    tomtomUid = nil,
}

local function Print(msg, ...)
    if select("#", ...) > 0 then msg = msg:format(...) end
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

---------------------------------------------------------------------------
-- Questie hozzaferes
---------------------------------------------------------------------------
local function Module(name)
    local loader = _G.QuestieLoader
    if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return nil end
    local ok, mod = pcall(loader.ImportModule, loader, name)
    if ok and type(mod) == "table" then return mod end
end

local function QuestieAvailable()
    return Module("QuestieDB") ~= nil
end

local function GetQuestieQuest(questId)
    local QP = Module("QuestiePlayer")
    if QP and type(QP.currentQuestlog) == "table" then
        local q = QP.currentQuestlog[questId]
        if type(q) == "table" then return q end
    end
    local DB = Module("QuestieDB")
    if DB and type(DB.GetQuest) == "function" then
        local ok, q = pcall(DB.GetQuest, questId)
        if ok and type(q) == "table" then return q end
        ok, q = pcall(DB.GetQuest, DB, questId)
        if ok and type(q) == "table" then return q end
    end
end

local function GetNPC(id)
    local DB = Module("QuestieDB")
    if not (DB and type(DB.GetNPC) == "function") then return end
    local ok, npc = pcall(DB.GetNPC, DB, id)
    if ok and type(npc) == "table" then return npc end
    ok, npc = pcall(DB.GetNPC, id)
    if ok and type(npc) == "table" then return npc end
end

local function GetObject(id)
    local DB = Module("QuestieDB")
    if not (DB and type(DB.GetObject) == "function") then return end
    local ok, obj = pcall(DB.GetObject, DB, id)
    if ok and type(obj) == "table" then return obj end
    ok, obj = pcall(DB.GetObject, id)
    if ok and type(obj) == "table" then return obj end
end

local function SortedValues(t)
    local keys, out = {}, {}
    if type(t) ~= "table" then return out end
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return tostring(a) < tostring(b)
    end)
    for _, k in ipairs(keys) do out[#out + 1] = t[k] end
    return out
end

-- Egy quest objective-jei, mindegyikhez a forrasok (mob / object) spawnokkal.
local function CollectTargets(quest, isComplete)
    local result = {}

    if isComplete and type(quest.Finisher) == "table" then
        local f = quest.Finisher
        local sources, names = {}, {}
        for _, id in ipairs(type(f.NPC) == "table" and f.NPC or {}) do
            local npc = GetNPC(id)
            if npc then
                sources[#sources + 1] = { id = id, name = npc.name, spawns = npc.spawns, isNpc = true }
                names[#names + 1] = npc.name
            end
        end
        for _, id in ipairs(type(f.GameObject) == "table" and f.GameObject or {}) do
            local obj = GetObject(id)
            if obj then
                sources[#sources + 1] = { id = id, name = obj.name, spawns = obj.spawns, isNpc = false }
                names[#names + 1] = obj.name
            end
        end
        if #sources > 0 then
            result[1] = {
                desc = "Leadás: " .. table.concat(names, ", "),
                completed = false,
                turnIn = true,
                sources = sources,
            }
            return result
        end
    end

    local all = SortedValues(quest.Objectives)
    for _, o in ipairs(SortedValues(quest.SpecialObjectives)) do all[#all + 1] = o end

    for _, o in ipairs(all) do
        if type(o) == "table" then
            local desc = o.Description or o.Text or o.Type or "?"
            if type(o.Collected) == "number" and type(o.Needed) == "number" and o.Needed > 0
                and not tostring(desc):find("%d+%s*/%s*%d+") then
                desc = ("%s %d/%d"):format(desc, o.Collected, o.Needed)
            end
            local entry = { desc = desc, completed = o.Completed and true or false, sources = {} }
            if o.Type == "item" and o.Id then entry.itemId = o.Id end
            local seen = {}

            for id, s in pairs(o.spawnList or {}) do
                if type(s) == "table" then
                    local isNpc
                    if type(s.TooltipKey) == "string" then
                        isNpc = s.TooltipKey:sub(1, 2) == "m_"
                    else
                        isNpc = (o.Type == "monster" or o.Type == "killcredit")
                    end
                    local key = (isNpc and "m" or "o") .. tostring(s.Id or id)
                    if not seen[key] then
                        seen[key] = true
                        entry.sources[#entry.sources + 1] = {
                            id = s.Id or id, name = s.Name, spawns = s.Spawns, isNpc = isNpc,
                        }
                    end
                end
            end

            -- Tartalek: ha a Questie meg nem toltotte ki a spawnList-et
            if #entry.sources == 0 and o.Type == "monster" and o.Id then
                local npc = GetNPC(o.Id)
                if npc then
                    entry.sources[1] = { id = o.Id, name = npc.name, spawns = npc.spawns, isNpc = true }
                end
            end

            result[#result + 1] = entry
        end
    end
    return result
end

-- Keresett item: honnan szerezheto (foldon/objectbol, mobbol dropol, vendor).
-- Visszaad egy listat { text, r, g, b } sorokkal; max 'limit' forrassor.
local function ItemSourceLines(entry, limit)
    local lines = {}
    if not entry.itemId then return lines end
    limit = limit or 4
    local DB = Module("QuestieDB")
    local objs, mobs = {}, {}
    for _, s in ipairs(entry.sources) do
        if s.isNpc then mobs[#mobs + 1] = s else objs[#objs + 1] = s end
    end
    local n = 0
    for _, s in ipairs(objs) do
        if n >= limit then break end
        n = n + 1
        lines[#lines + 1] = { "Felvehető: " .. (s.name or "?") .. " (földön / tárgyban)", 0.6, 1, 0.6 }
    end
    for _, s in ipairs(mobs) do
        if n >= limit then break end
        n = n + 1
        local txt = "Dropol: " .. (s.name or "?")
        local npc = GetNPC(s.id)
        if npc and type(npc.minLevel) == "number" then
            local maxL = type(npc.maxLevel) == "number" and npc.maxLevel or npc.minLevel
            txt = txt .. (maxL ~= npc.minLevel and (" (lvl %d-%d)"):format(npc.minLevel, maxL)
                or (" (lvl %d)"):format(npc.minLevel))
        end
        if DB and type(DB.GetItemDroprate) == "function" then
            local ok, rate = pcall(DB.GetItemDroprate, entry.itemId, s.id)
            if ok and type(rate) == "table" then rate = rate[1] end
            rate = tonumber(rate)
            if rate and rate > 0 then txt = txt .. (" ~%s%%"):format(rate >= 10 and ("%d"):format(rate) or ("%.1f"):format(rate)) end
        end
        lines[#lines + 1] = { txt, 1, 0.7, 0.4 }
    end
    -- Vendor forras (a spawnList-ben nincs kulon jelolve)
    if DB then
        local ok, item = pcall(DB.GetItem, DB, entry.itemId)
        if ok and type(item) == "table" and type(item.Sources) == "table" then
            for _, src in ipairs(item.Sources) do
                if src.Vendor and n < limit + 1 then
                    local npc = GetNPC(src.Id)
                    if npc then
                        n = n + 1
                        lines[#lines + 1] = { "Vásárolható: " .. (npc.name or "?"), 1, 0.9, 0.3 }
                    end
                end
            end
        end
    end
    local total = #objs + #mobs
    if total > limit then
        lines[#lines + 1] = { ("+%d további forrás"):format(total - limit), 0.6, 0.6, 0.6 }
    end
    return lines
end

---------------------------------------------------------------------------
-- Quest log segedek (classic es modern API-ra is)
---------------------------------------------------------------------------
local function GetLogEntry(index)
    if GetQuestLogTitle then
        local title, _, _, isHeader, _, isComplete, _, questId = GetQuestLogTitle(index)
        return title, isHeader, questId, (isComplete == 1 or isComplete == true)
    elseif C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(index)
        if info then
            local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID) or false
            return info.title, info.isHeader, info.questID, done
        end
    end
end

local function NumLogEntries()
    if GetNumQuestLogEntries then return (GetNumQuestLogEntries()) end
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then return (C_QuestLog.GetNumQuestLogEntries()) end
    return 0
end

local function FindQuestInLog(questId)
    for i = 1, NumLogEntries() do
        local title, isHeader, qid, done = GetLogEntry(i)
        if not isHeader and qid == questId then return title, done end
    end
end

---------------------------------------------------------------------------
-- Koordinatak, tavolsag
---------------------------------------------------------------------------
local uiMapCache = {}
local function UiMapFromArea(areaId)
    local cached = uiMapCache[areaId]
    if cached ~= nil then return cached or nil end
    local ZoneDB = Module("ZoneDB")
    local id
    if ZoneDB and type(ZoneDB.GetUiMapIdByAreaId) == "function" then
        local ok, r = pcall(ZoneDB.GetUiMapIdByAreaId, ZoneDB, areaId)
        if ok then id = r end
    end
    uiMapCache[areaId] = id or false
    return id
end

local function WorldPos(uiMap, x, y)
    local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, uiMap, CreateVector2D(x, y))
    if ok and cont and world then return cont, world.x, world.y end
end

local function PlayerWorldPos()
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return end
    local px, py = pos:GetXY()
    return WorldPos(map, px, py)
end

local function ZoneName(uiMap)
    local info = C_Map.GetMapInfo(uiMap)
    return info and info.name or ("map " .. tostring(uiMap))
end

-- Visszaadja a legkozelebbi spawnt a forrasok kozul (+ tavolsag yardban, ha ugyanazon a kontinensen van)
local function FindNearest(sources)
    local pc, px, py = PlayerWorldPos()
    local best, bestScore, bestDist
    for _, src in ipairs(sources) do
        if type(src.spawns) == "table" then
            for areaId, list in pairs(src.spawns) do
                local uiMap = UiMapFromArea(areaId)
                if uiMap and type(list) == "table" then
                    for _, c in ipairs(list) do
                        local x, y = c[1], c[2]
                        if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
                            local wc, wx, wy = WorldPos(uiMap, x / 100, y / 100)
                            local dist, score
                            if pc and wc == pc and wx then
                                dist = math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
                                score = dist
                            else
                                score = wc and 1e9 or 2e9
                            end
                            if not bestScore or score < bestScore then
                                bestScore, bestDist = score, dist
                                best = { map = uiMap, x = x, y = y, name = src.name, wc = wc, wx = wx, wy = wy }
                            end
                        end
                    end
                end
            end
        end
    end
    return best, bestDist
end

---------------------------------------------------------------------------
-- Macro
---------------------------------------------------------------------------
local PING_LINE = "/ping [@target,harm,nodead] attack; [@target,help,nodead] assist"

-- Macro feltetellel nem lehet "tapped"-et vizsgalni, ezert harcon kivul az addon a
-- nameplate-ek kozul kivalasztja az elo, meg senki altal meg nem tapolt quest mobot, es a
-- macroba kozvetlenul azt irja: /target nameplateN. Harcban a macro nem irhato, ott a
-- nev szerinti targetelés dolgozik.
local targetNames = {}
local pickTicker = CreateFrame("Frame")
local UpdateMacro -- lent definialva

local function NameplatesUsable()
    return C_NamePlate and C_NamePlate.GetNamePlates and GetCVar
        and GetCVar("nameplateShowEnemies") == "1"
end

local function TapDenied(unit)
    if UnitIsTapDenied then return UnitIsTapDenied(unit) end
    if UnitIsTapped then return UnitIsTapped(unit) and not UnitIsTappedByPlayer(unit) end
    return false
end

local function GoodQuestUnit(unit)
    return unit and UnitExists(unit) and targetNames[UnitName(unit) or ""]
        and not UnitIsDead(unit) and UnitCanAttack("player", unit) and not TapDenied(unit)
end

local function PickNameplate()
    if InCombatLockdown() then return end
    local pick, idle, seenBad
    if next(targetNames) then
        -- Kozvetlenul a nameplateN unit tokeneken megyunk vegig (nameplate addonoktol fuggetlen)
        for i = 1, 40 do
            local unit = "nameplate" .. i
            if not UnitExists(unit) then
                -- lyukak lehetnek a sorszamokban, ezert nem allunk meg
            elseif GoodQuestUnit(unit) then
                if UnitIsUnit(unit, "target") then pick = unit break end -- marad a mostani
                if not UnitAffectingCombat(unit) then idle = idle or unit else pick = pick or unit end
            elseif unit and UnitExists(unit) and targetNames[UnitName(unit) or ""] then
                seenBad = true -- latszik quest mob, de halott vagy mas tapolta
            end
        end
    end
    pick = (pick and UnitIsUnit(pick, "target")) and pick or idle or pick
    -- Ha a kozelben csak tapolt/halott quest mob van: "busy" -> a macro nem targetel semmit
    if not pick and seenBad then pick = "busy" end
    if state.pick ~= pick then
        state.pick = pick
        if state.questId and UpdateMacro then UpdateMacro() end
    end
end

local pickElapsed = 0
pickTicker:SetScript("OnUpdate", function(_, dt)
    pickElapsed = pickElapsed + dt
    if pickElapsed > 0.2 then pickElapsed = 0; PickNameplate() end
end)

local function BuildMacroBody(objectives, onlyIndex)
    local usePing = not (QuestFocusDB and QuestFocusDB.noPing)
    -- Nameplate-ekkel: /target nameplateN (elo, nem tapolt mob). Ha nincs latszo quest mob
    -- (vagy harc): /targetexact nev szerint, a hullat eldobjuk, a tapoltat itt nem tudjuk kiszurni.
    -- Leadasnal baratsagos NPC kell: ott mindig nev szerint
    local turnIn = objectives and objectives[1] and objectives[1].turnIn
    local useNP = NameplatesUsable() and not turnIn and not InCombatLockdown()
    local CLEAR, DEADCLR = "/cleartarget", "/cleartarget [dead]"
    local pick = useNP and state.pick or nil
    if pick == "busy" then
        CLEAR = '/run UIErrorsFrame:AddMessage("QuestFocus: a közeli quest mobok foglaltak",1,.6,.2)'
    elseif pick then
        CLEAR = "/target " .. pick
    end
    -- Opcionalis tap: spell es/vagy autoattack a celpontra (csak ellenseges, elo celra)
    local tail = {}
    local spell = QuestFocusDB and QuestFocusDB.spell
    if not turnIn and QuestFocusDB and QuestFocusDB.startAttack then
        tail[#tail + 1] = "/startattack [@target,harm,nodead]"
    end
    if not turnIn and QuestFocusDB and QuestFocusDB.useSpell and spell and spell ~= "" then
        tail[#tail + 1] = "/cast [@target,harm,nodead] " .. spell
    end
    if usePing then tail[#tail + 1] = PING_LINE end
    local lines, seen = { CLEAR }, {}
    local len = #CLEAR + 1
    for _, t in ipairs(tail) do len = len + #t + 1 end
    local n = 0
    wipe(targetNames)
    for i, obj in ipairs(objectives or {}) do
        if (onlyIndex == nil and not obj.completed) or onlyIndex == i then
            for _, src in ipairs(obj.sources) do
                if src.isNpc and src.name and not seen[src.name] then
                    seen[src.name] = true
                    targetNames[src.name] = true
                    n = n + 1
                    if not pick then -- nev szerint, ha nincs latszo quest mob nameplate (vagy harc)
                        local line = "/targetexact [noexists] " .. src.name
                        local cost = #line + 1 + #DEADCLR + 1
                        if len + cost <= MACRO_MAX then
                            lines[#lines + 1] = line
                            lines[#lines + 1] = DEADCLR
                            len = len + cost
                        end
                    end
                end
            end
        end
    end
    if n == 0 then
        return '/run print("QuestFocus: nincs targetelheto mob")', 0
    end
    for _, t in ipairs(tail) do lines[#lines + 1] = t end
    return table.concat(lines, "\n"), n
end

local iconCache = {}
local function IconId(name)
    if type(name) == "number" then return name end
    if type(name) ~= "string" or name == "" then return ICON_FALLBACK end
    if iconCache[name] then return iconCache[name] end
    local id
    if GetFileIDFromPath then
        local path = name:find("[/\\]") and name or ("Interface\\Icons\\" .. name)
        local ok, r = pcall(GetFileIDFromPath, path)
        if ok and type(r) == "number" and r > 0 then id = r end
    end
    if not id and tonumber(name) then id = tonumber(name) end
    iconCache[name] = id or ICON_FALLBACK
    return iconCache[name]
end

local function CurrentIcon()
    if QuestFocusDB and QuestFocusDB.icon then return IconId(QuestFocusDB.icon) end
    if not state.questId then return IconId(ICON_IDLE) end
    local objs = state.objectives or {}
    if objs[1] and objs[1].turnIn then return IconId(ICON_TURNIN) end
    return IconId(ICON_HUNT)
end

local function ApplyMacro(body)
    if InCombatLockdown() then
        if not state.pendingBody then Print("Harcban vagy, a QFocus macro harc után frissül.") end
        state.pendingBody = body
        return
    end
    state.pendingBody = nil
    local idx = GetMacroIndexByName(MACRO_NAME)
    if idx and idx > 0 then
        EditMacro(idx, MACRO_NAME, CurrentIcon(), body)
    else
        local numAccount = GetNumMacros()
        if numAccount >= (MAX_ACCOUNT_MACROS or 120) then
            Print("Nincs hely új account macronak, töröld valamelyiket.")
            return
        end
        CreateMacro(MACRO_NAME, CurrentIcon(), body, nil)
        Print("Létrehoztam a |cffffff00%s|r macrot. Nyisd meg a /macro ablakot és húzd fel az actionbarra.", MACRO_NAME)
    end
    state.lastBody = body
    state.lastIcon = CurrentIcon()
end

UpdateMacro = function()
    local body, n = BuildMacroBody(state.objectives, state.objIndex)
    state.macroCount = n
    if body ~= state.lastBody or state.pendingBody or CurrentIcon() ~= state.lastIcon then ApplyMacro(body) end
end

---------------------------------------------------------------------------
-- Nyil
---------------------------------------------------------------------------
local arrow = CreateFrame("Button", "QuestFocusArrow", UIParent)
arrow:SetSize(64, 80)
arrow:SetPoint("TOP", UIParent, "TOP", 0, -140)
arrow:SetMovable(true)
arrow:SetClampedToScreen(true)
arrow:EnableMouse(true)
arrow:RegisterForDrag("LeftButton")
arrow:RegisterForClicks("RightButtonUp")
arrow:SetScript("OnDragStart", arrow.StartMoving)
arrow:SetScript("OnDragStop", arrow.StopMovingOrSizing)
arrow.tex = arrow:CreateTexture(nil, "ARTWORK")
arrow.tex:SetTexture("Interface\\Minimap\\MinimapArrow")
arrow.tex:SetSize(48, 48)
arrow.tex:SetPoint("TOP")
arrow.text = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
arrow.text:SetPoint("TOP", arrow.tex, "BOTTOM", 0, 4)
arrow:Hide()
arrow:SetScript("OnClick", function(self)
    state.waypoint = nil
    self:Hide()
end)

local arrowElapsed = 0
arrow:SetScript("OnUpdate", function(self, elapsed)
    arrowElapsed = arrowElapsed + elapsed
    if arrowElapsed < 0.05 then return end
    arrowElapsed = 0
    local w = state.waypoint
    if not w then self:Hide() return end
    local pc, px, py = PlayerWorldPos()
    if not pc or not w.wc or pc ~= w.wc or not w.wx then
        self.tex:SetRotation(0)
        self.tex:SetVertexColor(0.6, 0.6, 0.6)
        self.text:SetText((w.title or "?") .. "\n" .. ZoneName(w.map))
        return
    end
    local dx, dy = w.wx - px, w.wy - py
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 10 then
        self.tex:SetRotation(0)
        self.tex:SetVertexColor(0.2, 1, 0.2)
        self.text:SetText((w.title or "?") .. "\n|cff33ff33Megérkeztél|r")
        return
    end
    local facing = GetPlayerFacing() or 0
    local angle = math.atan2(dy, dx) - facing
    self.tex:SetRotation(angle)
    local a = math.abs(((angle + math.pi) % (2 * math.pi)) - math.pi) -- 0 = egyenesen elore
    local t = a / math.pi
    self.tex:SetVertexColor(t, 1 - t * 0.6, 0.1)
    self.text:SetFormattedText("%s\n%d yd", w.title or "?", dist)
end)

local function UseOwnArrow()
    return not (TomTom and TomTom.AddWaypoint) and not (QuestFocusDB and QuestFocusDB.noArrow)
end

---------------------------------------------------------------------------
-- Waypoint
---------------------------------------------------------------------------
local function SetWaypoint(p, title)
    state.waypoint = { map = p.map, x = p.x, y = p.y, title = title, wc = p.wc, wx = p.wx, wy = p.wy }

    if TomTom and TomTom.AddWaypoint then
        if state.tomtomUid and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, state.tomtomUid) end
        local ok, uid = pcall(TomTom.AddWaypoint, TomTom, p.map, p.x / 100, p.y / 100,
            { title = title, persistent = false, crazy = true, from = "QuestFocus" })
        if ok then state.tomtomUid = uid end
    end

    if C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local canSet = true
        if C_Map.CanSetUserWaypointOnMap then canSet = C_Map.CanSetUserWaypointOnMap(p.map) end
        if canSet then
            if pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(p.map, p.x / 100, p.y / 100)) then
                state.ownsUserWaypoint = true
            end
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
            end
        end
    end

    if UseOwnArrow() then arrow:Show() else arrow:Hide() end
end

-- Minden altalunk lerakott marker torlese (TomTom, beepitett map pin, sajat nyil)
local function ClearWaypoint()
    state.waypoint = nil
    arrow:Hide()
    if state.tomtomUid and TomTom and TomTom.RemoveWaypoint then
        pcall(TomTom.RemoveWaypoint, TomTom, state.tomtomUid)
    end
    state.tomtomUid = nil
    if state.ownsUserWaypoint and C_Map.ClearUserWaypoint then
        pcall(C_Map.ClearUserWaypoint)
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, false)
        end
    end
    state.ownsUserWaypoint = nil
end

arrow:SetScript("OnClick", function() ClearWaypoint() end)

local function MarkObjective(i)
    local objs = state.objectives or {}
    local list = {}
    if i and objs[i] then
        list[1] = objs[i]
    else
        for _, o in ipairs(objs) do if not o.completed then list[#list + 1] = o end end
        if #list == 0 then list = objs end
    end
    local sources = {}
    for _, o in ipairs(list) do
        for _, s in ipairs(o.sources) do sources[#sources + 1] = s end
    end
    if #sources == 0 then
        Print("Nincs ismert hely ehhez: %s", state.title or "?")
        return
    end
    local p, dist = FindNearest(sources)
    if not p then
        Print("Nem találok koordinátát (lehet, hogy instance-ben van).")
        return
    end
    SetWaypoint(p, p.name or state.title)
    Print("Marker: |cffffff00%s|r - %s %.1f, %.1f%s", p.name or "?", ZoneName(p.map), p.x, p.y,
        dist and (" (%d yd)"):format(dist) or "")
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local panel = CreateFrame("Frame", "QuestFocusPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
panel:SetSize(280, 60)
panel:SetPoint("RIGHT", UIParent, "RIGHT", -260, 80)
panel:SetMovable(true)
panel:SetClampedToScreen(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
if panel.SetBackdrop then
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0, 0, 0, 0.75)
end
panel:Hide()

panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
panel.title:SetPoint("TOPLEFT", 10, -9)
panel.title:SetWidth(236)
panel.title:SetJustifyH("LEFT")
panel.title:SetWordWrap(false)

local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetSize(24, 24)
close:SetPoint("TOPRIGHT", 0, 0)
close:SetScript("OnClick", function()
    QuestFocusDB.hidePanel = true
    panel:Hide()
    Print("Panel elrejtve. Visszajön, ha questre kattintasz, vagy: /qf")
end)

panel.footer = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
panel.footer:SetJustifyH("LEFT")
panel.footer:SetWidth(260)

panel.lines = {}

local SelectObjective -- forward

local function GetLine(i)
    local line = panel.lines[i]
    if line then return line end
    line = CreateFrame("Button", nil, panel)
    line:SetSize(262, 16)
    line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.text:SetAllPoints()
    line.text:SetJustifyH("LEFT")
    line.text:SetWordWrap(false)
    local hl = line:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    line:SetScript("OnClick", function(self, button)
        if button == "RightButton" then SelectObjective(nil) else SelectObjective(self.index) end
    end)
    line:SetScript("OnEnter", function(self)
        local o = state.objectives and state.objectives[self.index]
        if not o then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(o.desc, 1, 0.82, 0, 1, true)
        if o.itemId then
            for _, l in ipairs(ItemSourceLines(o, 8)) do GameTooltip:AddLine(l[1], l[2], l[3], l[4]) end
        else
            for n, s in ipairs(o.sources) do
                if n > 8 then GameTooltip:AddLine("...", 0.7, 0.7, 0.7) break end
                GameTooltip:AddLine((s.isNpc and "Mob: " or "Object: ") .. (s.name or "?"), 1, 1, 1)
            end
        end
        local p, dist = FindNearest(o.sources)
        if p then
            GameTooltip:AddLine(("Legközelebb: %s %.1f, %.1f%s"):format(ZoneName(p.map), p.x, p.y,
                dist and (" (%d yd)"):format(dist) or ""), 0.6, 0.8, 1)
        end
        GameTooltip:AddLine("Bal klikk: marker + macro csak erre", 0.5, 0.5, 0.5)
        GameTooltip:AddLine("Jobb klikk: macro az összes hátralévőre", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    line:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.lines[i] = line
    return line
end

local function Panel_Update()
    if not state.questId or QuestFocusDB.hidePanel then
        panel:Hide()
        return
    end
    panel.title:SetText(state.title or ("Quest " .. state.questId))
    local objs = state.objectives or {}
    local y = -28
    for i, o in ipairs(objs) do
        local line = GetLine(i)
        line.index = i
        local prefix = (state.objIndex == i) and "|cff33ff99> |r" or "   "
        local color = o.completed and "|cff808080" or (o.turnIn and "|cffffff00" or "|cffffffff")
        line.text:SetText(prefix .. color .. o.desc .. "|r")
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, y)
        line:Show()
        y = y - 16
    end
    for i = #objs + 1, #panel.lines do panel.lines[i]:Hide() end
    if #objs == 0 then
        panel.footer:SetText(QuestieAvailable() and "Nincs objective adat ehhez a questhez." or "Questie nincs betöltve.")
    elseif state.macroCount > 0 then
        panel.footer:SetText(("QFocus macro: %d mob"):format(state.macroCount))
    else
        panel.footer:SetText("QFocus macro: nincs targetelhető mob")
    end
    panel.footer:ClearAllPoints()
    panel.footer:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, y - 4)
    panel:SetHeight(-y + 24)
    panel:Show()
end

---------------------------------------------------------------------------
-- Kijeloles
---------------------------------------------------------------------------
local function Refresh(keepObjective)
    if not state.questId then return end
    local quest = GetQuestieQuest(state.questId)
    state.objectives = quest and CollectTargets(quest, state.isComplete) or {}
    if not keepObjective then state.objIndex = nil end
    if state.objIndex and not state.objectives[state.objIndex] then state.objIndex = nil end
    UpdateMacro()
    Panel_Update()
end

SelectObjective = function(i)
    state.objIndex = i
    UpdateMacro()
    Panel_Update()
    MarkObjective(i)
end

local function SelectQuest(questId, title, isComplete, mark)
    if not questId or questId == 0 then return end
    if not QuestieAvailable() then
        Print("A Questie nincs betöltve, enélkül nem tudom, hol vannak a mobok.")
    end
    -- Egy kattintasra tobb hook is lefuthat (gomb + C_QuestLog): csak egyszer jeloljunk
    local now = GetTime()
    if mark and state.lastMarkQuest == questId and state.lastMarkTime and now - state.lastMarkTime < 0.5 then
        mark = false
    end
    if mark then state.lastMarkQuest, state.lastMarkTime = questId, now end
    local changed = questId ~= state.questId
    state.questId = questId
    state.title = title or state.title
    state.isComplete = isComplete and true or false
    QuestFocusDB.lastQuest = questId
    if mark then QuestFocusDB.hidePanel = false end -- kattintasra a bezart panel visszajon
    Refresh(not changed)
    if mark then MarkObjective(state.objIndex) end
end

local function ClearQuest()
    state.questId, state.title, state.objectives, state.objIndex = nil, nil, nil, nil
    ClearWaypoint()
    panel:Hide()
    QuestFocusDB.lastQuest = nil
    state.macroCount = 0
    wipe(targetNames)
    local body = '/run print("QuestFocus: nincs kijelolt quest")'
    if body ~= state.lastBody or CurrentIcon() ~= state.lastIcon then ApplyMacro(body) end
end

local function SelectByLogIndex(index, mark)
    if not index or index == 0 then return end
    local title, isHeader, questId, done = GetLogEntry(index)
    if isHeader or not questId then return end
    SelectQuest(questId, title, done, mark)
end

---------------------------------------------------------------------------
-- Quest log tooltip
---------------------------------------------------------------------------
local function AddQuestTooltip(tooltip, questId, isComplete)
    local quest = GetQuestieQuest(questId)
    if not quest then return end
    local objs = CollectTargets(quest, isComplete)
    if #objs == 0 then return end
    tooltip:AddLine(" ")
    tooltip:AddLine("QuestFocus", 0.2, 1, 0.6)
    for _, o in ipairs(objs) do
        if o.completed then
            tooltip:AddLine(o.desc, 0.5, 0.5, 0.5, true)
        else
            tooltip:AddLine(o.desc, 1, 0.82, 0, true)
            local names = {}
            for n, s in ipairs(o.sources) do
                if n > 3 then names[#names + 1] = "..." break end
                names[#names + 1] = s.name or "?"
            end
            local p, dist = FindNearest(o.sources)
            local where = p and (("%s %.0f,%.0f"):format(ZoneName(p.map), p.x, p.y)
                .. (dist and (" (%d yd)"):format(dist) or "")) or ""
            if o.itemId then
                for _, l in ipairs(ItemSourceLines(o, 3)) do
                    tooltip:AddLine("  " .. l[1], l[2], l[3], l[4])
                end
                if where ~= "" then tooltip:AddLine("  Legközelebb: " .. where, 0.6, 0.8, 1) end
            else
                tooltip:AddDoubleLine("  " .. table.concat(names, ", "), where, 1, 1, 1, 0.6, 0.8, 1)
            end
        end
    end
    tooltip:AddLine("Kattintás: marker + QFocus macro", 0.5, 0.5, 0.5)
    tooltip:Show()
end

local function HookQuestLogButtons()
    local hooked = 0
    for i = 1, 50 do
        local btn = _G["QuestLogTitle" .. i]
        if not btn then break end
        if not btn.QuestFocusHooked then
            btn.QuestFocusHooked = true
            hooked = hooked + 1
            btn:HookScript("OnEnter", function(self)
                local index = self:GetID()
                if not index or index == 0 then return end
                local title, isHeader, questId, done = GetLogEntry(index)
                if isHeader or not questId then return end
                if GameTooltip:GetOwner() ~= self then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(title or "?", 1, 1, 1)
                    self.QuestFocusOwnsTooltip = true
                end
                AddQuestTooltip(GameTooltip, questId, done)
            end)
            btn:HookScript("OnLeave", function(self)
                if self.QuestFocusOwnsTooltip then
                    self.QuestFocusOwnsTooltip = nil
                    if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
                end
            end)
        end
    end
    return hooked
end

local function InstallHooks()
    local clickHooked = false

    -- Kattintas a quest log egy soran -> marker + macro
    if type(QuestLogTitleButton_OnClick) == "function" then
        hooksecurefunc("QuestLogTitleButton_OnClick", function(self, button)
            if not GetQuestLogSelection then return end
            SelectByLogIndex(GetQuestLogSelection(), true)
        end)
        clickHooked = true
    end

    -- Barmilyen kijeloles-valtas -> macro frissites (marker csak ha nincs click hook)
    if type(QuestLog_SetSelection) == "function" then
        hooksecurefunc("QuestLog_SetSelection", function(index)
            local _, isHeader, questId = GetLogEntry(index or 0)
            if isHeader or not questId then return end
            if questId ~= state.questId then SelectByLogIndex(index, not clickHooked) end
        end)
    end

    -- Modern quest log
    if C_QuestLog and type(C_QuestLog.SetSelectedQuest) == "function" then
        hooksecurefunc(C_QuestLog, "SetSelectedQuest", function(questId)
            if not questId or questId == 0 then return end
            local title, done = FindQuestInLog(questId)
            SelectQuest(questId, title, done, true)
        end)
    end

    HookQuestLogButtons()
    if QuestLogFrame then
        QuestLogFrame:HookScript("OnShow", HookQuestLogButtons)
    end
end

---------------------------------------------------------------------------
-- Esemenyek
---------------------------------------------------------------------------
local refreshPending = false
local function ScheduleRefresh()
    if refreshPending or not state.questId then return end
    refreshPending = true
    C_Timer.After(1, function()
        refreshPending = false
        if not state.questId then return end
        local title, done = FindQuestInLog(state.questId)
        if not title then
            -- Leadva vagy abandon: marker es kijeloles torlese
            local old = state.title
            ClearQuest()
            Print("|cffffff00%s|r eltűnt a logból, a markert töröltem.", old or "Quest")
            return
        end
        local becameComplete = done and not state.isComplete
        local prevDone = {}
        for i, o in ipairs(state.objectives or {}) do prevDone[i] = o.completed end
        state.title, state.isComplete = title, done and true or false
        Refresh(not becameComplete)
        if becameComplete then
            Print("|cffffff00%s|r kész, a marker a leadó NPC-re került.", title)
            MarkObjective(nil)
            return
        end
        -- Ha egy objective most lett kesz, a marker a kovetkezo hatralevore ugrik
        local justDone
        for i, o in ipairs(state.objectives or {}) do
            if o.completed and prevDone[i] == false then justDone = i end
        end
        if justDone and (state.objIndex == nil or state.objIndex == justDone) then
            state.objIndex = nil
            UpdateMacro()
            Panel_Update()
            if state.waypoint or state.tomtomUid then
                Print("Objective kész, a marker a következő célra került.")
                MarkObjective(nil)
            end
        end
    end)
end

QF:RegisterEvent("ADDON_LOADED")
QF:RegisterEvent("PLAYER_LOGIN")
QF:RegisterEvent("PLAYER_REGEN_ENABLED")
QF:RegisterEvent("QUEST_LOG_UPDATE")
QF:RegisterEvent("CVAR_UPDATE")
QF:RegisterEvent("PLAYER_REGEN_DISABLED")
QF:RegisterEvent("PLAYER_TARGET_CHANGED")
QF:SetScript("OnEvent", function(self, event, arg1)
    if event == "CVAR_UPDATE" then
        -- nameplate ki/be: mas macro kell (click vs. targetexact)
        if state.questId then C_Timer.After(0.1, UpdateMacro) end
        return
    elseif event == "PLAYER_TARGET_CHANGED" then
        if UnitExists("target") and targetNames[UnitName("target") or ""] and TapDenied("target")
            and not UnitIsDead("target") and UIErrorsFrame then
            UIErrorsFrame:AddMessage("QuestFocus: ezt a mobot már más tapolta", 1, 0.3, 0.3)
        end
        return
    end
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        QuestFocusDB = QuestFocusDB or {}
    elseif event == "PLAYER_LOGIN" then
        InstallHooks()
        if not _G.QuestieLoader then
            Print("|cffff5555A Questie nem található.|r Telepítsd, enélkül nem működik.")
        end
        -- Utolso kijelolt quest visszaallitasa, ha a Questie mar betoltott
        C_Timer.After(8, function()
            local id = QuestFocusDB.lastQuest
            if id and not state.questId then
                local title, done = FindQuestInLog(id)
                if title then SelectQuest(id, title, done, false) end
            end
        end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Harcban a gombot nem lehet atallitani, a regi nameplate token pedig mar mas mobra
        -- mutathat: inkabb engedjuk el, harc alatt a nev szerinti target dolgozik.
        state.pick = nil
        if state.questId and not InCombatLockdown() then UpdateMacro() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if state.pendingBody then ApplyMacro(state.pendingBody) end
        PickNameplate()
    elseif event == "QUEST_LOG_UPDATE" then
        ScheduleRefresh()
    end
end)

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
    if not silent then Print("Zóna fókusz ki: a korábbi questek visszakerültek a trackerbe.") end
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
    Print("Zóna fókusz: |cffffff00%s|r (%d quest marad, %d elrejtve). Kikapcsolás: ugyanaz a gomb / /qf zone",
        zone or "?", kept, hidden)
end

local function ToggleZoneFocus()
    if QuestFocusDB.zoneFocus then ZoneFocusOff() else ZoneFocusOn() end
end

-- Zonavaltaskor a fokusz koveti a jatekost
local zoneWatcher = CreateFrame("Frame")
zoneWatcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoneWatcher:SetScript("OnEvent", function()
    C_Timer.After(1, function()
        local zf = QuestFocusDB and QuestFocusDB.zoneFocus
        local zone = GetRealZoneText and GetRealZoneText() or GetZoneText()
        if zf and zone and zone ~= "" and zf.zone ~= zone then ZoneFocusOn() end
    end)
end)

---------------------------------------------------------------------------
-- Debug szoveg (chat es az options Debug fule)
---------------------------------------------------------------------------
local function DebugLines()
    local out = {}
    local names = {}
    for k in pairs(targetNames) do names[#names + 1] = k end
    local u = state.pick
    out[#out + 1] = ("Quest: %s (%s)"):format(state.title or "-", tostring(state.questId or "-"))
    out[#out + 1] = ("Nameplate mód: %s"):format(NameplatesUsable() and "be" or "ki (V gomb)")
    out[#out + 1] = ("Keresett mobok: %s"):format(#names > 0 and table.concat(names, ", ") or "-")
    out[#out + 1] = ("Kiválasztott: %s"):format(u == "busy" and "mind foglalt" or
        (u and ((UnitName(u) or "?") .. " (" .. u .. ")") or "nincs (név szerinti tartalék)"))
    out[#out + 1] = ("Harcban: %s"):format(InCombatLockdown() and "igen (a macro ilyenkor nem frissül)" or "nem")
    out[#out + 1] = ("Zóna fókusz: %s"):format(QuestFocusDB.zoneFocus and (QuestFocusDB.zoneFocus.zone or "?") or "ki")
    out[#out + 1] = "Látható quest mob nameplate-ek:"
    local any
    for i = 1, 40 do
        local nu = "nameplate" .. i
        if UnitExists(nu) and targetNames[UnitName(nu) or ""] then
            any = true
            out[#out + 1] = ("  %s: %s  halott=%s tapolt=%s támadható=%s harcban=%s"):format(nu, UnitName(nu),
                tostring(UnitIsDead(nu)), tostring(TapDenied(nu)), tostring(UnitCanAttack("player", nu)),
                tostring(UnitAffectingCombat(nu)))
        end
    end
    if not any then out[#out + 1] = "  (nincs)" end
    out[#out + 1] = "Macro:"
    for line in (state.lastBody or "-"):gmatch("[^\n]+") do out[#out + 1] = "  " .. line end
    return out
end

---------------------------------------------------------------------------
-- Beallitasok (Options > AddOns > QuestFocus)
---------------------------------------------------------------------------
local function RebuildMacro()
    state.lastBody = nil
    if state.questId then UpdateMacro() Panel_Update() end
end

local function SpellNameById(id)
    if not id then return end
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function SpellIcon(name)
    if not name or name == "" then return end
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(name) end
    if GetSpellTexture then return GetSpellTexture(name) end
end

local opt = CreateFrame("Frame")
opt.name = "QuestFocus"
local optCategory

local function OptLabel(parent, text, template)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

local function OptCheck(label, tip, get, set)
    local cb = CreateFrame("CheckButton", nil, opt.pageMain, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb.label = OptLabel(cb, label)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine(tip, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cb.refresh = function() cb:SetChecked(get()) end
    return cb
end

local optTitle = OptLabel(opt, "QuestFocus", "GameFontNormalLarge")
optTitle:SetPoint("TOPLEFT", 16, -16)
local optSub = OptLabel(opt, "QFocus macro és marker beállítások. Minden opcionális.", "GameFontHighlightSmall")
optSub:SetPoint("TOPLEFT", optTitle, "BOTTOMLEFT", 0, -6)

-- Fulek: Beallitasok / Debug
local pageMain = CreateFrame("Frame", nil, opt)
pageMain:SetPoint("TOPLEFT", optSub, "BOTTOMLEFT", 0, -40)
pageMain:SetPoint("BOTTOMRIGHT", opt, "BOTTOMRIGHT", -16, 16)
local pageDebug = CreateFrame("Frame", nil, opt)
pageDebug:SetAllPoints(pageMain)
pageDebug:Hide()

local tabs = {}
local function SelectTab(i)
    for n, t in ipairs(tabs) do
        if n == i then t:Disable() else t:Enable() end
        t.page:SetShown(n == i)
    end
end
for i, def in ipairs({ { "Beállítások", pageMain }, { "Debug", pageDebug } }) do
    local t = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate")
    t:SetSize(110, 22)
    t:SetText(def[1])
    t.page = def[2]
    t:SetPoint("TOPLEFT", optSub, "BOTTOMLEFT", (i - 1) * 114, -10)
    t:SetScript("OnClick", function() SelectTab(i) end)
    tabs[i] = t
end
opt.pageMain = pageMain

-- Spell a tapeleshez
local cbSpell = OptCheck("Spell a macroban (tapelés)",
    "Ha be van kapcsolva, a QFocus macro a target után el is süti a kiválasztott spellt a mobra. "
    .. "Leadásnál (barátságos NPC) nem castol.",
    function() return QuestFocusDB.useSpell end,
    function(v) QuestFocusDB.useSpell = v; RebuildMacro() end)
cbSpell:SetPoint("TOPLEFT", pageMain, "TOPLEFT", -2, 0)

local spellSlot = CreateFrame("Button", nil, pageMain)
spellSlot:SetSize(36, 36)
spellSlot:SetPoint("TOPLEFT", cbSpell, "BOTTOMLEFT", 26, -8)
spellSlot.bg = spellSlot:CreateTexture(nil, "BACKGROUND")
spellSlot.bg:SetAllPoints()
spellSlot.bg:SetColorTexture(0, 0, 0, 0.5)
spellSlot.icon = spellSlot:CreateTexture(nil, "ARTWORK")
spellSlot.icon:SetPoint("TOPLEFT", 2, -2)
spellSlot.icon:SetPoint("BOTTOMRIGHT", -2, 2)
spellSlot:RegisterForClicks("LeftButtonUp", "RightButtonUp")

local spellBox = CreateFrame("EditBox", nil, pageMain, "InputBoxTemplate")
spellBox:SetSize(200, 20)
spellBox:SetAutoFocus(false)
spellBox:SetPoint("LEFT", spellSlot, "RIGHT", 14, 6)
local spellHint = OptLabel(pageMain,"Húzz ide egy spellt a spellbookból (P), vagy írd be a nevét + Enter. Jobb klikk: törlés.",
    "GameFontDisableSmall")
spellHint:SetPoint("TOPLEFT", spellBox, "BOTTOMLEFT", -4, -4)
spellHint:SetWidth(360)

local function RefreshSpellUI()
    local s = QuestFocusDB.spell
    spellBox:SetText(s or "")
    spellSlot.icon:SetTexture(SpellIcon(s) or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
end

local function SetSpell(name)
    if name then name = name:match("^%s*(.-)%s*$") end
    if name == "" then name = nil end
    QuestFocusDB.spell = name
    if name and not QuestFocusDB.useSpell then QuestFocusDB.useSpell = true; cbSpell.refresh() end
    RefreshSpellUI()
    RebuildMacro()
    Print(name and ("Tap spell: |cffffff00%s|r"):format(name) or "Tap spell törölve.")
end

local function SpellFromCursor()
    local kind, a, b, c = GetCursorInfo()
    if kind ~= "spell" then return end
    local name = SpellNameById(c)
    if not name and GetSpellBookItemName and a then name = GetSpellBookItemName(a, b) end
    ClearCursor()
    if name then SetSpell(name) end
end

spellSlot:SetScript("OnReceiveDrag", SpellFromCursor)
spellSlot:SetScript("OnClick", function(_, button)
    if button == "RightButton" then SetSpell(nil) else SpellFromCursor() end
end)
spellSlot:SetScript("OnEnter", function(self)
    if not QuestFocusDB.spell then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(QuestFocusDB.spell, 1, 1, 1)
    GameTooltip:Show()
end)
spellSlot:SetScript("OnLeave", function() GameTooltip:Hide() end)
spellBox:SetScript("OnEnterPressed", function(self) SetSpell(self:GetText()); self:ClearFocus() end)
spellBox:SetScript("OnEscapePressed", function(self) RefreshSpellUI(); self:ClearFocus() end)

local cbAttack = OptCheck("Autoattack (/startattack)",
    "A target után automatikus támadás is indul (melee / wand / íj).",
    function() return QuestFocusDB.startAttack end,
    function(v) QuestFocusDB.startAttack = v; RebuildMacro() end)
cbAttack:SetPoint("TOPLEFT", spellSlot, "BOTTOMLEFT", -26, -28)

local cbPing = OptCheck("Ping a targetre",
    "A macro a végén pingeli a targetet (Z-s ping rendszer), partyban a többiek is látják.",
    function() return not QuestFocusDB.noPing end,
    function(v) QuestFocusDB.noPing = not v; RebuildMacro() end)
cbPing:SetPoint("TOPLEFT", cbAttack, "BOTTOMLEFT", 0, -6)

local cbArrow = OptCheck("Saját nyíl",
    "Nyíl a marker felé (TomTom mellett nem jelenik meg, akkor a TomTom nyila mutat).",
    function() return not QuestFocusDB.noArrow end,
    function(v)
        QuestFocusDB.noArrow = not v
        if not v then arrow:Hide() elseif state.waypoint and UseOwnArrow() then arrow:Show() end
    end)
cbArrow:SetPoint("TOPLEFT", cbPing, "BOTTOMLEFT", 0, -6)

---------------------------------------------------------------------------
-- Minimap gomb (bal klikk: beallitasok, jobb klikk: zona fokusz, huzhato)
---------------------------------------------------------------------------
local OpenOptions -- lent
local mmBtn = CreateFrame("Button", "QuestFocusMinimapButton", Minimap)
mmBtn:SetSize(31, 31)
mmBtn:SetFrameStrata("MEDIUM")
mmBtn:SetFrameLevel(8)
mmBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mmBtn:RegisterForDrag("LeftButton")
mmBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
do
    local bg = mmBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = mmBtn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\" .. ICON_HUNT)
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    mmBtn.icon = icon
    local border = mmBtn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
end

local function MinimapButtonPos()
    local angle = math.rad(QuestFocusDB.minimapAngle or 200)
    local r = (Minimap:GetWidth() / 2) + 10
    mmBtn:ClearAllPoints()
    mmBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function UpdateMinimapButton()
    if not QuestFocusDB then return end
    mmBtn:SetShown(not QuestFocusDB.hideMinimap)
    MinimapButtonPos()
end

mmBtn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local s = Minimap:GetEffectiveScale()
        QuestFocusDB.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
        MinimapButtonPos()
    end)
end)
mmBtn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mmBtn:RegisterEvent("PLAYER_LOGIN")
mmBtn:SetScript("OnEvent", function() UpdateMinimapButton() end)
mmBtn:SetScript("OnClick", function(_, button)
    if button == "RightButton" then ToggleZoneFocus() else OpenOptions() end
end)
mmBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("QuestFocus", 0.2, 1, 0.6)
    if state.title then GameTooltip:AddLine("Quest: " .. state.title, 1, 1, 1) end
    local zf = QuestFocusDB and QuestFocusDB.zoneFocus
    GameTooltip:AddLine("Zóna fókusz: " .. (zf and (zf.zone or "?") or "ki"), 1, 0.82, 0)
    GameTooltip:AddLine("Bal klikk: beállítások", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Jobb klikk: zóna fókusz ki/be", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Húzd: áthelyezés", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
mmBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Zona fokusz gomb a beallitasokban
local zoneBtn = CreateFrame("Button", nil, pageMain, "UIPanelButtonTemplate")
zoneBtn:SetSize(220, 24)
zoneBtn:SetPoint("TOPLEFT", cbArrow, "BOTTOMLEFT", 4, -14)
local zoneHint = OptLabel(pageMain, "Csak az aktuális zóna questjei maradnak a Questie trackerben (a kijelölt QFocus quest is). "
    .. "Zónaváltáskor követ, kikapcsolva minden visszakerül. Minimapon: jobb klikk.", "GameFontDisableSmall")
zoneHint:SetPoint("TOPLEFT", zoneBtn, "BOTTOMLEFT", 0, -4)
zoneHint:SetWidth(420)
local function RefreshZoneBtn()
    local zf = QuestFocusDB.zoneFocus
    zoneBtn:SetText(zf and ("Zóna fókusz KI (" .. (zf.zone or "?") .. ")") or "Fókusz erre a zónára")
end
zoneBtn:SetScript("OnClick", function() ToggleZoneFocus(); RefreshZoneBtn() end)

local cbMinimap = OptCheck("Minimap gomb",
    "Bal klikk: beállítások, jobb klikk: zóna fókusz. Húzással áthelyezhető.",
    function() return not QuestFocusDB.hideMinimap end,
    function(v) QuestFocusDB.hideMinimap = not v; UpdateMinimapButton() end)
cbMinimap:SetPoint("TOPLEFT", zoneHint, "BOTTOMLEFT", -6, -14)

local optNote = OptLabel(pageMain, "Harc közben a macro nem módosítható, a változás harc után érvényesül.",
    "GameFontDisableSmall")
optNote:SetPoint("TOPLEFT", cbMinimap, "BOTTOMLEFT", 2, -16)

-- Debug ful
local dbgScroll = CreateFrame("ScrollFrame", nil, pageDebug, "UIPanelScrollFrameTemplate")
dbgScroll:SetPoint("TOPLEFT", 0, -30)
dbgScroll:SetPoint("BOTTOMRIGHT", -26, 0)
local dbgChild = CreateFrame("Frame", nil, dbgScroll)
dbgChild:SetSize(560, 400)
dbgScroll:SetScrollChild(dbgChild)
local dbgText = dbgChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
dbgText:SetPoint("TOPLEFT")
dbgText:SetWidth(560)
dbgText:SetJustifyH("LEFT")
dbgText:SetJustifyV("TOP")
local function RefreshDebug()
    dbgText:SetText(table.concat(DebugLines(), "\n"))
    dbgChild:SetHeight(math.max(400, dbgText:GetStringHeight() + 10))
end
local dbgRefresh = CreateFrame("Button", nil, pageDebug, "UIPanelButtonTemplate")
dbgRefresh:SetSize(100, 22)
dbgRefresh:SetPoint("TOPLEFT")
dbgRefresh:SetText("Frissítés")
dbgRefresh:SetScript("OnClick", RefreshDebug)
local dbgChat = CreateFrame("Button", nil, pageDebug, "UIPanelButtonTemplate")
dbgChat:SetSize(120, 22)
dbgChat:SetPoint("LEFT", dbgRefresh, "RIGHT", 6, 0)
dbgChat:SetText("Chatbe írás")
dbgChat:SetScript("OnClick", function() for _, l in ipairs(DebugLines()) do Print(l) end end)
local dbgLive = OptLabel(pageDebug, "Élő: 0,5 mp-enként frissül, amíg nyitva van.", "GameFontDisableSmall")
dbgLive:SetPoint("LEFT", dbgChat, "RIGHT", 10, 0)
local dbgElapsed = 0
pageDebug:SetScript("OnShow", RefreshDebug)
pageDebug:SetScript("OnUpdate", function(_, dt)
    dbgElapsed = dbgElapsed + dt
    if dbgElapsed > 0.5 then dbgElapsed = 0; RefreshDebug() end
end)

opt:SetScript("OnShow", function()
    for _, cb in ipairs({ cbSpell, cbAttack, cbPing, cbArrow, cbMinimap }) do cb.refresh() end
    RefreshSpellUI()
    RefreshZoneBtn()
    SelectTab(1)
end)

if Settings and Settings.RegisterCanvasLayoutCategory then
    optCategory = Settings.RegisterCanvasLayoutCategory(opt, "QuestFocus")
    Settings.RegisterAddOnCategory(optCategory)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(opt)
end

OpenOptions = function()
    if InCombatLockdown() then Print("Harc után nyisd meg.") return end
    if optCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(optCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(opt)
        InterfaceOptionsFrame_OpenToCategory(opt)
    end
end

SLASH_QUESTFOCUS1 = "/qf"
SLASH_QUESTFOCUS2 = "/questfocus"
SlashCmdList.QUESTFOCUS = function(msg)
    local raw = (msg or ""):match("^%s*(.-)%s*$")
    msg = raw:lower()
    if msg == "options" or msg == "config" or msg == "opt" then
        OpenOptions()
    elseif msg == "debug" then
        for _, l in ipairs(DebugLines()) do Print(l) end
    elseif msg == "zone" then
        ToggleZoneFocus()
    elseif msg == "minimap" then
        QuestFocusDB.hideMinimap = not QuestFocusDB.hideMinimap
        UpdateMinimapButton()
        Print("Minimap gomb: %s", QuestFocusDB.hideMinimap and "ki" or "be")
    elseif msg == "spell" or msg:match("^spell%s") then
        local name = raw:match("^%S+%s+(.+)$")
        if name and name:lower() == "off" then
            QuestFocusDB.useSpell = false
            RebuildMacro()
            Print("Tap spell kikapcsolva.")
        else
            SetSpell(name)
        end
    elseif msg == "" then
        QuestFocusDB.hidePanel = panel:IsShown()
        if not state.questId then Print("Válassz ki egy questet a quest logban (L).") end
        Panel_Update()
    elseif msg == "next" then
        local objs = state.objectives or {}
        if #objs == 0 then Print("Nincs kijelölt quest.") return end
        local i = state.objIndex or 0
        for _ = 1, #objs do
            i = i % #objs + 1
            if not objs[i].completed then break end
        end
        SelectObjective(i)
    elseif msg == "all" then
        SelectObjective(nil)
    elseif msg == "mark" then
        MarkObjective(state.objIndex)
    elseif msg == "arrow" then
        QuestFocusDB.noArrow = not QuestFocusDB.noArrow
        Print("Saját nyíl: %s", QuestFocusDB.noArrow and "ki" or "be")
        if QuestFocusDB.noArrow then arrow:Hide() elseif state.waypoint and UseOwnArrow() then arrow:Show() end
    elseif msg == "ping" then
        QuestFocusDB.noPing = not QuestFocusDB.noPing
        Print("Ping a QFocus macroban: %s", QuestFocusDB.noPing and "ki" or "be")
        state.lastBody = nil
        if state.questId then UpdateMacro() Panel_Update() end
    elseif msg == "icon" or msg:match("^icon%s") then
        local name = msg:match("^icon%s+(%S+)")
        if name then
            local id = IconId(name)
            if id == ICON_FALLBACK then
                Print("Nem találom ezt az ikont: %s (pl. ability_hunter_snipershot)", name)
                return
            end
            QuestFocusDB.icon = name
            Print("QFocus ikon: |T%d:16|t %s", id, name)
        else
            QuestFocusDB.icon = nil
            Print("QFocus ikon: automatikus (célkereszt / levél leadásnál)")
        end
        state.lastIcon = nil
        if not InCombatLockdown() then ApplyMacro(state.lastBody or BuildMacroBody(state.objectives, state.objIndex)) end
    elseif msg == "unmark" then
        ClearWaypoint()
        Print("Marker törölve.")
    elseif msg == "clear" then
        ClearQuest()
        Print("Kijelölés törölve.")
    else
        Print("Parancsok:")
        Print("  /qf - panel ki/be")
        Print("  /qf options - beállítások (tap spell, autoattack, ping, nyíl, debug fül)")
        Print("  /qf zone - zóna fókusz ki/be (csak az aktuális zóna questjei a trackerben)")
        Print("  /qf minimap - minimap gomb ki/be")
        Print("  /qf debug - diagnosztika a chatbe")
        Print("  /qf spell <név> - tap spell a macroba; /qf spell - törlés; /qf spell off - kikapcsolás")
        Print("  /qf next - következő objective (marker + macro)")
        Print("  /qf all - macro az összes hátralévő objective mobjára")
        Print("  /qf mark - marker újra a legközelebbi helyre")
        Print("  /qf arrow - saját nyíl ki/be")
        Print("  /qf ping - ping a targetre a macroban ki/be")
        Print("  /qf icon <ikonnév> - saját ikon; /qf icon - automatikus")
        Print("  /qf unmark - marker törlése")
        Print("  /qf clear - kijelölés + marker törlése")
    end
end
