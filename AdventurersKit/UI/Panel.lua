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
local function FontSize() return math.max(8, math.min(20, tonumber(QuestFocusDB and QuestFocusDB.fontSize) or 10)) end
-- Fix szelesseg a betumeretbol (10-es betunel PANEL_W); nem huzhato, hogy a sorok kiferjenek
local function PW() return math.max(240, math.min(600, math.floor(PANEL_W * FontSize() / 10 + 0.5))) end
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
panel.title:SetWidth(PANEL_W - 100) -- a vegen a terkep + fokusz torles gomb
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

-- Terkep: a fokuszalt quest celja a vilagterkepen (a fokusz torles elott)
local MAP_ICON = "Interface\\Icons\\INV_Misc_Map_01"
local function MapButton(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexture(MAP_ICON)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end
-- Elozo / kovetkezo quest nyilak (Planner\QuestNav.lua) a quest neve utan, a terkep elott
local function NavButton(dir)
    local b = CreateFrame("Button", nil, panel)
    b:SetSize(18, 18)
    local base = "Interface\\Buttons\\UI-SpellbookIcon-" .. (dir == "next" and "NextPage" or "PrevPage")
    b:SetNormalTexture(base .. "-Up")
    b:SetPushedTexture(base .. "-Down")
    b:SetDisabledTexture(base .. "-Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", function()
        local fn = dir == "next" and NS.NextQuest or NS.PrevQuest
        if fn then fn() end
    end)
    b:SetScript("OnEnter", function(self) if NS.QuestNavTooltip then NS.QuestNavTooltip(self, dir) end end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end
local prevBtn, nextBtn = NavButton("prev"), NavButton("next")
prevBtn:SetPoint("LEFT", panel.title, "RIGHT", 4, 0)
nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 0, 0)
panel.prevBtn, panel.nextBtn = prevBtn, nextBtn
local mapBtn = MapButton(panel, 15)
mapBtn:SetPoint("LEFT", nextBtn, "RIGHT", 4, 0)
mapBtn:Hide()
-- a fokusz torles a terkep gomb utan, kozvetlenul a quest neve vegen
clearBtn:ClearAllPoints()
clearBtn:SetPoint("LEFT", mapBtn, "RIGHT", 4, 0)
mapBtn:SetScript("OnClick", function() if NS.ShowObjectiveOnMap then NS.ShowObjectiveOnMap(state.objIndex) end end)
mapBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(L["Show on map"], 1, 1, 1)
    GameTooltip:AddLine(L["Opens the world map on the quest's target (the selected objective, or the remaining ones) and puts the marker there."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
panel.mapBtn = mapBtn
clearBtn:HookScript("OnShow", function() mapBtn:Show(); prevBtn:Show(); nextBtn:Show() end)
clearBtn:HookScript("OnHide", function() mapBtn:Hide(); prevBtn:Hide(); nextBtn:Hide() end)

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
    panel.title:SetWidth(w - 100)
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
-- Atmeretezes (csak javaslat modban): a panel magassagat allitja (QuestFocusDB.panelH), a
-- szelesseg fix (betumeretbol). Quest modban a panel merete fix, ott a fogantyu nem latszik.
-- Jobb klikk: alapmeret.
grip:RegisterForClicks("RightButtonUp")
grip:SetScript("OnClick", function()
    QuestFocusDB.panelW, QuestFocusDB.panelH, QuestFocusDB.questPanelH = nil, nil, nil
    ApplyPanelWidth()
    if NS.Panel_Update then NS.Panel_Update() end
end)
grip:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    AnchorTopLeft()
    local _, y = GetCursorPosition()
    self.drag = { y = y, h = panel:GetHeight() }
    self:SetScript("OnUpdate", function()
        local _, cy = GetCursorPosition()
        local h = self.drag.h + (self.drag.y - cy) / panel:GetEffectiveScale()
        h = math.floor(math.max(120, math.min(900, h)))
        QuestFocusDB.panelH = h
        panel:SetHeight(h)
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

-- Quest modban a panel magassaga fix (a betumeretbol): fejlec + statisztika + 11 sornyi
-- tartalom (pl. 5 objective + 3 kozeli quest + 3 utvonal) + ket szekciofejlec + lablec.
-- Igy a panel alja sosem mozdul; a tartalom ebben osztozik (Panel_Update).
local function QuestH()
    local rh = RowH()
    return 112 + HEAD + 15 + 11 * (rh + 1) + 2 * 19 + 4 + (8 + rh + 12)
end

-- Tartalom utan: elvalaszto + lablec, panel magassag
-- isList: javaslat mod, ott a felhasznalo altal huzott magassag is szamit (tobb sor fer ki);
-- quest modban a magassag fix (QuestH), a fogantyu nem latszik.
local function PanelFinish(y, isList)
    -- A panel teteje maradjon a helyen (ne a kozepe korul nojon/zsugorodjon)
    AnchorTopLeft()
    -- a meretezo fogantyu mindig a tartalom (sorok, gorgetheto lista) folott legyen
    grip:SetFrameLevel(panel:GetFrameLevel() + 20)
    grip:SetShown(isList and true or false)
    local fh = RowH()
    local h = -y + 8 + fh + 12
    if isList and tonumber(QuestFocusDB.panelH) then h = math.max(h, QuestFocusDB.panelH) end
    if not isList and state.questId then h = QuestH() end
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
    if state.escort and not state.isComplete and NS.Escort then
        local t = NS.Escort.FooterText()
        if t then return t .. (distTxt and (" - " .. distTxt) or "") end
    end
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
    -- escort sor (eletero) eloben
    if panel.escortRow and panel.escortRow:IsShown() and NS.Escort then
        local t = NS.Escort.RowText()
        if t then panel.escortRow.text:SetText(t) end
    end
end)

local function PanelSelectObjective(i) return NS.SelectObjective(i) end -- Core\Selection.lua

-- Vekony gorgetosav egy ScrollFrame jobb szelen (arany savon huzhato "thumb", a lathato resz
-- aranyaban). Csak akkor latszik, ha a tartalom nem fer ki. onScroll: gorgetes utan (sorok
-- elrejtese). Visszaadja a sav frame-et; bar.Update() a tartalom / gorgetes valtozasakor.
local function AttachScrollBar(sc, onScroll)
    local bar = CreateFrame("Frame", nil, sc:GetParent())
    bar:SetWidth(8)
    bar:SetPoint("TOPLEFT", sc, "TOPRIGHT", -2, 0)
    bar:SetPoint("BOTTOMLEFT", sc, "BOTTOMRIGHT", -2, 0)
    bar:SetFrameLevel(sc:GetFrameLevel() + 5)
    bar:EnableMouse(true)
    bar:EnableMouseWheel(true)
    bar:Hide()
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetWidth(2)
    track:SetPoint("TOP")
    track:SetPoint("BOTTOM")
    track:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.18)
    local thumb = CreateFrame("Button", nil, bar)
    thumb:SetWidth(8)
    thumb:SetFrameLevel(bar:GetFrameLevel() + 1)
    local tex = thumb:CreateTexture(nil, "ARTWORK")
    tex:SetWidth(3)
    tex:SetPoint("TOP")
    tex:SetPoint("BOTTOM")
    tex:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.75)
    local function Range()
        local child = sc:GetScrollChild()
        local contentH, viewH = child and child:GetHeight() or 0, sc:GetHeight()
        return contentH, viewH, math.max(0, contentH - viewH)
    end
    local function SetScroll(v)
        local _, _, maxS = Range()
        sc:SetVerticalScroll(math.max(0, math.min(maxS, v)))
        if onScroll then onScroll() end
        bar.Update()
    end
    bar.Update = function()
        local contentH, viewH, maxS = Range()
        if not sc:IsShown() or maxS < 0.5 then bar:Hide() return end
        bar:Show()
        local th = math.max(10, viewH * viewH / contentH)
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", bar, "TOP", 0, -(viewH - th) * math.min(1, sc:GetVerticalScroll() / maxS))
    end
    thumb:SetScript("OnEnter", function() tex:SetColorTexture(1, 0.86, 0.5, 1) end)
    thumb:SetScript("OnLeave", function() tex:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.75) end)
    thumb:SetScript("OnMouseDown", function(self)
        local _, cy = GetCursorPosition()
        local startY, startS = cy, sc:GetVerticalScroll()
        self:SetScript("OnUpdate", function()
            local _, y = GetCursorPosition()
            local _, viewH, maxS = Range()
            local free = viewH - self:GetHeight()
            if free <= 0 then return end
            SetScroll(startS + (startY - y) / self:GetEffectiveScale() * maxS / free)
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    -- kattintas a savon: oda ugrik (a thumb kozepe a kurzorhoz)
    bar:SetScript("OnMouseDown", function(self)
        local _, cy = GetCursorPosition()
        local top = self:GetTop()
        if not top then return end
        local _, viewH, maxS = Range()
        local free = viewH - thumb:GetHeight()
        if free <= 0 then return end
        local off = top - cy / self:GetEffectiveScale() - thumb:GetHeight() / 2
        SetScroll(off / free * maxS)
    end)
    bar:SetScript("OnMouseWheel", function(_, delta)
        local f = sc:GetScript("OnMouseWheel")
        if f then f(sc, delta) end
    end)
    sc:HookScript("OnHide", function() bar:Hide() end)
    sc:HookScript("OnShow", function() bar.Update() end)
    return bar
end
NS.AttachScrollBar = AttachScrollBar

-- Objective sorok: gorgetheto teruleten (ha sok az objective es nem fernek ki a fix magas
-- panelben). A ScrollFrame csak rajzolast vag, egeret nem: a lathato ablakon kivuli sorokat
-- elrejtjuk (a Bags item gombja is csak lathato sorra kerul).
panel.objScroll = CreateFrame("ScrollFrame", nil, panel)
panel.objChild = CreateFrame("Frame", nil, panel.objScroll)
panel.objChild:SetSize(10, 10)
panel.objScroll:SetScrollChild(panel.objChild)
panel.objScroll:EnableMouseWheel(true)
local function ClipObjLines()
    local sc, step = panel.objScroll, RowH() + 1
    local top, h = sc:GetVerticalScroll(), sc:GetHeight()
    for i, line in ipairs(panel.lines) do
        local y0 = (i - 1) * step
        line:SetShown(i <= (sc.qfCount or 0) and y0 + step > top + 0.5 and y0 < top + h - 0.5)
    end
    if sc.qfBar then sc.qfBar.Update() end
end
panel.objScroll.qfBar = AttachScrollBar(panel.objScroll, ClipObjLines)
panel.objScroll:SetScript("OnMouseWheel", function(self, delta)
    local step = RowH() + 1
    local max = math.max(0, (self.qfCount or 0) * step - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * step)))
    ClipObjLines()
end)

local function GetLine(i)
    local line = panel.lines[i]
    if line then return line end
    line = CreateFrame("Button", nil, panel.objChild)
    line:SetSize(PANEL_W - 24, 16)
    line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- gorgetes a soron is (ha az objective-ek nem fernek ki)
    line:EnableMouseWheel(true)
    line:SetScript("OnMouseWheel", function(_, delta) panel.objScroll:GetScript("OnMouseWheel")(panel.objScroll, delta) end)
    line.text = line:CreateFontString(nil, "OVERLAY", "QuestFocusFontSmall")
    -- a sor vegen terkep gomb: a szoveg nem fut ala (a Bags hasznalhato item gombja ez ele kerul)
    line.qfMapInset = 18
    line.text:SetPoint("TOPLEFT")
    line.text:SetPoint("BOTTOMRIGHT", -line.qfMapInset, 0)
    line.text:SetJustifyH("LEFT")
    line.text:SetWordWrap(false)
    local hl = line:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    line.mapBtn = MapButton(line, 14)
    line.mapBtn:SetPoint("RIGHT", line, "RIGHT", -1, 0)
    line.mapBtn:SetScript("OnClick", function(self)
        local idx = self:GetParent().index
        -- kijeloli is az objective-et (macro + panel), majd terkep
        if idx and state.objIndex ~= idx then PanelSelectObjective(idx) end
        if NS.ShowObjectiveOnMap then NS.ShowObjectiveOnMap(idx) end
    end)
    line.mapBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Show on map"], 1, 1, 1)
        GameTooltip:AddLine(L["Selects this objective and opens the world map on it."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
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
local ICON_ESC = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12:12|t "

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

-- "Also nearby": ennyi sor latszik, ha a lista hosszabb (plusz egy "+N tovabbi" sor)
local EXTRA_SHOW = 3
-- a "+N tovabbi" sor kulon gomb (nem az extraRows-ban, igy a Bags nem tesz ra item gombot)
local function GetExtraMoreRow()
    local r = panel.extraMore
    if r then return r end
    r = CreateFrame("Button", nil, panel)
    r:SetSize(PANEL_W - 24, 16)
    r.text = r:CreateFontString(nil, "OVERLAY", "QuestFocusFontSmall")
    r.text:SetPoint("TOPLEFT", 16, 0)
    r.text:SetPoint("BOTTOMRIGHT")
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["Also nearby"], 1, 0.86, 0.5)
        for _, e in ipairs(self.hidden or {}) do
            GameTooltip:AddLine(("|cffd8c8a0%s:|r %s"):format(e.title or "?", e.desc or "?"), 1, 1, 1)
        end
        GameTooltip:AddLine(L["The QFocus macro targets these mobs too."], 0.45, 0.45, 0.45, true)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.extraMore = r
    return r
end

-- Sorok rovidites: ha tobb szovegnek kozos az eleje egy " - " vagy ": " elvalasztoig
-- (pl. "Green Hills of Stranglethorn - Chapter I" / "... - Chapter II"), az elmarad
-- ("Chapter I", "Chapter II"). Egy szovegnel / kozos elotag nelkul valtozatlan.
local function ShortDescs(list)
    local out = {}
    for i, s in ipairs(list) do out[i] = s end
    if #list < 2 then return out end
    local p = list[1]
    for i = 2, #list do
        local s, n = list[i], 0
        local m = math.min(#p, #s)
        while n < m and p:byte(n + 1) == s:byte(n + 1) do n = n + 1 end
        p = p:sub(1, n)
    end
    local cut = 0
    for _, sep in ipairs({ " - ", ": " }) do
        local from = 1
        while true do
            local a, b = p:find(sep, from, true)
            if not a then break end
            if b > cut then cut = b end
            from = a + 1
        end
    end
    if cut < 6 then return out end
    for i, s in ipairs(list) do
        local r = s:sub(cut + 1)
        if r ~= "" then out[i] = r end
    end
    return out
end

-- Belepeskor a panel rejtve marad, amig a tartalma be nem all (kulonben a sorok egymas utan
-- "csusznak bele": objective-ek, kozeli questek, utvonal...). A Panel_Update kozben is
-- lefut (a magassag szamolodik), csak nem latszik. Feloldas: ha a belepeskori visszaallitas
-- megtortent (NS.loginRestored, Core\Events.lua) es a panel magassaga 1.5 mp-ig nem valtozott
-- (vagy 10 mp utan mindenkepp), illetve azonnal, ha te kattintasz egy questre.
local hold = true
local function ShowPanel()
    if hold then panel:Hide() else panel:Show() end
end
local function ReleasePanelHold()
    if not hold then return end
    hold = false
    if NS.C.Panel_Update then NS.C.Panel_Update() end
end
do
    local w = CreateFrame("Frame")
    local t, since, stable, lastH, wait = 0, 0, 0, nil, 0
    w:SetScript("OnUpdate", function(self, dt)
        if not hold then self:SetScript("OnUpdate", nil) return end
        t = t + dt
        if t < 0.5 then return end
        if not NS.loginRestored then t = 0 return end
        since = since + t
        t = 0
        -- a kozeli questek listaja (3 mp-es ticker) egyszer mar meglegyen
        local ready = not state.questId or state.extra ~= nil or QuestFocusDB.noNearbyQuests
        local h = math.floor(panel:GetHeight() + 0.5)
        if ready and h == lastH then stable = stable + 0.5 else stable = 0 end
        lastH = h
        if stable >= 1.5 or since >= 10 then
            self:SetScript("OnUpdate", nil)
            ReleasePanelHold()
        elseif ready and NS.C.Panel_Update then
            -- rejtve is ujrarendezzuk, hogy a magassag kovesse a tartalmat
            wait = wait + 1
            if wait % 2 == 0 then NS.C.Panel_Update() end
        end
    end)
end
NS.ReleasePanelHold = ReleasePanelHold

local function Panel_Update()
    if QuestFocusDB.hidePanel then
        panel:Hide()
        return
    end
    clearBtn:SetShown(state.questId ~= nil)
    -- cimsor: quest modban nincs ikon elol (a cim a bal szelen kezdodik), a terkep es a
    -- fokusz torles gomb a quest neve utan jon; javaslat modban ikon + cim, mint eddig
    panel.title:ClearAllPoints()
    if state.questId then
        iconFrame:Hide()
        panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -12 - HEAD)
    else
        iconFrame:Show()
        panel.title:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 8, -1)
        panel.title:SetWidth(PW() - 100)
    end
    if not state.questId then
        -- Nincs kijelolt quest: javaslatok (QuestFocusPlanner.lua)
        for i = 1, #panel.lines do panel.lines[i]:Hide() end
        panel.objScroll:Hide()
        for i = 1, #panel.extraRows do panel.extraRows[i]:Hide() end
        panel.extraHeader:Hide()
        if panel.extraMore then panel.extraMore:Hide() end
        if panel.hsRow then panel.hsRow:Hide() end
        if panel.escortRow then panel.escortRow:Hide() end
        panel.icon:SetTexture("Interface\\Icons\\" .. NS.MacroIconName("idle"))
        if NS.ShowSuggestions and NS.ShowSuggestions() then ShowPanel() else panel:Hide() end
        return
    end
    if NS.HideSuggestions then NS.HideSuggestions() end
    panel.title:SetText(state.title or ("Quest " .. state.questId))
    -- a cim csak olyan szeles, mint a szoveg (max. a panel - a gombok helye: elozo / kovetkezo
    -- nyil, terkep, fokusz torles), igy a gombok a nev vegere kerulnek
    panel.title:SetWidth(PW() - 28 - 84)
    panel.title:SetWidth(math.min(math.ceil(panel.title:GetStringWidth()) + 2, PW() - 28 - 84))
    if prevBtn.SetEnabled and NS.HasQuestHistory then prevBtn:SetEnabled(NS.HasQuestHistory()) end
    panel.icon:SetTexture("Interface\\Icons\\" .. NS.MacroIconName(state.isComplete and "turnin" or "hunt"))
    local objs = state.objectives or {}
    local y = PanelChrome("quest", L["OBJECTIVES"])
    local rh = RowH()
    local step = rh + 1 -- objective / kozeli quest sor
    -- Escort quest: kit kisersz, hova, eletero (Core\Escort.lua)
    local escTxt = state.escort and not state.isComplete and NS.Escort and NS.Escort.RowText()
    -- Hearthstone tipp: hany kesz quest adhato le ott, ahova a HS visz
    -- (leadas modban mar 1-tol, kulonben 2-tol mutatjuk)
    local hsList, hsName, hsCd
    if NS.HearthTurnIns then
        local ok, a, b, c = pcall(NS.HearthTurnIns)
        if ok then hsList, hsName, hsCd = a, b, c end
    end
    local hsShow = hsList and (#hsList >= 2 or state.isComplete)
    -- A kozelben levo tobbi quest (ha nem egy objective-re szukitettel)
    local extras = (state.objIndex == nil) and state.extra or nil
    local nE = extras and #extras or 0
    -- Utvonal (a quest log tobbi questje, Planner\Suggestions.lua), minden modban
    local routeN = 0
    if NS.PrepareTurnInRoute then
        local ok, n = pcall(NS.PrepareTurnInRoute)
        if ok and n then routeN = n end
    end

    -- Hely elosztasa a fix magas panelben (QuestH):
    --   - "Also nearby" es az utvonal legalabb 3-3 sort kap (ha van annyi)
    --   - az objective-ek a tobbit; ha igy sem fernek ki, gorgethetok (legalabb 3 latszik,
    --     ehhez kell a hely eloszor az utvonaltol, aztan a kozeli questektol vesszuk el)
    --   - az utvonal legfeljebb 3 sor (a tobbi gorgetheto); ami marad, a kozeli questeke
    local avail = QuestH() - (8 + rh + 12) - (-y) - (escTxt and (rh + 3) or 0) - (hsShow and (rh + 5) or 0)
        - (nE > 0 and 19 or 0) - (routeN > 0 and 19 or 0)
    local nbRows, rRows = math.min(nE, 3), math.min(routeN, 3)
    local oRows = #objs
    local rest = avail - nbRows * step - rRows * rh
    if oRows * step > rest then
        oRows = math.max(math.min(#objs, 3), math.floor(rest / step))
        local deficit = oRows * step - rest
        while deficit > 0 and rRows > 1 do rRows = rRows - 1; deficit = deficit - rh end
        while deficit > 0 and nbRows > 1 do nbRows = nbRows - 1; deficit = deficit - step end
    end
    rest = avail - oRows * step - nbRows * step - rRows * rh
    local function grow(cur, cap, cost)
        local add = math.max(0, math.min(cap - cur, math.floor(rest / cost)))
        rest = rest - add * cost
        return cur + add
    end
    nbRows = grow(nbRows, nE, step)

    -- Objective-ek (gorgetheto teruleten). A kozos elotag (pl. "Green Hills of Stranglethorn - ")
    -- lemarad, a teljes szoveg a tooltipben van.
    -- a quest "hasznalando" iteme (QuestFocus_Bags) a kijelolt / elso nyitott objective soraba kerul
    local firstOpen = state.objIndex
    if not firstOpen then
        for i, o in ipairs(objs) do
            if not o.completed and not o.turnIn then firstOpen = i break end
        end
    end
    local descs, idx = {}, {}
    for i, o in ipairs(objs) do
        if not o.turnIn then descs[#descs + 1] = o.desc or ""; idx[#descs] = i end
    end
    local short = {}
    for k, s in ipairs(ShortDescs(descs)) do short[idx[k]] = s end
    local w = PW() - 24
    for i, o in ipairs(objs) do
        local line = GetLine(i)
        line.index = i
        line.useQid, line.useObj, line.useQuestItem = state.questId, o, (i == firstOpen)
        line:SetSize(w, rh)
        local icon = o.completed and ICON_DONE or (o.turnIn and ICON_TI) or (o.escort and ICON_ESC)
            or (state.objIndex == i and ICON_SEL) or ICON_TODO
        local color = o.completed and "|cff808080" or (o.turnIn and "|cffffff00")
            or (state.objIndex == i and "|cff33ff99") or "|cffffffff"
        local eta = not o.completed and NS.EtaShort and NS.EtaShort(o)
        line.text:SetText(icon .. color .. (short[i] or o.desc or "?") .. "|r" .. (eta and ("  |cff999999" .. eta .. "|r") or ""))
        line.mapBtn:SetShown(not o.completed and o.sources ~= nil and #o.sources > 0)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", panel.objChild, "TOPLEFT", 0, -(i - 1) * step)
    end
    local sc = panel.objScroll
    sc.qfCount = #objs
    panel.objChild:SetSize(w, math.max(1, #objs * step))
    sc:ClearAllPoints()
    sc:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    sc:SetSize(w, math.max(1, oRows * step))
    local maxScroll = math.max(0, (#objs - oRows) * step)
    if sc:GetVerticalScroll() > maxScroll then sc:SetVerticalScroll(maxScroll) end
    sc:Show()
    ClipObjLines()
    y = y - oRows * step
    if escTxt then
        local r = panel.escortRow
        if not r then
            r = CreateFrame("Button", nil, panel)
            r:SetSize(PANEL_W - 24, 16)
            r.text = r:CreateFontString(nil, "OVERLAY", "QuestFocusFontSmall")
            r.text:SetAllPoints()
            r.text:SetJustifyH("LEFT")
            r.text:SetWordWrap(false)
            local hl = r:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.08)
            r:SetScript("OnClick", function()
                if NS.ShowObjectiveOnMap then NS.ShowObjectiveOnMap(nil) end
            end)
            r:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetText(state.title or "?", 1, 0.86, 0.5)
                if NS.Escort then NS.Escort.RowTooltip(GameTooltip) end
                GameTooltip:AddLine(L["Click: show the end point on the map"], 0.45, 0.45, 0.45)
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            panel.escortRow = r
        end
        r:SetSize(w, rh)
        r.text:SetText(escTxt)
        y = y - 2
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
        r:Show()
        y = y - rh - 1
    elseif panel.escortRow then
        panel.escortRow:Hide()
    end
    -- Also nearby: nbRows sor; ha nem fer ki mind, az utolso helyen "+N tovabbi" sor
    -- (a macro mindet targeteli). Egy quest sorainal a kozos elotag lemarad.
    local nExtra = 0
    local moreShown = false
    if nE > 0 then
        y = y - 4
        panel.extraHeader:ClearAllPoints()
        panel.extraHeader:SetPoint("TOPLEFT", 14, y)
        panel.extraHeader:Show()
        y = y - 15
        local byQ = {}
        for i, e in ipairs(extras) do
            local g = byQ[e.qid]
            if not g then g = { s = {}, i = {} }; byQ[e.qid] = g end
            g.s[#g.s + 1] = e.desc or "?"
            g.i[#g.s] = i
        end
        local eShort = {}
        for _, g in pairs(byQ) do
            for k, s in ipairs(ShortDescs(g.s)) do eShort[g.i[k]] = s end
        end
        local seenQ = {}
        local limit = nE > nbRows and math.max(0, nbRows - 1) or nE
        for i, e in ipairs(extras) do
            if i > limit then break end
            local r = GetExtraRow(i)
            r.extra = e
            r.useQid, r.useObj, r.useQuestItem = e.qid, e.obj, not seenQ[e.qid]
            seenQ[e.qid] = true
            r:SetSize(w, rh)
            local eta = NS.EtaShort and NS.EtaShort(e.obj)
            r.text:SetText(("|TInterface\\COMMON\\Indicator-Yellow:12:12|t |cffd8c8a0%s:|r %s%s"):format(
                e.title or "?", eShort[i] or e.desc or "?", eta and ("  |cff999999" .. eta .. "|r") or ""))
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
            r:Show()
            y = y - step
            nExtra = i
        end
        if nE > limit then
            local r = GetExtraMoreRow()
            r.hidden = {}
            for i = limit + 1, nE do r.hidden[#r.hidden + 1] = extras[i] end
            r:SetSize(w, rh)
            r.text:SetText(("|cff999999" .. L["+%d more (the macro targets them too)"] .. "|r"):format(#r.hidden))
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
            r:Show()
            y = y - step
            moreShown = true
        end
    else
        panel.extraHeader:Hide()
    end
    for i = nExtra + 1, #panel.extraRows do panel.extraRows[i]:Hide() end
    if not moreShown and panel.extraMore then panel.extraMore:Hide() end
    if hsShow then
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
        r:SetSize(w, rh)
        local cdTxt = (hsCd and hsCd > 0) and ("  |cff999999" .. L["HS cooldown"] .. " " .. math.ceil(hsCd / 60) .. "m|r") or ""
        r.text:SetText(("|TInterface\\Icons\\INV_Misc_Rune_01:12:12|t |cff33ff99" .. L["Hearth home: %d quests to turn in at %s"] .. "|r%s")
            :format(#hsList, hsName or "?", cdTxt))
        y = y - 4
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
        r:Show()
        y = y - step
    elseif panel.hsRow then
        panel.hsRow:Hide()
    end
    -- Utvonal (quest log): rRows sor latszik, a tobbi gorgetheto (Planner\Suggestions.lua)
    if routeN > 0 and NS.ShowTurnInPickups then
        local ok, ny = pcall(NS.ShowTurnInPickups, y, rRows, true)
        if ok and ny then y = ny end
    end
    if #objs == 0 then
        panel.footer:SetText(QuestieAvailable() and L["No objective data for this quest."] or L["Questie is not loaded."])
    else
        panel.footer:SetText(FooterText())
    end
    UpdateStats()
    PanelFinish(y)
    ShowPanel()
end


-- belso exportok a tobbi core fajlnak
NS.C.ApplyFontSize, NS.C.ApplyPanelWidth, NS.C.Panel_Update, NS.C.RestorePanelPos, NS.C.panel = ApplyFontSize, ApplyPanelWidth, Panel_Update, RestorePanelPos, panel
