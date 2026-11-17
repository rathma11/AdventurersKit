-- QuestFocus
-- Quest kijelolesre: QFocus target macro, marker (waypoint + nyil), tooltip.
-- Az adatokat (mobok, itemek, spawn helyek, leado NPC) a Questie-bol veszi.

local ADDON_NAME, NS = ...
local L = NS.L
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
                desc = L["Turn in: "] .. table.concat(names, ", "),
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
            entry.qid = quest.Id
            entry.qo = o -- Questie objective (Collected/Needed) az ETA szamitashoz
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
        lines[#lines + 1] = { L["Pick up: "] .. (s.name or "?") .. L[" (on the ground / in an object)"], 0.6, 1, 0.6 }
    end
    for _, s in ipairs(mobs) do
        if n >= limit then break end
        n = n + 1
        local txt = L["Dropped by: "] .. (s.name or "?")
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
                        lines[#lines + 1] = { L["Sold by: "] .. (npc.name or "?"), 1, 0.9, 0.3 }
                    end
                end
            end
        end
    end
    local total = #objs + #mobs
    if total > limit then
        lines[#lines + 1] = { (L["+%d more sources"]):format(total - limit), 0.6, 0.6, 0.6 }
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

-- Marker celpont: ha mar a spawn teruleten vagy (IN_AREA yardon belul van spawn), nem kuld
-- sehova (inArea = true). Kulonben nem a puszta legkozelebbi pontot adja, hanem azt, ami
-- kozel van ES korulotte sok spawn van (suru resz), igy nem egy magányos pontra visz.
local IN_AREA, CLUSTER_R, CLUSTER_W = 150, 80, 40
local function FindSpawnTarget(sources)
    local pc, px, py = PlayerWorldPos()
    if not pc then return FindNearest(sources) end
    local pts = {}
    for _, src in ipairs(sources) do
        if type(src.spawns) == "table" then
            for areaId, list in pairs(src.spawns) do
                local uiMap = UiMapFromArea(areaId)
                if uiMap and type(list) == "table" then
                    for _, c in ipairs(list) do
                        local x, y = c[1], c[2]
                        if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
                            local wc, wx, wy = WorldPos(uiMap, x / 100, y / 100)
                            if wc == pc and wx then
                                pts[#pts + 1] = { map = uiMap, x = x, y = y, name = src.name, wc = wc, wx = wx, wy = wy,
                                    d = math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2) }
                            end
                        end
                    end
                end
            end
        end
    end
    if #pts == 0 then return FindNearest(sources) end -- masik kontinens: a regi mod
    local nearest
    for _, p in ipairs(pts) do if not nearest or p.d < nearest.d then nearest = p end end
    if nearest.d <= IN_AREA then return nearest, nearest.d, true end
    -- csak a kozelebbi pontokat nezzuk (a legkozelebbi tavolsaganak 3x-osaig), sulyozva a surusseggel
    local best, bestScore
    local limit = nearest.d * 3 + 200
    for _, p in ipairs(pts) do
        if p.d <= limit then
            local n = 0
            for _, q in ipairs(pts) do
                if q ~= p and math.abs(q.wx - p.wx) < CLUSTER_R and math.abs(q.wy - p.wy) < CLUSTER_R then n = n + 1 end
            end
            local score = p.d - CLUSTER_W * math.min(n, 8)
            if not bestScore or score < bestScore then best, bestScore = p, score end
        end
    end
    best = best or nearest
    return best, best.d, false
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
    -- Leadasnal: ha a leado NPC messze van (>100 yd), de a kozelben van mas quest mobja,
    -- a macro azokat targeteli; az NPC kozeleben visszavalt az NPC-re
    if turnIn and onlyIndex == nil and state.extra and #state.extra > 0 then
        local _, d = FindNearest(objectives[1].sources)
        if not d or d > 100 then
            turnIn = false
            objectives = {}
        end
    end
    local useNP = NameplatesUsable() and not turnIn and not InCombatLockdown()
    local CLEAR, DEADCLR = "/cleartarget", "/cleartarget [dead]"
    local pick = useNP and state.pick or nil
    if pick == "busy" then
        CLEAR = '/run UIErrorsFrame:AddMessage("QuestFocus: nearby quest mobs are taken",1,.6,.2)'
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
    -- Pingelni csak uj celpontra: ha a kivalasztott mob mar a targeted (vagy harcban a
    -- mostani target jo quest mob), a ping kimarad, igy a macro spamelese nem pingel ujra
    local onTarget
    if pick and pick ~= "busy" then
        onTarget = UnitIsUnit(pick, "target")
    elseif not pick then
        onTarget = GoodQuestUnit("target")
    end
    if usePing and not onTarget then tail[#tail + 1] = PING_LINE end
    local lines, seen = { CLEAR }, {}
    local len = #CLEAR + 1
    for _, t in ipairs(tail) do len = len + #t + 1 end
    local n = 0
    wipe(targetNames)
    local function addName(name)
        if not name or seen[name] then return end
        seen[name] = true
        targetNames[name] = true
        n = n + 1
        if not pick then -- nev szerint, ha nincs latszo quest mob nameplate (vagy harc)
            local line = "/targetexact [noexists] " .. name
            local cost = #line + 1 + #DEADCLR + 1
            if len + cost <= MACRO_MAX then
                lines[#lines + 1] = line
                lines[#lines + 1] = DEADCLR
                len = len + cost
            end
        end
    end
    for i, obj in ipairs(objectives or {}) do
        if (onlyIndex == nil and not obj.completed) or onlyIndex == i then
            for _, src in ipairs(obj.sources) do
                if src.isNpc then addName(src.name) end
            end
        end
    end
    -- A kozelben levo tobbi quest mobjai is (ha nem egy konkret objective-re szukitettel)
    if not turnIn and onlyIndex == nil then
        for _, e in ipairs(state.extra or {}) do
            for _, name in ipairs(e.names) do addName(name) end
        end
    end
    if n == 0 then
        return '/run print("QuestFocus: no targetable mob")', 0
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
        if not state.pendingBody then Print(L["You are in combat, the QFocus macro will update after combat."]) end
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
            Print(L["No room for a new account macro, delete one first."])
            return
        end
        CreateMacro(MACRO_NAME, CurrentIcon(), body, nil)
        Print(L["Created the |cffffff00%s|r macro. Open /macro and drag it to your action bar."], MACRO_NAME)
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
        self.text:SetText((w.title or "?") .. L["\n|cff33ff33You have arrived|r"])
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
        Print(L["No known location for: %s"], state.title or "?")
        return
    end
    local p, dist, inArea = FindSpawnTarget(sources)
    if not p then
        Print(L["No coordinates found (it may be inside an instance)."])
        return
    end
    -- Mob objective-nel, ha mar a teruleten vagy, nem kuldunk tovabb (leadasnal mindig jelolunk)
    local isTurnIn = list[1] and list[1].turnIn
    if inArea and not isTurnIn then
        ClearWaypoint()
        Print(L["You are in the spawn area of |cffffff00%s|r, no marker needed (nearest spawn %d yd)."], p.name or "?", dist or 0)
        return
    end
    SetWaypoint(p, p.name or state.title)
    Print(L["Marker: |cffffff00%s|r - %s %.1f, %.1f%s"], p.name or "?", ZoneName(p.map), p.x, p.y,
        dist and (" (%d yd)"):format(dist) or "")
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local panel = CreateFrame("Frame", "QuestFocusPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
local PANEL_W = 300 -- alap szelesseg; a fogantyuval allithato (QuestFocusDB.panelW / panelH)

-- Szelesseg, sormagassag es betumeret (a betumeret kulon beallitas: QuestFocusDB.fontSize)
local function PW() return math.max(240, math.min(600, tonumber(QuestFocusDB and QuestFocusDB.panelW) or PANEL_W)) end
local function FontSize() return math.max(8, math.min(20, tonumber(QuestFocusDB and QuestFocusDB.fontSize) or 10)) end
local function RowH() return math.max(16, FontSize() + 6) end
NS.PW, NS.RowH, NS.FontSize = PW, RowH, FontSize

-- Sajat font objektumok: a meretuk atallitasa minden ezt hasznalo szoveget frissit
local fontSmall = CreateFont("QuestFocusFontSmall")
fontSmall:CopyFontObject(GameFontHighlightSmall)
local fontTitle = CreateFont("QuestFocusFontTitle")
fontTitle:CopyFontObject(GameFontNormal)
local function ApplyFontSize()
    local size = FontSize()
    local p, _, f = GameFontHighlightSmall:GetFont()
    if p then fontSmall:SetFont(p, size, f or "") end
    local tp, _, tf = GameFontNormal:GetFont()
    if tp then fontTitle:SetFont(tp, size + 2, tf or "") end
end
NS.ApplyFontSize = ApplyFontSize
local GOLD = { 0.95, 0.78, 0.40 }
panel:SetSize(PANEL_W, 60)
panel:SetPoint("RIGHT", UIParent, "RIGHT", -260, 80)
panel:SetMovable(true)
panel:SetClampedToScreen(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", function(self) self.isMoving = true; self:StartMoving() end)
-- Pozicio: a bal FELSO sarkot mentjuk magunk (QuestFocusDB.panelPos), nem a WoW layout
-- cache-et, mert az a legkozelebbi pontot (pl. also/kozep) menti, es valtozo magassagnal
-- a panel lefele csuszott / kilogott a kepernyorol.
local function SavePanelPos()
    local l, t = panel:GetLeft(), panel:GetTop()
    if not (l and t) then return end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    if QuestFocusDB then QuestFocusDB.panelPos = { l = math.floor(l + 0.5), t = math.floor(t + 0.5) } end
end
local function RestorePanelPos()
    if panel.SetUserPlaced then pcall(panel.SetUserPlaced, panel, false) end
    local p = QuestFocusDB and QuestFocusDB.panelPos
    if p and p.l and p.t then
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.l, p.t)
    else
        SavePanelPos() -- elso alkalommal: a mostani (regi) helyet atvesszuk
    end
end
NS.RestorePanelPos = RestorePanelPos
panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self.isMoving = nil
    SavePanelPos()
    if self.SetUserPlaced then pcall(self.SetUserPlaced, self, false) end
end)
if panel.SetBackdrop then
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 20,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    panel:SetBackdropColor(0.04, 0.04, 0.06, 0.93)
    panel:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
end
panel:Hide()

-- Fejlec: ikon + cim + alcim
local iconFrame = CreateFrame("Frame", nil, panel, BackdropTemplateMixin and "BackdropTemplate" or nil)
iconFrame:SetSize(30, 30)
iconFrame:SetPoint("TOPLEFT", 11, -11)
if iconFrame.SetBackdrop then
    iconFrame:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
    iconFrame:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
end
panel.icon = iconFrame:CreateTexture(nil, "ARTWORK")
panel.icon:SetPoint("TOPLEFT", 3, -3)
panel.icon:SetPoint("BOTTOMRIGHT", -3, 3)
panel.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
panel.icon:SetTexture("Interface\\Icons\\" .. ICON_IDLE)

panel.title = panel:CreateFontString(nil, "OVERLAY", "QuestFocusFontTitle")
panel.title:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 8, -1)
panel.title:SetWidth(PANEL_W - 80)
panel.title:SetJustifyH("LEFT")
panel.title:SetWordWrap(false)
panel.title:SetTextColor(1, 0.86, 0.5)

panel.sub = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
panel.sub:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -3)
panel.sub:SetWidth(PANEL_W - 80)
panel.sub:SetJustifyH("LEFT")
panel.sub:SetWordWrap(false)

local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetSize(26, 26)
close:SetPoint("TOPRIGHT", -3, -3)
close:SetScript("OnClick", function()
    QuestFocusDB.hidePanel = true
    panel:Hide()
    Print(L["Panel hidden. It comes back when you click a quest, or: /qf"])
end)

local function Divider(y)
    local t = panel:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", 12, y)
    t:SetPoint("TOPRIGHT", -12, y)
    t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
    return t
end
panel.headDivider = Divider(-48)

-- Statisztika dobozok: haladas / hatralevo ido / tempo
panel.stats = CreateFrame("Frame", nil, panel)
panel.stats:SetPoint("TOPLEFT", 12, -55)
panel.stats:SetPoint("TOPRIGHT", -12, -55)
panel.stats:SetHeight(38)
panel.statBoxes = {}
local boxW = (PANEL_W - 24 - 8) / 3
for i, label in ipairs({ L["PROGRESS"], L["TIME LEFT"], L["PACE"] }) do
    local b = CreateFrame("Frame", nil, panel.stats, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b:SetSize(boxW, 38)
    b:SetPoint("TOPLEFT", (i - 1) * (boxW + 4), 0)
    if b.SetBackdrop then
        b:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        b:SetBackdropColor(0, 0, 0, 0.55)
        b:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
    end
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("TOP", 0, -5)
    b.label:SetText(label)
    b.label:SetTextColor(0.75, 0.65, 0.45)
    b.value = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.value:SetPoint("BOTTOM", 0, 5)
    b.value:SetText("-")
    panel.statBoxes[i] = b
end

-- Osszesitett haladas csik
panel.bar = CreateFrame("StatusBar", nil, panel)
panel.bar:SetPoint("TOPLEFT", 13, -99)
panel.bar:SetPoint("TOPRIGHT", -13, -99)
panel.bar:SetHeight(6)
panel.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
panel.bar:SetStatusBarColor(0.95, 0.75, 0.2)
panel.bar:SetMinMaxValues(0, 1)
local barBg = panel.bar:CreateTexture(nil, "BACKGROUND")
barBg:SetAllPoints()
barBg:SetColorTexture(0.15, 0.15, 0.15, 0.9)

panel.section = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
panel.section:SetTextColor(0.75, 0.65, 0.45)
panel.section:SetJustifyH("LEFT")

panel.footDivider = panel:CreateTexture(nil, "ARTWORK")
panel.footDivider:SetHeight(1)
panel.footDivider:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)

panel.footer = panel:CreateFontString(nil, "OVERLAY", "QuestFocusFontSmall")
panel.footer:SetJustifyH("LEFT")
panel.footer:SetWidth(PANEL_W - 44) -- a jobb also sarokban az atmeretezo fogantyu
panel.footer:SetWordWrap(false) -- egy sor: a panel magassaga ne valtozzon harc kozben

panel.lines = {}

-- Szelesseg alkalmazasa minden panel elemre (a fogantyu es a betoltes hivja)
local function ApplyPanelWidth()
    local w = PW()
    panel:SetWidth(w)
    panel.title:SetWidth(w - 80)
    panel.sub:SetWidth(w - 80)
    panel.footer:SetWidth(w - 44)
    local bw = (w - 24 - 8) / 3
    for i, b in ipairs(panel.statBoxes) do
        b:SetWidth(bw)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", (i - 1) * (bw + 4), 0)
    end
end
NS.ApplyPanelWidth = ApplyPanelWidth

-- A bal felso sarok maradjon a helyen (atmeretezes / tartalomvaltas eseten)
local function AnchorTopLeft()
    -- ha van mentett pozicio, mindig oda (igy a kepernyo szelen torteno "clamp" eltolas
    -- sem marad meg tartosan, a panel visszaall a mentett tetejere)
    local p = QuestFocusDB and QuestFocusDB.panelPos
    if p and p.l and p.t and not panel.isMoving then
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.l, p.t)
        return
    end
    local p1 = panel:GetPoint(1)
    local l, t = panel:GetLeft(), panel:GetTop()
    if p1 ~= "TOPLEFT" and l and t then
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    end
end

-- A panel egy pontja UIParent koordinatakban (a panel scale-je miatt atszamolva) -
-- a panelhez nem horgonyzott (secure) ablakok elhelyezesehez
NS.PanelEdge = function(which)
    local v = (which == "left" and panel:GetLeft()) or (which == "right" and panel:GetRight())
        or (which == "top" and panel:GetTop()) or (which == "bottom" and panel:GetBottom())
    if not v then return end
    return v * panel:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

local grip = CreateFrame("Button", nil, panel)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -4, 4)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
-- Atmeretezes: a panel szelesseget es (javaslat modban) magassagat allitja, a betumeret
-- NEM valtozik (az kulon beallitas). Nagyobb panel = tobb sor a javaslatokban.
-- Jobb klikk: alapmeret. Mentve: QuestFocusDB.panelW / panelH
grip:RegisterForClicks("RightButtonUp")
grip:SetScript("OnClick", function()
    QuestFocusDB.panelW, QuestFocusDB.panelH = nil, nil
    ApplyPanelWidth()
    if NS.Panel_Update then NS.Panel_Update() end
end)
grip:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    AnchorTopLeft()
    local x, y = GetCursorPosition()
    self.drag = { x = x, y = y, w = panel:GetWidth(), h = panel:GetHeight() }
    self:SetScript("OnUpdate", function()
        local cx, cy = GetCursorPosition()
        local es = panel:GetEffectiveScale()
        local w = self.drag.w + (cx - self.drag.x) / es
        local h = self.drag.h + (self.drag.y - cy) / es
        QuestFocusDB.panelW = math.floor(math.max(240, math.min(600, w)))
        QuestFocusDB.panelH = math.floor(math.max(120, math.min(900, h)))
        ApplyPanelWidth()
        panel:SetHeight(QuestFocusDB.panelH)
    end)
end)
grip:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
    self.drag = nil
    if NS.Panel_Update then NS.Panel_Update() end -- tartalom ujrarendezese (tobb/kevesebb sor)
end)
grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Drag to resize"], 1, 1, 1)
    GameTooltip:AddLine(L["Right click: reset size"], 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Fejlec es lablec elhelyezese; mode = "quest" (statisztikaval) vagy "list" (javaslatok).
-- Visszaadja, honnan kezdodhet a tartalom (y).
local function PanelChrome(mode, sectionText)
    -- Varosban nincs statisztika (ott nem harcolsz), kiveve leadas modban (utazas dobozok)
    local quest = mode == "quest" and (state.isComplete or not (NS.InCity and NS.InCity()))
    panel.stats:SetShown(quest)
    panel.bar:SetShown(quest)
    local y = quest and -112 or -56
    if sectionText then
        panel.section:ClearAllPoints()
        panel.section:SetPoint("TOPLEFT", 14, y)
        panel.section:SetText(sectionText)
        panel.section:Show()
        y = y - 15
    else
        panel.section:Hide()
    end
    return y
end

-- Tartalom utan: elvalaszto + lablec, panel magassag
-- isList: javaslat mod, ott a felhasznalo altal huzott magassag is szamit (tobb sor fer ki)
local function PanelFinish(y, isList)
    -- A panel teteje maradjon a helyen (ne a kozepe korul nojon/zsugorodjon)
    AnchorTopLeft()
    local fh = RowH()
    local h = -y + 8 + fh + 12
    if isList and tonumber(QuestFocusDB.panelH) then h = math.max(h, QuestFocusDB.panelH) end
    panel:SetHeight(h)
    -- a lablec mindig a panel aljan
    panel.footer:ClearAllPoints()
    panel.footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 13, 12)
    panel.footDivider:ClearAllPoints()
    panel.footDivider:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 12 + fh + 2)
    panel.footDivider:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 12 + fh + 2)
end
NS.PanelChrome, NS.PanelFinish = PanelChrome, PanelFinish

-- A panel alja: elo allapot (kit targetel a macro, mennyire van messze a marker)
local function MarkerDistance()
    local w = state.waypoint
    if not (w and w.wx) then return end
    local pc, px, py = PlayerWorldPos()
    if not pc or pc ~= w.wc then return end
    return math.floor(math.sqrt((px - w.wx) ^ 2 + (py - w.wy) ^ 2) + 0.5)
end

local function FooterText()
    local dist = MarkerDistance()
    local distTxt = dist and ("|cff99ccff%d yd|r"):format(dist) or nil
    local objs = state.objectives or {}
    if objs[1] and objs[1].turnIn then
        -- A leado NPC neve mar ott van az objective sorban: itt csak hogy mit csinal a macro
        local _, d = FindNearest(objs[1].sources)
        local npcTxt = d and ("|cff99ccff%d yd|r"):format(d) or nil
        local far = not d or d > 100
        if not (far and state.extra and #state.extra > 0) then
            return L["Macro: targets the turn-in NPC"] .. (npcTxt and (" - " .. npcTxt) or "")
        end
        -- messze az NPC, a macro a kozeli quest mobokat targeteli
        local u = state.pick
        local mob
        if u == "busy" then
            mob = L["|cffff9933Nearby mobs are taken|r"]
        elseif u and UnitExists(u) then
            mob = (L["|cff33ff99Target:|r %s"]):format(UnitName(u) or "?")
        else
            mob = L["No mob nearby"]
        end
        return mob .. (npcTxt and (L[" - turn-in "] .. npcTxt) or "")
    end
    if (state.macroCount or 0) == 0 then
        return L["No targetable mob (item / object gathering)"] .. (distTxt and (" - " .. distTxt) or "")
    end
    local u = state.pick
    if u == "busy" then
        return L["|cffff9933Nearby mobs are taken|r (tapped / dead)"]
    elseif u and UnitExists(u) then
        return (L["|cff33ff99Target:|r %s"]):format(UnitName(u) or "?")
    elseif InCombatLockdown() then
        return L["In combat: targeting by name"]
    end
    return L["No mob nearby"] .. (distTxt and (L[" - marker: "] .. distTxt) or "")
end

local footerElapsed = 0
panel:HookScript("OnUpdate", function(_, dt)
    footerElapsed = footerElapsed + dt
    if footerElapsed < 0.5 then return end
    footerElapsed = 0
    if state.objectives and #state.objectives > 0 then panel.footer:SetText(FooterText()) end
end)

local SelectObjective -- forward

local function GetLine(i)
    local line = panel.lines[i]
    if line then return line end
    line = CreateFrame("Button", nil, panel)
    line:SetSize(PANEL_W - 24, 16)
    line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    line.text = line:CreateFontString(nil, "OVERLAY", "QuestFocusFontSmall")
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
            GameTooltip:AddLine((L["Nearest: %s %.1f, %.1f%s"]):format(ZoneName(p.map), p.x, p.y,
                dist and (" (%d yd)"):format(dist) or ""), 0.6, 0.8, 1)
        end
        local etaLine = not o.completed and NS.EtaLine and NS.EtaLine(o)
        if etaLine then GameTooltip:AddLine(etaLine, 0.8, 0.8, 0.8, true) end
        GameTooltip:AddLine(L["Left click: marker + macro for this only"], 0.5, 0.5, 0.5)
        GameTooltip:AddLine(L["Right click: macro for all remaining"], 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    line:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.lines[i] = line
    return line
end

local ICON_DONE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t "
local ICON_TODO = "|TInterface\\COMMON\\Indicator-Gray:12:12|t "
local ICON_SEL = "|TInterface\\COMMON\\Indicator-Green:12:12|t "
local ICON_TI = "|TInterface\\GossipFrame\\ActiveQuestIcon:12:12|t "

-- Statisztika dobozok + haladas csik
local function UpdateStats()
    local objs = state.objectives or {}
    local have, need, doneObj, nObj = 0, 0, 0, 0
    for _, o in ipairs(objs) do
        if not o.turnIn then
            nObj = nObj + 1
            if o.completed then doneObj = doneObj + 1 end
            local c, n = o.qo and tonumber(o.qo.Collected), o.qo and tonumber(o.qo.Needed)
            if c and n and n > 0 then
                have, need = have + math.min(c, n), need + n
            else
                have, need = have + (o.completed and 1 or 0), need + 1
            end
        end
    end
    local b = panel.statBoxes
    -- Leadas modban: tavolsag / utazasi ido / legjobb mod (gyalog, HS, repules) a leado NPC-ig
    if state.isComplete then
        b[1].label:SetText(L["DISTANCE"]); b[2].label:SetText(L["TRAVEL"]); b[3].label:SetText(L["BEST WAY"])
        local dest = state.waypoint
        if not dest and objs[1] and objs[1].turnIn then dest = FindNearest(objs[1].sources) end
        local r = dest and NS.TravelAdvice and NS.TravelAdvice(dest)
        b[1].value:SetText(r and r.dist and ("%d yd"):format(r.dist) or "-")
        local t = r and (r.bestTime or r.walk)
        if t then
            local m = math.floor(t / 60)
            b[2].value:SetText(t < 60 and ("%ds"):format(t) or ("%dm %02ds"):format(m, t % 60))
        else
            b[2].value:SetText("-")
        end
        b[3].value:SetText(NS.BestWayText and NS.BestWayText(r) or "-")
        panel.bar:SetValue(0)
        panel.sub:SetText(state.isComplete and L["Ready to turn in"] or (L["%d / %d objectives"]):format(doneObj, nObj))
        return
    end
    b[1].label:SetText(L["PROGRESS"]); b[2].label:SetText(L["TIME LEFT"]); b[3].label:SetText(L["PACE"])
    if state.isComplete then
        b[1].value:SetText("|cff33ff99" .. L["Done"] .. "|r")
        panel.bar:SetValue(1)
        panel.bar:SetStatusBarColor(0.3, 0.85, 0.3)
    else
        b[1].value:SetText(need > 0 and ("%d / %d"):format(have, need) or "-")
        panel.bar:SetValue(need > 0 and have / need or 0)
        panel.bar:SetStatusBarColor(0.95, 0.75, 0.2)
    end
    local total = not state.isComplete and NS.QuestEta and NS.QuestEta(objs)
    b[2].value:SetText(total or "-")
    b[3].value:SetText(NS.PaceText and NS.PaceText(objs) or "-")
    if state.isComplete then
        panel.sub:SetText(L["Ready to turn in"])
    else
        panel.sub:SetText((L["%d / %d objectives"]):format(doneObj, nObj))
    end
end

local statsElapsed = 0
panel:HookScript("OnUpdate", function(_, dt)
    statsElapsed = statsElapsed + dt
    if statsElapsed < 2 then return end
    statsElapsed = 0
    if state.questId then UpdateStats() end
end)

local SelectQuestRef -- lent: SelectQuest

-- "ALSO NEARBY": a kozelben levo tobbi quest mob-objective-jei (a macro ezeket is targeteli)
panel.extraHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
panel.extraHeader:SetTextColor(0.75, 0.65, 0.45)
panel.extraHeader:SetText(L["ALSO NEARBY (in the macro too)"])
panel.extraRows = {}
local function GetExtraRow(i)
    local r = panel.extraRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, panel)
    r:SetSize(PANEL_W - 24, 16)
    r.text = r:CreateFontString(nil, "OVERLAY", "QuestFocusFontSmall")
    r.text:SetAllPoints()
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    r:SetScript("OnClick", function(self)
        local e = self.extra
        if e and SelectQuestRef then SelectQuestRef(e.qid, e.title, false, true) end
    end)
    r:SetScript("OnEnter", function(self)
        local e = self.extra
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(e.title or "?", 1, 1, 1)
        GameTooltip:AddLine(e.desc, 1, 0.82, 0, true)
        GameTooltip:AddLine(table.concat(e.names, ", "), 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine((L["Nearest: %d yd"]):format(e.dist), 0.6, 0.8, 1)
        local eta = NS.EtaLine and NS.EtaLine(e.obj)
        if eta then GameTooltip:AddLine(eta, 0.8, 0.8, 0.8, true) end
        GameTooltip:AddLine(L["The QFocus macro targets these mobs too."], 0.5, 0.5, 0.5)
        GameTooltip:AddLine(L["Click: focus this quest"], 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.extraRows[i] = r
    return r
end

local function Panel_Update()
    if QuestFocusDB.hidePanel then
        panel:Hide()
        return
    end
    if not state.questId then
        -- Nincs kijelolt quest: javaslatok (QuestFocusPlanner.lua)
        for i = 1, #panel.lines do panel.lines[i]:Hide() end
        for i = 1, #panel.extraRows do panel.extraRows[i]:Hide() end
        panel.extraHeader:Hide()
        if panel.hsRow then panel.hsRow:Hide() end
        panel.icon:SetTexture("Interface\\Icons\\" .. ICON_IDLE)
        if NS.ShowSuggestions and NS.ShowSuggestions() then panel:Show() else panel:Hide() end
        return
    end
    if NS.HideSuggestions then NS.HideSuggestions() end
    panel.title:SetText(state.title or ("Quest " .. state.questId))
    panel.icon:SetTexture("Interface\\Icons\\" .. (state.isComplete and ICON_TURNIN or ICON_HUNT))
    local objs = state.objectives or {}
    local y = PanelChrome("quest", L["OBJECTIVES"])
    for i, o in ipairs(objs) do
        local line = GetLine(i)
        line.index = i
        line:SetSize(PW() - 24, RowH())
        local icon = o.completed and ICON_DONE or (o.turnIn and ICON_TI)
            or (state.objIndex == i and ICON_SEL) or ICON_TODO
        local color = o.completed and "|cff808080" or (o.turnIn and "|cffffff00")
            or (state.objIndex == i and "|cff33ff99") or "|cffffffff"
        local eta = not o.completed and NS.EtaShort and NS.EtaShort(o)
        line.text:SetText(icon .. color .. o.desc .. "|r" .. (eta and ("  |cff999999" .. eta .. "|r") or ""))
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
        line:Show()
        y = y - RowH() - 1
    end
    for i = #objs + 1, #panel.lines do panel.lines[i]:Hide() end
    -- A kozelben levo tobbi quest (ha nem egy objective-re szukitettel es nem leadas van)
    local extras = (state.objIndex == nil) and state.extra or nil
    local nExtra = 0
    if extras and #extras > 0 then
        y = y - 4
        panel.extraHeader:ClearAllPoints()
        panel.extraHeader:SetPoint("TOPLEFT", 14, y)
        panel.extraHeader:Show()
        y = y - 15
        for i, e in ipairs(extras) do
            local r = GetExtraRow(i)
            r.extra = e
            r:SetSize(PW() - 24, RowH())
            local eta = NS.EtaShort and NS.EtaShort(e.obj)
            r.text:SetText(("|TInterface\\COMMON\\Indicator-Yellow:12:12|t |cffd8c8a0%s:|r %s%s"):format(
                e.title or "?", e.desc or "?", eta and ("  |cff999999" .. eta .. "|r") or ""))
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
            r:Show()
            y = y - RowH() - 1
            nExtra = i
        end
    else
        panel.extraHeader:Hide()
    end
    for i = nExtra + 1, #panel.extraRows do panel.extraRows[i]:Hide() end
    -- Hearthstone tipp: hany kesz quest adhato le ott, ahova a HS visz
    -- (leadas modban mar 1-tol, kulonben 2-tol mutatjuk)
    local hsList, hsName, hsCd
    if NS.HearthTurnIns then
        local ok, a, b, c = pcall(NS.HearthTurnIns)
        if ok then hsList, hsName, hsCd = a, b, c end
    end
    if hsList and (#hsList >= 2 or state.isComplete) then
        local r = panel.hsRow
        if not r then
            r = CreateFrame("Button", nil, panel)
            r:SetSize(PANEL_W - 24, 16)
            r.text = r:CreateFontString(nil, "OVERLAY", "QuestFocusFontSmall")
            r.text:SetAllPoints()
            r.text:SetJustifyH("LEFT")
            r.text:SetWordWrap(false)
            r:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetText((L["Hearthstone: %s"]):format(self.hsName or "?"), 1, 1, 1)
                GameTooltip:AddLine(L["Quests you could turn in there:"], 1, 0.82, 0)
                for _, t in ipairs(self.hsList or {}) do GameTooltip:AddLine("  " .. t, 1, 1, 1) end
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            panel.hsRow = r
        end
        r.hsList, r.hsName = hsList, hsName
        r:SetSize(PW() - 24, RowH())
        local cdTxt = (hsCd and hsCd > 0) and ("  |cff999999" .. L["HS cooldown"] .. " " .. math.ceil(hsCd / 60) .. "m|r") or ""
        r.text:SetText(("|TInterface\\Icons\\INV_Misc_Rune_01:12:12|t |cff33ff99" .. L["Hearth home: %d quests to turn in at %s"] .. "|r%s")
            :format(#hsList, hsName or "?", cdTxt))
        y = y - 4
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
        r:Show()
        y = y - RowH() - 1
    elseif panel.hsRow then
        panel.hsRow:Hide()
    end
    if #objs == 0 then
        panel.footer:SetText(QuestieAvailable() and L["No objective data for this quest."] or L["Questie is not loaded."])
    else
        panel.footer:SetText(FooterText())
    end
    UpdateStats()
    PanelFinish(y)
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
        Print(L["Questie is not loaded, without it I don't know where the mobs are."])
    end
    -- Egy kattintasra tobb hook is lefuthat (gomb + C_QuestLog): csak egyszer jeloljunk
    local now = GetTime()
    if mark and state.lastMarkQuest == questId and state.lastMarkTime and now - state.lastMarkTime < 0.5 then
        mark = false
    end
    if mark then state.lastMarkQuest, state.lastMarkTime = questId, now end
    local changed = questId ~= state.questId
    if changed then state.extra = nil end -- a ticker 3 mp-en belul ujraszamolja
    state.questId = questId
    state.title = title or state.title
    state.isComplete = isComplete and true or false
    QuestFocusDB.lastQuest = questId
    if mark then QuestFocusDB.hidePanel = false end -- kattintasra a bezart panel visszajon
    Refresh(not changed)
    if mark then MarkObjective(state.objIndex) end
end

SelectQuestRef = SelectQuest

-- Kozeli tobbi quest figyelese (3 mp-enkent, harcon kivul): a macro es a panel frissul
local extraTicker = CreateFrame("Frame")
local extraElapsed, lastExtraKey = 0, nil
extraTicker:SetScript("OnUpdate", function(_, dt)
    extraElapsed = extraElapsed + dt
    if extraElapsed < 3 then return end
    extraElapsed = 0
    if not state.questId or InCombatLockdown() then return end
    local list = {}
    if not QuestFocusDB.noNearbyQuests and NS.NearbyQuestTargets then
        local ok, r = pcall(NS.NearbyQuestTargets, state.questId, tonumber(QuestFocusDB.nearbyRadius) or 200)
        if ok and r then list = r end
    end
    -- leadasnal a "messze van-e az NPC" is szamit (a macro ennek megfeleloen valt)
    local far = ""
    if state.isComplete and state.objectives and state.objectives[1] and state.objectives[1].turnIn then
        local _, d = FindNearest(state.objectives[1].sources)
        far = (not d or d > 100) and "far" or "near"
    end
    local key = tostring(state.questId) .. "|" .. far .. "|"
    for _, e in ipairs(list) do key = key .. e.qid .. ":" .. tostring(e.desc) .. ";" end
    state.extra = list
    if key ~= lastExtraKey then
        lastExtraKey = key
        UpdateMacro()
        Panel_Update()
    end
end)

local function ClearQuest()
    state.questId, state.title, state.objectives, state.objIndex = nil, nil, nil, nil
    state.extra = nil
    ClearWaypoint()
    QuestFocusDB.lastQuest = nil
    Panel_Update() -- kijeloles nelkul javaslatokat mutat
    state.macroCount = 0
    wipe(targetNames)
    local body = '/run print("QuestFocus: no quest selected")'
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
    local here = C_Map.GetBestMapForUnit("player")
    -- Fejlec: QuestFocus + haladas + hatralevo ido
    local done, total = 0, 0
    for _, o in ipairs(objs) do
        if not o.turnIn then total = total + 1; if o.completed then done = done + 1 end end
    end
    local eta = not isComplete and NS.QuestEta and NS.QuestEta(objs)
    local right = isComplete and ("|cff33ff99" .. L["ready to turn in"] .. "|r")
        or (("%d/%d"):format(done, total) .. (eta and ("  ·  " .. eta) or ""))
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine("|cff33ff99QuestFocus|r", right, 1, 1, 1, 0.8, 0.8, 0.8)

    for _, o in ipairs(objs) do
        local p, dist = FindNearest(o.sources)
        local distTxt = dist and ("%d yd"):format(dist) or ""
        if o.completed then
            tooltip:AddLine("|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t " .. o.desc, 0.5, 0.5, 0.5)
        else
            local icon = o.turnIn and "|TInterface\\GossipFrame\\ActiveQuestIcon:12:12|t "
                or "|TInterface\\COMMON\\Indicator-Yellow:12:12|t "
            tooltip:AddDoubleLine(icon .. o.desc, distTxt, 1, 0.82, 0, 0.6, 0.8, 1)
            -- Forrasok (behuzva, kisebb hangsulyal, ismetles nelkul)
            local seen = {}
            if o.itemId then
                for _, l in ipairs(ItemSourceLines(o, 3)) do
                    local t = l[1]:gsub("%s*%(on the ground / in an object%)", "")
                    if not seen[t] then
                        seen[t] = true
                        tooltip:AddLine("     " .. t, l[2] * 0.85, l[3] * 0.85, l[4] * 0.85)
                    end
                end
            elseif not o.turnIn then
                local names = {}
                for _, s in ipairs(o.sources) do
                    if s.name and not seen[s.name] then
                        seen[s.name] = true
                        if #names >= 3 then names[#names + 1] = "..." break end
                        names[#names + 1] = s.name
                    end
                end
                if #names > 0 then tooltip:AddLine("     " .. table.concat(names, ", "), 0.85, 0.85, 0.85) end
            end
            -- Hol (a zona nevet csak akkor irjuk, ha nem ott vagy) + hatralevo ido
            local info = {}
            if p then
                info[#info + 1] = (p.map ~= here and (ZoneName(p.map) .. " ") or "") .. ("%.0f, %.0f"):format(p.x, p.y)
            end
            local short = NS.EtaShort and NS.EtaShort(o)
            if short then info[#info + 1] = short .. " " .. L["left"] end
            if #info > 0 then tooltip:AddLine("     " .. table.concat(info, "   ·   "), 0.55, 0.7, 0.9) end
        end
    end
    tooltip:AddLine(L["Click: marker + QFocus macro"], 0.45, 0.45, 0.45)
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
            Print(L["|cffffff00%s|r left the quest log, marker removed."], old or "Quest")
            return
        end
        local becameComplete = done and not state.isComplete
        local prevDone = {}
        for i, o in ipairs(state.objectives or {}) do prevDone[i] = o.completed end
        state.title, state.isComplete = title, done and true or false
        Refresh(not becameComplete)
        if becameComplete then
            Print(L["|cffffff00%s|r is complete, marker moved to the turn-in NPC."], title)
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
                Print(L["Objective complete, marker moved to the next target."])
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
            UIErrorsFrame:AddMessage(L["QuestFocus: this mob is already tapped by someone else"], 1, 0.3, 0.3)
        end
        -- Target valtas: a ping sor ki/be (uj celpontra pingel, a mostanira nem)
        -- Kesleltetve! A /target sor meg a macro futasa KOZBEN valtja ki ezt az esemenyt;
        -- ha azonnal atirnank a macrot, a hatralevo sorai (a ping) mar nem futnanak le.
        if state.questId and not state.targetRebuildPending then
            state.targetRebuildPending = true
            C_Timer.After(0.5, function()
                state.targetRebuildPending = nil
                if state.questId and not InCombatLockdown() then UpdateMacro() end
            end)
        end
        return
    end
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        QuestFocusDB = QuestFocusDB or {}
    elseif event == "PLAYER_LOGIN" then
        -- a regi (scale alapu) meretezes helyett szelesseg + betumeret
        if QuestFocusDB.panelScale then QuestFocusDB.panelScale = nil; panel:SetScale(1) end
        ApplyFontSize()
        ApplyPanelWidth()
        RestorePanelPos()
        -- a WoW layout cache a login utan meg atrakhatja: meg egyszer a sajat mentesunket
        C_Timer.After(1, RestorePanelPos)
        InstallHooks()
        if not _G.QuestieLoader then
            Print(L["|cffff5555Questie not found.|r Install it, QuestFocus does not work without it."])
        end
        -- Utolso kijelolt quest visszaallitasa, ha a Questie mar betoltott
        C_Timer.After(8, function()
            local id = QuestFocusDB.lastQuest
            if id and not state.questId then
                local title, done = FindQuestInLog(id)
                if title then SelectQuest(id, title, done, false) end
            end
            if not state.questId then Panel_Update() end
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

local function MaybeAskZone()
    if QuestFocusDB.noZonePrompt or QuestFocusDB.zoneFocus then return end
    local zone = GetRealZoneText and GetRealZoneText() or GetZoneText()
    if not zone or zone == "" or askedZone[zone] then return end
    local here, other = 0, 0
    for _, e in pairs(LogQuests()) do
        if e.header == zone then here = here + 1 else other = other + 1 end
    end
    -- csak ha van itt quest, es van mas is, amit el lehetne rejteni
    if here == 0 or other == 0 then return end
    if InCombatLockdown() then
        state.askZoneAfterCombat = true
        return
    end
    askedZone[zone] = true
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
        local zf = QuestFocusDB and QuestFocusDB.zoneFocus
        local zone = GetRealZoneText and GetRealZoneText() or GetZoneText()
        if zf and zone and zone ~= "" and zf.zone ~= zone then
            ZoneFocusOn()
        elseif not zf then
            MaybeAskZone()
        end
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
    out[#out + 1] = (L["Quest: %s (%s)"]):format(state.title or "-", tostring(state.questId or "-"))
    out[#out + 1] = (L["Nameplate mode: %s"]):format(NameplatesUsable() and L["on"] or L["off (V key)"])
    out[#out + 1] = (L["Wanted mobs: %s"]):format(#names > 0 and table.concat(names, ", ") or "-")
    out[#out + 1] = (L["Picked: %s"]):format(u == "busy" and L["all taken"] or
        (u and ((UnitName(u) or "?") .. " (" .. u .. ")") or L["none (fallback by name)"]))
    out[#out + 1] = (L["In combat: %s"]):format(InCombatLockdown() and L["yes (the macro can't update now)"] or L["no"])
    out[#out + 1] = (L["Zone focus: %s"]):format(QuestFocusDB.zoneFocus and (QuestFocusDB.zoneFocus.zone or "?") or L["off"])
    out[#out + 1] = L["Visible quest mob nameplates:"]
    local any
    for i = 1, 40 do
        local nu = "nameplate" .. i
        if UnitExists(nu) and targetNames[UnitName(nu) or ""] then
            any = true
            out[#out + 1] = (L["  %s: %s  dead=%s tapped=%s attackable=%s inCombat=%s"]):format(nu, UnitName(nu),
                tostring(UnitIsDead(nu)), tostring(TapDenied(nu)), tostring(UnitCanAttack("player", nu)),
                tostring(UnitAffectingCombat(nu)))
        end
    end
    if not any then out[#out + 1] = L["  (none)"] end
    out[#out + 1] = "Macro:"
    for line in (state.lastBody or "-"):gmatch("[^\n]+") do out[#out + 1] = "  " .. line end
    local h = QuestFocusDB.hearth
    out[#out + 1] = (L["Hearthstone: %s | position learned: %s"]):format(
        GetBindLocation and GetBindLocation() or "?",
        (h and GetBindLocation and h.name == GetBindLocation()) and L["yes"]
            or L["no (bind at an innkeeper or use your Hearthstone once)"])
    if NS.BuffDebugLines then
        out[#out + 1] = " "
        local ok, lines = pcall(NS.BuffDebugLines)
        if ok and lines then for _, l in ipairs(lines) do out[#out + 1] = l end end
    end
    local errs = NS.errors or {}
    out[#out + 1] = " "
    out[#out + 1] = (L["|cffff5555Lua errors: %d|r"]):format(#errs)
    for _, e in ipairs(errs) do
        out[#out + 1] = ("  [%s] x%d  %s"):format(e.time, e.count, e.msg)
        for line in (e.stack or ""):gmatch("[^\n]+") do out[#out + 1] = "      |cff808080" .. line .. "|r" end
    end
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

local function OptCheck(label, tip, get, set, parent)
    local cb = CreateFrame("CheckButton", nil, parent or opt.pageMain, "UICheckButtonTemplate")
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
local optSub = OptLabel(opt, L["QFocus macro and marker settings. Everything is optional."], "GameFontHighlightSmall")
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
for i, def in ipairs({ { L["Settings"], pageMain }, { "Debug", pageDebug } }) do
    local t = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate")
    t:SetSize(110, 22)
    t:SetText(def[1])
    t.page = def[2]
    t:SetPoint("TOPLEFT", optSub, "BOTTOMLEFT", (i - 1) * 114, -10)
    t:SetScript("OnClick", function() SelectTab(i) end)
    tabs[i] = t
end
opt.pageMain = pageMain

-- Uj ful a tobbi fajlnak (QuestFocusPlanner.lua, QuestFocusBuffs.lua)
NS.AddOptionsTab = function(label)
    local page = CreateFrame("Frame", nil, opt)
    page:SetAllPoints(pageMain)
    page:Hide()
    local i = #tabs + 1
    local t = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate")
    t:SetSize(110, 22)
    t:SetText(label)
    t.page = page
    t:SetPoint("TOPLEFT", optSub, "BOTTOMLEFT", (i - 1) * 114, -10)
    t:SetScript("OnClick", function() SelectTab(i) end)
    tabs[i] = t
    return page
end

-- Spell a tapeleshez
local cbSpell = OptCheck(L["Spell in the macro (tagging)"],
    L["When enabled, the QFocus macro also casts the chosen spell on the mob after targeting it. "]
    .. L["It does not cast at turn-in (friendly NPC)."],
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
local spellHint = OptLabel(pageMain,L["Drag a spell here from your spellbook (P), or type its name + Enter. Right click: clear."],
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
    Print(name and (L["Tag spell: |cffffff00%s|r"]):format(name) or L["Tag spell cleared."])
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
    L["Also starts auto attack after targeting (melee / wand / bow)."],
    function() return QuestFocusDB.startAttack end,
    function(v) QuestFocusDB.startAttack = v; RebuildMacro() end)
cbAttack:SetPoint("TOPLEFT", spellSlot, "BOTTOMLEFT", -26, -28)

local cbPing = OptCheck(L["Ping the target"],
    L["The macro pings the target at the end (ping system); party members see it too."],
    function() return not QuestFocusDB.noPing end,
    function(v) QuestFocusDB.noPing = not v; RebuildMacro() end)
cbPing:SetPoint("TOPLEFT", cbAttack, "BOTTOMLEFT", 0, -6)

local cbArrow = OptCheck(L["Own arrow"],
    L["Arrow pointing to the marker (hidden when TomTom is installed, TomTom's arrow is used instead)."],
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
    GameTooltip:AddLine(L["Zone focus: "] .. (zf and (zf.zone or "?") or L["off"]), 1, 0.82, 0)
    GameTooltip:AddLine(L["Left click: settings"], 0.6, 0.6, 0.6)
    GameTooltip:AddLine(L["Right click: zone focus on/off"], 0.6, 0.6, 0.6)
    GameTooltip:AddLine(L["Drag: move"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
mmBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Zona fokusz gomb a beallitasokban
local zoneBtn = CreateFrame("Button", nil, pageMain, "UIPanelButtonTemplate")
zoneBtn:SetSize(220, 24)
zoneBtn:SetPoint("TOPLEFT", cbArrow, "BOTTOMLEFT", 4, -14)
local zoneHint = OptLabel(pageMain, L["Only quests of the current zone stay in the Questie tracker (plus the selected QFocus quest). "]
    .. L["Follows you when you change zones; turning it off restores everything. Minimap: right click."], "GameFontDisableSmall")
zoneHint:SetPoint("TOPLEFT", zoneBtn, "BOTTOMLEFT", 0, -4)
zoneHint:SetWidth(420)
-- Allapot a gomb mellett, hogy egyertelmu legyen: be van-e kapcsolva, es melyik zonara
local zoneState = OptLabel(pageMain, "", "GameFontHighlightSmall")
zoneState:SetPoint("LEFT", zoneBtn, "RIGHT", 10, 0)
local function RefreshZoneBtn()
    local zf = QuestFocusDB.zoneFocus
    local here = GetRealZoneText and GetRealZoneText() or GetZoneText() or "?"
    if zf then
        zoneBtn:SetText(L["Turn off zone focus"])
        zoneState:SetText((L["Zone focus is |cff33ff99ON|r: %s"]):format(zf.zone or "?"))
    else
        zoneBtn:SetText((L["Focus on %s"]):format(here))
        zoneState:SetText(L["Zone focus is |cff808080off|r (all quests in the tracker)"])
    end
end
zoneBtn:SetScript("OnClick", function() ToggleZoneFocus(); RefreshZoneBtn() end)

local cbZoneAsk = OptCheck(L["Ask when entering a new zone"],
    L["When you enter a zone where you have quests, a popup asks whether to focus on that zone."],
    function() return not QuestFocusDB.noZonePrompt end,
    function(v) QuestFocusDB.noZonePrompt = not v end)
cbZoneAsk:SetPoint("TOPLEFT", zoneHint, "BOTTOMLEFT", -6, -8)

local cbMinimap = OptCheck(L["Minimap button"],
    L["Left click: settings, right click: zone focus. Drag to move."],
    function() return not QuestFocusDB.hideMinimap end,
    function(v) QuestFocusDB.hideMinimap = not v; UpdateMinimapButton() end)
cbMinimap:SetPoint("TOPLEFT", cbZoneAsk, "BOTTOMLEFT", 0, -6)

local optNote = OptLabel(pageMain, L["The macro can't be changed in combat; changes apply after combat."],
    "GameFontDisableSmall")
optNote:SetPoint("TOPLEFT", cbMinimap, "BOTTOMLEFT", 2, -16)

-- Debug ful
local dbgScroll = CreateFrame("ScrollFrame", nil, pageDebug, "UIPanelScrollFrameTemplate")
dbgScroll:SetPoint("TOPLEFT", 0, -60)
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
dbgRefresh:SetText(L["Refresh"])
dbgRefresh:SetScript("OnClick", RefreshDebug)
local dbgChat = CreateFrame("Button", nil, pageDebug, "UIPanelButtonTemplate")
dbgChat:SetSize(120, 22)
dbgChat:SetPoint("LEFT", dbgRefresh, "RIGHT", 6, 0)
dbgChat:SetText(L["Print to chat"])
dbgChat:SetScript("OnClick", function() for _, l in ipairs(DebugLines()) do Print(l) end end)
-- Masolas: addon nem irhat a vagolapra, ezert egy kijelolheto szovegmezobe tesszuk
-- (mar kijelolve), amibol Ctrl+C-vel ki lehet masolni
local copyFrame = CreateFrame("Frame", "QuestFocusCopyFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
copyFrame:SetSize(560, 380)
copyFrame:SetPoint("CENTER")
copyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
copyFrame:EnableMouse(true)
copyFrame:SetMovable(true)
copyFrame:RegisterForDrag("LeftButton")
copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
copyFrame:Hide()
if copyFrame.SetBackdrop then
    copyFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 20,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    copyFrame:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
    copyFrame:SetBackdropBorderColor(0.95, 0.78, 0.40, 1)
end
local copyTitle = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
copyTitle:SetPoint("TOPLEFT", 14, -12)
copyTitle:SetText(L["QuestFocus debug - press Ctrl+C to copy, then Esc"])
local copyClose = CreateFrame("Button", nil, copyFrame, "UIPanelCloseButton")
copyClose:SetPoint("TOPRIGHT", -4, -4)
local copyScroll = CreateFrame("ScrollFrame", "QuestFocusCopyScroll", copyFrame, "UIPanelScrollFrameTemplate")
copyScroll:SetPoint("TOPLEFT", 14, -36)
copyScroll:SetPoint("BOTTOMRIGHT", -32, 14)
local copyBox = CreateFrame("EditBox", nil, copyScroll)
copyBox:SetMultiLine(true)
copyBox:SetFontObject(ChatFontNormal)
copyBox:SetWidth(500)
copyBox:SetAutoFocus(false)
copyBox:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
-- csak olvashato: ha atirnad, visszaallitjuk
copyBox:SetScript("OnTextChanged", function(self, user)
    if user and self.text then self:SetText(self.text); self:HighlightText() end
end)
copyScroll:SetScrollChild(copyBox)

local function PlainText(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end

local function ShowCopy()
    local lines = {}
    for _, l in ipairs(DebugLines()) do lines[#lines + 1] = PlainText(l) end
    local text = table.concat(lines, "\n")
    copyBox.text = text
    copyBox:SetText(text)
    copyFrame:Show()
    copyBox:SetFocus()
    copyBox:HighlightText()
    copyScroll:SetVerticalScroll(0)
end
NS.ShowCopy = ShowCopy

local dbgCopy = CreateFrame("Button", nil, pageDebug, "UIPanelButtonTemplate")
dbgCopy:SetSize(80, 22)
dbgCopy:SetPoint("LEFT", dbgChat, "RIGHT", 6, 0)
dbgCopy:SetText(L["Copy"])
dbgCopy:SetScript("OnClick", ShowCopy)

local dbgLive = OptLabel(pageDebug, L["Live: refreshes every 0.5 s while open."], "GameFontDisableSmall")
dbgLive:SetPoint("LEFT", dbgCopy, "RIGHT", 10, 0)

local cbErrors = OptCheck(L["Lua error popup for QuestFocus errors"],
    L["Off: QuestFocus errors don't open the error window, they are only listed here (and one line in chat). "]
    .. L["On: the normal Lua error window shows them too. Other addons are not affected."],
    function() return QuestFocusDB.showErrors end,
    function(v) QuestFocusDB.showErrors = v end, pageDebug)
cbErrors:SetPoint("TOPLEFT", dbgRefresh, "BOTTOMLEFT", -2, -4)
local dbgClear = CreateFrame("Button", nil, pageDebug, "UIPanelButtonTemplate")
dbgClear:SetSize(110, 22)
dbgClear:SetPoint("LEFT", cbErrors.label, "RIGHT", 16, 0)
dbgClear:SetText(L["Clear errors"])
dbgClear:SetScript("OnClick", function() wipe(NS.errors); RefreshDebug() end)
local dbgElapsed = 0
pageDebug:SetScript("OnShow", function() cbErrors.refresh(); RefreshDebug() end)
pageDebug:SetScript("OnUpdate", function(_, dt)
    dbgElapsed = dbgElapsed + dt
    if dbgElapsed > 0.5 then dbgElapsed = 0; RefreshDebug() end
end)

opt:SetScript("OnShow", function()
    for _, cb in ipairs({ cbSpell, cbAttack, cbPing, cbArrow, cbMinimap, cbZoneAsk }) do cb.refresh() end
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
    if InCombatLockdown() then Print(L["Open it after combat."]) return end
    if optCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(optCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(opt)
        InterfaceOptionsFrame_OpenToCategory(opt)
    end
end

---------------------------------------------------------------------------
-- Kozos nevter a QuestFocusBags.lua szamara
---------------------------------------------------------------------------
NS.Print, NS.state, NS.GetQuestieQuest = Print, state, GetQuestieQuest
NS.NumLogEntries, NS.GetLogEntry, NS.FindQuestInLog = NumLogEntries, GetLogEntry, FindQuestInLog
NS.SelectQuest, NS.OptCheck, NS.opt, NS.optNote, NS.panel = SelectQuest, OptCheck, opt, optNote, panel
NS.CollectTargets, NS.WorldPos, NS.UiMapFromArea, NS.PlayerWorldPos = CollectTargets, WorldPos, UiMapFromArea, PlayerWorldPos
NS.ZoneName, NS.SetWaypoint, NS.Panel_Update, NS.GetNPC, NS.GetObject, NS.Module = ZoneName, SetWaypoint, Panel_Update, GetNPC, GetObject, Module
NS.ClearWaypoint, NS.AddQuestTooltip, NS.QuestieAvailable = ClearWaypoint, AddQuestTooltip, QuestieAvailable

SLASH_QUESTFOCUS1 = "/qf"
SLASH_QUESTFOCUS2 = "/questfocus"
SlashCmdList.QUESTFOCUS = function(msg)
    local raw = (msg or ""):match("^%s*(.-)%s*$")
    msg = raw:lower()
    if msg == "options" or msg == "config" or msg == "opt" then
        OpenOptions()
    elseif msg == "debug" then
        for _, l in ipairs(DebugLines()) do Print(l) end
    elseif msg == "copy" then
        ShowCopy()
    elseif msg == "zone" then
        ToggleZoneFocus()
    elseif msg == "bags" then
        if NS.ToggleBagList then NS.ToggleBagList() end
    elseif msg == "city" then
        if NS.ShowCityList then NS.ShowCityList() end
    elseif msg == "buffreset" then
        if NS.ResetBuffLearn then NS.ResetBuffLearn() end
    elseif msg == "junk" then
        if NS.DiscardLeftovers then NS.DiscardLeftovers() end
    elseif msg == "minimap" then
        QuestFocusDB.hideMinimap = not QuestFocusDB.hideMinimap
        UpdateMinimapButton()
        Print(L["Minimap button: %s"], QuestFocusDB.hideMinimap and L["off"] or L["on"])
    elseif msg == "spell" or msg:match("^spell%s") then
        local name = raw:match("^%S+%s+(.+)$")
        if name and name:lower() == "off" then
            QuestFocusDB.useSpell = false
            RebuildMacro()
            Print(L["Tag spell disabled."])
        else
            SetSpell(name)
        end
    elseif msg == "" then
        QuestFocusDB.hidePanel = panel:IsShown()
        if not state.questId and QuestFocusDB.noSuggest then Print(L["Select a quest in the quest log (L)."]) end
        Panel_Update()
    elseif msg == "next" then
        local objs = state.objectives or {}
        if #objs == 0 then Print(L["No quest selected."]) return end
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
        Print(L["Own arrow: %s"], QuestFocusDB.noArrow and L["off"] or L["on"])
        if QuestFocusDB.noArrow then arrow:Hide() elseif state.waypoint and UseOwnArrow() then arrow:Show() end
    elseif msg == "ping" then
        QuestFocusDB.noPing = not QuestFocusDB.noPing
        Print(L["Ping in the QFocus macro: %s"], QuestFocusDB.noPing and L["off"] or L["on"])
        state.lastBody = nil
        if state.questId then UpdateMacro() Panel_Update() end
    elseif msg == "icon" or msg:match("^icon%s") then
        local name = msg:match("^icon%s+(%S+)")
        if name then
            local id = IconId(name)
            if id == ICON_FALLBACK then
                Print(L["Icon not found: %s (e.g. ability_hunter_snipershot)"], name)
                return
            end
            QuestFocusDB.icon = name
            Print(L["QFocus icon: |T%d:16|t %s"], id, name)
        else
            QuestFocusDB.icon = nil
            Print(L["QFocus icon: automatic (crosshair / letter at turn-in)"])
        end
        state.lastIcon = nil
        if not InCombatLockdown() then ApplyMacro(state.lastBody or BuildMacroBody(state.objectives, state.objIndex)) end
    elseif msg == "unmark" then
        ClearWaypoint()
        Print(L["Marker removed."])
    elseif msg == "clear" then
        ClearQuest()
        Print(L["Selection cleared."])
    else
        Print(L["Commands:"])
        Print(L["  /qf - toggle panel"])
        Print(L["  /qf options - settings (tag spell, auto attack, ping, arrow, debug tab)"])
        Print(L["  /qf zone - toggle zone focus (only current zone quests in the tracker)"])
        Print(L["  /qf minimap - toggle minimap button"])
        Print(L["  /qf bags - toggle quest item list next to the bags"])
        Print(L["  /qf junk - destroy unsellable leftover quest items (asks one by one)"])
        Print(L["  /qf debug - diagnostics to chat"])
        Print(L["  /qf spell <name> - tag spell in the macro; /qf spell - clear; /qf spell off - disable"])
        Print(L["  /qf next - next objective (marker + macro)"])
        Print(L["  /qf all - macro for mobs of all remaining objectives"])
        Print(L["  /qf mark - re-place the marker at the nearest spot"])
        Print(L["  /qf arrow - toggle own arrow"])
        Print(L["  /qf ping - toggle target ping in the macro"])
        Print(L["  /qf icon <iconname> - custom icon; /qf icon - automatic"])
        Print(L["  /qf unmark - remove marker"])
        Print(L["  /qf clear - clear selection + marker"])
    end
end
