local ADDON_NAME, NS = ...
local L = NS.L
NS.C = NS.C or {}
local C = NS.C
local FindNearest, ICON_HUNT, ICON_IDLE, ICON_TURNIN, ItemSourceLines, PlayerWorldPos, Print, QuestieAvailable = C.FindNearest, C.ICON_HUNT, C.ICON_IDLE, C.ICON_TURNIN, C.ItemSourceLines, C.PlayerWorldPos, C.Print, C.QuestieAvailable
local state, ZoneName = C.state, C.ZoneName

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

-- Fejlec: legfelul ikonsor (options, dungeon, fokusz torles, X), alatta ikon + cim + alcim.
-- HEAD: ennyivel csuszik lejjebb minden az ikonsor miatt.
local HEAD = 16
local iconFrame = CreateFrame("Frame", nil, panel, BackdropTemplateMixin and "BackdropTemplate" or nil)
iconFrame:SetSize(30, 30)
iconFrame:SetPoint("TOPLEFT", 11, -11 - HEAD)
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
panel.title:SetWidth(PANEL_W - 80) -- a vegen a fokusz torles gomb
panel.title:SetJustifyH("LEFT")
panel.title:SetWordWrap(false)
panel.title:SetTextColor(1, 0.86, 0.5)

panel.sub = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
panel.sub:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -3)
panel.sub:SetWidth(PANEL_W - 60)
panel.sub:SetJustifyH("LEFT")
panel.sub:SetWordWrap(false)

local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetSize(24, 24)
close:SetPoint("TOPRIGHT", -3, -3)
close:SetScript("OnClick", function()
    QuestFocusDB.hidePanel = true
    panel:Hide()
    Print(L["Panel hidden. It comes back when you click a quest, or: /qf"])
end)

-- Fokusz torlese: a kijelolt quest a logban marad, csak a kijeloles + marker + makro
-- celpontjai torlodnek (mint a /qf clear). Csak akkor latszik, ha van kijelolt quest.
local clearBtn = CreateFrame("Button", nil, panel)
clearBtn:SetSize(16, 16)
-- a quest cimsoranak vegen (az ikonsorban nem lenne egyertelmu, mit torol)
clearBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -11 - HEAD)
clearBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
clearBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
clearBtn:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
clearBtn:Hide()
clearBtn:SetScript("OnClick", function()
    if NS.C.ClearQuest then NS.C.ClearQuest() end
    NS.Loud(Print, L["Focus cleared (the quest stays in your log)."])
end)
clearBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(L["Clear focus"], 1, 1, 1)
    GameTooltip:AddLine(L["Unselects this quest: marker and macro targets are cleared, the quest stays in your log. Same as /qf clear."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
clearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
panel.clearBtn = clearBtn

-- Ikonsor gombjai (jobbrol balra, az X mellett): dungeon, options
local function ToolButton(icon, title, desc, onClick)
    local b = CreateFrame("Button", nil, panel)
    b:SetSize(16, 16)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexture(icon)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(type(desc) == "function" and desc() or desc, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end
local dungeonBtn = ToolButton("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", L["Dungeons"],
    function()
        return NS.HasDungeonJournal and NS.HasDungeonJournal()
            and L["Dungeons for your level and their quests; click one to open it in Dungeon Journal. Same as /qf dungeon."]
            or L["Dungeons for your level and their quests (click: marker on the quest giver). Same as /qf dungeon."]
    end,
    function() if NS.ToggleDungeonList then NS.ToggleDungeonList() end end)
local optBtn = ToolButton("Interface\\Icons\\INV_Misc_Gear_01", L["Options"],
    L["Opens the Adventurer's Kit options. Same as /qf options."],
    function() if NS.C.OpenOptions then NS.C.OpenOptions() end end)
panel.dungeonBtn, panel.optBtn = dungeonBtn, optBtn
-- az X gomb kepe kitolt a keretebol: tobb hely kell, kulonben osszeernek
dungeonBtn:SetPoint("RIGHT", close, "LEFT", -6, 0)
optBtn:SetPoint("RIGHT", dungeonBtn, "LEFT", -7, 0)

local function Divider(y)
    local t = panel:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", 12, y)
    t:SetPoint("TOPRIGHT", -12, y)
    t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
    return t
end
panel.headDivider = Divider(-48 - HEAD)

-- Statisztika dobozok: haladas / hatralevo ido / tempo
panel.stats = CreateFrame("Frame", nil, panel)
panel.stats:SetPoint("TOPLEFT", 12, -55 - HEAD)
panel.stats:SetPoint("TOPRIGHT", -12, -55 - HEAD)
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
panel.bar:SetPoint("TOPLEFT", 13, -99 - HEAD)
panel.bar:SetPoint("TOPRIGHT", -13, -99 - HEAD)
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
    panel.sub:SetWidth(w - 60)
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
    local y = (quest and -112 or -56) - HEAD
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

local function PanelSelectObjective(i) return NS.SelectObjective(i) end -- Core\Selection.lua

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
        if button == "RightButton" then PanelSelectObjective(nil) else PanelSelectObjective(self.index) end
    end)
    line:SetScript("OnEnter", function(self)
        local o = state.objectives and state.objectives[self.index]
        if not o then return end
        local TT = NS.TT
        local tt = TT.Begin(self, "ANCHOR_LEFT", state.title or "?", TT.Progress(state.objectives, state.isComplete))
        TT.Objective(tt, o, { sources = 6, highlight = state.objIndex == self.index })
        TT.Note(tt, not o.completed and NS.EtaLine and NS.EtaLine(o) or nil)
        TT.Finish(tt, L["Left click: marker + macro for this only"], L["Right click: macro for all remaining"])
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

local function SelectQuestRef(...) return NS.SelectQuest(...) end -- Core\Selection.lua

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
        if not (e and SelectQuestRef) then return end
        -- atvaltunk erre a questre, es rogton erre az objective-re (marker + nyil + makro)
        SelectQuestRef(e.qid, e.title, false, true)
        if state.questId == e.qid and state.objectives then
            for i, o in ipairs(state.objectives) do
                if o.desc == e.desc then PanelSelectObjective(i) break end
            end
        end
    end)
    r:SetScript("OnEnter", function(self)
        local e = self.extra
        if not e then return end
        local TT = NS.TT
        local tt = TT.Begin(self, "ANCHOR_LEFT", e.title or "?", L["also nearby"])
        TT.Objective(tt, e.obj)
        TT.Note(tt, NS.EtaLine and NS.EtaLine(e.obj) or nil)
        TT.Note(tt, L["The QFocus macro targets these mobs too."])
        TT.Finish(tt, L["Click: focus this quest and objective (marker + arrow + macro)"])
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
    clearBtn:SetShown(state.questId ~= nil)
    if not state.questId then
        -- Nincs kijelolt quest: javaslatok (QuestFocusPlanner.lua)
        for i = 1, #panel.lines do panel.lines[i]:Hide() end
        for i = 1, #panel.extraRows do panel.extraRows[i]:Hide() end
        panel.extraHeader:Hide()
        if panel.hsRow then panel.hsRow:Hide() end
        panel.icon:SetTexture("Interface\\Icons\\" .. NS.MacroIconName("idle"))
        if NS.ShowSuggestions and NS.ShowSuggestions() then panel:Show() else panel:Hide() end
        return
    end
    if NS.HideSuggestions then NS.HideSuggestions() end
    panel.title:SetText(state.title or ("Quest " .. state.questId))
    panel.icon:SetTexture("Interface\\Icons\\" .. NS.MacroIconName(state.isComplete and "turnin" or "hunt"))
    local objs = state.objectives or {}
    local y = PanelChrome("quest", L["OBJECTIVES"])
    -- a quest "hasznalando" iteme (QuestFocus_Bags) a kijelolt / elso nyitott objective soraba kerul
    local firstOpen = state.objIndex
    if not firstOpen then
        for i, o in ipairs(objs) do
            if not o.completed and not o.turnIn then firstOpen = i break end
        end
    end
    for i, o in ipairs(objs) do
        local line = GetLine(i)
        line.index = i
        line.useQid, line.useObj, line.useQuestItem = state.questId, o, (i == firstOpen)
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
        local seenQ = {}
        for i, e in ipairs(extras) do
            local r = GetExtraRow(i)
            r.extra = e
            r.useQid, r.useObj, r.useQuestItem = e.qid, e.obj, not seenQ[e.qid]
            seenQ[e.qid] = true
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
                local TT = NS.TT
                local tt = TT.Begin(self, "ANCHOR_LEFT", (L["Hearthstone: %s"]):format(self.hsName or "?"))
                TT.Sub(tt, L["Quests you could turn in there:"])
                for _, t in ipairs(self.hsList or {}) do
                    tt:AddLine("|TInterface\\GossipFrame\\ActiveQuestIcon:12:12|t " .. t, 1, 1, 1)
                end
                TT.Finish(tt)
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
    -- Leadas modban alul a kozeli felveheto questek (QuestFocusPlanner.lua)
    if state.isComplete and NS.ShowTurnInPickups then
        local ok, ny = pcall(NS.ShowTurnInPickups, y)
        if ok and ny then y = ny end
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


-- belso exportok a tobbi core fajlnak
NS.C.ApplyFontSize, NS.C.ApplyPanelWidth, NS.C.Panel_Update, NS.C.RestorePanelPos, NS.C.panel = ApplyFontSize, ApplyPanelWidth, Panel_Update, RestorePanelPos, panel
