-- Farm session: ido, XP (+ /ora, ETA a szintig), lootolt arany, lootolt itemek erteke
-- (vendor ar, es "legjobb eladas" = max(AH ar, vendor ar), ha van aukcios addon).
-- Inditas / leallitas: a panel ikonsoraban az erme gomb, vagy /qf farm (start / stop / pause / reset).
-- A futo session karakterenkent mentve (NS.CharDB().farm): /reload es ujra belepes utan folytatodik.
-- Az eltelt idobe a kijelentkezett ido NEM szamit bele: masodpercenkent adjuk hozza a jatekban
-- toltott idot (GetTime kulonbseg), igy offline / betoltokepernyon toltott ido kimarad.
-- Lootolt arany: csak a CHAT_MSG_MONEY (felvett / csapatban elosztott penz); vendor eladas es quest
-- jutalom nem ilyen uzenet, azok csak a "Net gold change" sorban latszanak (GetMoney kulonbseg).
-- Lootolt item: csak a "You receive loot" uzenetek (LOOT_ITEM_SELF*), a vasarolt / quest jutalom
-- ("You receive item") nem.
local ADDON_NAME, NS = ...
local L = NS.L
local GetItemInfo = NS.SafeItem.GetItemInfo
local GetItemInfoInstant = NS.SafeItem.GetItemInfoInstant

local F = {}
NS.Farm = F

---------------------------------------------------------------------------
-- Tiszta segedfuggvenyek (tests\run.lua is hivja oket)
---------------------------------------------------------------------------
-- Formatum string (pl. "%d Gold", "You receive loot: %sx%d.") -> Lua minta: a %s / %d elkapva,
-- a tobbes szam jeloles (|4arany:aranyak;) barmilyen szo.
local function FormatToPattern(fmt)
    local out, i = {}, 1
    while i <= #fmt do
        local c = fmt:sub(i, i)
        local spec, len = fmt:match("^%%%d*%$?([sd])()", i)
        if spec then
            out[#out + 1] = spec == "s" and "(.+)" or "(%d+)"
            i = len
        elseif fmt:find("^|4[^;]*;", i) then
            local _, e = fmt:find("^|4[^;]*;", i)
            out[#out + 1] = "%S+"
            i = e + 1
        else
            out[#out + 1] = c:find("[%^%$%(%)%%%.%[%]%*%+%-%?]") and ("%" .. c) or c
            i = i + 1
        end
    end
    return table.concat(out)
end
F.FormatToPattern = FormatToPattern

local moneyPatterns
local function MoneyPatterns()
    if moneyPatterns then return moneyPatterns end
    moneyPatterns = {
        { FormatToPattern(rawget(_G, "GOLD_AMOUNT") or "%d Gold"), 10000 },
        { FormatToPattern(rawget(_G, "SILVER_AMOUNT") or "%d Silver"), 100 },
        { FormatToPattern(rawget(_G, "COPPER_AMOUNT") or "%d Copper"), 1 },
    }
    return moneyPatterns
end
-- "You loot 1 Gold, 2 Silver, 3 Copper" / "Your share of the loot is 5 Silver." -> rezben
function F.ParseMoney(msg)
    if type(msg) ~= "string" then return 0 end
    local total = 0
    for _, p in ipairs(MoneyPatterns()) do
        local n = msg:match(p[1])
        if n then total = total + tonumber(n) * p[2] end
    end
    return total
end

local lootPatterns
local function LootPatterns()
    if lootPatterns then return lootPatterns end
    lootPatterns = {}
    -- a tobbszoros elol, kulonben az egyszeres elnyelne az "x3"-at
    for _, k in ipairs({ { "LOOT_ITEM_SELF_MULTIPLE", "You receive loot: %sx%d." },
        { "LOOT_ITEM_SELF", "You receive loot: %s." } }) do
        lootPatterns[#lootPatterns + 1] = "^" .. FormatToPattern(rawget(_G, k[1]) or k[2]) .. "$"
    end
    return lootPatterns
end
-- sajat loot uzenet -> itemID, link, darab (mas uzenetre nil)
function F.ParseLoot(msg)
    if type(msg) ~= "string" then return end
    for _, p in ipairs(LootPatterns()) do
        local link, n = msg:match(p)
        if link then
            local id = tonumber(link:match("|Hitem:(%d+)") or link:match("item:(%d+)"))
            if id then return id, link, tonumber(n) or 1 end
        end
    end
end

-- rez -> "1g 02s 03c" (szines betukkel)
function F.FormatMoney(c, plain)
    c = math.floor((tonumber(c) or 0) + 0.5)
    local neg = c < 0
    if neg then c = -c end
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local G, S, C = "g", "s", "c"
    if not plain then G, S, C = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r" end
    local t
    if g > 0 then t = ("%d%s %02d%s %02d%s"):format(g, G, s, S, cp, C)
    elseif s > 0 then t = ("%d%s %02d%s"):format(s, S, cp, C)
    else t = ("%d%s"):format(cp, C) end
    return (neg and "-" or "") .. t
end

function F.FormatTime(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    local h, m, s = math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60
    if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
    return ("%d:%02d"):format(m, s)
end
local function FormatETA(sec)
    if not sec or sec ~= sec or sec == math.huge then return "?" end
    sec = math.floor(sec + 0.5)
    local h, m = math.floor(sec / 3600), math.floor(sec / 60) % 60
    if h > 0 then return ("%dh %02dm"):format(h, m) end
    return ("%dm"):format(math.max(1, m))
end
local function Num(n)
    n = math.floor((tonumber(n) or 0) + 0.5)
    local s = tostring(math.abs(n))
    s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (n < 0 and "-" or "") .. s
end
F.Num = Num

---------------------------------------------------------------------------
-- Aukcios ar (opcionalis: Auctionator, TSM, Auctioneer; mind pcall-lal)
---------------------------------------------------------------------------
local function AHPrice(id, link)
    local A = rawget(_G, "Auctionator")
    if type(A) == "table" and A.API and A.API.v1 and A.API.v1.GetAuctionPriceByItemID then
        local ok, v = pcall(A.API.v1.GetAuctionPriceByItemID, ADDON_NAME, id)
        if ok and tonumber(v) and tonumber(v) > 0 then return tonumber(v), "Auctionator" end
    end
    local T = rawget(_G, "TSM_API")
    if type(T) == "table" and T.GetCustomPriceValue then
        local ok, v = pcall(T.GetCustomPriceValue, "dbmarket", "i:" .. id)
        if ok and tonumber(v) and tonumber(v) > 0 then return tonumber(v), "TSM" end
    end
    local Auc = rawget(_G, "AucAdvanced")
    if type(Auc) == "table" and Auc.API and Auc.API.GetMarketValue and link then
        local ok, v = pcall(Auc.API.GetMarketValue, link)
        if ok and tonumber(v) and tonumber(v) > 0 then return tonumber(v), "Auctioneer" end
    end
end
F.AHPrice = AHPrice
-- van-e aukcios addon (a "Best sale" sor csak ekkor latszik)
function F.AHSource()
    local A = rawget(_G, "Auctionator")
    if type(A) == "table" and A.API and A.API.v1 then return "Auctionator" end
    local T = rawget(_G, "TSM_API")
    if type(T) == "table" and T.GetCustomPriceValue then return "TSM" end
    local Auc = rawget(_G, "AucAdvanced")
    if type(Auc) == "table" and Auc.API then return "Auctioneer" end
end

---------------------------------------------------------------------------
-- Session adatok
---------------------------------------------------------------------------
local function DB()
    local c = NS.CharDB()
    return rawget(c, "farm")
end

local pendingInfo = {} -- itemID -> true: GetItemInfo meg nem adott sellPrice-t

-- sellPrice (11.) es bindType (14.) bekerese; nil = meg nem tolt be
local function ItemPrice(rec, id)
    if rec.sell ~= nil then return rec.sell end
    local name, link, _, _, _, _, _, _, _, _, sell, _, _, bind = GetItemInfo(id)
    if not name then pendingInfo[id] = true return nil end
    rec.sell = tonumber(sell) or 0
    rec.bop = (bind == 1) or nil
    rec.name = name
    if link then rec.link = link end
    pendingInfo[id] = nil
    return rec.sell
end

-- Egy item ertekei: vendor (darab * sellPrice), legjobb (darab * max(AH, vendor)); a nem
-- eladhato (sellPrice 0) 0, a BoP nem mehet AH-ra.
local function ItemValue(rec, id)
    local sell = ItemPrice(rec, id)
    if sell == nil then return nil end
    local n = rec.n or 0
    if sell <= 0 then return 0, 0 end
    local best = sell
    if not rec.bop then
        local ah = AHPrice(id, rec.link)
        if ah and ah > best then best = ah end
    end
    return n * sell, n * best
end

-- Osszesites: idot, XP-t, penzt, erteket es oras rataikat egy tablaba
function F.Totals(fd, now)
    fd = fd or DB()
    if not fd then return nil end
    local t = { elapsed = fd.elapsed or 0, xp = fd.xp or 0, money = fd.money or 0,
        vendor = 0, best = 0, pending = 0, items = {} }
    for id, rec in pairs(fd.items or {}) do
        local v, b = ItemValue(rec, id)
        if v == nil then
            t.pending = t.pending + 1
        else
            t.vendor, t.best = t.vendor + v, t.best + b
            t.items[#t.items + 1] = { id = id, n = rec.n, link = rec.link or rec.name or ("item:" .. id), vendor = v, best = b }
        end
    end
    table.sort(t.items, function(a, b)
        if a.best ~= b.best then return a.best > b.best end
        return a.id < b.id
    end)
    local h = t.elapsed / 3600
    if t.elapsed >= 60 then
        t.xpH = t.xp / h
        t.goldH = (t.money + t.vendor) / h
        t.bestH = (t.money + t.best) / h
    end
    local lvl = UnitLevel("player") or 1
    local maxLvl = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    if lvl < maxLvl then
        t.need = math.max(0, (UnitXPMax("player") or 0) - (UnitXP("player") or 0))
        if t.xpH and t.xpH > 0 then t.eta = t.need / t.xpH * 3600 end
    end
    if fd.moneyStart then t.net = (GetMoney() or 0) - fd.moneyStart end
    return t
end

function F.IsRunning() local fd = DB() return fd and fd.running or false end
function F.IsPaused() local fd = DB() return fd and fd.running and fd.paused or false end

local lastTick -- GetTime() az utolso idohozzaadaskor (nem mentjuk: belepeskor ujraindul)
local function Accumulate()
    local fd = DB()
    local now = GetTime()
    if fd and fd.running and not fd.paused and lastTick then
        local d = now - lastTick
        -- nagy ugras (pl. betoltes alatt megallt a kliens): legfeljebb 5 mp szamit
        if d > 0 then fd.elapsed = (fd.elapsed or 0) + math.min(d, 5) end
    end
    lastTick = now
end
F.Accumulate = Accumulate

local function BaselineXP(fd)
    fd.lastXP, fd.lastMax, fd.lastLevel = UnitXP("player") or 0, UnitXPMax("player") or 0, UnitLevel("player") or 1
end

-- XP valtozas; szintlepesnel (akar elobb jon az XP esemeny, mint a szint) az elozo szint maradeka + az uj XP
function F.OnXP()
    local fd = DB()
    if not (fd and fd.running) then return end
    local cur, max, lvl = UnitXP("player") or 0, UnitXPMax("player") or 0, UnitLevel("player") or 1
    if fd.lastXP == nil then BaselineXP(fd) return end
    local d
    if lvl > (fd.lastLevel or lvl) then
        d = math.max(0, (fd.lastMax or 0) - fd.lastXP) + cur
        fd.lastLevel = lvl
    elseif cur < fd.lastXP then
        d = math.max(0, (fd.lastMax or 0) - fd.lastXP) + cur
        fd.lastLevel = lvl + 1 -- a szint meg nem frissult; a kovetkezo esemenyen mar ez lesz
    else
        d = cur - fd.lastXP
    end
    if not fd.paused and d > 0 then fd.xp = (fd.xp or 0) + d end
    fd.lastXP, fd.lastMax = cur, max
end

function F.OnMoneyMsg(msg)
    local fd = DB()
    if not (fd and fd.running) or fd.paused then return end
    local c = F.ParseMoney(msg)
    if c > 0 then fd.money = (fd.money or 0) + c end
end

function F.OnLootMsg(msg)
    local fd = DB()
    if not (fd and fd.running) or fd.paused then return end
    local id, link, n = F.ParseLoot(msg)
    if not id then return end
    fd.items = fd.items or {}
    local rec = fd.items[id]
    if not rec then rec = {}; fd.items[id] = rec end
    rec.n = (rec.n or 0) + n
    rec.link = rec.link or link
    ItemPrice(rec, id)
end

function F.OnItemInfo(id)
    id = tonumber(id)
    if not (id and pendingInfo[id]) then return end
    local fd = DB()
    local rec = fd and fd.items and fd.items[id]
    if rec then ItemPrice(rec, id) else pendingInfo[id] = nil end
end

---------------------------------------------------------------------------
-- Keret: kis doboz a panel / buff emlekezteto stilusaban
---------------------------------------------------------------------------
local GOLD = { 0.95, 0.78, 0.40 }
local box = CreateFrame("Frame", "QuestFocusFarmFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
F.frame = box
box:SetSize(210, 60)
box:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260, -200)
box:SetFrameStrata("MEDIUM")
box:SetMovable(true)
box:SetClampedToScreen(true)
box:EnableMouse(true)
box:RegisterForDrag("LeftButton")
box:Hide()
if box.SetBackdrop then
    box:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    box:SetBackdropColor(0.04, 0.04, 0.06, 0.92)
    box:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
end
box:SetScript("OnDragStart", function(self) self:StartMoving() end)
box:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local l, t = self:GetLeft(), self:GetTop()
    if l and t and QuestFocusDB then
        QuestFocusDB.farmPos = { l = math.floor(l + 0.5), t = math.floor(t + 0.5) }
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    end
    if self.SetUserPlaced then pcall(self.SetUserPlaced, self, false) end
end)
local function RestorePos()
    local p = QuestFocusDB and QuestFocusDB.farmPos
    if p and p.l and p.t then
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.l, p.t)
    end
end

box.header = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
box.header:SetPoint("TOPLEFT", 10, -9)
box.header:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

local function SmallButton(label, tip, onClick)
    local b = CreateFrame("Button", nil, box)
    b:SetSize(16, 14)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(type(tip) == "function" and tip() or tip, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end
box.stopBtn = SmallButton("|cffff6060x|r", L["Stop the farm session (summary in chat)"], function() NS.Loud(F.Stop) end)
box.stopBtn:SetPoint("TOPRIGHT", -6, -6)
box.pauseBtn = SmallButton("||", function() return F.IsPaused() and L["Resume"] or L["Pause"] end,
    function() F.TogglePause() end)
box.pauseBtn:SetPoint("RIGHT", box.stopBtn, "LEFT", -2, 0)

box.body = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
box.body:SetPoint("TOPLEFT", 10, -24)
box.body:SetJustifyH("LEFT")
box.body:SetWordWrap(false)
if box.body.SetSpacing then box.body:SetSpacing(2) end

local function Lines(t, fd)
    local out = {}
    local function add(label, value) out[#out + 1] = "|cffaaaaaa" .. label .. ":|r " .. value end
    add(L["Time"], F.FormatTime(t.elapsed) .. (fd.paused and ("  |cffff9933" .. L["paused"] .. "|r") or ""))
    add(L["XP"], Num(t.xp) .. (t.xpH and ("  |cff999999(" .. Num(t.xpH) .. L["/h"] .. ")|r") or ""))
    if t.need then
        add(L["To level"], Num(t.need) .. (t.eta and ("  |cff999999ETA " .. FormatETA(t.eta) .. "|r") or ""))
    end
    add(L["Looted gold"], F.FormatMoney(t.money))
    add(L["Items (vendor)"], F.FormatMoney(t.vendor) .. (t.pending > 0 and ("  |cff999999+" .. t.pending .. "?|r") or ""))
    local src = F.AHSource()
    if src then
        add(L["Best sale"], F.FormatMoney(t.money + t.best) .. "  |cff999999(" .. src .. ")|r")
    end
    add(L["Per hour"], t.goldH and (F.FormatMoney(t.goldH) .. (src and t.bestH and ("  |cff999999" .. L["best"] .. " "
        .. F.FormatMoney(t.bestH, true) .. "|r") or "")) or "-")
    if t.net then add(L["Net gold change"], F.FormatMoney(t.net)) end
    if not src then out[#out + 1] = "|cff777777" .. L["No auction addon: vendor prices only"] .. "|r" end
    return out
end
F.Lines = Lines

local function Refresh()
    local fd = DB()
    local btn = NS.panel and NS.panel.farmBtn
    if btn and btn.tex then
        local on = fd and fd.running
        if btn.tex.SetDesaturated then btn.tex:SetDesaturated(not on) end
        btn.tex:SetAlpha(on and 1 or 0.75)
    end
    if not (fd and fd.running) then box:Hide() return end
    local t = F.Totals(fd)
    box.header:SetText(L["FARM SESSION"])
    box.pauseBtn.text:SetText(fd.paused and "|cff33ff99>|r" or "||")
    local lines = Lines(t, fd)
    box.body:SetText(table.concat(lines, "\n"))
    -- a doboz a szoveghez igazodik (a fejlec gombjai miatt legalabb 190 szeles)
    local w = math.max(190, math.ceil(tonumber(box.body:GetStringWidth()) or 170) + 22)
    local h = tonumber(box.body:GetStringHeight()) or 0
    if h < #lines * 10 then h = #lines * 13 end
    box:SetSize(math.min(360, w), 32 + h)
    box:Show()
end
F.Refresh = Refresh

box:SetScript("OnEnter", function(self)
    local t = F.Totals()
    if not t then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(L["Farm session: top looted items"], 1, 1, 1)
    if #t.items == 0 then GameTooltip:AddLine(L["Nothing looted yet."], 0.8, 0.8, 0.8) end
    local src = F.AHSource()
    for i = 1, math.min(5, #t.items) do
        local it = t.items[i]
        GameTooltip:AddDoubleLine(("%s x%d"):format(it.link, it.n or 1),
            F.FormatMoney(src and it.best or it.vendor), 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Drag to move. Looted gold counts only money you loot, not vendor sales or quest rewards."], 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end)
box:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- Inditas / leallitas
---------------------------------------------------------------------------
local ticker
local function EnsureTicker()
    local fd = DB()
    if fd and fd.running then
        if not ticker then
            lastTick = GetTime()
            ticker = C_Timer.NewTicker(1, function() Accumulate() Refresh() end)
        end
    elseif ticker then
        ticker:Cancel()
        ticker = nil
    end
end

function F.Start()
    local c = NS.CharDB()
    local fd = { running = true, elapsed = 0, xp = 0, money = 0, items = {}, moneyStart = GetMoney() or 0,
        started = time and time() or 0 }
    BaselineXP(fd)
    rawset(c, "farm", fd)
    lastTick = GetTime()
    NS.Print(L["Farm session started. /qf farm stop shows a summary."])
    EnsureTicker()
    Refresh()
end

function F.Summary(fd)
    fd = fd or DB()
    local t = fd and F.Totals(fd)
    if not t then return {} end
    local out = {}
    out[#out + 1] = (L["Farm session: %s, %s XP (%s/h), looted gold %s, items %s (vendor)"]):format(
        F.FormatTime(t.elapsed), Num(t.xp), t.xpH and Num(t.xpH) or "-", F.FormatMoney(t.money), F.FormatMoney(t.vendor))
    local src = F.AHSource()
    if src then out[#out + 1] = (L["  Best sale (%s): %s"]):format(src, F.FormatMoney(t.money + t.best)) end
    if t.goldH then out[#out + 1] = (L["  Per hour: %s"]):format(F.FormatMoney(t.goldH)) end
    if t.items[1] then
        local top = {}
        for i = 1, math.min(3, #t.items) do top[i] = t.items[i].link .. "x" .. (t.items[i].n or 1) end
        out[#out + 1] = L["  Top: "] .. table.concat(top, ", ")
    end
    return out
end

function F.Stop()
    local fd = DB()
    if not (fd and fd.running) then NS.Print(L["No farm session is running."]) return end
    Accumulate()
    for _, l in ipairs(F.Summary(fd)) do NS.Print(l) end
    fd.running = false
    EnsureTicker()
    Refresh()
end

function F.TogglePause()
    local fd = DB()
    if not (fd and fd.running) then return end
    Accumulate()
    fd.paused = not fd.paused or nil
    if not fd.paused then BaselineXP(fd) end -- szunet alatti XP nem szamit
    lastTick = GetTime()
    NS.Print(fd.paused and L["Farm session paused."] or L["Farm session resumed."])
    Refresh()
end

function F.Toggle()
    if F.IsRunning() then F.Stop() else F.Start() end
end
NS.FarmToggle = function() NS.Loud(F.Toggle) end

-- /qf farm [start | stop | pause | resume | reset]
function F.Command(arg)
    arg = (arg or ""):lower()
    if arg == "" then F.Toggle()
    elseif arg == "start" then
        if F.IsRunning() then NS.Print(L["A farm session is already running (/qf farm reset starts over)."]) else F.Start() end
    elseif arg == "stop" then F.Stop()
    elseif arg == "pause" or arg == "resume" then
        if (arg == "pause") ~= (F.IsPaused() and true or false) then F.TogglePause() end
    elseif arg == "reset" then
        if F.IsRunning() then Accumulate() for _, l in ipairs(F.Summary()) do NS.Print(l) end end
        F.Start()
    else
        NS.Print(L["  /qf farm - start / stop a farm session; /qf farm pause | resume | reset"])
    end
end
NS.FarmCommand = F.Command

---------------------------------------------------------------------------
-- Esemenyek
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_XP_UPDATE")
ev:RegisterEvent("CHAT_MSG_MONEY")
ev:RegisterEvent("CHAT_MSG_LOOT")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "PLAYER_LOGIN" then
        RestorePos()
        local fd = DB()
        -- belepeskor / reload utan: az XP alapvonal ujra (offline nem jon XP), az ido innen megy tovabb
        if fd and fd.running then BaselineXP(fd) end
        EnsureTicker()
        Refresh()
    elseif event == "PLAYER_XP_UPDATE" then
        F.OnXP()
    elseif event == "CHAT_MSG_MONEY" then
        F.OnMoneyMsg(a1)
    elseif event == "CHAT_MSG_LOOT" then
        F.OnLootMsg(a1)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        F.OnItemInfo(a1)
    elseif event == "PLAYER_LOGOUT" then
        Accumulate()
    end
end)
