local ADDON_NAME, NS = ...
local L = NS.L
NS.C = NS.C or {}
local C = NS.C
local NameplatesUsable, state, TapDenied, targetNames = C.NameplatesUsable, C.state, C.TapDenied, C.targetNames

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


-- belso exportok a tobbi core fajlnak
NS.C.DebugLines = DebugLines
