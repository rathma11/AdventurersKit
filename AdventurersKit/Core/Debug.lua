local ADDON_NAME, NS = ...
local L = NS.L
NS.C = NS.C or {}
local C = NS.C
local NameplatesUsable, state, TapDenied, targetNames = C.NameplatesUsable, C.state, C.TapDenied, C.targetNames

---------------------------------------------------------------------------
-- Debug pillanatkepek (Core\DebugLog.lua szekcioi). A modulok a sajat szekciojukat a sajat
-- fajljukban toltik (NS.DebugSnapshot); itt a core reszek: general, target, zone, bags / buffs
-- (a ket kulon addon adatai), route (hearthstone).
---------------------------------------------------------------------------
local function YN(v) return v and "yes" or "no" end

-- Targeting / AKit macro: ez a regi "/ak debug" tartalma (plain /ak debug ezt irja ki)
local function TargetLines(out)
    out = out or {}
    local names = {}
    for k in pairs(targetNames) do names[#names + 1] = k end
    table.sort(names)
    local u = state.pick
    out[#out + 1] = (L["Quest: %s (%s)"]):format(state.title or "-", tostring(state.questId or "-"))
    out[#out + 1] = (L["Nameplate mode: %s"]):format(NameplatesUsable() and L["on"] or L["off (V key)"])
    out[#out + 1] = (L["Wanted mobs: %s"]):format(#names > 0 and table.concat(names, ", ") or "-")
    out[#out + 1] = (L["Picked: %s"]):format(u == "busy" and L["all taken"] or
        (u and ((UnitName(u) or "?") .. " (" .. u .. ")") or L["none (fallback by name)"]))
    -- Ping mod (ask / on / off, csapatban a valasz) es a mostani target: a "nem pingelt" /
    -- "nem targetelt" bejelentesek ebbol azonnal olvashatok
    local pm = NS.PingMode and NS.PingMode() or "?"
    local grouped = IsInGroup and IsInGroup()
    local answer = pm == "ask" and (grouped and (NS.pingSession == true and "yes" or NS.pingSession == false and "no"
        or "not answered") or "solo") or nil
    out[#out + 1] = (L["Ping: %s%s -> %s"]):format(pm, answer and (" (" .. answer .. ")") or "",
        (NS.UsePing and NS.UsePing()) and L["pings"] or L["no ping"])
    -- miert van / nincs ping sor a mostani macroban (Targeting.lua: BuildMacroBody)
    out[#out + 1] = (L["Ping in the macro: %s"]):format(state.pingWhy or "-")
    if UnitExists("target") then
        out[#out + 1] = (L["Target: %s  dead=%s tapped=%s attackable=%s isPick=%s"]):format(UnitName("target") or "?",
            tostring(UnitIsDead("target")), tostring(TapDenied("target")), tostring(UnitCanAttack("player", "target")),
            tostring(u ~= nil and u ~= "busy" and UnitIsUnit(u, "target") or false))
    else
        out[#out + 1] = L["Target: none"]
    end
    out[#out + 1] = (L["In combat: %s"]):format(InCombatLockdown() and L["yes (the macro can't update now)"] or L["no"])
    out[#out + 1] = ("Extra (nearby quests in the macro): %d | macro mobs: %s | pending (combat): %s"):format(
        state.extra and #state.extra or 0, tostring(state.macroCount or 0), YN(state.pendingBody))
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
    return out
end
NS.DebugSnapshot("target", TargetLines)

NS.DebugSnapshot("zone", function(out)
    local zf = QuestFocusDB.zoneFocus
    out[#out + 1] = (L["Zone focus: %s"]):format(zf and (zf.zone or "?") or L["off"])
    if zf then
        local r, a = 0, 0
        for _ in pairs(zf.removed or {}) do r = r + 1 end
        for _ in pairs(zf.added or {}) do a = a + 1 end
        out[#out + 1] = ("Hidden from the tracker by the focus: %d | added to it: %d"):format(r, a)
    end
    out[#out + 1] = ("Current zone: %s | ask on new zone: %s | follow without asking: %s"):format(
        GetRealZoneText and GetRealZoneText() or "?", YN(not QuestFocusDB.noZonePrompt), YN(QuestFocusDB.zoneAutoFollow))
end)

NS.DebugSnapshot("route", function(out)
    local h = QuestFocusDB.hearth
    out[#out + 1] = (L["Hearthstone: %s | position learned: %s"]):format(
        GetBindLocation and GetBindLocation() or "?",
        (h and GetBindLocation and h.name == GetBindLocation()) and L["yes"]
            or L["no (bind at an innkeeper or use your Hearthstone once)"])
end)

NS.DebugSnapshot("bags", function(out)
    out[#out + 1] = "Module: " .. ((NS.ModuleOn and NS.ModuleOn("QuestFocus_Bags")) and "on" or "off / not loaded")
    out[#out + 1] = "Bag highlight: " .. (NS.bagFocusDebug or "-")
    if NS.BagDebugLines then
        local ok, lines = pcall(NS.BagDebugLines)
        if ok and lines then for _, l in ipairs(lines) do out[#out + 1] = l end end
    end
end)

NS.DebugSnapshot("buffs", function(out)
    if not NS.BuffDebugLines then out[#out + 1] = "Buffs addon not loaded" return end
    out[#out + 1] = "Module: " .. ((NS.ModuleOn and NS.ModuleOn("QuestFocus_Buffs")) and "on" or "off")
    local ok, lines = pcall(NS.BuffDebugLines)
    if ok and lines then for _, l in ipairs(lines) do out[#out + 1] = l end
    elseif not ok then out[#out + 1] = "error: " .. tostring(lines) end
end)

---------------------------------------------------------------------------
-- General: verzio, kliens, Questie, mas addonok, beallitasok, Lua hibak
---------------------------------------------------------------------------
local OTHER_ADDONS = { "Questie", "TomTom", "Bagnon", "Auctionator", "TradeSkillMaster", "Auc-Advanced",
    "ForeverDungeonJournal", "AllTheThings", "AdventurersKit_Bags", "AdventurersKit_Buffs" }
local function Meta(addon, field)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not get then return nil end
    local ok, v = pcall(get, addon, field)
    return ok and v or nil
end
local function Loaded(addon)
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not f then return false end
    local ok, v = pcall(f, addon)
    return ok and v and true or false
end

NS.DebugSnapshot("general", function(out)
    local build, _, _, toc = "?", nil, nil, "?"
    if GetBuildInfo then build, _, _, toc = GetBuildInfo() end
    out[#out + 1] = ("Version: %s | client %s (%s) | locale %s"):format(NS.Version and NS.Version() or "?",
        tostring(build), tostring(toc), tostring(NS.locale))
    out[#out + 1] = ("Questie: %s"):format(_G.QuestieLoader and ("loaded " .. (Meta("Questie", "Version") or "?"))
        or "NOT FOUND")
    local others = {}
    for _, a in ipairs(OTHER_ADDONS) do
        if a ~= "Questie" and Loaded(a) then
            local v = Meta(a, "Version")
            others[#others + 1] = a .. (v and (" " .. v) or "")
        end
    end
    out[#out + 1] = "Other addons: " .. (#others > 0 and table.concat(others, ", ") or "-")
    out[#out + 1] = ("Chat quiet: %s | error popup: %s | panel hidden: %s"):format(YN(QuestFocusDB.quietChat),
        YN(QuestFocusDB.showErrors), YN(QuestFocusDB.hidePanel))
    local on = {}
    for _, s in ipairs(NS.DEBUG_SECTIONS) do if NS.DebugOn(s.key) then on[#on + 1] = s.key end end
    out[#out + 1] = "Debug logs on: " .. (#on > 0 and table.concat(on, ", ") or "-")
    local errs = NS.errors or {}
    out[#out + 1] = (L["|cffff5555Lua errors: %d|r"]):format(#errs)
    for _, e in ipairs(errs) do
        out[#out + 1] = ("  [%s] x%d  %s"):format(e.time, e.count, e.msg)
        for line in (e.stack or ""):gmatch("[^\n]+") do out[#out + 1] = "      |cff808080" .. line .. "|r" end
    end
end)

-- belso exportok a tobbi core fajlnak (a regi DebugLines: a targeting pillanatkep)
NS.C.DebugLines = function() return TargetLines({}) end
