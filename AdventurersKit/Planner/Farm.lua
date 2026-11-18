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

-- rez -> penz ermeikonokkal (a kozos NS.FormatMoney, Core\Prices.lua); plain: "1g 2s 3c" szoveg
function F.FormatMoney(c, plain) return NS.FormatMoney(c, plain) end

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
    local best, src, age, why = sell, "vendor", nil, nil
    if rec.bop then
        why = "bop"                                   -- soulbound: csak vendor
    else
        local ah, s, a = AHPrice(id, rec.link)
        if not ah then why = "noah"                   -- nincs AH ara: vendor ar
        elseif ah > best then best, src, age = ah, s, a
        else why = "lower" end                        -- az AH ar kevesebb a vendor arnal
    end
    return n * sell, n * best, src, age, why
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
        vendor = 0, best = 0, pending = 0, items = {}, ahItems = 0, fallback = 0 }
    for id, rec in pairs(fd.items or {}) do
        local v, b, src, age, why = ItemValue(rec, id)
        if v == nil then
            t.pending = t.pending + 1
        else
            t.vendor, t.best = t.vendor + v, t.best + b
            -- AH aron szamolt / vendor arra visszaeso (nincs AH ar, BoP, vagy az AH olcsobb) eladhato itemek
            if v > 0 then
                if why then t.fallback = t.fallback + 1 else t.ahItems = t.ahItems + 1 end
            end
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
    -- kill XP (a rested bonusszal egyutt): a tobbi XP (quest leadas, felfedezes) = osszes - kill XP
    fd.killXP = (fd.killXP or 0) + (tonumber(msg:match("you gain (%d+) experience")) or 0)
end

---------------------------------------------------------------------------
-- XP minta az utolso ~5 perc tempojahoz: 30 mp-enkent { eltelt ido, XP } (csak memoriaban)
---------------------------------------------------------------------------
local xpSamples = {}
local RECENT = 300
function F.SampleXP(fd)
    fd = fd or DB()
    if not (fd and fd.running) then return end
    local e = fd.elapsed or 0
    local last = xpSamples[#xpSamples]
    if last and e - last.e < 30 then return end
    xpSamples[#xpSamples + 1] = { e = e, xp = fd.xp or 0 }
    while #xpSamples > 2 and e - xpSamples[2].e >= RECENT do table.remove(xpSamples, 1) end
end
function F.ResetSamples() wipe(xpSamples) end
-- XP / ora az utolso ~5 percben (legalabb 2 perc minta kell), kulonben nil
function F.RecentXPH(fd)
    fd = fd or DB()
    local first = xpSamples[1]
    if not (fd and first) then return nil end
    local span = (fd.elapsed or 0) - first.e
    if span < 120 then return nil end
    return ((fd.xp or 0) - first.xp) / span * 3600, span
end

-- XP adatok a tooltiphez: kill XP (alap / rested), quest es egyeb XP, kill atlag, killek a szintig,
-- ETA rested poollal es anelkul, a rested pool hany killig tart, szint haladas, session a szint %-aban
function F.XPStats(t, fd)
    fd = fd or DB()
    local s = {}
    local kills = fd and fd.killCount or 0
    s.killXP = math.min(t.xp, fd and fd.killXP or 0)
    s.rested = math.min(t.rested or 0, s.killXP)
    s.baseKill = s.killXP - s.rested
    s.other = math.max(0, t.xp - s.killXP)
    s.kills = kills
    if kills > 0 then
        s.perKill = s.killXP / kills
        s.basePerKill = s.baseKill / kills
    end
    s.cur, s.max = UnitXP("player") or 0, UnitXPMax("player") or 0
    s.pct = s.max > 0 and s.cur / s.max * 100 or nil
    s.sessionPct = s.max > 0 and t.xp / s.max * 100 or nil
    s.pool = t.restedLeft or 0
    if t.need and s.basePerKill and s.basePerKill > 0 then
        -- rested killnel a bonus = alap XP (dupla), amig van pool: killek = (need - min(pool, need/2)) / alap
        s.killsToLevel = math.ceil((t.need - math.min(s.pool, t.need / 2)) / s.basePerKill)
        if s.pool > 0 then s.poolKills = math.ceil(s.pool / s.basePerKill) end
    end
    s.recentH = F.RecentXPH(fd)
    if t.need then
        s.etaRested = t.eta
        if t.baseH and t.baseH > 0 then s.etaNoRested = t.need / t.baseH * 3600 end
    end
    return s
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

-- statisztika dobozba roviden, ermeikonokkal: "12[g] 34[s]" / "34[s] 56[c]" / "7[c]"
local function Short(c) return NS.FormatMoney(c, nil, true) end
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
        out[#out + 1] = ico("Interface\\Icons\\INV_Misc_Coin_02") .. lab(L["Items (AH)"]) .. F.FormatMoney(t.best)
            .. dim(src .. (t.fallback > 0 and (", " .. (L["%d at vendor price"]):format(t.fallback)) or ""))
    else
        out[#out + 1] = ico("Interface\\Icons\\INV_Misc_Coin_02") .. "|cff777777" .. L["Items (AH): needs Auctionator, TSM or Auctioneer"] .. "|r"
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
    -- arany: AH aron, ha van aukcios addon (a cimke mutatja), kulonben vendor aron; hoverre bontas
    local gH, kind = F.GoldPerHour(t)
    local gained = t.money + (kind == "AH" and t.best or t.vendor)
    b[3].label:SetText(gH and (kind == "AH" and L["GOLD/H (AH)"] or L["GOLD/H VENDOR"])
        or (kind == "AH" and L["GOLD (AH)"] or L["GOLD VENDOR"]))
    b[2].value:SetText(t.xpH and Num(t.xpH) or ((t.xp > 0) and ("+" .. Num(t.xp)) or "-"))
    b[3].value:SetText(gH and Short(gH) or ((gained > 0) and ("+" .. Short(gained)) or "-"))
    if not b[3].qfFarmTip then
        b[3].qfFarmTip = true
        b[3]:SetScript("OnEnter", function(self) if F.Viewing() and F.RouteTooltip then F.RouteTooltip(self) end end)
        b[3]:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    b[3]:EnableMouse(true)
    if not b[2].qfFarmTip then
        b[2].qfFarmTip = true
        b[2]:SetScript("OnEnter", function(self) if F.Viewing() and F.XPTooltip then F.XPTooltip(self) end end)
        b[2]:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    b[2]:EnableMouse(true)
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

-- Arany per ora: aukcios addonnal AH aron (az item max(AH, vendor) aron), kulonben vendor aron.
-- Visszaadja: ertek (nil az elso percben), "AH" / "vendor"
function F.GoldPerHour(t)
    if F.AHSource() then return t.bestH, "AH" end
    return t.goldH, "vendor"
end

-- Arany bontas a tooltipbe: nyers arany, itemek vendor / AH aron, ossz vendorolva / AH-zva;
-- osszeg es ora rata (az elso perc utan)
function F.GoldBreakdown(tt, t)
    local src = F.AHSource()
    local h = t.elapsed >= 60 and (t.elapsed / 3600) or nil
    local function line(label, v, r, g, b)
        tt:AddDoubleLine(label, F.FormatMoney(v) .. (h and ("  |cff999999" .. F.FormatMoney(v / h) .. L["/h"] .. "|r") or ""),
            r or 1, g or 1, b or 1, 1, 1, 1)
    end
    if NS.TT then NS.TT.Sub(tt, L["Gold breakdown"]) else tt:AddLine(L["Gold breakdown"], 1, 0.82, 0) end
    line(L["Raw gold looted (coins)"], t.money)
    line(L["Items: if you vendor them"], t.vendor)
    if src then
        line((L["Items: if you sell them on the AH (%s)"]):format(src), t.best)
        if t.fallback > 0 then
            tt:AddLine((L["  %d of them at vendor price (no AH price, soulbound, or the AH pays less)"]):format(t.fallback),
                0.6, 0.6, 0.6, true)
        end
    else
        tt:AddLine(L["  AH value: needs Auctionator, TSM or Auctioneer"], 0.6, 0.6, 0.6, true)
    end
    line(L["Total if vendored"], t.money + t.vendor, 1, 0.86, 0.5)
    if src then line(L["Total if sold on the AH"], t.money + t.best, 1, 0.86, 0.5) end
    tt:AddLine(src and L["Gold per hour = (raw gold + items at AH price) / time; an item without an AH price counts at vendor price."]
        or L["Gold per hour = (raw gold + items at vendor price) / time."], 0.6, 0.6, 0.6, true)
    if not h then tt:AddLine(L["Per hour values come after the first minute."], 0.6, 0.6, 0.6, true) end
end

-- XP bontas a tooltipbe (elo nezet: XP doboz, XP / szint / kill sorok; osszegzo: TIME AND XP sorok)
function F.XPBreakdown(tt, t, fd)
    local s = F.XPStats(t, fd)
    local h = t.elapsed >= 60 and (t.elapsed / 3600) or nil
    local function line(label, value, r, g, b) tt:AddDoubleLine(label, value, r or 1, g or 1, b or 1, 1, 1, 1) end
    local function dim(x) return "  |cff999999" .. x .. "|r" end
    local function rate(v) return h and dim(Num(v / h) .. L["/h"]) or "" end
    if NS.TT then NS.TT.Sub(tt, L["XP breakdown"]) else tt:AddLine(L["XP breakdown"], 1, 0.82, 0) end
    line(L["XP gained"], Num(t.xp) .. rate(t.xp), 1, 0.86, 0.5)
    line(L["  from kills"], Num(s.killXP) .. rate(s.killXP))
    line(L["    base"], Num(s.baseKill))
    if s.rested > 0 then line(L["    rested bonus"], Num(s.rested), 0.6, 0.75, 1) end
    line(L["  quests and other"], Num(s.other) .. rate(s.other))

    if NS.TT then NS.TT.Sub(tt, L["Pace"]) else tt:AddLine(L["Pace"], 1, 0.82, 0) end
    line(L["XP per hour"], t.xpH and Num(t.xpH) or L["after the first minute"])
    line(L["XP per hour, last 5 min"], s.recentH and Num(s.recentH) or L["after 2 minutes"])
    line(L["Kills"], Num(s.kills) .. (h and dim(Num(s.kills / h) .. L["/h"]) or ""))
    if s.perKill then
        line(L["XP per kill"], Num(s.perKill) .. (s.rested > 0 and dim((L["base %s"]):format(Num(s.basePerKill))) or ""))
    end

    if NS.TT then NS.TT.Sub(tt, L["Level"]) else tt:AddLine(L["Level"], 1, 0.82, 0) end
    line((L["Level %d"]):format(UnitLevel("player") or 0),
        ("%s / %s"):format(Num(s.cur), Num(s.max)) .. (s.pct and dim(("%.1f%%"):format(s.pct)) or ""))
    if s.sessionPct then line(L["This session"], ("%.1f%%"):format(s.sessionPct) .. dim(L["of a level"])) end
    if t.need then
        line(L["XP to level"], Num(t.need))
        line(L["Kills to level"], s.killsToLevel and Num(s.killsToLevel) or "?")
        line(L["Time to level"], s.etaRested and FormatETA(s.etaRested) or "?")
        if s.pool > 0 and s.etaNoRested then line(L["  without the rested XP"], FormatETA(s.etaNoRested), 0.75, 0.75, 0.75) end
    else
        line(L["XP to level"], L["max level"])
    end
    line(L["Rested XP left"], Num(s.pool) .. (s.poolKills and dim((L["~%d kills"]):format(s.poolKills)) or ""),
        0.6, 0.75, 1)
    tt:AddLine(L["Kill XP comes from the kill lines in chat; quests and other = the rest. The time to level uses your "]
        .. L["pace without rested XP, plus the rested XP you have left (it doubles kill XP until it runs out)."],
        0.6, 0.6, 0.6, true)
end
local function XPTooltip(owner, t, anchor)
    t = t or F.Totals()
    if not t then return end
    local tt = NS.TT and NS.TT.Begin(owner, anchor or "ANCHOR_LEFT", L["Farm session"], F.FormatTime(t.elapsed))
    if not tt then GameTooltip:SetOwner(owner, anchor or "ANCHOR_LEFT"); GameTooltip:SetText(L["Farm session"], 1, 1, 1); tt = GameTooltip end
    F.XPBreakdown(tt, t, DB())
    if NS.TT then NS.TT.Finish(tt) else GameTooltip:Show() end
end
F.XPTooltip = XPTooltip

-- Sorok (sajat keszlet a panelen)
local rows = {}
local function TopItemsTooltip(owner)
    local t = F.Totals()
    if not t then return end
    local fd = DB()
    local tt = NS.TT and NS.TT.Begin(owner, "ANCHOR_LEFT", L["Farm session"], F.FormatTime(t.elapsed))
    if not tt then GameTooltip:SetOwner(owner, "ANCHOR_LEFT"); GameTooltip:SetText(L["Farm session"], 1, 1, 1); tt = GameTooltip end
    F.GoldBreakdown(tt, t)
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
    -- az elso harom sor (XP, szint, kill) az XP bontast mutatja, a tobbi (arany, itemek) az aranyat
    r:SetScript("OnEnter", function(self) if i <= 3 then XPTooltip(self) else TopItemsTooltip(self) end end)
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
    -- quest modban a 3. stat doboz nem a farm tooltipje
    local b3 = NS.panel and NS.panel.statBoxes and NS.panel.statBoxes[3]
    if b3 and b3.qfFarmTip then b3:EnableMouse(false) end
    local b2 = NS.panel and NS.panel.statBoxes and NS.panel.statBoxes[2]
    if b2 and b2.qfFarmTip then b2:EnableMouse(false) end
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
    local extra = t and (F.FormatTime(t.elapsed) .. (t.goldH and ("  " .. F.FormatMoney(t.goldH) .. L["/h"]) or "")) or ""
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
    -- TIME AND XP es a kill sor: hoverre XP bontas (tip = "xp"); a LOOT sorok: arany (tip = "gold")
    local function xrow(label, value, sub) row(label, value, sub); out[#out].tip = "xp" end

    sec(L["TIME AND XP"])
    xrow(L["Duration"], F.FormatTime(t.elapsed))
    xrow(L["XP gained"], Num(t.xp))
    if (t.rested or 0) > 0 then xrow(L["of it rested bonus"], Num(t.rested), true) end
    xrow(L["XP per hour"], t.xpH and Num(t.xpH) or dim(short and L["- (under 1 min)"] or "-"))
    local lv = (UnitLevel("player") or 0) - (fd.startLevel or UnitLevel("player") or 0)
    if lv > 0 then xrow(L["Levels gained"], ("|cff%s+%d|r  (%d)"):format(HEX.GOOD, lv, UnitLevel("player") or 0)) end
    if t.need then xrow(L["To level"], Num(t.need) .. (t.eta and ("  " .. dim("ETA " .. FormatETA(t.eta))) or "")) end
    if (t.restedLeft or 0) > 0 then xrow(L["Rested XP left"], Num(t.restedLeft)) end
    div()

    sec(L["KILLS"])
    xrow(L["Mobs killed"], Num(fd.killCount or 0))
    for _, k in ipairs(F.TopKills(fd, 3)) do row(k.name, "x" .. k.n, true) end
    div()

    sec(L["LOOT"])
    local function trow(label, value, sub) row(label, value, sub); out[#out].tip = "gold" end
    trow(L["Raw gold looted"], F.FormatMoney(t.money))
    local nItems = 0
    for _, it in pairs(fd.items or {}) do nItems = nItems + (it.n or 0) end
    trow(L["Items looted"], Num(nItems))
    trow(L["Items at vendor price"], F.FormatMoney(t.vendor))
    local src = F.AHSource()
    if src then
        trow(L["Items at AH price"], F.FormatMoney(t.best) .. "  " .. dim(src))
        if t.fallback > 0 then trow((L["%d at vendor price (no AH price)"]):format(t.fallback), "", true) end
    end
    for i = 1, math.min(3, #t.items) do
        local it = t.items[i]
        trow(it.link .. " x" .. (it.n or 1), F.FormatMoney(src and it.best or it.vendor)
            .. (src and it.src == "vendor" and it.vendor > 0 and ("  " .. dim(L["vendor"])) or ""), true)
    end
    local gH, kind = F.GoldPerHour(t)
    trow(kind == "AH" and L["Gold per hour (AH)"] or L["Gold per hour (vendor)"],
        gH and F.FormatMoney(gH) or dim(short and L["- (under 1 min)"] or "-"))
    if kind == "AH" and t.goldH then trow(L["if vendored"], F.FormatMoney(t.goldH), true) end
    out.totals = t
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
        F.FormatMoney(t.vendor), (function()
            local gH, kind = F.GoldPerHour(t)
            return gH and (F.FormatMoney(gH) .. " (" .. (kind == "AH" and L["AH"] or L["vendor"]) .. ")") or "-"
        end)())
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
        if it.hit then it.hit:Hide() end
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
            -- hover terulet (LOOT sorok): arany bontas tooltip
            it.hit = CreateFrame("Button", nil, sum)
            S.RowHighlight(it.hit)
            it.hit:SetScript("OnEnter", function(self)
                local t = sum.totals
                if not t then return end
                if self.tipKind == "xp" then XPTooltip(self, t, "ANCHOR_RIGHT") return end
                local tt = NS.TT and NS.TT.Begin(self, "ANCHOR_RIGHT", L["Farm session"], F.FormatTime(t.elapsed))
                if not tt then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(L["Farm session"], 1, 1, 1); tt = GameTooltip end
                F.GoldBreakdown(tt, t)
                if NS.TT then NS.TT.Finish(tt) else GameTooltip:Show() end
            end)
            it.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    f.totals = data.totals -- a LOOT sorok tooltipje ebbol bont
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
            it.hit:ClearAllPoints()
            it.hit:SetPoint("TOPLEFT", f, "TOPLEFT", 10, y + 1)
            it.hit:SetSize(SUM_W - 20, ROW_H)
            it.hit.tipKind = e.tip
            it.hit:SetShown(e.tip and true or false)
            y = y - ROW_H
        end
        it.a:Show()
    end
    for i = #data + 1, #f.items do
        local it = f.items[i]
        if it.a then it.a:Hide() end
        if it.b then it.b:Hide() end
        if it.hit then it.hit:Hide() end
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
                F.SampleXP() -- az utolso 5 perc XP tempojahoz
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
    F.ResetSamples()
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
