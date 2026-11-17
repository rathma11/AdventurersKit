local ADDON_NAME, NS = ...
local L = NS.L
NS.C = NS.C or {}
local C = NS.C
local FindNearest, FindSpawnTarget, ICON_FALLBACK, ICON_HUNT, ICON_IDLE, ICON_TURNIN, MACRO_MAX, MACRO_NAME = C.FindNearest, C.FindSpawnTarget, C.ICON_FALLBACK, C.ICON_HUNT, C.ICON_IDLE, C.ICON_TURNIN, C.MACRO_MAX, C.MACRO_NAME
local PlayerWorldPos, Print, state, ZoneName = C.PlayerWorldPos, C.Print, C.state, C.ZoneName

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
    if pickElapsed < 0.25 then return end
    pickElapsed = 0
    -- csak ha van fokuszalt quest (kulonben nincs mit targetelni), harcban a macro ugysem irhato
    if not state.questId or InCombatLockdown() then return end
    PickNameplate()
end)

local function BuildMacroBody(objectives, onlyIndex)
    -- Escort quest: az escortalt NPC tamadoja / maga az NPC / kudarcnal a quest ado (Core\Escort.lua)
    if NS.Escort and state.escort then
        local ok, body = pcall(NS.Escort.MacroBody, objectives, onlyIndex)
        if ok and body then
            wipe(targetNames)
            return body, 1
        end
    end
    local usePing = NS.UsePing()
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
    -- A mar kijelolt elo, ellenseges celpontot megtartjuk ([noharm][dead]): a kezzel kattintott
    -- quest mob maradjon (harcban a macro nem irhato, ott ez vedi a kattintott mobot).
    -- Csak ha harcon kivul epul es a mostani target elo, ellenseges, de NEM jo quest mob
    -- (mas mob vagy tapolt), akkor valtunk el rola feltetel nelkul. Leadasnal (baratsagos
    -- NPC) mindig ujratargetelunk. Target valtaskor a macro ujraepul (Events.lua).
    local dropTarget = turnIn or (UnitExists("target") and UnitCanAttack("player", "target")
        and not UnitIsDead("target") and not GoodQuestUnit("target"))
    local CLEAR = dropTarget and "/cleartarget" or "/cleartarget [noharm][dead]"
    local DEADCLR = "/cleartarget [dead]"
    local pick = useNP and state.pick or nil
    if pick == "busy" then
        CLEAR = '/run UIErrorsFrame:AddMessage("QFocus: nearby quest mobs are taken",1,.6,.2)'
    elseif pick then
        CLEAR = (dropTarget and "/target " or "/target [noharm][dead] ") .. pick
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
        return '/run print("QFocus: no targetable mob")', 0
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

-- Makro (es panel) ikon allapotonkent: idle = nincs kijelolt quest, hunt = mobok / gyujtes,
-- turnin = leadas. QuestFocusDB.macroIcons[kind] = ikon nev (Interface\Icons\...), nil = alap.
local ICON_DEFAULTS = { idle = ICON_IDLE, hunt = ICON_HUNT, turnin = ICON_TURNIN }
local function MacroIconName(kind)
    local db = QuestFocusDB
    if not db then return ICON_DEFAULTS[kind] end
    -- regi /qf icon beallitas (egy ikon mindenre) -> mindharom allapotra
    if db.icon then
        db.macroIcons = { idle = db.icon, hunt = db.icon, turnin = db.icon }
        db.icon = nil
    end
    local t = db.macroIcons
    return (t and t[kind]) or ICON_DEFAULTS[kind]
end
local function CurrentIconKind()
    if not state.questId then return "idle" end
    local objs = state.objectives or {}
    if objs[1] and objs[1].turnIn then return "turnin" end
    return "hunt"
end
local function CurrentIcon()
    return IconId(MacroIconName(CurrentIconKind()))
end
NS.MacroIconName, NS.MacroIconDefaults, NS.CurrentIconKind = MacroIconName, ICON_DEFAULTS, CurrentIconKind

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
            { title = title, persistent = false, crazy = true, from = "Adventurer's Kit" })
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

local function MarkObjective(i, nextSpawn)
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
    local p, dist, inArea = FindSpawnTarget(sources, nextSpawn)
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
    -- spawn pont (nem leadas, nem vendor): ha odaersz es nincs ott, a kovetkezore lepunk
    if state.waypoint and not isTurnIn and not p.static then
        state.waypoint.spawn, state.waypoint.objIndex = true, i
    end
    if nextSpawn then
        Print(L["Not here right now - next spawn point: |cffffff00%s|r (%d yd)"], p.name or "?", dist or 0)
        return
    end
    Print(L["Marker: |cffffff00%s|r - %s %.1f, %.1f%s"], p.name or "?", ZoneName(p.map), p.x, p.y,
        dist and (" (%d yd)"):format(dist) or "")
end

-- Tovabblepes: ha a markerezett spawn pontnal allsz (ARRIVE_R) ARRIVE_T mp-ig, es a keresett
-- mob nincs ott (nincs ilyen nevu elo nameplate a kozelben), a pont "megnezett" lesz, es a
-- marker a kovetkezo, meg nem nezett spawn pontra lep. Objectnel (lada, novenyek) nincs
-- nameplate: ott csak az ido szamit (ha ott volt, kozben ugyis felvetted).
local ARRIVE_R, ARRIVE_T = 25, 4
local arriveAt
local function TargetVisible(name)
    if not (name and C_NamePlate and C_NamePlate.GetNamePlates) then return false end
    for _, np in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local u = np.namePlateUnitToken or (np.UnitFrame and np.UnitFrame.unit)
        if u then
            local ok, n = pcall(UnitName, u)
            if ok and n == name and not UnitIsDead(u) then return true end
        end
    end
    return false
end
local hopper = CreateFrame("Frame")
local hopElapsed = 0
hopper:SetScript("OnUpdate", function(_, dt)
    hopElapsed = hopElapsed + dt
    if hopElapsed < 1 then return end
    hopElapsed = 0
    local w = state.waypoint
    if not (w and w.spawn and w.wx) or InCombatLockdown() or not state.questId then arriveAt = nil return end
    local pc, px, py = PlayerWorldPos()
    if not pc or pc ~= w.wc or (px - w.wx) ^ 2 + (py - w.wy) ^ 2 > ARRIVE_R * ARRIVE_R then arriveAt = nil return end
    if TargetVisible(w.title) then arriveAt = nil return end -- itt van: nem lepunk tovabb
    arriveAt = arriveAt or GetTime()
    if GetTime() - arriveAt < ARRIVE_T then return end
    arriveAt = nil
    if NS.MarkSpawnVisited then NS.MarkSpawnVisited(w) end
    MarkObjective(w.objIndex, true)
end)

-- A quest log-ban (es a terkep melletti quest panelen, ami ezt koveti) a quest kijelolese:
-- a fejlecet, ami alatt van, kinyitjuk (a tobbi osszecsukott fejlec ugy marad).
local function FocusInQuestLog(qid)
    if not qid or not GetNumQuestLogEntries or not GetQuestLogTitle then return end
    local function QidAt(i) return select(8, GetQuestLogTitle(i)) end
    local function Find()
        for i = 1, (GetNumQuestLogEntries()) do
            if QidAt(i) == qid then return i end
        end
    end
    local idx = Find()
    if not idx and ExpandQuestHeader then
        -- osszecsukott fejlecek egyenkent: ha nem ott van, visszacsukjuk
        local i = 1
        while i <= (GetNumQuestLogEntries()) do
            local _, _, _, isHeader, isCollapsed = GetQuestLogTitle(i)
            if isHeader and isCollapsed then
                ExpandQuestHeader(i)
                idx = Find()
                if idx then break end
                if CollapseQuestHeader then CollapseQuestHeader(i) end
            end
            i = i + 1
        end
    end
    if not idx then return end
    if SelectQuestLogEntry then pcall(SelectQuestLogEntry, idx) end
    if C_QuestLog and C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, qid) end
    return idx
end
NS.FocusInQuestLog = FocusInQuestLog

-- Terkep gomb (panel cim / objective sor): a cel helye a vilagterkepen. A markert akkor is
-- lerakja, ha a teruleten vagy (ott a "nem kell marker" itt nem szamit), es a terkepet a
-- cel zonajan nyitja meg. i = objective index, nil = a hatralevo objective-ek.
local function ShowObjectiveOnMap(i)
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
        for _, s in ipairs(o.sources or {}) do sources[#sources + 1] = s end
    end
    local p = (#sources > 0) and FindSpawnTarget(sources) or nil
    if not p then
        NS.Loud(Print, L["No coordinates found (it may be inside an instance)."])
        return
    end
    SetWaypoint(p, p.name or state.title)
    local wm = WorldMapFrame
    if not wm then return end
    -- ha a kliensnek van terkep melletti quest panelje: azon a fokuszalt quest reszletei
    -- nyiljanak meg (kulonben csak a sima terkep)
    FocusInQuestLog(state.questId)
    local qd = _G.QuestMapFrame_OpenToQuestDetails
    if qd and state.questId then
        pcall(qd, state.questId)
    end
    if not wm:IsShown() then
        if ToggleWorldMap then ToggleWorldMap() else ShowUIPanel(wm) end
    end
    -- a quest reszletei sajat zonat valaszthatnak (itt nincs quest POI): a celunk zonaja
    if wm.SetMapID then pcall(wm.SetMapID, wm, p.map) end
end
NS.ShowObjectiveOnMap = ShowObjectiveOnMap


-- belso exportok a tobbi core fajlnak
NS.C.ApplyMacro, NS.C.BuildMacroBody, NS.C.ClearWaypoint, NS.C.CurrentIcon, NS.C.IconId, NS.C.MarkObjective, NS.C.NameplatesUsable, NS.C.PickNameplate = ApplyMacro, BuildMacroBody, ClearWaypoint, CurrentIcon, IconId, MarkObjective, NameplatesUsable, PickNameplate
NS.C.SetWaypoint, NS.C.TapDenied, NS.C.UpdateMacro, NS.C.UseOwnArrow, NS.C.arrow, NS.C.targetNames = SetWaypoint, TapDenied, UpdateMacro, UseOwnArrow, arrow, targetNames
