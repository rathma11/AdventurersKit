-- QuestFocus: kozos tooltip epito. Minden QuestFocus tooltip (panel sorok, javaslatok,
-- popupok, quest log) ugyanazt a szerkezetet es szineket hasznalja:
--   Cim (feher)                         jobb oldal (szurke: haladas / tavolsag)
--   Alcim (arany)
--   [ikon] objective                    tavolsag (kek)
--        forrasok (halvany)
--        hely  ·  hatralevo ido (kek)
--   megjegyzes (szurke)
--   (ures sor)
--   kattintas tippek (sotetszurke)
local ADDON_NAME, NS = ...
local L = NS.L
NS.C = NS.C or {}
local C = NS.C
local FindNearest, ItemSourceLines, ZoneName = C.FindNearest, C.ItemSourceLines, C.ZoneName

local TT = {}
NS.TT = TT

local ICON_DONE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t "
local ICON_TI = "|TInterface\\GossipFrame\\ActiveQuestIcon:12:12|t "
local ICON_TODO = "|TInterface\\COMMON\\Indicator-Yellow:12:12|t "
local INDENT = "     "

-- Uj tooltip: cim + (opcionalis) jobb oldali szoveg
function TT.Begin(owner, anchor, title, right)
    local tt = GameTooltip
    tt:SetOwner(owner, anchor or "ANCHOR_LEFT")
    tt:ClearLines()
    if right and right ~= "" then
        tt:AddDoubleLine(title or "?", right, 1, 1, 1, 0.75, 0.75, 0.75)
    else
        tt:AddLine(title or "?", 1, 1, 1)
    end
    return tt
end

function TT.Sub(tt, text) if text then tt:AddLine(text, 1, 0.82, 0, true) end end
function TT.Info(tt, text) if text then tt:AddLine(INDENT .. text, 0.55, 0.7, 0.9) end end
function TT.Note(tt, text) if text then tt:AddLine(text, 0.6, 0.6, 0.6, true) end end

-- Kattintas tippek a vegen, egy ures sorral elvalasztva; utana Show
function TT.Finish(tt, ...)
    local n = select("#", ...)
    if n > 0 then
        tt:AddLine(" ")
        for i = 1, n do
            local h = select(i, ...)
            if h then tt:AddLine(h, 0.45, 0.45, 0.45) end
        end
    end
    tt:Show()
end

-- Haladas szoveg a jobb oldalra: "3/5 · ~10m" vagy "leadhato"
function TT.Progress(objs, isComplete)
    if isComplete then return "|cff33ff99" .. L["ready to turn in"] .. "|r" end
    local done, total = 0, 0
    for _, o in ipairs(objs or {}) do
        if not o.turnIn then total = total + 1; if o.completed then done = done + 1 end end
    end
    local eta = NS.QuestEta and NS.QuestEta(objs)
    return ("%d/%d"):format(done, total) .. (eta and ("  ·  " .. eta) or "")
end

-- Hely szoveg: zona csak ha nem ott vagy
function TT.Where(p)
    if not p then return end
    local here = C_Map.GetBestMapForUnit("player")
    return (p.map ~= here and (ZoneName(p.map) .. " ") or "") .. ("%.0f, %.0f"):format(p.x, p.y)
end

-- Egy objective blokk. opts.sources: max forras (alap 3), opts.highlight: kijelolt (zold)
function TT.Objective(tt, o, opts)
    opts = opts or {}
    if o.completed then
        tt:AddLine(ICON_DONE .. o.desc, 0.5, 0.5, 0.5)
        return
    end
    local p, dist = FindNearest(o.sources)
    local icon = o.turnIn and ICON_TI or ICON_TODO
    local r, g, b = 1, 0.82, 0
    if opts.highlight then r, g, b = 0.2, 1, 0.6 end
    tt:AddDoubleLine(icon .. o.desc, dist and ("%d yd"):format(dist) or "", r, g, b, 0.6, 0.8, 1)
    -- Forrasok (behuzva, ismetles nelkul)
    local limit, seen = opts.sources or 3, {}
    if o.itemId then
        for _, l in ipairs(ItemSourceLines(o, limit)) do
            local t = l[1]:gsub("%s*%(on the ground / in an object%)", "")
            if not seen[t] then
                seen[t] = true
                tt:AddLine(INDENT .. t, l[2] * 0.85, l[3] * 0.85, l[4] * 0.85)
            end
        end
    elseif not o.turnIn then
        local names = {}
        for _, s in ipairs(o.sources or {}) do
            if s.name and not seen[s.name] then
                seen[s.name] = true
                if #names >= limit then names[#names + 1] = "..." break end
                names[#names + 1] = s.name
            end
        end
        if #names > 0 then tt:AddLine(INDENT .. table.concat(names, ", "), 0.85, 0.85, 0.85, true) end
    end
    local info = {}
    info[#info + 1] = TT.Where(p)
    local short = NS.EtaShort and NS.EtaShort(o)
    if short then info[#info + 1] = short .. " " .. L["left"] end
    if #info > 0 then TT.Info(tt, table.concat(info, "   ·   ")) end
end

function TT.Objectives(tt, objs, opts)
    for _, o in ipairs(objs or {}) do TT.Objective(tt, o, opts) end
end

-- Felveheto quest (javaslat sor, popup, varos lista)
function TT.Pickup(owner, anchor, d, extraNote)
    local tt = TT.Begin(owner, anchor, ("[%s] %s"):format(tostring(d.level or "?"), d.name or "?"),
        d.dist and ("%d yd"):format(d.dist) or nil)
    TT.Sub(tt, (L["Quest giver: %s"]):format(d.point and d.point.name or "?"))
    TT.Info(tt, TT.Where(d.point))
    -- XP, lanc, itemmel indul (Planner\City.lua: NS.QuestExtraInfo)
    local info = NS.QuestExtraInfo and d.qid and NS.QuestExtraInfo(d.qid, d.quest)
    if info then
        if info.xp then TT.Info(tt, ("|cffd8c070%s|r"):format(NS.XpText(info.xp))) end
        if info.chainPos then
            TT.Info(tt, ("|cffb48cff" .. L["Quest chain: part %d of %d"] .. "|r"):format(info.chainPos, info.chainLen))
        end
        if info.byItem then TT.Info(tt, "|cffff9933" .. L["Can also be started by an item"] .. "|r") end
    end
    TT.Note(tt, extraNote)
    TT.Finish(tt, L["Click: marker on the quest giver"])
end
