-- Adventurer's Kit: kozos item ar (NS.ItemPrice). Minden helyen ezt hasznaljuk, ahol egy itemnek
-- erteke van (farm session, AH "Quest items" ful, Bags tooltip).
--   vendor: GetItemInfo sellPrice (darabar; nil, ha az item info meg nem toltott be)
--   AH:     1. Auctionator (a teljes AH scan adatbazisa; GetAuctionAge: hany napos)
--           2. TSM (dbmarket)   3. Auctioneer (market value)
--           4. a sajat AH ful utolso lekerdezese (NS.AHQ.prices: legolcsobb darabar)
-- Minden kulso hivas pcall-lal; egyik addon sem kotelezo. Itemenkent rovid ideig cache-eljuk.
-- Vissza: vendor, ah, best, source, age (napok; nil = ismeretlen).
--   best = max(vendor, ah); source = az AH ar forrasa ("Auctionator" / "TSM" / "Auctioneer" / "AH scan").
local ADDON_NAME, NS = ...

local CALLER_ID = "AdventurersKit" -- az Auctionator API-nak string callerID kell
local CACHE_TTL = 30               -- mp
NS.PRICE_CALLER_ID = CALLER_ID

local cache = {}   -- kulcs (itemID vagy link) -> { t, vendor, ah, src, age }
local seenA, seenT -- az utoljara latott Auctionator / TSM tabla: ha valtozik, uritjuk a cache-t
local registered

local function Now() return GetTime and GetTime() or 0 end

function NS.ItemPriceFlush() wipe(cache) end

-- itemID egy szambol, "123"-bol vagy linkbol / item stringbol
local function ItemID(item)
    if type(item) == "number" then return item end
    if type(item) == "string" then return tonumber(item) or tonumber(item:match("item:(%d+)")) end
end
NS.ItemPriceID = ItemID

local function Positive(ok, v)
    v = ok and tonumber(v)
    if v and v > 0 then return v end
end

local function Auctionator()
    local A = rawget(_G, "Auctionator")
    local api = type(A) == "table" and type(A.API) == "table" and A.API.v1
    if type(api) == "table" then return api end
end

-- Az Auctionator teljes scan utan szol: akkor ujraszamolunk
local function Register(api)
    if registered or type(api.RegisterForDBUpdate) ~= "function" then return end
    registered = true
    pcall(api.RegisterForDBUpdate, CALLER_ID, function() wipe(cache) end)
end

local function FromAuctionator(id, link)
    local api = Auctionator()
    if not api then return end
    Register(api)
    local v
    if link and type(api.GetAuctionPriceByItemLink) == "function" then
        v = Positive(pcall(api.GetAuctionPriceByItemLink, CALLER_ID, link))
    end
    if not v and type(api.GetAuctionPriceByItemID) == "function" then
        v = Positive(pcall(api.GetAuctionPriceByItemID, CALLER_ID, id))
    end
    if not v then return end
    local age
    if link and type(api.GetAuctionAgeByItemLink) == "function" then
        local ok, a = pcall(api.GetAuctionAgeByItemLink, CALLER_ID, link)
        age = ok and tonumber(a) or nil
    end
    if age == nil and type(api.GetAuctionAge) == "function" then
        local ok, a = pcall(api.GetAuctionAge, CALLER_ID, id)
        age = ok and tonumber(a) or nil
    end
    return v, "Auctionator", age
end

local function FromTSM(id)
    local T = rawget(_G, "TSM_API")
    if type(T) ~= "table" or type(T.GetCustomPriceValue) ~= "function" then return end
    local v = Positive(pcall(T.GetCustomPriceValue, "dbmarket", "i:" .. id))
    if v then return v, "TSM" end
end

local function FromAuctioneer(link)
    local Auc = rawget(_G, "AucAdvanced")
    if not (link and type(Auc) == "table" and type(Auc.API) == "table" and type(Auc.API.GetMarketValue) == "function") then return end
    local v = Positive(pcall(Auc.API.GetMarketValue, link))
    if v then return v, "Auctioneer" end
end

-- A sajat AH ful utolso lekerdezese: a legolcsobb darabar (nem a sajat aukciod)
local function FromOwnScan(id)
    local A = NS.AHQ
    local p = A and type(A.prices) == "table" and A.prices[id]
    if not (p and type(p.listings) == "table") then return end
    local best
    for _, l in ipairs(p.listings) do
        local unit = tonumber(l.unit)
        if not unit and (tonumber(l.buyout) or 0) > 0 and (tonumber(l.count) or 0) > 0 then unit = l.buyout / l.count end
        if unit and unit > 0 and (not best or unit < best) then best = unit end
    end
    if best then return math.floor(best + 0.5), "AH scan", p.time and math.max(0, Now() - p.time) / 86400 or nil end
end

local function AHPrice(id, link)
    local v, src, age = FromAuctionator(id, link)
    if v then return v, src, age end
    v, src = FromTSM(id)
    if v then return v, src end
    v, src = FromAuctioneer(link)
    if v then return v, src end
    return FromOwnScan(id)
end

-- NS.ItemPrice(itemIdOrLink) -> vendor, ah, best, source, age
function NS.ItemPrice(item)
    local id = ItemID(item)
    if not id then return end
    local link = type(item) == "string" and item:find("item:", 1, true) and item or nil
    local A, T = rawget(_G, "Auctionator"), rawget(_G, "TSM_API")
    if A ~= seenA or T ~= seenT then wipe(cache); seenA, seenT = A, T end
    local key = link or id
    local now = Now()
    local c = cache[key]
    if not (c and now - c.t < CACHE_TTL) then
        local ok, sell = pcall(function() return select(11, NS.SafeItem.GetItemInfo(id)) end)
        local vendor = ok and tonumber(sell) or nil
        local ah, src, age = AHPrice(id, link)
        c = { t = now, vendor = vendor, ah = ah, src = src, age = age }
        if vendor ~= nil then cache[key] = c end -- az item info meg nincs meg: legkozelebb ujra
    end
    local best = math.max(c.vendor or 0, c.ah or 0)
    return c.vendor, c.ah, (best > 0 and best or c.vendor), c.src, c.age
end

-- Melyik aukcios addon ad arat (a "Best sale" sor csak ekkor latszik); a sajat scan nem szamit
function NS.PriceAddon()
    if Auctionator() then return "Auctionator" end
    local T = rawget(_G, "TSM_API")
    if type(T) == "table" and T.GetCustomPriceValue then return "TSM" end
    local Auc = rawget(_G, "AucAdvanced")
    if type(Auc) == "table" and Auc.API then return "Auctioneer" end
end

-- Kor roviden: "today", "2d"
function NS.PriceAgeText(age)
    age = tonumber(age)
    if not age then return nil end
    if age < 1 then return NS.L["today"] end
    return ("%dd"):format(math.floor(age))
end

---------------------------------------------------------------------------
-- Penz kiirasa: arany / ezust / rez ikonnal (a kliens ermeikonjai), a betu ("g s c") helyett.
-- Az ikon magassaga 0 = a szoveg sormagassaga, igy minden betumerethez illik.
-- NS.FormatMoney(c)         -> "1[arany] 2[ezust] 3[rez]" (a nulla reszek kimaradnak, mint a jatekban)
-- NS.FormatMoney(c, true)   -> "1g 2s 3c" sima szoveg (tesztek / ahol ikon nem jelenhet meg)
-- NS.FormatMoney(c, nil, true) -> rovid: aranynal csak arany + ezust, ezustnel ezust + rez (stat doboz)
---------------------------------------------------------------------------
local COIN = {
    g = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
    s = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
    c = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
NS.COIN_ICONS = COIN
function NS.FormatMoney(c, plain, short)
    c = math.floor((tonumber(c) or 0) + 0.5)
    local neg = c < 0
    if neg then c = -c end
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local function part(n, k) return n .. (plain and k or COIN[k]) end
    local parts = {}
    if g > 0 then parts[#parts + 1] = part(g, "g") end
    if s > 0 then parts[#parts + 1] = part(s, "s") end
    if cp > 0 then parts[#parts + 1] = part(cp, "c") end
    if #parts == 0 then parts[1] = part(0, "c") end
    if short and #parts > 2 then parts[3] = nil end
    return (neg and "-" or "") .. table.concat(parts, " ")
end

-- Forras szovegkent a tooltipekbe: "AH (Auctionator, 2d)", "vendor"
function NS.PriceSourceText(src, age)
    if not src or src == "vendor" then return NS.L["vendor"] end
    local a = NS.PriceAgeText(age)
    return ("AH (%s%s)"):format(src, a and (", " .. a) or "")
end
