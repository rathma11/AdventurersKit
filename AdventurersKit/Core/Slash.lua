local ADDON_NAME, NS = ...
local L = NS.L
NS.C = NS.C or {}
local C = NS.C
local AddQuestTooltip, ApplyMacro, arrow, BuildMacroBody, ClearQuest, ClearWaypoint, CollectTargets, DebugLines = C.AddQuestTooltip, C.ApplyMacro, C.arrow, C.BuildMacroBody, C.ClearQuest, C.ClearWaypoint, C.CollectTargets, C.DebugLines
local FindQuestInLog, GetLogEntry, GetNPC, GetObject, GetQuestieQuest, ICON_FALLBACK, IconId, MarkObjective = C.FindQuestInLog, C.GetLogEntry, C.GetNPC, C.GetObject, C.GetQuestieQuest, C.ICON_FALLBACK, C.IconId, C.MarkObjective
local Module, NumLogEntries, OpenOptions, opt, OptCheck, optNote, panel, Panel_Update = C.Module, C.NumLogEntries, C.OpenOptions, C.opt, C.OptCheck, C.optNote, C.panel, C.Panel_Update
local PlayerWorldPos, Print, QuestieAvailable, RebuildMacro, SelectObjective, SelectQuest, SetSpell, SetWaypoint = C.PlayerWorldPos, C.Print, C.QuestieAvailable, C.RebuildMacro, C.SelectObjective, C.SelectQuest, C.SetSpell, C.SetWaypoint
local ShowCopy, state, ToggleZoneFocus, UiMapFromArea, UpdateMacro, UpdateMinimapButton, UseOwnArrow, WorldPos = C.ShowCopy, C.state, C.ToggleZoneFocus, C.UiMapFromArea, C.UpdateMacro, C.UpdateMinimapButton, C.UseOwnArrow, C.WorldPos
local ZoneName = C.ZoneName

---------------------------------------------------------------------------
-- Kozos nevter a QuestFocusBags.lua szamara
---------------------------------------------------------------------------
NS.Print, NS.state, NS.GetQuestieQuest = Print, state, GetQuestieQuest
NS.NumLogEntries, NS.GetLogEntry, NS.FindQuestInLog = NumLogEntries, GetLogEntry, FindQuestInLog
NS.SelectQuest, NS.OptCheck, NS.opt, NS.optNote, NS.panel = SelectQuest, OptCheck, opt, optNote, panel
NS.CollectTargets, NS.WorldPos, NS.UiMapFromArea, NS.PlayerWorldPos = CollectTargets, WorldPos, UiMapFromArea, PlayerWorldPos
NS.ZoneName, NS.SetWaypoint, NS.Panel_Update, NS.GetNPC, NS.GetObject, NS.Module = ZoneName, SetWaypoint, Panel_Update, GetNPC, GetObject, Module
NS.ClearWaypoint, NS.AddQuestTooltip, NS.QuestieAvailable = ClearWaypoint, AddQuestTooltip, QuestieAvailable

SLASH_QUESTFOCUS1 = "/ak"
SLASH_QUESTFOCUS2 = "/qf"          -- regi parancs, csendes alias
SLASH_QUESTFOCUS3 = "/questfocus"
local function SlashHandler(msg)
    local raw = (msg or ""):match("^%s*(.-)%s*$")
    msg = raw:lower()
    if msg == "options" or msg == "config" or msg == "opt" then
        OpenOptions()
    elseif msg == "debug" then
        for _, l in ipairs(DebugLines()) do Print(l) end
    elseif msg:match("^debug%s") then
        -- /ak debug <szekcio> [on | off | clear]; /ak debug list (Core\DebugLog.lua)
        local word, sw = msg:match("^debug%s+(%S+)%s*(%S*)")
        local key = NS.DebugKey(word)
        if word == "all" and (sw == "on" or sw == "off") then
            NS.SetDebugAll(sw == "on")
            Print(L["Debug log %s: %s"], L["all sections"], sw == "on" and L["on"] or L["off"])
            return
        end
        if word == "list" or word == "help" or not key then
            if word ~= "list" and word ~= "help" then Print(L["Unknown debug section: %s"], tostring(word)) end
            Print(L["Debug sections: %s"], NS.DebugKeyList())
            Print(L["  /ak debug <section> - snapshot + last log lines; /ak debug <section> on | off | clear - its log"])
            Print(L["  /ak debug all on | off - every section's log"])
            return
        end
        local title = L[NS.DebugSection(key).title]
        if sw == "on" or sw == "off" then
            NS.SetDebugOn(key, sw == "on")
            NS.Debug(key, "log switched on")
            Print(L["Debug log %s: %s"], title, sw == "on" and L["on"] or L["off"])
            return
        elseif sw == "clear" then
            NS.DebugClear(key)
            Print(L["Debug log %s: cleared"], title)
            return
        end
        Print("|cffffff00%s|r [%s]", title, key)
        for _, l in ipairs(NS.DebugSnapshotLines(key)) do Print(l) end
        local log = NS.DebugLogLines(key)
        Print(L["Log: %s, %d lines%s"], NS.DebugOn(key) and L["on"] or L["off"], #log,
            #log > 10 and L[" (last 10; /ak copy for all)"] or "")
        for i = math.max(1, #log - 9), #log do Print("  " .. log[i]) end
    elseif msg == "copy" or msg:match("^copy%s") then
        -- /ak copy: targeting; /ak copy <szekcio> | all
        local word = msg:match("^copy%s+(%S+)")
        if word == "all" then ShowCopy("all") return end
        local key = word and NS.DebugKey(word)
        if word and not key then
            Print(L["Unknown debug section: %s"], word)
            Print(L["Debug sections: %s"], NS.DebugKeyList())
            return
        end
        ShowCopy(key)
    elseif msg == "zone" then
        ToggleZoneFocus()
    elseif msg == "bags" then
        if NS.ToggleBagList then NS.ToggleBagList() end
    elseif msg == "city" then
        if NS.ToggleCityList then NS.ToggleCityList() end
    elseif msg == "dungeon" or msg == "dungeons" then
        if NS.ToggleDungeonList then NS.ToggleDungeonList() end
    elseif msg:match("^dungeons?%s") then
        -- /ak dungeon <nev> (reszleges nev is): dungeon prep mod; /ak dungeon off: vege
        if NS.PrepCommand then NS.PrepCommand(raw:match("^%S+%s+(.+)$")) end
    elseif msg == "farm" or msg:match("^farm%s") then
        -- Planner\Farm.lua: /ak farm (start / stop), /ak farm pause | resume | reset
        if NS.FarmCommand then NS.FarmCommand(msg:match("^farm%s+(%S+)")) end
    elseif msg == "export" then
        if NS.OpenShareSettings then NS.OpenShareSettings("export") end
    elseif msg == "import" then
        if NS.OpenShareSettings then NS.OpenShareSettings("import") end
    elseif msg == "chat" then
        QuestFocusDB.quietChat = not QuestFocusDB.quietChat
        Print(L["Chat messages: %s"], QuestFocusDB.quietChat and L["off (only the login line and command replies)"] or L["on"])
    elseif msg == "notes" or msg == "changelog" then
        if NS.OpenReleaseNotes then NS.OpenReleaseNotes() end
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
        -- korbe: ask -> on -> off -> ask
        local nextMode = ({ ask = "on", on = "off", off = "ask" })[NS.PingMode()] or "on"
        QuestFocusDB.pingMode = nextMode
        QuestFocusDB.noPing = (nextMode == "off") or nil
        if NS.RefreshPingUI then NS.RefreshPingUI() end
        Print(L["Ping in the AKit macro: %s"], nextMode == "ask" and L["ask when joining a group"]
            or nextMode == "on" and L["on"] or L["off"])
        state.lastBody = nil
        if state.questId then UpdateMacro() Panel_Update() end
    elseif msg == "icon" or msg:match("^icon%s") then
        local name = msg:match("^icon%s+(%S+)")
        -- egy ikon mindharom allapotra; allapotonkent: Options > Macro & marker > Macro icons
        if name then
            local id = IconId(name)
            if id == ICON_FALLBACK then
                Print(L["Icon not found: %s (e.g. ability_hunter_snipershot)"], name)
                return
            end
            for kind in pairs(NS.MacroIconDefaults) do NS.SetMacroIcon(kind, name, true) end
            Print(L["AKit icon (all states): |T%d:16|t %s"], id, name)
        else
            for kind in pairs(NS.MacroIconDefaults) do NS.SetMacroIcon(kind, nil, true) end
            Print(L["AKit icons: defaults (map / crosshair / letter at turn-in)"])
        end
    elseif msg == "unmark" then
        ClearWaypoint()
        Print(L["Marker removed."])
    elseif msg == "clear" then
        ClearQuest()
        Print(L["Selection cleared."])
    elseif msg == "selftest" then
        -- Core\SelfTest.lua: tiszta logikai ellenorzesek az elo adatokon
        if NS.SelfTest then NS.SelfTest() end
    else
        Print(L["Commands:"])
        Print(L["  /ak - toggle panel"])
        Print(L["  /ak options - settings (tag spell, auto attack, ping, arrow, debug tab)"])
        Print(L["  /ak zone - toggle zone focus (only current zone quests in the tracker)"])
        Print(L["  /ak minimap - toggle minimap button"])
        Print(L["  /ak bags - toggle quest item list next to the bags"])
        Print(L["  /ak junk - destroy unsellable leftover quest items (asks one by one)"])
        Print(L["  /ak debug - targeting diagnostics to chat; /ak debug <section> [on | off] - a section's snapshot / log"])
        Print(L["  /ak copy <section> | all - debug text to copy (Options > Debug)"])
        Print(L["    sections: %s"], NS.DebugKeyList())
        Print(L["  /ak spell <name> - tag spell in the macro; /ak spell - clear; /ak spell off - disable"])
        Print(L["  /ak next - next objective (marker + macro)"])
        Print(L["  /ak all - macro for mobs of all remaining objectives"])
        Print(L["  /ak mark - re-place the marker at the nearest spot"])
        Print(L["  /ak arrow - toggle own arrow"])
        Print(L["  /ak ping - toggle target ping in the macro"])
        Print(L["  /ak icon <iconname> - custom icon; /ak icon - automatic"])
        Print(L["  /ak unmark - remove marker"])
        Print(L["  /ak clear - clear selection + marker"])
        Print(L["  /ak city - open / close the city list (also outside towns)"])
        Print(L["  /ak dungeon - dungeon list; /ak dungeon <name> - dungeon prep (quests, then the entrance); /ak dungeon off - end it"])
        Print(L["  /ak farm - start / stop a farm session; /ak farm pause | resume | reset | show"])
        Print(L["  /ak chat - toggle chat messages; /ak notes - release notes"])
        Print(L["  /ak selftest - quick self test (Questie data, macro, settings, tables)"])
    end
end
-- a parancsok valasza mindig kikerul a chatre (akkor is, ha a chat uzenetek ki vannak kapcsolva)
SlashCmdList.QUESTFOCUS = function(msg) NS.Loud(SlashHandler, msg) end
