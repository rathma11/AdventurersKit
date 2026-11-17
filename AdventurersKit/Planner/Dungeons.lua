-- Dungeonok a szintedhez: a panel fejleceben a koponya gomb (es /qf dungeon).
--  - Ha fent van a ForeverDungeonJournal: az o adatai (Forever sajat dungeonjai is), es
--    kattintasra az o ablaka nyilik az adott dungeon / quest quest oldalan.
--  - Ha nincs: hasonlo lista a Questie adataibol (classic dungeonok), kattintasra marker a
--    quest adora.
local ADDON_NAME, NS = ...
local L = NS.L

local DJ_W, DJ_ROW_H, DJ_VISIBLE = 460, 18, 18

-- Journal (opcionalis): a namespace-e globalis
local function FDJ()
    local f = _G.ForeverDungeonJournal_NS
    return type(f) == "table" and type(f.DB) == "table" and f or nil
end
NS.HasDungeonJournal = function() return FDJ() ~= nil end

-- Lanc ikon: a Journal sajatja, ha fent van (kulonben csak a lila 2/5 szoveg)
NS.ChainMarkup = function()
    -- utana egy szokoz: ne erjen ossze a 2/5 szoveggel
    if FDJ() then return "|TInterface\\AddOns\\ForeverDungeonJournal\\Media\\QuestChain:12:12|t " end
    return ""
end

-- quest ID -> dungeon nev a Journal adataibol (egyszer epitjuk); NS.QuestDungeon hasznalja
local djQuestMap
NS.JournalDungeonOfQuest = function(qid)
    local f = FDJ()
    if not f or not qid then return end
    if not djQuestMap then
        djQuestMap = {}
        for name, d in pairs(f.DB) do
            for _, q in ipairs(type(d.quests) == "table" and d.quests or {}) do
                if q.id then djQuestMap[q.id] = name end
            end
        end
    end
    return djQuestMap[qid]
end

-- Questie nelkuli (Journal nelkuli) lista: classic dungeonok szintsavval
local CLASSIC = {
    { "Ragefire Chasm", 13, 18 }, { "Wailing Caverns", 17, 24 }, { "The Deadmines", 17, 26 },
    { "Shadowfang Keep", 22, 30 }, { "Blackfathom Deeps", 24, 32 }, { "The Stockade", 24, 32 },
    { "Gnomeregan", 29, 38 }, { "Razorfen Kraul", 29, 38 }, { "Scarlet Monastery", 34, 45 },
    { "Razorfen Downs", 37, 46 }, { "Uldaman", 41, 51 }, { "Zul'Farrak", 44, 54 }, { "Maraudon", 46, 55 },
    { "Sunken Temple", 50, 56 }, { "Blackrock Depths", 52, 60 }, { "Blackrock Spire", 55, 60 },
    { "Dire Maul", 55, 60 }, { "Scholomance", 58, 60 }, { "Stratholme", 58, 60 },
}

local function InLog(qid)
    local QP = NS.Module("QuestiePlayer")
    if QP and type(QP.currentQuestlog) == "table" and QP.currentQuestlog[qid] then return true end
    return C_QuestLog and C_QuestLog.GetLogIndexForQuestID and (C_QuestLog.GetLogIndexForQuestID(qid) or 0) > 0 or false
end

-- Lathato szintsav: ami most jo neked (a felso hatar meg nem volt alattad), plusz par szinttel elore
local function InRange(lo, hi, level)
    return hi >= level - 1 and lo <= level + 5
end

-- { name, lo, hi, quests = { {qid, name, level, requires, note, inLog} } }
-- only: csak ez a dungeon, szintsavtol fuggetlenul (dungeon prep, Planner\Prep.lua)
local function CollectJournal(f, level, only)
    local fac = UnitFactionGroup and UnitFactionGroup("player")
    local out = {}
    for name, d in pairs(only and { [only] = f.DB[only] } or f.DB) do
        local lo, hi = tostring(d.level or ""):match("(%d+)%D+(%d+)")
        lo, hi = tonumber(lo), tonumber(hi)
        local hidden = false
        if f.FactionHiddenFor then
            local ok, h = pcall(f.FactionHiddenFor, name, fac)
            hidden = ok and h and true or false
        end
        if lo and hi and not hidden and (only or InRange(lo, hi, level)) then
            local e = { name = name, lo = lo, hi = hi, quests = {} }
            for _, q in ipairs(type(d.quests) == "table" and d.quests or {}) do
                local qf = q.faction
                if q.id and (not qf or qf == "Both" or qf == fac) and not NS.QuestIsDone(q.id) then
                    e.quests[#e.quests + 1] = { qid = q.id, name = q.name, level = q.level, requires = q.requires,
                        note = q.pickup, inLog = InLog(q.id) }
                end
            end
            out[#out + 1] = e
        end
    end
    return out
end

local function CollectQuestie(level, only)
    local byName = {}
    local out = {}
    for _, c in ipairs(CLASSIC) do
        if (only and c[1] == only) or (not only and InRange(c[2], c[3], level)) then
            local e = { name = c[1], lo = c[2], hi = c[3], quests = {} }
            byName[c[1]] = e
            out[#out + 1] = e
        end
    end
    -- felveheto questek (Questie AvailableQuests) + ami mar a logodban van
    local AQ = NS.Module("AvailableQuests")
    local QP = NS.Module("QuestiePlayer")
    local ids = {}
    for qid in pairs(AQ and type(AQ.__availableQuests) == "table" and AQ.__availableQuests or {}) do ids[qid] = false end
    for qid in pairs(QP and type(QP.currentQuestlog) == "table" and QP.currentQuestlog or {}) do ids[qid] = true end
    for qid, inLog in pairs(ids) do
        local q = NS.GetQuestieQuest(qid)
        local dname = q and NS.QuestDungeon(q, qid)
        local e = dname and byName[dname]
        if e and (inLog or not NS.QuestIsDone(qid)) then
            local giver
            if type(q.Starts) == "table" and type(q.Starts.NPC) == "table" and q.Starts.NPC[1] then
                local npc = NS.GetNPC(q.Starts.NPC[1])
                giver = npc and npc.name
            end
            e.quests[#e.quests + 1] = { qid = qid, name = q.name, level = q.level, requires = q.requiredLevel,
                note = giver, inLog = inLog, quest = q }
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Ablak (a varos lista mintajara)
---------------------------------------------------------------------------
local dj = CreateFrame("Frame", "QuestFocusDungeonList", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
dj:SetSize(DJ_W, 80)
dj:SetPoint("TOP", UIParent, "TOP", 0, -160)
dj:SetFrameStrata("HIGH")
dj:EnableMouse(true)
dj:SetMovable(true)
dj:SetClampedToScreen(true)
dj:RegisterForDrag("LeftButton")
dj:SetScript("OnDragStart", dj.StartMoving)
dj:SetScript("OnDragStop", dj.StopMovingOrSizing)
dj:Hide()
tinsert(UISpecialFrames, "QuestFocusDungeonList") -- Esc bezarja
if dj.SetBackdrop then
    dj:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 20,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    dj:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
    dj:SetBackdropBorderColor(0.95, 0.45, 0.30, 1)
end
dj.icon = dj:CreateTexture(nil, "ARTWORK")
dj.icon:SetSize(20, 20)
dj.icon:SetPoint("TOPLEFT", 12, -11)
dj.icon:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
dj.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
dj.title = dj:CreateFontString(nil, "OVERLAY", "GameFontNormal")
dj.title:SetPoint("LEFT", dj.icon, "RIGHT", 6, 0)
dj.title:SetTextColor(1, 0.6, 0.45)
local djClose = CreateFrame("Button", nil, dj, "UIPanelCloseButton")
djClose:SetSize(24, 24)
djClose:SetPoint("TOPRIGHT", -4, -4)
dj.foot = dj:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
dj.foot:SetJustifyH("LEFT")
dj.foot:SetWidth(DJ_W - 28)

local scroll = CreateFrame("ScrollFrame", "QuestFocusDungeonScroll", dj, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 12, -38)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(DJ_W - 48, 10)
scroll:SetScrollChild(content)
scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = self:GetVerticalScrollRange() or 0
    local v = math.max(0, math.min(max, self:GetVerticalScroll() - delta * DJ_ROW_H * 3))
    if self.ScrollBar and self.ScrollBar:IsShown() then self.ScrollBar:SetValue(v) else self:SetVerticalScroll(v) end
end)

local function OpenInJournal(dungeon, qid)
    local f = FDJ()
    if not f then return false end
    local jf = _G.ForeverDungeonJournalFrame
    if not (jf and jf:IsShown()) and _G.ForeverDungeonJournal_Toggle then _G.ForeverDungeonJournal_Toggle() end
    if f.OpenQuestPage then
        local ok = pcall(f.OpenQuestPage, dungeon, qid)
        return ok
    end
    return false
end

local function MarkGiver(d)
    local q = d.quest
    if not (q and type(q.Starts) == "table") then return end
    local npcId = type(q.Starts.NPC) == "table" and q.Starts.NPC[1]
    local npc = npcId and NS.GetNPC(npcId)
    if not (npc and type(npc.spawns) == "table") then
        NS.Loud(NS.Print, L["No known location for the quest giver of %s."], d.name or "?")
        return
    end
    -- a jatekoshoz legkozelebbi spawn ugyanazon a kontinensen, kulonben az elso
    local pc, px, py = NS.PlayerWorldPos()
    local best, bestD, first
    for areaId, list in pairs(npc.spawns) do
        local uiMap = NS.UiMapFromArea(areaId)
        for _, c in ipairs(uiMap and type(list) == "table" and list or {}) do
            if type(c[1]) == "number" and c[1] >= 0 then
                local p = { map = uiMap, x = c[1], y = c[2], name = npc.name }
                first = first or p
                local wc, wx, wy = NS.WorldPos(uiMap, c[1] / 100, c[2] / 100)
                if pc and wc == pc and wx then
                    local dd = (wx - px) ^ 2 + (wy - py) ^ 2
                    if not bestD or dd < bestD then best, bestD = p, dd end
                end
            end
        end
    end
    local p = best or first
    if not p then return end
    NS.SetWaypoint(p, npc.name)
    NS.Loud(NS.Print, L["Marker: quest giver |cffffff00%s|r for %s"], npc.name or "?", d.name or "?")
end

local rows = {}
local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, content)
    r:SetSize(DJ_W - 48, DJ_ROW_H - 1)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 2, 0)
    r.text:SetPoint("RIGHT", -150, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.right:SetPoint("RIGHT", -2, 0)
    r.right:SetWidth(146)
    r.right:SetJustifyH("RIGHT")
    r.right:SetWordWrap(false)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    -- dungeon (fejlec) sor: "Prep" gomb a dungeon prep modhoz (Planner\Prep.lua)
    r.prep = CreateFrame("Button", nil, r)
    r.prep:SetSize(34, DJ_ROW_H - 3)
    r.prep:SetPoint("RIGHT", r, "RIGHT", -150, 0)
    r.prep.text = r.prep:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.prep.text:SetAllPoints()
    r.prep.text:SetText(L["Prep"])
    r.prep.text:SetTextColor(0.4, 1, 0.4)
    local phl = r.prep:CreateTexture(nil, "HIGHLIGHT")
    phl:SetAllPoints()
    phl:SetColorTexture(0.4, 1, 0.4, 0.15)
    r.prep:SetScript("OnClick", function(self)
        local row = self:GetParent()
        if row.dungeon and NS.StartPrep then NS.StartPrep(row.dungeon) end
        dj:Hide()
    end)
    r.prep:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Prep this dungeon"], 0.4, 1, 0.4)
        GameTooltip:AddLine(L["The quest panel lists this dungeon's quests you can still pick up (nearest first, with the marker on the quest giver), then the entrance. Same as /qf dungeon <name>, or a click on the row."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    r.prep:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.prep:Hide()
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, button)
        local d = self.data
        if not d then return end
        -- kattintas (dungeon vagy quest sor): dungeon prep mod erre a dungeonra; Shift+klikk: a
        -- regi mod (Dungeon Journal oldal, Journal nelkul marker a quest adora)
        if not IsShiftKeyDown() then
            if self.dungeon and NS.StartPrep then NS.StartPrep(self.dungeon) end
            dj:Hide()
            return
        end
        if FDJ() then
            OpenInJournal(self.dungeon, d.qid)
        elseif d.qid then
            MarkGiver(d)
        end
    end)
    r:SetScript("OnEnter", function(self)
        local d = self.data
        if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if d.qid then
            GameTooltip:SetText(("[%s] %s"):format(tostring(d.level or "?"), d.name or "?"), 1, 1, 1)
            GameTooltip:AddLine(("|cffff7040" .. L["Dungeon"] .. ": %s|r"):format(self.dungeon or "?"))
            if d.requires then GameTooltip:AddLine((L["Requires level %d"]):format(d.requires), 0.8, 0.8, 0.8) end
            if d.note then GameTooltip:AddLine((L["Quest giver: %s"]):format(d.note), 0.8, 0.8, 0.8, true) end
            if d.inLog then GameTooltip:AddLine(L["Already in your quest log"], 0.4, 1, 0.4) end
        else
            GameTooltip:SetText(self.dungeon or "?", 1, 0.6, 0.45)
            GameTooltip:AddLine((L["Level %d-%d"]):format(d.lo, d.hi), 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine(L["Click: prep this dungeon (its quests on the panel, then the entrance)"], 0.4, 1, 0.4)
        if FDJ() or d.qid then
            GameTooltip:AddLine(FDJ() and L["Shift+click: open in Dungeon Journal"] or L["Shift+click: marker on the quest giver"],
                0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

local function Refresh()
    local level = UnitLevel("player") or 1
    local f = FDJ()
    local list = f and CollectJournal(f, level) or CollectQuestie(level)
    table.sort(list, function(a, b) if a.lo ~= b.lo then return a.lo < b.lo end return a.name < b.name end)
    for _, r in ipairs(rows) do r:Hide(); r.data = nil end
    local n, y, nq = 0, 0, 0
    local chain = NS.ChainMarkup()
    for _, e in ipairs(list) do
        table.sort(e.quests, function(a, b) return (a.level or 0) < (b.level or 0) end)
        n = n + 1
        local h = Row(n)
        h.data, h.dungeon = e, e.name
        h.prep:Show()
        h.text:SetPoint("RIGHT", -188, 0)
        local fits = level >= e.lo and level <= e.hi
        h.bg:SetColorTexture(0.75, 0.25, 0.1, fits and 0.30 or 0.14)
        h.text:SetText(("|cffffa070%s|r"):format(e.name))
        h.right:SetText(("%s%d-%d|r  |cff999999%d %s|r"):format(fits and "|cff80ff80" or "|cffcccccc", e.lo, e.hi,
            #e.quests, L["quests"]))
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        h:Show()
        y = y - DJ_ROW_H
        for _, q in ipairs(e.quests) do
            n = n + 1
            nq = nq + 1
            local r = Row(n)
            r.data, r.dungeon = q, e.name
            r.prep:Hide()
            r.text:SetPoint("RIGHT", -150, 0)
            r.bg:SetColorTexture(0, 0, 0, 0)
            local col = GetQuestDifficultyColor and q.level and GetQuestDifficultyColor(q.level)
            local hex = col and ("|cff%02x%02x%02x"):format(col.r * 255, col.g * 255, col.b * 255) or "|cffffffff"
            local tag = ""
            local info = NS.QuestExtraInfo and NS.GetQuestieQuest(q.qid) and NS.QuestExtraInfo(q.qid)
            if info and info.chainPos then tag = ("   %s|cffb48cff%d/%d|r"):format(chain, info.chainPos, info.chainLen) end
            if q.inLog then tag = tag .. "     |cff60ff60(" .. L["in log"] .. ")|r" end
            r.text:SetText(("    %s[%s] %s|r%s"):format(hex, tostring(q.level or "?"), q.name or "?", tag))
            r.right:SetText(q.requires and (L["from level %d"]):format(q.requires) or "")
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
            r:Show()
            y = y - DJ_ROW_H
        end
    end
    dj.title:SetText((L["Dungeons for your level (%d quests)"]):format(nq))
    if n == 0 then
        n = 1
        local r = Row(1)
        r.data, r.dungeon = nil, nil
        r.prep:Hide()
        r.bg:SetColorTexture(0, 0, 0, 0)
        r.text:SetText("|cff999999" .. L["No dungeon for your level right now."] .. "|r")
        r.right:SetText("")
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        r:Show()
        y = -DJ_ROW_H
    end
    content:SetHeight(math.max(-y, 1))
    local visH = math.min(n, DJ_VISIBLE) * DJ_ROW_H
    local needBar = n > DJ_VISIBLE
    scroll:SetPoint("BOTTOMRIGHT", dj, "TOPLEFT", DJ_W - (needBar and 34 or 12), -38 - visH)
    if scroll.ScrollBar then scroll.ScrollBar:SetShown(needBar) end
    if not needBar then scroll:SetVerticalScroll(0) end
    dj.foot:SetText(L["Click a dungeon or quest: dungeon prep (its quests on the panel, then an arrow to the entrance; /qf dungeon <name>)."]
        .. "\n" .. (f and L["Shift+click: opens the quest in Dungeon Journal. Wheel: scroll. Drag to move."]
        or L["Shift+click: marker on the quest giver. Wheel: scroll. Drag to move. (Dungeon Journal addon: more dungeons and details.)"]))
    dj.foot:ClearAllPoints()
    dj.foot:SetPoint("TOPLEFT", dj, "TOPLEFT", 14, -38 - visH - 6)
    dj:SetHeight(38 + visH + 14 + (dj.foot:GetStringHeight() or 12) + 8)
end

-- Egy dungeon questjei (szintsavtol fuggetlenul): { name, lo, hi, quests } vagy nil
NS.CollectDungeon = function(name)
    local f = FDJ()
    local level = UnitLevel("player") or 1
    local list = (f and f.DB[name]) and CollectJournal(f, level, name) or CollectQuestie(level, name)
    return list[1]
end
-- Ismert dungeon nevek (a Journal-bol, kulonben a classic listabol), plusz a bejarat tablabol
NS.DungeonNames = function()
    local seen, out = {}, {}
    local function add(n) if n and not seen[n] then seen[n] = true; out[#out + 1] = n end end
    local f = FDJ()
    if f then
        local fac = UnitFactionGroup and UnitFactionGroup("player")
        for name, d in pairs(f.DB) do
            local hidden = false
            if f.FactionHiddenFor then
                local ok, h = pcall(f.FactionHiddenFor, name, fac)
                hidden = ok and h and true or false
            end
            -- a Journal DB-ben NPC-k is lehetnek: csak a szintsavos (dungeon) bejegyzesek
            if not hidden and tostring(d.level or ""):match("%d+%D+%d+") then add(name) end
        end
    else
        for _, c in ipairs(CLASSIC) do add(c[1]) end
    end
    for name in pairs(NS.DungeonEntrances or {}) do
        -- Journal mellett az alias nevek (pl. "Dire Maul") nem kellenek
        if not f or f.DB[name] then add(name) end
    end
    table.sort(out)
    return out
end

NS.ToggleDungeonList = function()
    if dj:IsShown() then dj:Hide() return end
    Refresh()
    dj:Show()
end

-- Egy dungeon quest "Start dungeon" gombja: Journalban az o quest oldala, kulonben a lista
NS.OpenDungeonFor = function(qid, dungeon)
    dungeon = dungeon or (qid and NS.JournalDungeonOfQuest(qid))
    if dungeon and FDJ() and FDJ().DB[dungeon] and OpenInJournal(dungeon, qid) then return end
    Refresh()
    dj:Show()
end

-- Kis koponya gomb (dungeon quest sorokhoz): parent-en belul, a hivo helyezi el
local SKULL = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
NS.DUNGEON_ICON = SKULL
NS.MakeDungeonButton = function(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 14, size or 14)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexture(SKULL)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", function(self) NS.OpenDungeonFor(self.qid, self.dungeon) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Start dungeon"], 1, 0.6, 0.45)
        GameTooltip:AddLine(self.dungeon or "", 1, 1, 1)
        GameTooltip:AddLine(FDJ() and L["Click: open this quest in Dungeon Journal"]
            or L["Click: dungeons for your level and their quests"], 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end
