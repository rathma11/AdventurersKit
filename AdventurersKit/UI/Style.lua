-- Adventurer's Kit: kozos UI stilus (DESIGN.md). Uj ablak / gomb / sor ezeket hasznalja, hogy
-- minden ugyanugy nezzen ki, mint a panel. Az ertekek a mar meglevo ablakokbol vannak
-- (Panel.lua, PingAsk.lua, Popup.lua, Buffs.lua, Farm.lua, City.lua) - ne talalj ki ujat.
-- A regi ablakok meg a sajat masolatukat hasznaljak; ha itt valtozik valami, ott is kell.
local ADDON_NAME, NS = ...

local S = {}
NS.Style = S

---------------------------------------------------------------------------
-- Paletta (r, g, b[, a]); a szoveg szinek kodja: "|cff" .. S.HEX.GOOD .. "szoveg|r"
---------------------------------------------------------------------------
S.GOLD = { 0.95, 0.78, 0.40 }            -- keret, elvalaszto, gorgetosav, lapos gomb szele
S.BG = { 0.04, 0.04, 0.06, 0.93 }        -- nagy ablak hattere (panel, city lista)
S.BOX_BG = { 0.04, 0.04, 0.06, 0.92 }    -- kis doboz / popup hattere (buff reminder, quest popup, farm)
S.ACCENT = { 1, 0.55, 0.25 }             -- 2px narancs csik balra (kis dobozok)
S.HEADER = { 1, 0.6, 0.3 }               -- kis nagybetus fejlec ("BUFF REMINDER", "QFOCUS PING")
S.TITLE = { 1, 0.86, 0.5 }               -- ablak cime (panel quest neve, city lista cime)
S.SECTION = { 0.75, 0.65, 0.45 }         -- szekcio fejlec ("OBJECTIVES", "ALSO NEARBY")
S.DESC = { 0.62, 0.62, 0.62 }            -- leiras (Options)
S.BTN_BG = { 0.08, 0.06, 0.03, 0.9 }     -- lapos gomb hattere
S.BTN_SEL = { 0.30, 0.22, 0.05, 0.9 }    -- valaszto kijelolt eleme
S.BTN_EDGE_A = 0.35                      -- lapos gomb 1px arany szele
S.BTN_HL = { 1, 0.82, 0, 0.15 }          -- lapos gomb / menusor hover
S.ROW_HL = { 1, 1, 1, 0.08 }             -- kattinthato sor hover
S.DIVIDER_A = 0.25                       -- elvalaszto vonal
S.SCROLL_TRACK_A, S.SCROLL_THUMB_A = 0.18, 0.75
-- dungeon valtozat (dungeon lista): voros-narancs keret es cim
S.DUNGEON_BORDER = { 0.95, 0.45, 0.30 }
S.DUNGEON_TITLE = { 1, 0.6, 0.45 }
S.HEX = {
    GOOD = "33ff99",   -- kesz, siker, "Target:"
    WARN = "ff9933",   -- figyelmeztetes, "paused"
    BAD = "ff4444",    -- hiba, hianyzik
    DIST = "99ccff",   -- tavolsag ("120 yd")
    NAME = "ffff00",   -- nev / parancs kiemelese chatben
    GOLD = "ffd100",   -- arany kiemeles
    DIM = "999999",    -- masodlagos ertek
    LABEL = "aaaaaa",  -- "cimke:" a farm dobozban
}
S.TEXCOORD = { 0.08, 0.92, 0.08, 0.92 } -- ikonok kerete levagva

---------------------------------------------------------------------------
-- Hatter + keret. kind: "window" (panel, city lista: dialog keret, edgeSize 20) vagy
-- "box" (popup, dialog, buff reminder: tooltip keret, edgeSize 12). Template kell hozza:
-- CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
---------------------------------------------------------------------------
function S.Backdrop(frame, kind, border)
    if not frame.SetBackdrop then return end
    local g = border or S.GOLD
    if kind == "box" then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame:SetBackdropColor(S.BOX_BG[1], S.BOX_BG[2], S.BOX_BG[3], S.BOX_BG[4])
        frame:SetBackdropBorderColor(g[1], g[2], g[3], 0.9)
    else
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 16, edgeSize = 20,
            insets = { left = 5, right = 5, top = 5, bottom = 5 },
        })
        frame:SetBackdropColor(S.BG[1], S.BG[2], S.BG[3], S.BG[4])
        frame:SetBackdropBorderColor(g[1], g[2], g[3], 1)
    end
end

-- 2px szines csik a bal szelen ("box" keretben). color: alap narancs (S.ACCENT)
function S.Accent(frame, color)
    local c = color or S.ACCENT
    local t = frame:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", 4, -4)
    t:SetPoint("BOTTOMLEFT", 4, 4)
    t:SetWidth(2)
    t:SetColorTexture(c[1], c[2], c[3], 1)
    return t
end

-- Kis nagybetus fejlec bal felul (a szoveg mar nagybetuvel: L["BUFF REMINDER"])
function S.Header(frame, text, color)
    local c = color or S.HEADER
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", 12, -8)
    fs:SetTextColor(c[1], c[2], c[3])
    if text then fs:SetText(text) end
    return fs
end

-- Szekcio fejlec a tartalomban ("OBJECTIVES", "ALSO NEARBY"); a hivo helyezi el
function S.Section(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetTextColor(S.SECTION[1], S.SECTION[2], S.SECTION[3])
    fs:SetJustifyH("LEFT")
    if text then fs:SetText(text) end
    return fs
end

-- Bezaro X. big: nagy ablak (24px, -4,-4), kulonben kis doboz (20px, -2,-2)
function S.CloseButton(frame, big)
    local b = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    if big then
        b:SetSize(24, 24)
        b:SetPoint("TOPRIGHT", -4, -4)
    else
        b:SetSize(20, 20)
        b:SetPoint("TOPRIGHT", -2, -2)
    end
    return b
end

-- Lapos gomb: sotet hatter, 1px arany szel (0.35), hoverre arany fenyes. Ugyanaz, mint NS.FlatButton.
function S.FlatButton(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 100, h or 22)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(S.BTN_BG[1], S.BTN_BG[2], S.BTN_BG[3], S.BTN_BG[4])
    local g = S.GOLD
    local function edge(p1, p2, ww, hh)
        local t = b:CreateTexture(nil, "BORDER")
        t:SetColorTexture(g[1], g[2], g[3], S.BTN_EDGE_A)
        t:SetPoint(p1); t:SetPoint(p2)
        if ww then t:SetWidth(ww) else t:SetHeight(hh) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1); edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1); edge("TOPRIGHT", "BOTTOMRIGHT", 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(S.BTN_HL[1], S.BTN_HL[2], S.BTN_HL[3], S.BTN_HL[4])
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(text or "")
    return b
end

-- Tagolt valaszto (egyszerre egy, mint a ping ablak "Ask / Always / Never" sora).
-- items = { { value, label }, ... }. seg:Select(value); seg.onSelect(value) kattintaskor.
function S.Segmented(parent, items, w, h, gap)
    local seg = { buttons = {} }
    w, h, gap = w or 90, h or 18, gap or 3
    function seg:Select(value)
        self.value = value
        for _, b in ipairs(self.buttons) do
            local on = b.value == value
            local c = on and S.BTN_SEL or S.BTN_BG
            b.bg:SetColorTexture(c[1], c[2], c[3], c[4])
            b.text:SetFontObject(on and "GameFontHighlightSmall" or "GameFontDisableSmall")
        end
    end
    for i, it in ipairs(items) do
        local b = S.FlatButton(parent, it[2], w, h)
        b.value = it[1]
        if i > 1 then b:SetPoint("LEFT", seg.buttons[i - 1], "RIGHT", gap, 0) end
        b:SetScript("OnClick", function(self)
            seg:Select(self.value)
            if seg.onSelect then seg.onSelect(self.value) end
        end)
        seg.buttons[i] = b
    end
    seg.first = seg.buttons[1] -- ezt kell elhelyezni, a tobbi utana jon
    return seg
end

-- Elvalaszto: 1px arany vonal; a hivo helyezi el (TOPLEFT 12 / TOPRIGHT -12)
function S.Divider(parent, alpha)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    t:SetColorTexture(S.GOLD[1], S.GOLD[2], S.GOLD[3], alpha or S.DIVIDER_A)
    return t
end

-- Kis piros kor gomb: torles / megszakitas / "ne figyeld tobbet" (16px, sorban 14px)
function S.ClearButton(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 16, size or 16)
    b:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    b:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
    b:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Ikon gomb (a panel jobb felso ikonsora): 16px, levagott ikon, negyzet hover, tooltip
function S.IconButton(parent, icon, title, desc, onClick, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 16, size or 16)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexture(icon)
    b.tex:SetTexCoord(S.TEXCOORD[1], S.TEXCOORD[2], S.TEXCOORD[3], S.TEXCOORD[4])
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    if onClick then b:SetScript("OnClick", onClick) end
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(type(title) == "function" and title() or title or "", 1, 1, 1)
        local d = type(desc) == "function" and desc() or desc
        if d then GameTooltip:AddLine(d, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Elozo / kovetkezo nyil (konyv lapozo), 18px. dir: "prev" vagy "next"
function S.ArrowButton(parent, dir)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    local base = "Interface\\Buttons\\UI-SpellbookIcon-" .. (dir == "next" and "NextPage" or "PrevPage")
    b:SetNormalTexture(base .. "-Up")
    b:SetPushedTexture(base .. "-Down")
    b:SetDisabledTexture(base .. "-Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Hover a kattinthato soron (HIGHLIGHT reteg: magatol jelenik meg)
function S.RowHighlight(row, color)
    local c = color or S.ROW_HL
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(c[1], c[2], c[3], c[4])
    return hl
end

-- Atmeretezo fogantyu a jobb also sarokban (a viselkedest a hivo adja: OnMouseDown / Up)
function S.ResizeGrip(frame)
    local g = CreateFrame("Button", nil, frame)
    g:SetSize(16, 16)
    g:SetPoint("BOTTOMRIGHT", -4, 4)
    g:SetFrameLevel(frame:GetFrameLevel() + 5)
    g:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    g:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    g:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    g:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return g
end

-- Huzhato ablak, a bal felso sarok mentve QuestFocusDB[key]-be ({ l, t }), kepernyon belul.
-- S.RestorePos(frame, key) betolteskor (QuestFocusDB csak ADDON_LOADED utan van).
function S.Draggable(frame, key)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local l, t = self:GetLeft(), self:GetTop()
        if l and t and key and QuestFocusDB then
            QuestFocusDB[key] = { l = math.floor(l + 0.5), t = math.floor(t + 0.5) }
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
        end
        if self.SetUserPlaced then pcall(self.SetUserPlaced, self, false) end
    end)
end

function S.RestorePos(frame, key)
    local p = QuestFocusDB and key and QuestFocusDB[key]
    if p and p.l and p.t then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.l, p.t)
        return true
    end
end

-- Vekony arany gorgetosav egy ScrollFrame-re (UI\Panel.lua: NS.AttachScrollBar)
function S.ScrollBar(scrollFrame, onScroll)
    return NS.AttachScrollBar and NS.AttachScrollBar(scrollFrame, onScroll)
end

-- Kis "box" ablak egy lepesben: hatter + narancs csik + fejlec + X. Visszaadja: frame
function S.Box(name, w, h, headerText, strata)
    local f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(w or 250, h or 40)
    f:SetFrameStrata(strata or "MEDIUM")
    f:Hide()
    S.Backdrop(f, "box")
    f.accent = S.Accent(f)
    f.header = S.Header(f, headerText)
    f.close = S.CloseButton(f)
    return f
end
