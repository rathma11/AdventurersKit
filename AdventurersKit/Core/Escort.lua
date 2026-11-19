local ADDON_NAME, NS = ...
local L = NS.L
NS.C = NS.C or {}
local C = NS.C
local GetNPC, GetQuestieQuest, Module, Print, state = C.GetNPC, C.GetQuestieQuest, C.Module, C.Print, C.state

---------------------------------------------------------------------------
-- Escort questek
-- Felismeres: a Questie "event" objective-je (triggerEnd) escort jellegu szoveggel
-- ("Escort X to Y", "Protect X", "Help X ...", "X escorted ..."), vagy a quest tag 84 (Escort).
-- Az escortalt NPC: a quest kezdo NPC-je (a legtobb escortnal o maga indul el), vagy a
-- szovegbol kiolvasott nev. Vege pont: az event objective koordinataja (ha nincs: leado NPC).
-- Kudarcnal (quest log: failed) a marker es a macro a quest adora mutat (ujrakezdes).
---------------------------------------------------------------------------
local ESCORT_TAG = 84
local ICON_STAR = 1
local LOW_PCT, REARM_PCT = 35, 60

-- event szovegek, amik escortot jelentenek (kisbetus)
local PATTERNS = {
    "escort", "protect ", "to safety", "^help ", "^lead ", "guided", "^take .+ to ", "^free ", "rescue", "^defend ",
    "must reach", "^return the .+ to ",
}
local function LooksEscort(text)
    if type(text) ~= "string" then return false end
    local t = text:lower()
    for _, p in ipairs(PATTERNS) do
        if t:find(p) then return true end
    end
    return false
end

-- Nev a szovegbol: "Escort <nev> to ...", "Protect <nev> until ...", "<nev> escorted to ..."
local CUTS = { " to ", " back ", " out ", " away ", " from ", " on ", " past ", " until ", " while ", " safely", " get ",
    " escape", " find ", " reach", " must ", " escorted", " guided", "%.", ":", "%(" }
local function NameFromText(text)
    if type(text) ~= "string" then return end
    local s = text:gsub("^%s+", "")
    local rest = s:match("^[Ee]scort (.+)") or s:match("^[Pp]rotect (.+)") or s:match("^[Hh]elp (.+)")
        or s:match("^[Ll]ead (.+)") or s:match("^[Tt]ake (.+)") or s:match("^[Ff]ree (.+)")
        or s:match("^[Rr]escue (.+)") or s:match("^[Dd]efend (.+)")
    if not rest then
        rest = s:match("^(.-) escorted") or s:match("^(.-) must reach") or s:match("^(.-) guided")
            or s:match("^(.-) [Rr]escue$")
    end
    if not rest then return end
    rest = " " .. rest .. " "
    local cut = #rest
    for _, c in ipairs(CUTS) do
        local i = rest:find(c)
        if i and i < cut then cut = i end
    end
    local name = rest:sub(1, cut - 1):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or #name > 40 then return end
    return name
end

local function QuestTag(qid)
    local DB = Module("QuestieDB")
    if DB and type(DB.GetQuestTagInfo) == "function" then
        local ok, tag = pcall(DB.GetQuestTagInfo, qid)
        if ok and tag then return tag end
    end
    if C_QuestLog and C_QuestLog.GetQuestTagInfo then
        local ok, info = pcall(C_QuestLog.GetQuestTagInfo, qid)
        if ok and type(info) == "table" then return info.tagID end
    end
    if GetQuestTagInfo then
        local ok, tag = pcall(GetQuestTagInfo, qid)
        if ok then return tag end
    end
end

-- Escort adatok questenkent (statikus: egyszer szamoljuk)
local infoCache = {}
local function EscortInfo(qid)
    if not qid then return end
    local cached = infoCache[qid]
    if cached ~= nil then return cached or nil end
    local quest = GetQuestieQuest(qid)
    if not quest then return end -- Questie meg nem toltott be: kesobb ujra
    local evText, evSpawns
    local function scan(list, textKey)
        for _, o in pairs(type(list) == "table" and list or {}) do
            if type(o) == "table" and o.Type == "event" then
                local t = o[textKey] or o.Text or o.Description
                if LooksEscort(t) or not evText then
                    evText = t
                    if type(o.Coordinates) == "table" and next(o.Coordinates) then evSpawns = o.Coordinates end
                end
            end
        end
    end
    scan(quest.ObjectiveData, "Text")
    scan(quest.Objectives, "Description")
    -- Nincs event objective (pl. Forever sajat questek, Zimmix's Great Escape): a quest celja
    -- szovegebol ("Escort X away from ..."), csak ha escort igevel kezdodik
    if not LooksEscort(evText) then
        local ot = quest.objectivesText or quest.Description
        if type(ot) == "string" then ot = { ot } end
        for _, t in ipairs(type(ot) == "table" and ot or {}) do
            if type(t) == "string" and (t:find("^%s*[Ee]scort ") or t:find("^%s*[Pp]rotect ")
                or t:find("^%s*[Hh]elp ") or t:find("^%s*[Ll]ead ") or t:find("^%s*[Gg]uide ")) then
                evText = t
                break
            end
        end
    end
    local tagged = QuestTag(qid) == ESCORT_TAG
    if not (tagged or LooksEscort(evText)) then
        infoCache[qid] = false
        return
    end
    -- kezdo NPC (quest ado = ujrakezdes helye; legtobbszor o az escortalt NPC)
    local giver
    local starts = type(quest.Starts) == "table" and quest.Starts.NPC
    if type(starts) == "table" then
        for _, id in ipairs(starts) do
            local npc = GetNPC(id)
            if npc then giver = { id = id, name = npc.name, spawns = npc.spawns, isNpc = true, static = true } break end
        end
    end
    local parsed = NameFromText(evText)
    local name, npcId = parsed, nil
    if giver and giver.name then
        local g, p = giver.name:lower(), parsed and parsed:lower()
        if not p or g:find(p, 1, true) or p:find(g, 1, true) then
            name, npcId = giver.name, giver.id
        end
    end
    if not name then name = giver and giver.name end
    if not name then
        infoCache[qid] = false
        return
    end
    -- vege pont: az event koordinatai, kulonben a leado NPC
    local dest
    if evSpawns then
        dest = { { id = 0, name = evText or name, spawns = evSpawns, isNpc = false, static = true } }
    elseif type(quest.Finisher) == "table" and type(quest.Finisher.NPC) == "table" then
        for _, id in ipairs(quest.Finisher.NPC) do
            local npc = GetNPC(id)
            if npc and npc.spawns then
                dest = { { id = id, name = npc.name, spawns = npc.spawns, isNpc = false, static = true } }
                break
            end
        end
    end
    local info = { qid = qid, name = name, npcId = npcId, giver = giver, text = evText, dest = dest }
    infoCache[qid] = info
    return info
end

-- Nyers quest log allapot: -1 = elbukott
local function QuestFailed(qid)
    if not (GetNumQuestLogEntries and GetQuestLogTitle) then return false end
    for i = 1, (GetNumQuestLogEntries()) do
        local _, _, _, isHeader, _, isComplete, _, id = GetQuestLogTitle(i)
        if not isHeader and id == qid then return isComplete == -1 end
    end
    return false
end

---------------------------------------------------------------------------
-- Escortalt NPC a jatekban (target, mouseover, focus, nameplate-ek)
---------------------------------------------------------------------------
local live = { hp = nil, seen = 0, guid = nil, unitName = nil, attacker = nil, dead = false }
local warned = false
local iconDone = {} -- GUID -> true: mar tettunk ra ikont (nem tesszuk ujra, ha leveszed)

local function NpcIdOf(unit)
    local guid = UnitGUID(unit)
    if not guid then return end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

-- Csak a quest adatbol megerositett NPC: ha ismert az NPC ID, annak kell egyeznie (azonos nevu
-- mas mob nem jo); kulonben pontos nev. Ellenseges unit soha nem az escort (pl. ami rad tamad).
local function IsEscortUnit(unit, info)
    if not (info and info.name and unit and UnitExists(unit)) or UnitIsPlayer(unit) then return false end
    if UnitCanAttack and UnitCanAttack("player", unit) then return false end
    local id = NpcIdOf(unit)
    if info.npcId and id then return id == info.npcId end
    return UnitName(unit) == info.name
end

local function CanMark()
    if not SetRaidTarget then return false end
    if IsInRaid and IsInRaid() then
        return (UnitIsGroupLeader and UnitIsGroupLeader("player")) or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
    end
    return true -- egyedul vagy partyban barki tehet ikont
end

local function TryMark(unit)
    if QuestFocusDB and QuestFocusDB.noEscortIcon then return end
    local guid = UnitGUID(unit)
    if not guid or iconDone[guid] then return end
    if GetRaidTargetIndex(unit) then iconDone[guid] = true return end -- mar van rajta ikon
    if not CanMark() then NS.Debug("escort", "no star icon: not raid leader / assistant") return end
    if pcall(SetRaidTarget, unit, ICON_STAR) then
        iconDone[guid] = true
        NS.Debug("escort", "star icon on %s (%s)", tostring(UnitName(unit)), unit)
    end
end

local function Observe(unit, info)
    if not IsEscortUnit(unit, info) then return false end
    local hp, max = UnitHealth(unit), UnitHealthMax(unit)
    if max and max > 0 then live.hp = math.floor(hp / max * 100 + 0.5) end
    live.dead = UnitIsDead(unit) and true or false
    live.seen, live.guid, live.unitName = GetTime(), UnitGUID(unit), UnitName(unit)
    local tt = unit .. "target"
    live.attacker = (UnitExists(tt) and UnitCanAttack("player", tt) and not UnitIsDead(tt)) and UnitName(tt) or nil
    TryMark(unit)
    return true
end

local function Scan(info)
    for _, u in ipairs({ "target", "mouseover", "focus", "targettarget" }) do
        if Observe(u, info) then return true end
    end
    for i = 1, 40 do
        local u = "nameplate" .. i
        if UnitExists(u) and Observe(u, info) then return true end
    end
    return false
end

local function CurrentInfo()
    if not state.questId or state.isComplete then return end
    return EscortInfo(state.questId)
end

local ticker = CreateFrame("Frame")
local tickElapsed = 0
ticker:SetScript("OnUpdate", function(_, dt)
    tickElapsed = tickElapsed + dt
    if tickElapsed < 0.3 then return end
    tickElapsed = 0
    local info = CurrentInfo()
    if not info or state.escortFailed then return end
    if not Scan(info) then return end
    if live.dead then return end
    if live.hp and live.hp <= LOW_PCT and not warned then
        warned = true
        NS.Debug("escort", "low health warning: %s at %d%%", tostring(info.name), live.hp)
        local msg = (L["Escort %s is low: %d%%!"]):format(info.name, live.hp)
        if UIErrorsFrame then UIErrorsFrame:AddMessage(msg, 1, 0.2, 0.2) end
        if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
        Print("|cffff3333" .. msg .. "|r")
    elseif live.hp and live.hp >= REARM_PCT then
        warned = false
    end
end)
local ev = CreateFrame("Frame")
for _, e in ipairs({ "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event, unit)
    local info = CurrentInfo()
    if not info or state.escortFailed then return end
    if event == "UPDATE_MOUSEOVER_UNIT" then Observe("mouseover", info)
    elseif event == "PLAYER_TARGET_CHANGED" then Observe("target", info)
    elseif unit then Observe(unit, info) end
end)

---------------------------------------------------------------------------
-- Objective-ek atalakitasa (Selection.Refresh hivja a CollectTargets utan)
---------------------------------------------------------------------------
local function Decorate(objectives)
    local prevQid, prevFailed = state.escortQid, state.escortFailed
    local info = CurrentInfo()
    state.escort = info
    state.escortQid = info and info.qid or nil
    if not info then state.escortFailed = nil return objectives end
    if prevQid ~= info.qid then
        live.hp, live.seen, live.guid, live.attacker, live.dead = nil, 0, nil, nil, false
        warned = false
        NS.Debug("escort", "escort quest %s: NPC %s (id %s), giver %s, %d end point(s)", tostring(info.qid), tostring(info.name),
            tostring(info.npcId or "?"), tostring(info.giver and info.giver.name), info.dest and #info.dest or 0)
    end
    local failed = QuestFailed(info.qid)
    if failed and not prevFailed then NS.Debug("escort", "escort %s failed: macro + marker on the quest giver", tostring(info.qid)) end
    state.escortFailed = failed or nil
    if failed then
        local giver = info.giver
        objectives = { {
            desc = (L["Escort failed - restart at %s"]):format(giver and giver.name or "?"),
            completed = false, escort = true, restart = true, qid = info.qid,
            sources = giver and { giver } or {},
        } }
        if not prevFailed and prevQid == info.qid then
            Print(L["|cffff3333Escort failed.|r Abandon the quest and take it again from |cffffff00%s|r; marker moved there."],
                giver and giver.name or "?")
            C_Timer.After(0, function() if state.escortFailed and C.MarkObjective then C.MarkObjective(nil) end end)
        end
        return objectives
    end
    -- az event objective: escort sor, a vege pontja mindig marker (static)
    local found
    for _, o in ipairs(objectives) do
        if not o.turnIn and (not o.itemId) and (#o.sources == 0 or not o.sources[1].isNpc) and not o.completed
            and (LooksEscort(o.desc) or (info.text and o.desc and o.desc:find(info.text, 1, true))) then
            o.escort = true
            if #o.sources == 0 and info.dest then o.sources = info.dest end
            for _, s in ipairs(o.sources) do s.static = true end
            found = true
        end
    end
    if not found then
        table.insert(objectives, 1, {
            desc = (info.text and #info.text <= 60) and info.text or ((L["Escort %s"]):format(info.name)),
            completed = false, escort = true,
            qid = info.qid, sources = info.dest or {},
        })
    end
    return objectives
end

---------------------------------------------------------------------------
-- Macro: az escortalt NPC tamadoja; ha nincs, maga az NPC. Kudarcnal a quest ado.
---------------------------------------------------------------------------
local function MacroBody(objectives, onlyIndex)
    local info = state.escort
    if not info or state.isComplete then return end
    if onlyIndex and not (objectives and objectives[onlyIndex] and objectives[onlyIndex].escort) then return end
    if state.escortFailed then
        local g = info.giver
        if not (g and g.name) then return end
        return "/targetexact " .. g.name
    end
    local lines = {
        "/cleartarget [dead]",
        "/targetexact [noharm] " .. info.name,
        "/assist [help,nodead]",
    }
    if QuestFocusDB and QuestFocusDB.startAttack then lines[#lines + 1] = "/startattack [@target,harm,nodead]" end
    local spell = QuestFocusDB and QuestFocusDB.spell
    if QuestFocusDB and QuestFocusDB.useSpell and spell and spell ~= "" then
        lines[#lines + 1] = "/cast [@target,harm,nodead] " .. spell
    end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Panel szovegek
---------------------------------------------------------------------------
local function HpColor(p)
    if p <= LOW_PCT then return "|cffff3333" elseif p < REARM_PCT then return "|cffffcc33" end
    return "|cff33ff33"
end

-- Panel sor: ki, hova, eletero
local function RowText()
    local info = state.escort
    if not info then return end
    if state.escortFailed then
        return "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12|t |cffff3333" .. L["Escort failed"] .. "|r - "
            .. (L["take the quest again from %s"]):format("|cffffff00" .. (info.giver and info.giver.name or "?") .. "|r")
    end
    local hp
    if live.dead then
        hp = "|cffff3333" .. L["dead"] .. "|r"
    elseif live.hp and GetTime() - live.seen < 10 then
        hp = HpColor(live.hp) .. live.hp .. "%|r"
    elseif live.hp then
        hp = "|cff999999" .. live.hp .. "%?|r"
    else
        hp = "|cff999999" .. L["HP ?"] .. "|r"
    end
    local dest = info.dest and info.dest[1] and info.dest[1].name
    local where = (dest and dest ~= info.text) and dest or nil
    return ("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12:12|t |cffffd100%s|r %s  %s%s"):format(
        L["Escort:"], info.name, hp, where and ("  |cff999999-> " .. where .. "|r") or "")
end

local function RowTooltip(tt)
    local info = state.escort
    if not info then return end
    tt:AddLine((L["Escorting: %s"]):format(info.name), 1, 1, 1)
    if info.text then tt:AddLine(info.text, 0.8, 0.8, 0.8, true) end
    if info.giver then tt:AddLine((L["Quest giver (restart): %s"]):format(info.giver.name or "?"), 0.7, 0.7, 0.7) end
    if live.attacker then tt:AddLine((L["Attacked by: %s"]):format(live.attacker), 1, 0.5, 0.3) end
    tt:AddLine(L["The AKit macro targets whatever the escort is fighting, otherwise the escort itself."], 0.6, 0.8, 1, true)
    tt:AddLine((L["Health warning below %d%%. Health is read when the escort is your target, mouseover or has a nameplate."]):format(LOW_PCT), 0.6, 0.6, 0.6, true)
    if not (QuestFocusDB and QuestFocusDB.noEscortIcon) then
        tt:AddLine(L["A star raid icon goes on the escort when you target or mouse over it."], 0.6, 0.6, 0.6, true)
    end
end

local function FooterText()
    local info = state.escort
    if not info then return end
    if state.escortFailed then return L["Macro: targets the quest giver (restart the escort)"] end
    if live.attacker and GetTime() - live.seen < 5 then
        return (L["|cffff6633%s attacks the escort|r - the macro targets it"]):format(live.attacker)
    end
    return L["Macro: the escort's attacker, otherwise the escort"]
end

NS.Escort = {
    Info = EscortInfo, Decorate = Decorate, MacroBody = MacroBody, RowText = RowText, RowTooltip = RowTooltip,
    FooterText = FooterText, NameFromText = NameFromText, LooksEscort = LooksEscort,
    IsEscortUnit = IsEscortUnit, Observe = Observe,
}

-- Debug: escort pillanatkep (Core\DebugLog.lua)
NS.DebugSnapshot("escort", function(out)
    local qid = state.questId
    local info = qid and EscortInfo(qid)
    if not info then
        out[#out + 1] = ("Escort: no (focused quest %s is not an escort%s)"):format(tostring(qid or "-"),
            state.isComplete and ", or it is ready to turn in" or "")
        return
    end
    out[#out + 1] = ("Escort quest %s: NPC %s (id %s) | failed: %s | star icon: %s"):format(tostring(info.qid), tostring(info.name),
        tostring(info.npcId or "?"), tostring(state.escortFailed == true), (QuestFocusDB.noEscortIcon and "off") or (CanMark() and "on" or "no rights"))
    out[#out + 1] = ("Giver: %s | end points: %d | text: %s"):format(tostring(info.giver and info.giver.name), info.dest and #info.dest or 0,
        tostring(info.text or "-"))
    out[#out + 1] = ("Seen: %s | hp %s%% | dead %s | attacker %s"):format(
        live.seen > 0 and ("%.0f s ago"):format(GetTime() - live.seen) or "never", tostring(live.hp or "?"), tostring(live.dead),
        tostring(live.attacker or "-"))
end)
