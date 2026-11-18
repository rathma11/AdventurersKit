-- Farm session: ido, XP (+ /ora, ETA a szintig), lootolt arany, lootolt itemek erteke
-- (vendor ar, es "legjobb eladas" = max(AH ar, vendor ar), ha van aukcios addon).
-- Inditas / leallitas: a panel ikonsoraban az ora gomb, vagy /ak farm (start / stop / pause / reset).
-- Futas kozben a quest panelen latszik, mint egy quest (UI\Panel.lua: NS.FarmViewing), az utvonal
-- elso allomasakent; leallitaskor osszegzo ablak (kill, XP, szint, arany, itemek).
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
-- Aukcios ar: a kozos NS.ItemPrice (Core\Prices.lua: Auctionator, TSM, Auctioneer, sajat AH scan)
---------------------------------------------------------------------------
local function AHPrice(id, link)
    local _, ah, _, src, age = NS.ItemPrice(link or id)
    if ah then return ah, src, age end
end
F.AHPrice = AHPrice
-- van-e aukcios addon (a "Best sale" sor csak ekkor latszik)
function F.AHSource() return NS.PriceAddon() end

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
    local best, src, age = sell, "vendor", nil
    if not rec.bop then
        local ah, s, a = AHPrice(id, rec.link)
        if ah and ah > best then best, src, age = ah, s, a end
    end
    return n * sell, n * best, src, age
end

-- ETA a szintig az alap (rested nelkuli) tempobol: amig van rested pool, a kill dupla XP-t ad
-- (a bonus a poolbol fogy), utana sima. need XP-hez: rested resz = min(pool, need / 2),
-- a tobbit alap tempoval kell osszeszedni: ido = (need - min(pool, need / 2)) / alap ora.
function F.EtaSeconds(need, baseH, pool)
    if not (need and baseH and baseH > 0) then return nil end
    local fromRested = math.min(math.max(0, pool or 0), need / 2)
    return (need - fromRested) / baseH * 3600
end

-- "Mangy Wolf dies, you gain 250 experience. (+125 exp Rested bonus)" -> 125. A csapat bonus
-- ("+20 exp group bonus") nem rested. Csak az angol kliens szovege (a felhasznalo enUS).
function F.ParseRested(msg)
    if type(msg) ~= "string" then return 0 end
    for n, what in msg:gmatch("%(%s*%+?(%d+)%s+exp%s+([^%)]-)%s+bonus%)") do
        if what:lower() == "rested" then return tonumber(n) or 0 end
    end
    return 0
end

-- Osszesites: idot, XP-t, penzt, erteket es oras rataikat egy tablaba
function F.Totals(fd, now)
    fd = fd or DB()
    if not fd then return nil end
    local t = { elapsed = fd.elapsed or 0, xp = fd.xp or 0, money = fd.money or 0,
        vendor = 0, best = 0, pending = 0, items = {} }
    for id, rec in pairs(fd.items or {}) do
        local v, b, src, age = ItemValue(rec, id)
        if v == nil then
            t.pending = t.pending + 1
        else
            t.vendor, t.best = t.vendor + v, t.best + b
            t.items[#t.items + 1] = { id = id, n = rec.n, link = rec.link or rec.name or ("item:" .. id), vendor = v, best = b, src = src, age = age }
        end
    end
    table.sort(t.items, function(a, b)
        if a.best ~= b.best then return a.best > b.best end
        return a.id < b.id
    end)
    local h = t.elapsed / 3600
    -- rested: a kill XP-bol ennyi volt a rested bonus; a "sajat" (alap) XP ennyivel kevesebb
    t.rested = math.min(fd.rested or 0, t.xp)
    t.restedLeft = math.max(0, tonumber(GetXPExhaustion and GetXPExhaustion()) or 0)
    if t.elapsed >= 60 then
        t.xpH = t.xp / h
        t.baseH = (t.xp - t.rested) / h
        t.goldH = (t.money + t.vendor) / h
        t.bestH = (t.money + t.best) / h
    end
    local lvl = UnitLevel("player") or 1
    local maxLvl = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    if lvl < maxLvl then
        t.need = math.max(0, (UnitXPMax("player") or 0) - (UnitXP("player") or 0))
        t.eta = F.EtaSeconds(t.need, t.baseH, t.restedLeft)
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

-- Kill: "X dies, you gain N experience" (CHAT_MSG_COMBAT_XP_GAIN; a combat log tiltott, mint a Pace.lua-ban)
function F.OnKillMsg(msg)
    local fd = DB()
    if not (fd and fd.running) or fd.paused or type(msg) ~= "string" then return end
    local name = msg:match("^(.-) dies")
    if not name or name == "" then return end
    fd.kills = fd.kills or {}
    fd.kills[name] = (fd.kills[name] or 0) + 1
    fd.killCount = (fd.killCount or 0) + 1
    fd.rested = (fd.rested or 0) + F.ParseRested(msg)
end

-- legtobbet olt mobok: { { name, n }, ... } csokkeno sorrendben
function F.TopKills(fd, max)
    local out = {}
    for name, n in pairs(fd and fd.kills or {}) do out[#out + 1] = { name = name, n = n } end
    table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
    while max and #out > max do out[#out] = nil end
    return out
end

---------------------------------------------------------------------------
-- Megjelenites a quest panelen: a farm session "pszeudo-quest" (UI\Panel.lua hivja)
---------------------------------------------------------------------------
local S = NS.Style
local HEX = S and S.HEX or { LABEL = "aaaaaa", DIM = "999999", WARN = "ff9933", GOOD = "33ff99" }
F.ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"

-- a farm nezet latszik a panelen (fut, es nem lapoztal el rola a nyillal / quest kattintassal)
function F.Viewing()
    local fd = DB()
    return fd and fd.running and fd.view and true or false
end
NS.FarmViewing = F.Viewing

local function PanelUpdate() if NS.Panel_Update then NS.Panel_Update() end end

-- on: a farm nezetre valt; off: vissza a questekhez (a "vissza" nyil a farmra hoz)
function F.SetView(on)
    local fd = DB()
    if not (fd and fd.running) then return end
    on = on and true or nil
    if fd.view == on then return end
    fd.view = on
    if not on and NS.QuestNavPushFarm then NS.QuestNavPushFarm() end
    if on and QuestFocusDB then QuestFocusDB.hidePanel = false end
    PanelUpdate()
end
-- Core\Selection.lua: kattintassal valasztott quest (quest log, route sor, kovetes) elviszi a farm nezetrol
function F.OnUserSelect()
    if F.Viewing() then F.SetView(false) end
end

local function Short(c)
    -- statisztika dobozba: "12g 34s" / "34s 56c" / "7c"
    c = math.floor((tonumber(c) or 0) + 0.5)
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    if g > 0 then return ("%d|cffffd700g|r %d|cffc7c7cfs|r"):format(g, s) end
    if s > 0 then return ("%d|cffc7c7cfs|r %d|cffeda55fc|r"):format(s, cp) end
    return ("%d|cffeda55fc|r"):format(cp)
end
F.Short = Short

-- A panel sorai (objective stilusban): { text }, a sorrend fix, hogy a sorok ne ugraljanak
function F.PanelLines(t, fd)
    local function lab(s) return "|cff" .. HEX.LABEL .. s .. ":|r " end
    local function dim(s) return "  |cff" .. HEX.DIM .. s .. "|r" end
    local ico = function(path) return "|T" .. path .. ":12:12|t " end
    local out = {}
    out[#out + 1] = ico("Interface\\COMMON\\Indicator-Yellow") .. lab(L["XP gained"]) .. Num(t.xp)
        .. ((t.rested or 0) > 0 and dim((L["rested %s"]):format(Num(t.rested))) or "")
        .. (t.xpH and dim(Num(t.xpH) .. L["/h"]) or "")
    if t.need then
        out[#out + 1] = ico("Interface\\COMMON\\Indicator-Yellow") .. lab(L["To level"]) .. Num(t.need)
            .. (t.eta and dim("ETA " .. FormatETA(t.eta)) or "")
            .. ((t.restedLeft or 0) > 0 and dim((L["rested left %s"]):format(Num(t.restedLeft))) or "")
    else
        out[#out + 1] = ico("Interface\\COMMON\\Indicator-Gray") .. lab(L["To level"]) .. L["max level"]
    end
    out[#out + 1] = ico("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8") .. lab(L["Mobs killed"]) .. Num(fd.killCount or 0)
    out[#out + 1] = ico("Interface\\Icons\\INV_Misc_Coin_01") .. lab(L["Looted gold"]) .. F.FormatMoney(t.money)
    out[#out + 1] = ico("Interface\\Icons\\INV_Misc_Bag_10") .. lab(L["Items (vendor)"]) .. F.FormatMoney(t.vendor)
        .. (t.pending > 0 and dim("+" .. t.pending .. "?") or "")
    local src = F.AHSource()
    if src then
        out[#out + 1] = ico("Interface\\Icons\\INV_Misc_Coin_02") .. lab(L["Best sale"]) .. F.FormatMoney(t.money + t.best) .. dim(src)
    else
        out[#out + 1] = ico("Interface\\Icons\\INV_Misc_Coin_02") .. "|cff777777" .. L["Best sale: needs Auctionator, TSM or Auctioneer"] .. "|r"
    end
    return out
end

-- Statisztika dobozok: ido / XP per ora / arany + ertek per ora; csik: XP a szintig
function F.UpdatePanelStats(panel)
    local fd = DB()
    if not (fd and panel and panel.statBoxes) then return end
    local t = F.Totals(fd)
    local b = panel.statBoxes
    b[1].label:SetText(L["TIME"]); b[2].label:SetText(L["XP / HOUR"]); b[3].label:SetText(L["GOLD / HOUR"])
    b[1].value:SetText(fd.paused and ("|cff" .. HEX.WARN .. F.FormatTime(t.elapsed) .. "|r") or F.FormatTime(t.elapsed))
    -- az elso percben meg nincs megbizhato ora rata: addig a szerzett osszeg latszik ("+250"),
    -- igy az elso killtol latod, hogy szamol (0.7.8-ban ilyenkor "-" volt: mintha nem szamolna)
    b[2].label:SetText(t.xpH and L["XP / HOUR"] or L["XP GAINED"])
    b[3].label:SetText(t.goldH and L["GOLD / HOUR"] or L["GOLD GAINED"])
    b[2].value:SetText(t.xpH and Num(t.xpH) or ((t.xp > 0) and ("+" .. Num(t.xp)) or "-"))
    b[3].value:SetText(t.goldH and Short(t.goldH) or ((t.money + t.vendor > 0) and ("+" .. Short(t.money + t.vendor)) or "-"))
    local max = UnitXPMax("player") or 0
    panel.bar:SetValue(max > 0 and (UnitXP("player") or 0) / max or 0)
    panel.bar:SetStatusBarColor(0.58, 0.35, 0.85) -- XP lila (mint a jatek XP csikja)
    panel.sub:SetText((fd.paused and ("|cff" .. HEX.WARN .. L["Paused"] .. "|r")
        or (fd.started and date and (L["Running since %s"]):format(date("%H:%M", fd.started)) or L["Running"]))
        .. "  |cff" .. HEX.DIM .. (L["%d kills"]):format(fd.killCount or 0) .. "|r")
    return t
end

function F.FooterText()
    local fd = DB()
    if fd and fd.paused then return L["Paused: /ak farm resume"] end
    return L["Hover a row: top items. Stop: the clock button."]
end

-- Sorok (sajat keszlet a panelen)
local rows = {}
local function TopItemsTooltip(owner)
    local t = F.Totals()
    if not t then return end
    local fd = DB()
    local tt = NS.TT and NS.TT.Begin(owner, "ANCHOR_LEFT", L["Farm session"], F.FormatTime(t.elapsed))
    if not tt then GameTooltip:SetOwner(owner, "ANCHOR_LEFT"); GameTooltip:SetText(L["Farm session"], 1, 1, 1); tt = GameTooltip end
    if NS.TT then NS.TT.Sub(tt, L["Top looted items"]) else tt:AddLine(L["Top looted items"], 1, 0.82, 0) end
    if #t.items == 0 then tt:AddLine(L["Nothing looted yet."], 0.8, 0.8, 0.8) end
    local src = F.AHSource()
    for i = 1, math.min(5, #t.items) do
        local it = t.items[i]
        tt:AddDoubleLine(("%s x%d"):format(it.link, it.n or 1), F.FormatMoney(src and it.best or it.vendor)
            .. ((src and it.best > 0) and (" |cff888888" .. NS.PriceSourceText(it.src, it.age) .. "|r") or ""), 1, 1, 1, 1, 1, 1)
    end
    local top = F.TopKills(fd, 3)
    if top[1] then
        if NS.TT then NS.TT.Sub(tt, L["Most killed"]) else tt:AddLine(L["Most killed"], 1, 0.82, 0) end
        for _, k in ipairs(top) do tt:AddDoubleLine(k.name, "x" .. k.n, 1, 1, 1, 0.8, 0.8, 0.8) end
    end
    if t.net then tt:AddLine((L["Net gold change (vendor, quests, repairs too): %s"]):format(F.FormatMoney(t.net)), 0.6, 0.6, 0.6, true) end
    if NS.TT then
        NS.TT.Finish(tt, L["Looted gold is only money you loot, not vendor sales or quest rewards."])
    else
        GameTooltip:Show()
    end
end
local function GetRow(panel, i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, panel)
    r.text = r:CreateFontString(nil, "OVERLAY", "QuestFocusFontSmall")
    r.text:SetAllPoints()
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    if S then S.RowHighlight(r) end
    r:SetScript("OnEnter", function(self) TopItemsTooltip(self) end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

-- y-tol rajzolja a sorokat (w szeles, rh magas), visszaadja az uj y-t
function F.DrawPanel(panel, y, w, rh)
    local fd = DB()
    if not fd then return y end
    local lines = F.PanelLines(F.Totals(fd), fd)
    local step = rh + 1
    for i, text in ipairs(lines) do
        local r = GetRow(panel, i)
        r:SetSize(w, rh)
        r.text:SetText(text)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
        r:Show()
        y = y - step
    end
    for i = #lines + 1, #rows do rows[i]:Hide() end
    return y
end
function F.HidePanelRows()
    for _, r in ipairs(rows) do r:Hide() end
end

-- masodpercenkent: csak a szovegek (a sorok helye nem valtozik)
local function RefreshPanel()
    local panel = NS.panel
    if not (panel and F.Viewing() and panel:IsShown() and rows[1] and rows[1]:IsShown()) then return end
    local fd = DB()
    local t = F.UpdatePanelStats(panel)
    for i, text in ipairs(F.PanelLines(t, fd)) do
        if rows[i] then rows[i].text:SetText(text) end
    end
    panel.footer:SetText(F.FooterText())
end

-- Az utvonal elso sora (Planner\Suggestions.lua): a futo session, ha nem az latszik
function F.RouteEntry()
    local fd = DB()
    if not (fd and fd.running) or fd.view then return nil end
    return { farm = true, title = L["Farm session"] }
end
function F.RouteText(i)
    local t = F.Totals()
    local fd = DB()
    local extra = t and (F.FormatTime(t.elapsed) .. (t.goldH and ("  " .. F.FormatMoney(t.goldH, true) .. L["/h"]) or "")) or ""
    return ("%d. |T%s:12:12|t |cff33ff99%s|r  |cff999999%s%s|r"):format(i, F.ICON, L["Farm session"], extra,
        fd and fd.paused and ("  " .. L["paused"]) or "")
end
F.RouteTooltip = TopItemsTooltip

---------------------------------------------------------------------------
-- A panel ora gombja: allo: szurke ora; fut: zold fenyes + piros X (stop) ugyanott
---------------------------------------------------------------------------
local function UpdateButton()
    local btn = NS.panel and NS.panel.farmBtn
    if not (btn and btn.tex) then return end
    local on = F.IsRunning()
    if not btn.glow then
        btn.glow = btn:CreateTexture(nil, "BACKGROUND")
        btn.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        btn.glow:SetBlendMode("ADD")
        btn.glow:SetVertexColor(0.2, 1, 0.3, 0.9)
        btn.glow:SetPoint("CENTER")
        btn.glow:SetSize(30, 30)
        btn.stop = btn:CreateTexture(nil, "OVERLAY")
        btn.stop:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        btn.stop:SetSize(11, 11)
        btn.stop:SetPoint("BOTTOMRIGHT", 4, -4)
    end
    if btn.tex.SetDesaturated then btn.tex:SetDesaturated(not on) end
    btn.tex:SetAlpha(on and 1 or 0.8)
    btn.glow:SetShown(on)
    btn.stop:SetShown(on)
end
F.UpdateButton = UpdateButton

---------------------------------------------------------------------------
-- Osszegzo ablak leallitaskor (DESIGN.md: kis "box" dialog, mint a panel: szekcio fejlecek,
-- elvalasztok a csoportok kozott, cimke balra / ertek jobbra, lapos NS.Style gombok kozepen)
---------------------------------------------------------------------------
-- Az osszegzes adatai csoportokban: { sec = "FEJLEC" } / { label, value, sub = true } / { div = true }
function F.SummaryData(fd)
    fd = fd or DB()
    local t = fd and F.Totals(fd)
    if not t then return {} end
    local out = {}
    local function sec(s) out[#out + 1] = { sec = s } end
    local function row(label, value, sub) out[#out + 1] = { label = label, value = value, sub = sub } end
    local function div() out[#out + 1] = { div = true } end
    local function dim(s) return "|cff" .. HEX.DIM .. s .. "|r" end
    local short = t.elapsed < 60 -- egy perc alatt nincs ora rata

    sec(L["TIME AND XP"])
    row(L["Duration"], F.FormatTime(t.elapsed))
    row(L["XP gained"], Num(t.xp))
    if (t.rested or 0) > 0 then row(L["of it rested bonus"], Num(t.rested), true) end
    row(L["XP per hour"], t.xpH and Num(t.xpH) or dim(short and L["- (under 1 min)"] or "-"))
    local lv = (UnitLevel("player") or 0) - (fd.startLevel or UnitLevel("player") or 0)
    if lv > 0 then row(L["Levels gained"], ("|cff%s+%d|r  (%d)"):format(HEX.GOOD, lv, UnitLevel("player") or 0)) end
    if t.need then row(L["To level"], Num(t.need) .. (t.eta and ("  " .. dim("ETA " .. FormatETA(t.eta))) or "")) end
    if (t.restedLeft or 0) > 0 then row(L["Rested XP left"], Num(t.restedLeft)) end
    div()

    sec(L["KILLS"])
    row(L["Mobs killed"], Num(fd.killCount or 0))
    for _, k in ipairs(F.TopKills(fd, 3)) do row(k.name, "x" .. k.n, true) end
    div()

    sec(L["LOOT"])
    row(L["Looted gold"], F.FormatMoney(t.money))
    local nItems = 0
    for _, it in pairs(fd.items or {}) do nItems = nItems + (it.n or 0) end
    row(L["Items looted"], Num(nItems))
    row(L["Vendor value"], F.FormatMoney(t.vendor))
    local src = F.AHSource()
    if src then row(L["Best sale"], F.FormatMoney(t.money + t.best) .. "  " .. dim(src)) end
    for i = 1, math.min(3, #t.items) do
        local it = t.items[i]
        row(it.link .. " x" .. (it.n or 1), F.FormatMoney(src and it.best or it.vendor), true)
    end
    row(L["Gold per hour"], t.goldH and F.FormatMoney(t.goldH) or dim(short and L["- (under 1 min)"] or "-"))
    if src and t.bestH then row(L["best sale per hour"], F.FormatMoney(t.bestH), true) end
    return out
end

-- Sima szoveg sorok (teszt, regi hivok): "FEJLEC" / "cimke: ertek"
function F.SummaryLines(fd)
    local out = {}
    for _, e in ipairs(F.SummaryData(fd)) do
        if e.sec then out[#out + 1] = e.sec
        elseif e.label then out[#out + 1] = e.label .. ": " .. e.value end
    end
    return out
end

-- egy sor a chatbe
function F.ChatLine(fd)
    fd = fd or DB()
    local t = fd and F.Totals(fd)
    if not t then return "" end
    return (L["Farm session: %s, %d kills, %s XP (%s/h), looted gold %s, items %s (vendor), %s per hour"]):format(
        F.FormatTime(t.elapsed), fd.killCount or 0, Num(t.xp), t.xpH and Num(t.xpH) or "-", F.FormatMoney(t.money),
        F.FormatMoney(t.vendor), t.goldH and F.FormatMoney(t.goldH) or "-")
end

local SUM_W, ROW_H = 300, 15
local sum
local function SummaryFrame()
    if sum then return sum end
    sum = S.Box("AdventurersKitFarmSummary", SUM_W, 200, L["FARM SESSION SUMMARY"], "DIALOG")
    sum:SetPoint("TOP", UIParent, "TOP", 0, -160)
    S.Draggable(sum, "farmSumPos")
    sum.items = {} -- ujrahasznalt elemek: { kind, a, b }
    sum.footLine = S.Divider(sum)
    sum.footLine:SetPoint("BOTTOMLEFT", 12, 44)
    sum.footLine:SetPoint("BOTTOMRIGHT", -12, 44)
    local function Btn(text, tip, onClick)
        local b = S.FlatButton(sum, text, 120, 24)
        b.text:SetFontObject("GameFontNormal")
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(text, 1, 1, 1)
            GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    sum.newBtn = Btn(L["Start new"], L["Starts a new farm session from zero. Same as /ak farm start."],
        function() sum:Hide(); NS.Loud(F.Start) end)
    sum.closeBtn = Btn(L["Close"], L["Closes this window (Esc works too)."], function() sum:Hide() end)
    sum.newBtn:SetPoint("BOTTOMRIGHT", sum, "BOTTOM", -4, 12)
    sum.closeBtn:SetPoint("BOTTOMLEFT", sum, "BOTTOM", 4, 12)
    if UISpecialFrames then table.insert(UISpecialFrames, "AdventurersKitFarmSummary") end
    return sum
end

-- az i. elem (szekcio fejlec / sor / elvalaszto) a keszletbol
local function SumItem(i, kind)
    local it = sum.items[i]
    if it and it.kind ~= kind then
        if it.a then it.a:Hide() end
        if it.b then it.b:Hide() end
        it = nil
    end
    if not it then
        it = { kind = kind }
        if kind == "sec" then
            it.a = S.Section(sum)
        elseif kind == "div" then
            it.a = S.Divider(sum)
        else
            it.a = sum:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            it.a:SetJustifyH("LEFT")
            it.a:SetWordWrap(false)
            it.b = sum:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            it.b:SetJustifyH("RIGHT")
            it.b:SetWordWrap(false)
        end
        sum.items[i] = it
    end
    return it
end

function F.ShowSummary(fd)
    local f = SummaryFrame()
    S.RestorePos(f, "farmSumPos")
    local y = -26
    local data = F.SummaryData(fd)
    for i, e in ipairs(data) do
        local kind = e.sec and "sec" or (e.div and "div" or "row")
        local it = SumItem(i, kind)
        it.a:ClearAllPoints()
        if kind == "sec" then
            it.a:SetText(e.sec)
            it.a:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y)
            y = y - 15
        elseif kind == "div" then
            y = y - 4
            it.a:SetPoint("TOPLEFT", f, "TOPLEFT", 12, y)
            it.a:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, y)
            y = y - 7
        else
            it.a:SetText(e.label)
            it.a:SetTextColor(e.sub and 0.75 or 1, e.sub and 0.75 or 1, e.sub and 0.75 or 1)
            it.a:SetPoint("TOPLEFT", f, "TOPLEFT", e.sub and 24 or 14, y)
            it.a:SetWidth(SUM_W * 0.55 - (e.sub and 10 or 0))
            it.b:ClearAllPoints()
            it.b:SetText(e.value)
            it.b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, y)
            it.b:SetWidth(SUM_W * 0.42)
            it.b:Show()
            y = y - ROW_H
        end
        it.a:Show()
    end
    for i = #data + 1, #f.items do
        local it = f.items[i]
        if it.a then it.a:Hide() end
        if it.b then it.b:Hide() end
    end
    f:SetHeight(-y + 8 + 44)
    f:Show()
end
F.SummaryFrame = function() return sum end

---------------------------------------------------------------------------
-- Inditas / leallitas
---------------------------------------------------------------------------
local ticker, tickN = nil, 0
local function EnsureTicker()
    local fd = DB()
    if fd and fd.running then
        if not ticker then
            lastTick = GetTime()
            ticker = C_Timer.NewTicker(1, function()
                Accumulate()
                tickN = tickN + 1
                -- 10 mp-enkent a teljes panel (az utvonal sorrendje, quest modban a farm sor ideje),
                -- kozben csak a farm nezet szovegei
                if tickN % 10 == 0 and NS.panel and NS.panel:IsShown() and not NS.panel:IsMouseOver() then
                    PanelUpdate()
                else
                    RefreshPanel()
                end
            end)
        end
    elseif ticker then
        ticker:Cancel()
        ticker = nil
    end
end

function F.Start()
    local c = NS.CharDB()
    local fd = { running = true, view = true, elapsed = 0, xp = 0, money = 0, items = {}, kills = {}, killCount = 0,
        moneyStart = GetMoney() or 0, started = time and time() or 0, startLevel = UnitLevel("player") or 1 }
    BaselineXP(fd)
    rawset(c, "farm", fd)
    lastTick = GetTime()
    if QuestFocusDB then QuestFocusDB.hidePanel = false end
    NS.Print(L["Farm session started. Click the clock button (or /ak farm) to stop it."])
    EnsureTicker()
    UpdateButton()
    PanelUpdate()
end

function F.Stop()
    local fd = DB()
    if not (fd and fd.running) then NS.Print(L["No farm session is running."]) return end
    Accumulate()
    NS.Print(F.ChatLine(fd))
    fd.running, fd.view = false, nil
    EnsureTicker()
    UpdateButton()
    PanelUpdate()
    if not (QuestFocusDB and QuestFocusDB.noFarmSummary) then F.ShowSummary(fd) end
end

function F.TogglePause()
    local fd = DB()
    if not (fd and fd.running) then return end
    Accumulate()
    fd.paused = not fd.paused or nil
    if not fd.paused then BaselineXP(fd) end -- szunet alatti XP nem szamit
    lastTick = GetTime()
    NS.Print(fd.paused and L["Farm session paused."] or L["Farm session resumed."])
    RefreshPanel()
end

function F.Toggle()
    if F.IsRunning() then F.Stop() else F.Start() end
end
NS.FarmToggle = function() NS.Loud(F.Toggle) end

-- /ak farm [start | stop | pause | resume | reset | show]
function F.Command(arg)
    arg = (arg or ""):lower()
    if arg == "" then F.Toggle()
    elseif arg == "start" then
        if F.IsRunning() then NS.Print(L["A farm session is already running (/ak farm reset starts over)."]) else F.Start() end
    elseif arg == "stop" then F.Stop()
    elseif arg == "show" then
        if F.IsRunning() then F.SetView(true) else NS.Print(L["No farm session is running."]) end
    elseif arg == "pause" or arg == "resume" then
        if (arg == "pause") ~= (F.IsPaused() and true or false) then F.TogglePause() end
    elseif arg == "reset" then
        if F.IsRunning() then Accumulate() NS.Print(F.ChatLine()) end
        F.Start()
    else
        NS.Print(L["  /ak farm - start / stop a farm session; /ak farm pause | resume | reset | show"])
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
ev:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "PLAYER_LOGIN" then
        local fd = DB()
        -- belepeskor / reload utan: az XP alapvonal ujra (offline nem jon XP), az ido innen megy tovabb
        if fd and fd.running then BaselineXP(fd) end
        EnsureTicker()
        UpdateButton()
    elseif event == "PLAYER_XP_UPDATE" then
        F.OnXP()
        RefreshPanel()
    elseif event == "CHAT_MSG_MONEY" then
        F.OnMoneyMsg(a1)
        RefreshPanel()
    elseif event == "CHAT_MSG_LOOT" then
        F.OnLootMsg(a1)
        RefreshPanel()
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        F.OnKillMsg(a1)
        -- az XP a UnitXP kulonbsegbol jon; ha a PLAYER_XP_UPDATE a chat uzenet elott jott (vagy
        -- elmaradt), kicsit kesobb meg egyszer megnezzuk (kulonbseg alapu: dupla szamolas nincs)
        F.OnXP()
        RefreshPanel()
        C_Timer.After(0.3, function() F.OnXP() RefreshPanel() end)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        F.OnItemInfo(a1)
    elseif event == "PLAYER_LOGOUT" then
        Accumulate()
    end
end)
