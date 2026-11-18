-- Minimal WoW API stub layer for the offline smoke tests (Lua 5.1).
-- Not a game emulator: frames are tables with no-op methods, the "world" is a few fake maps,
-- and everything the tests need to steer lives in the W table (returned by this file).
--
-- Rules of the fakes:
--   * Every widget (frame, texture, font string, tooltip, unknown global API table) is one
--     "Obj" type. Known methods behave sensibly (Show/Hide/IsShown, SetScript/GetScript,
--     SetText/GetText, sizes, RegisterEvent...). Unknown PascalCase keys give a callable child
--     Obj (so `cb.Text:SetText()` and `f:SomeSetter()` work); setters return self (chainable),
--     unknown Get*/Is*/Has*/Can* calls return nil. Lowercase unknown keys are plain nil fields.
--   * Unknown globals: PascalCase / C_* names give an auto-stub Obj and are recorded in
--     W.autoGlobals (the runner prints them, so a typo'd local shows up there).
--   * New globals written while addon code runs are recorded in W.newGlobals.

-- The game runs Lua 5.1; these two keep a newer interpreter usable (not the target, though)
unpack = unpack or table.unpack
loadstring = loadstring or load

local W = {
    time = 1000,
    player = {
        name = "Tester", realm = "Testrealm", class = "WARRIOR", level = 20, faction = "Alliance",
        map = 1429, x = 0.50, y = 0.55, resting = false, onTaxi = false, auras = {},
    },
    units = {},           -- token -> { name, hostile, dead, tapped, combat, guid }
    inCombat = false,
    inGroup = false, inRaid = false, groupSize = 1,
    cvars = { nameplateShowEnemies = "0" },
    macros = {},          -- name -> { name, icon, body }
    macroOrder = {},
    chat = {},            -- lines printed to DEFAULT_CHAT_FRAME
    log = {},             -- quest log: { title, header, qid, complete, level }
    bags = { [0] = { 16, 10 }, { 10, 5 }, { 10, 5 }, { 10, 5 }, { 10, 5 } }, -- bag -> { slots, free }
    durability = 1,
    instance = nil,       -- nil = outdoors, or { name, type, instanceID }
    errors = {},          -- Lua errors caught in event handlers / timers / OnUpdate
    autoGlobals = {},     -- unknown global name -> count
    newGlobals = {},      -- global name -> "file:line"
    frames = {},          -- every Obj created by CreateFrame
    timers = {},
    trackGlobals = false, -- the runner turns it on while addon files run
}

-- Fake maps: uiMap -> { name, continent, worldX0, worldY0, width (yd), height (yd), mapType, parent }
-- map coordinates 0..1 -> world yards: wx = x0 + x * w, wy = y0 + y * h
W.maps = {
    [1415] = { "Eastern Kingdoms", 0, 0, 0, 40000, 40000, 2, nil },
    [1414] = { "Kalimdor", 1, 0, 0, 40000, 40000, 2, nil },
    [1429] = { "Elwynn Forest", 0, 10000, 10000, 5000, 5000, 3, 1415 },
    [1436] = { "Westfall", 0, 5000, 15000, 5000, 5000, 3, 1415 },
    [1453] = { "Stormwind City", 0, 10000, 6000, 2000, 2000, 3, 1415 },
    [1455] = { "Ironforge", 0, 14000, 2000, 1500, 1500, 3, 1415 },
    [1413] = { "The Barrens", 1, 10000, 10000, 8000, 8000, 3, 1414 },
}
-- Questie area id -> uiMap
W.areaToMap = { [12] = 1429, [40] = 1436, [1519] = 1453, [1537] = 1455, [17] = 1413 }

local function now() return W.time end

local function report(where, err)
    W.errors[#W.errors + 1] = where .. ": " .. tostring(err)
end
W.report = report

local function safecall(where, fn, ...)
    local args, n = { ... }, select("#", ...)
    local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end, debug.traceback)
    if not ok then report(where, err) end
    return ok
end
W.safecall = safecall

---------------------------------------------------------------------------
-- Obj: the one widget / stub type
---------------------------------------------------------------------------
local Obj = {}
local ObjMT = {}
local function isGetter(k) return k:find("^Get") or k:find("^Is") or k:find("^Has") or k:find("^Can") or k:find("^Num") end

local function NewObj(kind, name, parent)
    local o = { __kind = kind or "Frame", __name = name, __parent = parent, __shown = true, __scripts = {},
        __events = {}, __w = 100, __h = 20, __text = nil, __checked = false, __value = 0 }
    return setmetatable(o, ObjMT)
end
W.NewObj = NewObj

ObjMT.__index = function(self, k)
    local m = Obj[k]
    if m ~= nil then return m end
    if type(k) == "string" and k:find("^[A-Z]") then
        -- unknown method or template child: a callable child Obj, cached on the object
        local child = NewObj("Auto", k, self)
        rawset(child, "__autoName", k)
        rawset(self, k, child)
        return child
    end
    return nil
end
-- Calling an auto child as a method: obj:Unknown(...) -> child(obj, ...)
ObjMT.__call = function(self, owner, ...)
    local n = rawget(self, "__autoName")
    if n and isGetter(n) then return nil end
    if type(owner) == "table" and getmetatable(owner) == ObjMT then return owner end
    return nil
end

local function fire(self, script, ...)
    local fn = self.__scripts[script]
    if fn then safecall((self.__name or self.__kind) .. ":" .. script, fn, self, ...) end
end
W.FireScript = fire

function Obj:SetScript(s, fn) self.__scripts[s] = fn; return self end
function Obj:GetScript(s) return self.__scripts[s] end
function Obj:HookScript(s, fn)
    local old = self.__scripts[s]
    self.__scripts[s] = function(...) if old then old(...) end; fn(...) end
    return self
end
function Obj:HasScript() return true end
function Obj:RegisterEvent(e) self.__events[e] = true; return self end
function Obj:RegisterUnitEvent(e) self.__events[e] = true; return self end
function Obj:UnregisterEvent(e) self.__events[e] = nil; return self end
function Obj:UnregisterAllEvents() self.__events = {}; return self end
function Obj:RegisterAllEvents() self.__allEvents = true; return self end
function Obj:IsEventRegistered(e) return self.__events[e] and true or false end
function Obj:Show() if not self.__shown then self.__shown = true; fire(self, "OnShow") end; return self end
function Obj:Hide() if self.__shown then self.__shown = false; fire(self, "OnHide") end; return self end
function Obj:SetShown(b) if b then self:Show() else self:Hide() end; return self end
function Obj:IsShown() return self.__shown end
function Obj:IsVisible()
    local o = self
    while o do
        if not rawget(o, "__shown") then return false end
        o = rawget(o, "__parent")
    end
    return true
end
function Obj:GetName() return self.__name end
function Obj:GetParent() return self.__parent end
function Obj:SetParent(p) self.__parent = p; return self end
function Obj:GetChildren() return end
function Obj:GetRegions() return end
function Obj:GetNumChildren() return 0 end
function Obj:GetNumRegions() return 0 end
function Obj:GetObjectType() return self.__kind end
function Obj:IsObjectType(t) return self.__kind == t end
function Obj:GetID() return self.__id or 0 end
function Obj:SetID(id) self.__id = id; return self end
function Obj:SetText(t) self.__text = t; return self end
function Obj:SetFormattedText(fmt, ...) self.__text = fmt:format(...); return self end
function Obj:GetText() return self.__text end
function Obj:GetStringWidth() return #(tostring(self.__text or "")) * 6 end
function Obj:GetUnboundedStringWidth() return #(tostring(self.__text or "")) * 6 end
function Obj:GetStringHeight() return 12 end
function Obj:GetNumLines() return 1 end
function Obj:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function Obj:GetFontObject() return NewObj("Font") end
function Obj:GetTextColor() return 1, 1, 1, 1 end
function Obj:SetWidth(w) self.__w = w; return self end
function Obj:SetHeight(h) self.__h = h; return self end
function Obj:SetSize(w, h) self.__w, self.__h = w, h or w; return self end
function Obj:GetWidth() return self.__w end
function Obj:GetHeight() return self.__h end
function Obj:GetSize() return self.__w, self.__h end
function Obj:GetLeft() return 100 end
function Obj:GetRight() return 100 + self.__w end
function Obj:GetTop() return 600 end
function Obj:GetBottom() return 600 - self.__h end
function Obj:GetCenter() return 100 + self.__w / 2, 600 - self.__h / 2 end
function Obj:GetRect() return 100, 600 - self.__h, self.__w, self.__h end
function Obj:GetScale() return 1 end
function Obj:GetEffectiveScale() return 1 end
function Obj:GetAlpha() return 1 end
function Obj:GetFrameLevel() return 1 end
function Obj:GetFrameStrata() return "MEDIUM" end
function Obj:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Obj:GetNumPoints() return 1 end
function Obj:SetChecked(b) self.__checked = b and true or false; return self end
function Obj:GetChecked() return self.__checked end
function Obj:SetValue(v) self.__value = v; return self end
function Obj:GetValue() return self.__value end
function Obj:GetMinMaxValues() return 0, 1 end
function Obj:GetVerticalScroll() return 0 end
function Obj:GetVerticalScrollRange() return 0 end
function Obj:GetHorizontalScroll() return 0 end
function Obj:GetScrollChild() return self.__scrollChild end
function Obj:SetScrollChild(c) self.__scrollChild = c; return self end
function Obj:GetNumber() return tonumber(self.__text) or 0 end
function Obj:HasFocus() return false end
function Obj:GetCursorPosition() return 0 end
function Obj:IsMouseOver() return false end
function Obj:IsMouseEnabled() return true end
function Obj:IsEnabled() return not self.__disabled end
function Obj:Enable() self.__disabled = false; return self end
function Obj:Disable() self.__disabled = true; return self end
function Obj:GetTexture() return self.__texture end
function Obj:SetTexture(t) self.__texture = t; return self end
function Obj:IsPlaying() return false end
function Obj:IsDragging() return false end
function Obj:IsMovable() return true end
function Obj:IsUserPlaced() return false end
function Obj:GetAttribute(k) return self.__attr and self.__attr[k] end
function Obj:SetAttribute(k, v) self.__attr = self.__attr or {}; self.__attr[k] = v; return self end
function Obj:Click(button) fire(self, "OnClick", button or "LeftButton", false); return self end
function Obj:IsForbidden() return false end
function Obj:IsProtected() return false end
function Obj:GetOwner() return self.__owner end
function Obj:IsOwned(o) return self.__owner == o end
function Obj:SetOwner(o) self.__owner = o; self.__lines = {}; return self end
function Obj:AddLine(t) self.__lines = self.__lines or {}; self.__lines[#self.__lines + 1] = t; return self end
function Obj:AddDoubleLine(a, b) return self:AddLine(tostring(a) .. " | " .. tostring(b)) end
function Obj:NumLines() return #(self.__lines or {}) end
function Obj:ClearLines() self.__lines = {}; return self end
function Obj:GetTop() return 600 end
local function region(self, kind) return NewObj(kind, nil, self) end
function Obj:CreateFontString() return region(self, "FontString") end
function Obj:CreateTexture() return region(self, "Texture") end
function Obj:CreateMaskTexture() return region(self, "MaskTexture") end
function Obj:CreateLine() return region(self, "Line") end
function Obj:CreateAnimationGroup() return region(self, "AnimationGroup") end
function Obj:CreateAnimation() return region(self, "Animation") end
-- the rest (SetPoint, ClearAllPoints, SetBackdrop, SetFont, SetTextColor, EnableMouse, ...)
-- falls through to the auto child: a chainable no-op

---------------------------------------------------------------------------
-- Globals
---------------------------------------------------------------------------
local G = _G
local function def(name, v) rawset(G, name, v) end

def("CreateFrame", function(kind, name, parent, template)
    local f = NewObj(kind or "Frame", name, parent)
    f.__template = template
    W.frames[#W.frames + 1] = f
    if name then rawset(G, name, f) end
    if kind == "GameTooltip" then f.__lines = {} end
    return f
end)

for _, n in ipairs({ "UIParent", "WorldFrame", "Minimap", "GameTooltip", "ItemRefTooltip", "UIErrorsFrame",
    "WorldMapFrame", "QuestLogFrame", "GossipFrame", "ChatFrame1", "SettingsPanel", "InterfaceOptionsFrame",
    "InterfaceOptionsFramePanelContainer", "ContainerFrame1", "PaperDollFrame", "QuestFrame", "MerchantFrame",
    "ChatFontNormal", "GameFontNormal", "GameFontNormalSmall", "GameFontHighlight", "GameFontHighlightSmall",
    "GameFontNormalLarge", "GameFontDisable", "GameFontDisableSmall", "ChatFontSmall", "NumberFontNormal" }) do
    def(n, NewObj("Frame", n))
end
G.WorldMapFrame.__shown = false
G.QuestLogFrame.__shown = false
def("DEFAULT_CHAT_FRAME", NewObj("Frame", "DEFAULT_CHAT_FRAME"))
function G.DEFAULT_CHAT_FRAME:AddMessage(msg) W.chat[#W.chat + 1] = tostring(msg) end

def("C_Timer", {
    After = function(sec, fn)
        W.timers[#W.timers + 1] = { at = now() + (tonumber(sec) or 0), fn = fn }
    end,
    NewTicker = function(sec, fn, iterations)
        local t = { cancelled = false }
        local left = iterations
        local function tick()
            if t.cancelled then return end
            fn(t)
            if left then left = left - 1; if left <= 0 then return end end
            W.timers[#W.timers + 1] = { at = now() + sec, fn = tick }
        end
        W.timers[#W.timers + 1] = { at = now() + sec, fn = tick }
        function t:Cancel() self.cancelled = true end
        function t:IsCancelled() return self.cancelled end
        return t
    end,
})
G.C_Timer.NewTimer = function(sec, fn) return G.C_Timer.NewTicker(sec, fn, 1) end

def("GetTime", now)
def("GetServerTime", function() return math.floor(now()) end)
def("time", os.time)
def("date", os.date)
def("debugstack", function() return debug.traceback() end)
def("wipe", function(t) for k in pairs(t) do t[k] = nil end return t end)
def("tinsert", table.insert)
def("tremove", table.remove)
def("strsplit", function(sep, s, limit)
    local out, start = {}, 1
    while true do
        if limit and #out == limit - 1 then out[#out + 1] = s:sub(start) break end
        local i, j = s:find(sep, start, true)
        if not i then out[#out + 1] = s:sub(start) break end
        out[#out + 1] = s:sub(start, i - 1)
        start = j + 1
    end
    return unpack(out)
end)
def("strtrim", function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end)
def("strjoin", function(sep, ...) return table.concat({ ... }, sep) end)
def("format", string.format)
def("strlower", string.lower)
def("strupper", string.upper)
def("strlen", string.len)
def("strsub", string.sub)
def("strfind", string.find)
def("strmatch", string.match)
def("gsub", string.gsub)
def("floor", math.floor)
def("ceil", math.ceil)
def("abs", math.abs)
def("min", math.min)
def("max", math.max)
def("sqrt", math.sqrt)
def("issecretvalue", nil)
def("print", function(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    W.chat[#W.chat + 1] = table.concat(t, " ")
end)

local errHandler = function(msg) report("geterrorhandler", msg) end
def("geterrorhandler", function() return errHandler end)
def("seterrorhandler", function(fn) errHandler = fn end)

def("hooksecurefunc", function(a, b, c)
    local tbl, name, hook = a, b, c
    if type(a) == "string" then tbl, name, hook = G, a, b end
    local orig = rawget(tbl, name) or tbl[name]
    local wrapped = function(...)
        local r = { n = 0 }
        if type(orig) == "function" or type(orig) == "table" then
            r = { n = select("#", ...), orig(...) }
        end
        hook(...)
        return unpack(r, 1, r.n)
    end
    rawset(tbl, name, wrapped)
end)

-- Locale / client
def("GetLocale", function() return "enUS" end)
def("GetBuildInfo", function() return "1.15.0", "1", "Nov 2026", 11500 end)
def("C_AddOns", { GetAddOnMetadata = function(addon, field)
    return W.metadata and W.metadata[addon] and W.metadata[addon][field]
end, IsAddOnLoaded = function(n) return W.loadedAddons and W.loadedAddons[n] or false end })
def("GetAddOnMetadata", G.C_AddOns.GetAddOnMetadata)
def("IsAddOnLoaded", G.C_AddOns.IsAddOnLoaded)
def("GetCVar", function(k) return W.cvars[k] end)
def("SetCVar", function(k, v) W.cvars[k] = tostring(v) end)
def("InCombatLockdown", function() return W.inCombat end)
def("ReloadUI", function() end)
def("PlaySound", function() end)
def("SOUNDKIT", { RAID_WARNING = 8959, IG_QUEST_LIST_OPEN = 875, IG_MAINMENU_OPTION_CHECKBOX_ON = 856 })
def("Enum", { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4 },
    ItemClass = { Consumable = 0, Weapon = 2, Armor = 4, Questitem = 12 } })
def("NUM_BAG_SLOTS", 4)
def("MAX_ACCOUNT_MACROS", 120)
def("SlashCmdList", {})
def("StaticPopupDialogs", {})
def("StaticPopup_Show", function() end)
def("StaticPopup_Hide", function() end)
def("UISpecialFrames", {})
def("LOCALIZED_CLASS_NAMES_MALE", setmetatable({}, { __index = function(_, k) return k end }))
def("RAID_CLASS_COLORS", setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff" } end }))
def("ITEM_SPELL_TRIGGER_ONUSE", "Use:")
def("CANCEL", "Cancel")
def("Settings", {
    RegisterCanvasLayoutCategory = function(frame, name) return { GetID = function() return name end, ID = name } end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
})
def("InterfaceOptions_AddCategory", function() end)
def("InterfaceOptionsFrame_OpenToCategory", function() end)
def("BackdropTemplateMixin", {})
def("CreateVector2D", function(x, y)
    local v = { x = x, y = y }
    function v:GetXY() return self.x, self.y end
    return v
end)
def("CreateFont", function(name) local f = NewObj("Font", name); if name then rawset(G, name, f) end; return f end)
def("IsShiftKeyDown", function() return false end)
def("IsControlKeyDown", function() return false end)
def("IsAltKeyDown", function() return false end)
def("GetCursorPosition", function() return W.cursorX or 0, W.cursorY or 0 end)
def("GetBindingKey", function() return nil end)
def("GetBindingText", function(k) return k end)
def("GetFileIDFromPath", function() return nil end)
def("ToggleWorldMap", function() end)
def("ShowUIPanel", function(f) if f and f.Show then f:Show() end end)
def("HideUIPanel", function(f) if f and f.Hide then f:Hide() end end)

-- Player / units
local function unit(tok)
    if tok == "player" then
        return { name = W.player.name, hostile = false, dead = false, guid = "Player-1-0001" }
    end
    return W.units[tok]
end
def("UnitName", function(u) local x = unit(u); if x then return x.name, nil end end)
def("UnitExists", function(u) return unit(u) ~= nil end)
def("UnitGUID", function(u) local x = unit(u); return x and (x.guid or ("Creature-0-0-0-0-" .. tostring(x.id or 1) .. "-0")) end)
def("UnitIsDead", function(u) local x = unit(u); return x and x.dead or false end)
def("UnitIsDeadOrGhost", function(u) local x = unit(u); return x and x.dead or false end)
def("UnitCanAttack", function(_, u) local x = unit(u); return x and x.hostile or false end)
def("UnitIsFriend", function(_, u) local x = unit(u); return x and not x.hostile or false end)
def("UnitIsTapDenied", function(u) local x = unit(u); return x and x.tapped or false end)
def("UnitIsUnit", function(a, b) local x, y = unit(a), unit(b); return x ~= nil and x == y end)
def("UnitAffectingCombat", function(u) local x = unit(u); return x and x.combat or false end)
def("UnitIsPlayer", function(u) return u == "player" end)
def("UnitHealth", function() return 100 end)
def("UnitHealthMax", function() return 100 end)
def("UnitLevel", function(u) if u == "player" then return W.player.level end return 10 end)
def("UnitXP", function(u) return u == "player" and (W.player.xp or 0) or 0 end)
def("UnitXPMax", function(u) return u == "player" and (W.player.xpMax or 1000) or 0 end)
def("GetMaxPlayerLevel", function() return 60 end)
def("GetMoney", function() return W.money or 0 end)
def("UnitClass", function() return W.player.class:sub(1, 1) .. W.player.class:sub(2):lower(), W.player.class, 1 end)
def("UnitRace", function() return "Human", "Human" end)
def("UnitFactionGroup", function() return W.player.faction, W.player.faction end)
def("UnitOnTaxi", function() return W.player.onTaxi end)
def("UnitIsGroupLeader", function() return false end)
def("UnitIsGroupAssistant", function() return false end)
def("GetUnitSpeed", function() return 0, 7, 7, 4.7 end)
def("GetPlayerFacing", function() return 0 end)
def("GetRealmName", function() return W.player.realm end)
def("IsResting", function() return W.player.resting end)
def("IsInGroup", function() return W.inGroup end)
def("IsInRaid", function() return W.inRaid end)
def("GetNumGroupMembers", function() return W.inGroup and W.groupSize or 0 end)
def("IsInInstance", function()
    if W.instance then return true, W.instance.type or "party" end
    return false, "none"
end)
def("GetInstanceInfo", function()
    local i = W.instance
    if i then return i.name, i.type or "party", 1, "Normal", 5, 0, false, i.instanceID or 36 end
    return "Eastern Kingdoms", "none", 0, "", 0, 0, false, 0
end)
def("GetRealZoneText", function() local m = W.maps[W.player.map]; return m and m[1] or "" end)
def("GetZoneText", G.GetRealZoneText)
def("GetMinimapZoneText", function() return "Goldshire" end)
def("GetBindLocation", function() return "Goldshire" end)
def("IsPlayerSpell", function() return false end)
def("IsSpellKnown", function() return false end)
def("GetRaidTargetIndex", function() return nil end)
def("SetRaidTarget", function() end)

-- Auras: W.player.auras = { { name, spellId, expires, count, source } } (noSource = true: sourceUnit nil)
local function auraAt(i)
    local a = W.player.auras[i]
    if not a then return end
    return a
end
def("C_UnitAuras", {
    GetAuraDataByIndex = function(u, i, filter)
        if u ~= "player" then return end
        local a = auraAt(i)
        if not a then return end
        return { name = a.name, spellId = a.spellId, expirationTime = a.expires or 0, duration = a.duration or 0,
            applications = a.count or 1, sourceUnit = (not a.noSource) and (a.source or "player") or nil, icon = 134400 }
    end,
    GetPlayerAuraBySpellID = function(id)
        for _, a in ipairs(W.player.auras) do
            if a.spellId == id then return { name = a.name, spellId = a.spellId, expirationTime = a.expires or 0 } end
        end
    end,
})
def("UnitAura", function(u, i)
    if u ~= "player" then return end
    local a = auraAt(i)
    if a then return a.name, 134400, a.count or 1, nil, a.duration or 0, a.expires or 0, (not a.noSource) and (a.source or "player") or nil,
        nil, nil, a.spellId end
end)
def("UnitBuff", G.UnitAura)

-- Map / world
local function worldPos(uiMap, x, y)
    local m = W.maps[uiMap]
    if not m then return end
    return m[2], m[3] + x * m[5], m[4] + y * m[6]
end
W.WorldPos = worldPos
def("C_Map", {
    GetBestMapForUnit = function(u) if u == "player" and not W.instance then return W.player.map end end,
    GetPlayerMapPosition = function(map, u)
        if u ~= "player" or map ~= W.player.map or W.instance then return end
        return G.CreateVector2D(W.player.x, W.player.y)
    end,
    GetWorldPosFromMapPos = function(uiMap, v)
        local c, wx, wy = worldPos(uiMap, v.x, v.y)
        if c then return c, G.CreateVector2D(wx, wy) end
    end,
    GetMapInfo = function(uiMap)
        local m = W.maps[uiMap]
        if m then return { mapID = uiMap, name = m[1], mapType = m[7], parentMapID = m[8] } end
    end,
    GetMapChildrenInfo = function() return {} end,
    CanSetUserWaypointOnMap = function() return true end,
    SetUserWaypoint = function(p) W.userWaypoint = p end,
    ClearUserWaypoint = function() W.userWaypoint = nil end,
    HasUserWaypoint = function() return W.userWaypoint ~= nil end,
})
def("UiMapPoint", { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, position = { x = x, y = y } } end })
def("C_SuperTrack", { SetSuperTrackedUserWaypoint = function() end })
def("C_TaxiMap", { GetAllTaxiNodes = function() return {} end })
def("C_NamePlate", { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end })

-- Quest log: W.log = { { title, header, qid, complete, level } }
def("GetNumQuestLogEntries", function()
    local n = 0
    for _, e in ipairs(W.log) do if not e.header then n = n + 1 end end
    return #W.log, n
end)
def("GetQuestLogTitle", function(i)
    local e = W.log[i]
    if not e then return end
    return e.title, e.level or 10, nil, e.header and true or false, false, e.complete and 1 or nil, 0, e.qid
end)
def("GetQuestLogIndexByID", function(qid)
    for i, e in ipairs(W.log) do if e.qid == qid then return i end end
    return 0
end)
def("GetQuestLogSelection", function() return W.logSel or 0 end)
def("SelectQuestLogEntry", function(i) W.logSel = i end)
def("GetQuestLogPushable", function() return true end)
def("QuestLogPushQuest", function() W.pushed = (W.pushed or 0) + 1 end)
def("IsQuestWatched", function() return false end)
def("AddQuestWatch", function() end)
def("RemoveQuestWatch", function() end)
def("ExpandQuestHeader", function() end)
def("CollapseQuestHeader", function() end)
def("QuestLog_SetSelection", function() end)
def("QuestLog_Update", function() end)
def("QuestLogTitleButton_OnClick", function() end)
def("ToggleQuestLog", function() end)
def("GetQuestDifficultyColor", function() return { r = 1, g = 1, b = 0 } end)
def("IsQuestFlaggedCompleted", function(qid) return W.completed and W.completed[qid] or false end)
def("C_QuestLog", {
    IsQuestFlaggedCompleted = G.IsQuestFlaggedCompleted,
    GetLogIndexForQuestID = function(qid) local i = G.GetQuestLogIndexByID(qid); return i > 0 and i or nil end,
    SetSelectedQuest = function() end,
    AddQuestWatch = function() end,
    RemoveQuestWatch = function() end,
    GetQuestWatchType = function() return nil end,
    GetQuestTagInfo = function() return nil end,
})

-- Macros
def("GetMacroIndexByName", function(name)
    for i, n in ipairs(W.macroOrder) do if n == name then return i end end
    return 0
end)
def("GetNumMacros", function() return #W.macroOrder, 0 end)
def("CreateMacro", function(name, icon, body)
    if W.inCombat then error("CreateMacro in combat (protected)") end
    W.macros[name] = { name = name, icon = icon, body = body }
    W.macroOrder[#W.macroOrder + 1] = name
    return #W.macroOrder
end)
def("EditMacro", function(idx, name, icon, body)
    if W.inCombat then error("EditMacro in combat (protected)") end
    local n = W.macroOrder[idx]
    if not n then error("EditMacro: bad index " .. tostring(idx)) end
    W.macros[n] = { name = name or n, icon = icon, body = body }
    return idx
end)

-- Bags / items / gear
local function bagInfo(bag) return W.bags[bag] end
def("C_Container", {
    GetContainerNumSlots = function(bag) local b = bagInfo(bag); return b and b[1] or 0 end,
    GetContainerNumFreeSlots = function(bag) local b = bagInfo(bag); return b and b[2] or 0, 0 end,
    GetContainerItemID = function() return nil end,
    GetContainerItemInfo = function() return nil end,
    GetContainerItemQuestInfo = function() return { isQuestItem = false } end,
    GetItemCooldown = function() return 0, 0, 1 end,
    PickupContainerItem = function() end,
})
def("GetContainerNumSlots", G.C_Container.GetContainerNumSlots)
def("GetContainerNumFreeSlots", G.C_Container.GetContainerNumFreeSlots)
def("GetItemCooldown", function() return 0, 0, 1 end)
def("GetInventoryItemDurability", function(slot)
    if slot == 1 or slot == 5 or slot == 16 then return math.floor(100 * W.durability), 100 end
end)
def("GetInventoryItemID", function() return nil end)
def("GetInventoryItemCount", function() return 0 end)
def("GetWeaponEnchantInfo", function() return false end)
def("C_Item", {
    GetItemCount = function(id) return W.items and W.items[id] or 0 end,
    -- W.itemInfo[id] = { name, sellPrice, bindType } overrides it; false = not cached yet (returns nil)
    GetItemInfo = function(id)
        local o = W.itemInfo and W.itemInfo[tonumber(id) or tonumber(tostring(id):match("item:(%d+)"))]
        if o == false then return nil end
        if o then
            return o[1], "|cffffffff|Hitem:" .. tostring(id) .. "|h[" .. o[1] .. "]|h|r", 1, 1, 1, "Trade Goods",
                "Trade Goods", 20, "", 134400, o[2], 7, 0, o[3] or 0
        end
        return "Item " .. tostring(id), nil, 1, 1, 1, "Consumable", "Food & Drink", 20, "", 134400
    end,
    GetItemInfoInstant = function(id) return id, "Consumable", "Food & Drink", "", 134400, 0, 5 end,
    GetItemIconByID = function() return 134400 end,
    GetItemSpell = function() return nil end,
})
def("GetItemCount", G.C_Item.GetItemCount)
def("GetItemInfo", G.C_Item.GetItemInfo)
def("GetItemInfoInstant", G.C_Item.GetItemInfoInstant)
def("GetItemIcon", G.C_Item.GetItemIconByID)
def("GetItemSpell", G.C_Item.GetItemSpell)
def("C_Spell", {
    GetSpellName = function(id) return "Spell " .. tostring(id) end,
    GetSpellTexture = function() return 134400 end,
    GetSpellInfo = function(id) return { name = "Spell " .. tostring(id), spellID = id, iconID = 134400 } end,
    GetSpellDescription = function() return "" end,
})
def("GetSpellInfo", function(id) return "Spell " .. tostring(id), nil, 134400 end)
def("GetSpellTexture", function() return 134400 end)
def("GetSpellDescription", function() return "" end)
def("C_Minimap", { GetNumTrackingTypes = function() return 0 end, GetTrackingInfo = function() return nil end })
def("GetTrackingTexture", function() return nil end)
def("C_TooltipInfo", { GetItemByID = function() return { lines = {} } end })
def("CursorHasItem", function() return false end)
def("GetCursorInfo", function() return nil end)
def("ClearCursor", function() end)

-- Auction house (classic "list" API). W.ahAll = every auction on the fake AH:
--   { name, count, buyout, owner, itemId }. QueryAuctionItems fills W.ahList (exact / substring
--   match on name, 50 per page) and records the call in W.ahQueries; the test fires
--   AUCTION_ITEM_LIST_UPDATE itself. PlaceAuctionBid records W.ahBids and removes the auction.
W.ahAll, W.ahList, W.ahTotal, W.ahQueries, W.ahBids, W.ahCanQuery = {}, {}, 0, {}, {}, true
def("CanSendAuctionQuery", function() return W.ahCanQuery, false end)
def("QueryAuctionItems", function(text, minL, maxL, page, usable, quality, getAll, exact)
    W.ahQueries[#W.ahQueries + 1] = { text = text, page = page or 0, exact = exact }
    local hits = {}
    for _, a in ipairs(W.ahAll) do
        if (exact and a.name == text) or (not exact and a.name:lower():find((text or ""):lower(), 1, true)) then
            hits[#hits + 1] = a
        end
    end
    W.ahList, W.ahTotal = {}, #hits
    for i = (page or 0) * 50 + 1, math.min(#hits, ((page or 0) + 1) * 50) do W.ahList[#W.ahList + 1] = hits[i] end
end)
def("GetNumAuctionItems", function(kind) if kind == "list" then return #W.ahList, W.ahTotal end return 0, 0 end)
def("GetAuctionItemInfo", function(kind, i)
    local a = kind == "list" and W.ahList[i]
    if not a then return nil end
    return a.name, 134400, a.count, 1, true, 1, "", 1, 1, a.buyout, 0, nil, nil, a.owner, a.owner, 0, a.itemId, true
end)
def("GetAuctionItemLink", function(kind, i)
    local a = kind == "list" and W.ahList[i]
    return a and ("|cffffffff|Hitem:" .. a.itemId .. "::::::::|h[" .. a.name .. "]|h|r") or nil
end)
def("PlaceAuctionBid", function(kind, i, amount)
    local a = W.ahList[i]
    W.ahBids[#W.ahBids + 1] = { index = i, amount = amount, auction = a }
    if a then
        for k, x in ipairs(W.ahAll) do if x == a then table.remove(W.ahAll, k) break end end
        table.remove(W.ahList, i)
        W.money = (W.money or 0) - amount
    end
end)

-- optional addons that must stay absent unless a test installs them
def("TomTom", nil)
def("Bagnon", nil)
def("ForeverDungeonJournal", nil)

---------------------------------------------------------------------------
-- Strict-ish _G: unknown reads and new writes are recorded
---------------------------------------------------------------------------
local OPTIONAL_NIL = { TomTom = true, Bagnon = true, ForeverDungeonJournal = true, ForeverDungeonJournal_NS = true,
    issecretvalue = true,
    QuestieLoader = true, Questie = true, QuestFocusDB = true, QuestFocusNS = true, BagBrother = true,
    ElvUI = true, AdiBags = true, ArkInventory = true, C_PartyInfo = true }
setmetatable(G, {
    __index = function(_, k)
        if type(k) ~= "string" or OPTIONAL_NIL[k] then return nil end
        if k:find("^C_") or k:find("^[A-Z]") then
            W.autoGlobals[k] = (W.autoGlobals[k] or 0) + 1
            local o = NewObj("Auto", k)
            rawset(o, "__autoName", k)
            return o -- not cached: each read is counted
        end
        return nil
    end,
    __newindex = function(t, k, v)
        if W.trackGlobals and W.newGlobals[k] == nil then
            local info = debug.getinfo(2, "Sl")
            W.newGlobals[k] = info and (tostring(info.short_src) .. ":" .. tostring(info.currentline)) or "?"
        end
        rawset(t, k, v)
    end,
})

---------------------------------------------------------------------------
-- Driving the fake game
---------------------------------------------------------------------------
-- Fire an event at every frame that registered it.
function W.Fire(event, ...)
    for _, f in ipairs(W.frames) do
        if (f.__events[event] or f.__allEvents) and f.__scripts.OnEvent then
            safecall("OnEvent " .. event .. " (" .. tostring(f.__name or "frame") .. ")", f.__scripts.OnEvent, f, event, ...)
        end
    end
end

-- Advance the clock: due C_Timer callbacks run, OnUpdate runs on visible frames.
function W.Advance(seconds, step)
    step = step or 0.5
    local target = W.time + seconds
    while W.time < target do
        local dt = math.min(step, target - W.time)
        W.time = W.time + dt
        local due, keep = {}, {}
        for _, t in ipairs(W.timers) do
            if t.at <= W.time then due[#due + 1] = t else keep[#keep + 1] = t end
        end
        W.timers = keep
        table.sort(due, function(a, b) return a.at < b.at end)
        for _, t in ipairs(due) do safecall("C_Timer", t.fn) end
        local list = {}
        for _, f in ipairs(W.frames) do list[#list + 1] = f end
        for _, f in ipairs(list) do
            if f.__scripts.OnUpdate and f:IsVisible() then
                safecall("OnUpdate (" .. tostring(f.__name or f.__kind) .. ")", f.__scripts.OnUpdate, f, dt)
            end
        end
    end
end

-- Put the player somewhere: map + 0..1 coordinates
function W.MovePlayer(map, x, y)
    W.player.map, W.player.x, W.player.y = map, x, y
end
-- Player position at a given distance (yd) east of a map point
function W.PlaceNear(map, x, y, yd)
    local m = W.maps[map]
    W.MovePlayer(map, x + yd / m[5], y)
end

return W
