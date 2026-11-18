-- Adventurer's Kit: "Quest items" ful az aukcios haznal.
-- Az AH ablak jobb szelen egy kis ikon ful; kattintasra egy panel stilusu ablak a quest logod
-- meg hianyzo, AH-n megveheto quest itemeivel (quest-only / BoP itemek nelkul), az utolso sajat
-- lekerdezes legolcsobb araival, kereses (sorra kattintas), Buy gomb megerositessel, alul
-- osszesen + Buy all. A vasarlas (PlaceAuctionBid) kattintasonkent egy aukcio: a kliens
-- hardveres esemenyt (kattintast) ker hozza, ezert a megerosito ablak gombja lepeget.
local ADDON_NAME, NS = ...
local L = NS.L
local S = NS.Style
local GetItemCount, GetItemInfo = NS.SafeItem.GetItemCount, NS.SafeItem.GetItemInfo -- biztonsagos item API (Core\Init.lua)

local A = {}
NS.AHQ = A

local PAGE_SIZE = 50      -- NUM_AUCTION_ITEMS_PER_PAGE
local MAX_PAGES = 3       -- itemenkent legfeljebb ennyi oldalt olvasunk (quest itembol ritkan van tobb)
local QUERY_TIMEOUT = 6   -- mp: ha addig nincs AUCTION_ITEM_LIST_UPDATE, ujra / tovabb
local RESCAN_AGE = 300    -- mp: panel nyitasakor ennel regebbi arakat ujra lekerdezunk
local SEARCH_PAUSE = 20   -- mp: sorra kattintott kereses utan ennyi ideig nem kerdezunk (ne irjuk felul a talalatot)
local ICON = "Interface\\Icons\\INV_Misc_Coin_02"

local function Now() return GetTime and GetTime() or 0 end
local function Me() return UnitName and UnitName("player") or nil end

---------------------------------------------------------------------------
-- Penz szovegkent: "1g 2s 3c" (a megerosito szovegben), ikonokkal a listaban
---------------------------------------------------------------------------
function A.FormatCoins(c)
    c = math.floor((tonumber(c) or 0) + 0.5)
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if cp > 0 or #parts == 0 then parts[#parts + 1] = cp .. "c" end
    return table.concat(parts, " ")
end
local function Money(c)
    local f = rawget(_G, "GetCoinTextureString")
    if type(f) == "function" then
        local ok, s = pcall(f, math.floor((tonumber(c) or 0) + 0.5))
        if ok and type(s) == "string" then return s end
    end
    return A.FormatCoins(c)
end

---------------------------------------------------------------------------
-- Mi kell meg: a quest log item objective-jei (Questie), ami meg hianyzik es AH-n lehet.
-- Hianyzik = Needed - max(Collected, ami a taskaban van) - amit most vettel (postaban var).
-- bindType 4 (quest item) es 1 (BoP) nem lehet az AH-n: kimarad.
---------------------------------------------------------------------------
local pendingMail = {} -- itemId -> megvett darab (az AH a postara kuldi; MAIL_CLOSED torli)
A.pendingMail = pendingMail
A.loading = 0           -- hany item info nincs meg betoltve (GET_ITEM_INFO_RECEIVED-re ujra)

function A.NeededItems()
    local out, byId = {}, {}
    A.loading = 0
    local C = NS.C
    if not (C and C.NumLogEntries and C.GetLogEntry and C.GetQuestieQuest) then return out end
    for i = 1, C.NumLogEntries() do
        local title, isHeader, qid, done = C.GetLogEntry(i)
        if not isHeader and qid and not done then
            local q = C.GetQuestieQuest(qid)
            if q and type(q.Objectives) == "table" then
                for _, o in pairs(q.Objectives) do
                    local id = type(o) == "table" and o.Type == "item" and tonumber(o.Id)
                    if id and not o.Completed then
                        local needed = tonumber(o.Needed) or 0
                        local have = math.max(tonumber(o.Collected) or 0, GetItemCount(id) or 0) + (pendingMail[id] or 0)
                        local need = needed - have
                        if need > 0 then
                            local name, _, _, _, _, _, _, _, _, icon, _, _, _, bind = GetItemInfo(id)
                            if not name then
                                A.loading = A.loading + 1
                            elseif bind ~= 4 and bind ~= 1 then
                                local e = byId[id]
                                if e then
                                    e.need = e.need + need
                                    e.quest = e.quest .. ", " .. (title or "?")
                                else
                                    e = { id = id, name = name, icon = icon, need = need, quest = title or "?", qid = qid }
                                    byId[id] = e
                                    out[#out + 1] = e
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.quest ~= b.quest then return a.quest < b.quest end
        return a.name < b.name
    end)
    return out
end

---------------------------------------------------------------------------
-- Ar matek. listing = { count, buyout, owner, page, idx }
-- A.Plan: a legolcsobb aukcio-osszeallitas, ami fedezi a 'need' darabot (0/1 hatizsak:
-- dp[c] = legkisebb osszeg, amivel min(c, need) darab megvan). Ha nincs eleg aukcio: mind.
---------------------------------------------------------------------------
local function Usable(l, me)
    return (tonumber(l.buyout) or 0) > 0 and (tonumber(l.count) or 0) > 0 and not (me and l.owner == me)
end
local function ByUnit(a, b)
    local ua, ub = a.buyout / a.count, b.buyout / b.count
    if ua ~= ub then return ua < ub end
    return a.buyout < b.buyout
end

function A.Plan(listings, need, me)
    need = math.floor(tonumber(need) or 0)
    local cand = {}
    for _, l in ipairs(listings or {}) do
        if Usable(l, me) then cand[#cand + 1] = l end
    end
    if need <= 0 or #cand == 0 then return nil end
    table.sort(cand, ByUnit)
    local plan = { lowestUnit = cand[1].buyout / cand[1].count, picks = {}, cost = 0, covered = 0, available = 0 }
    for _, l in ipairs(cand) do plan.available = plan.available + l.count end
    local INF = math.huge
    local prev, hist = {}, {}
    for c = 0, need do prev[c] = (c == 0) and 0 or INF end
    for i, l in ipairs(cand) do
        local cur, took = {}, {}
        for c = 0, need do cur[c] = prev[c] end
        for c = 0, need do
            if prev[c] < INF then
                local nc = math.min(need, c + l.count)
                local v = prev[c] + l.buyout
                if v < cur[nc] then cur[nc], took[nc] = v, c end
            end
        end
        hist[i], prev = took, cur
    end
    if prev[need] < INF then
        local c = need
        for i = #cand, 1, -1 do
            local from = hist[i][c]
            if from then
                plan.picks[#plan.picks + 1] = cand[i]
                c = from
            end
        end
        table.sort(plan.picks, ByUnit)
    else
        for _, l in ipairs(cand) do plan.picks[#plan.picks + 1] = l end
        plan.partial = true
    end
    for _, l in ipairs(plan.picks) do
        plan.cost = plan.cost + l.buyout
        plan.covered = plan.covered + l.count
        local u = l.buyout / l.count
        if not plan.maxUnit or u > plan.maxUnit then plan.maxUnit = u end
    end
    return plan
end

-- Vasarlas kozben: a frissen lekerdezett oldalon a legolcsobb aukcio, ami belefer a megerositett
-- arba (egysegar <= a terv legdragabb egysegara, es az eddigi koltes + ez <= a megerositett osszeg)
function A.PickNext(listings, step, me)
    local best
    for _, l in ipairs(listings or {}) do
        if Usable(l, me) and l.buyout <= step.maxUnit * l.count + 1e-6 and step.spent + l.buyout <= step.cap
            and (not best or ByUnit(l, best)) then
            best = l
        end
    end
    return best
end

-- A "list" aktualis oldalabol az adott item aukcioi. Vissza: sajat item aukcioi, idegen sorok
-- szama (mas kereses eredmenye?), osszes talalat.
function A.ReadList(id, name, page)
    local mine, other = {}, 0
    if not (GetNumAuctionItems and GetAuctionItemInfo) then return mine, 0, 0 end
    local n, total = GetNumAuctionItems("list")
    n = tonumber(n) or 0
    for i = 1, n do
        local nm, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemId = GetAuctionItemInfo("list", i)
        itemId = tonumber(itemId)
        if not itemId and GetAuctionItemLink then
            local link = GetAuctionItemLink("list", i)
            itemId = link and tonumber(tostring(link):match("item:(%d+)"))
        end
        if itemId == id or (not itemId and nm and nm == name) then
            mine[#mine + 1] = { idx = i, page = page, count = tonumber(count) or 1, buyout = tonumber(buyout) or 0, owner = owner }
        elseif nm then
            other = other + 1
        end
    end
    return mine, other, tonumber(total) or n
end

-- Modern (retail) AH: a Forever kliens ezt hasznalja (C_AuctionHouse). A klasszikus "list" API
-- (QueryAuctionItems, AUCTION_ITEM_LIST_UPDATE) ott nincs; az csak tartalek mas klienseken.
local function Modern()
    local C = rawget(_G, "C_AuctionHouse")
    if type(C) == "table" and type(C.SendSearchQuery) == "function" and type(C.MakeItemKey) == "function" then return C end
end
A.Modern = Modern

-- Commodity (darabra vett aru, pl. Linen Cloth): barmennyi darab veheto, a legolcsobb egysegektol
-- kezdve. listing = { count, unit, commodity = true }. Vissza: mint A.Plan (picks: hasznalt sorok).
function A.PlanCommodity(listings, need, me)
    need = math.floor(tonumber(need) or 0)
    local cand = {}
    for _, l in ipairs(listings or {}) do
        if (tonumber(l.unit) or 0) > 0 and (tonumber(l.count) or 0) > 0 and not (me and l.owner == me) then cand[#cand + 1] = l end
    end
    if need <= 0 or #cand == 0 then return nil end
    table.sort(cand, function(a, b) return a.unit < b.unit end)
    local plan = { commodity = true, lowestUnit = cand[1].unit, picks = {}, cost = 0, covered = 0, available = 0 }
    for _, l in ipairs(cand) do plan.available = plan.available + l.count end
    for _, l in ipairs(cand) do
        if plan.covered >= need then break end
        local take = math.min(l.count, need - plan.covered)
        plan.picks[#plan.picks + 1] = l
        plan.cost = plan.cost + take * l.unit
        plan.covered = plan.covered + take
        plan.maxUnit = l.unit
    end
    plan.partial = plan.covered < need or nil
    return plan
end

-- Modern keresesi eredmenyek. kind: "commodity" (key = itemID) vagy "item" (key = itemKey)
function A.ReadModern(kind, key)
    local C, mine = Modern(), {}
    if not C then return mine end
    if kind == "commodity" then
        local ok, n = pcall(C.GetNumCommoditySearchResults, key)
        for i = 1, (ok and tonumber(n) or 0) do
            local ok2, r = pcall(C.GetCommoditySearchResultInfo, key, i)
            if ok2 and type(r) == "table" then
                local cnt = (tonumber(r.quantity) or 0) - (tonumber(r.numOwnerItems) or 0) -- a sajatodat nem veszed meg
                if cnt > 0 and (tonumber(r.unitPrice) or 0) > 0 then
                    mine[#mine + 1] = { count = cnt, unit = r.unitPrice, buyout = r.unitPrice * cnt, commodity = true }
                end
            end
        end
    else
        local ok, n = pcall(C.GetNumItemSearchResults, key)
        for i = 1, (ok and tonumber(n) or 0) do
            local ok2, r = pcall(C.GetItemSearchResultInfo, key, i)
            if ok2 and type(r) == "table" and not r.containsOwnerItem then
                mine[#mine + 1] = { count = tonumber(r.quantity) or 1, buyout = tonumber(r.buyoutPrice) or 0, auctionID = r.auctionID }
            end
        end
    end
    return mine
end

---------------------------------------------------------------------------
-- Lekerdezes sor (CanSendAuctionQuery throttling)
---------------------------------------------------------------------------
local prices = {}   -- itemId -> { pages = { [p] = listings }, listings, time, scanning }
A.prices = prices
local queue = {}    -- { id, name, page, tries }
local active        -- elkuldott lekerdezes: { id, name, page, purpose = "scan" | "buy", sent, tries }
local pauseUntil = 0
local ahOpen = false
local buy           -- futo vasarlas (lent)

local function CanQuery()
    local C = Modern()
    if C then
        if type(C.IsThrottledMessageSystemReady) ~= "function" then return true end
        local ok, ready = pcall(C.IsThrottledMessageSystemReady)
        return ok and ready and true or false
    end
    if type(CanSendAuctionQuery) ~= "function" or type(QueryAuctionItems) ~= "function" then return false end
    local ok, can = pcall(CanSendAuctionQuery)
    return ok and can and true or false
end

local function Send(q, purpose)
    local C, ok = Modern(), false
    if C then
        -- egy item osszes aukcioja, ar szerint; a sajatjaid kulon sorban (splitOwnedItems)
        local ok1, key = pcall(C.MakeItemKey, q.id)
        if ok1 and key then ok = pcall(C.SendSearchQuery, key, { { sortOrder = 0, reverseSort = false } }, true) end
    else
        -- QueryAuctionItems(text, minLevel, maxLevel, page, usable, quality, getAll, exactMatch)
        ok = type(QueryAuctionItems) == "function" and pcall(QueryAuctionItems, q.name, nil, nil, q.page or 0, false, -1, false, true)
    end
    if not ok then return false end
    active = { id = q.id, name = q.name, page = q.page or 0, purpose = purpose, sent = Now(), tries = q.tries or 0 }
    return true
end

local function QueueScan(e, front)
    for _, q in ipairs(queue) do if q.id == e.id then return end end
    local q = { id = e.id, name = e.name, page = 0 }
    if front then table.insert(queue, 1, q) else queue[#queue + 1] = q end
    local p = prices[e.id] or {}
    prices[e.id] = p
    p.scanning = true
    p.pages = {}
end

local Refresh -- a panel ujrarajzolasa (lent)
local BuyOnList, BuyQueryNeeded, BuyTimeout

local function FinishScan(id)
    local p = prices[id]
    if not p then return end
    local all = {}
    for pg = 0, MAX_PAGES - 1 do
        for _, l in ipairs(p.pages and p.pages[pg] or {}) do all[#all + 1] = l end
    end
    p.listings, p.time, p.scanning = all, Now(), nil
end

-- AUCTION_ITEM_LIST_UPDATE a sajat lekerdezesunkre
local function OnList(modernKind, key)
    if not active then return end
    local q = active
    local mine, other, total
    if modernKind then
        local id = modernKind == "commodity" and tonumber(key) or (type(key) == "table" and tonumber(key.itemID))
        if id ~= q.id then return end -- mas kereses eredmenye (pl. az AH sajat listaja)
        mine, other, total = A.ReadModern(modernKind, key), 0, 0
    else
        mine, other, total = A.ReadList(q.id, q.name, q.page)
    end
    if #mine == 0 and other > 0 then
        -- mas kereses eredmenye (pl. kozben te kerestel): meg egyszer, aztan feladjuk
        active = nil
        if q.purpose == "scan" then
            if q.tries < 2 then table.insert(queue, 1, { id = q.id, name = q.name, page = q.page, tries = q.tries + 1 })
            else FinishScan(q.id) end
            if Refresh then Refresh() end
        elseif BuyQueryNeeded then
            BuyQueryNeeded(q.tries + 1)
        end
        return
    end
    active = nil
    if q.purpose == "buy" then
        if BuyOnList then BuyOnList(mine, q) end
        return
    end
    local p = prices[q.id]
    if not p then return end
    p.pages = p.pages or {}
    p.pages[q.page] = mine
    if total > (q.page + 1) * PAGE_SIZE and q.page + 1 < MAX_PAGES then
        table.insert(queue, 1, { id = q.id, name = q.name, page = q.page + 1 })
    else
        FinishScan(q.id)
    end
    if Refresh then Refresh() end
end
A.OnList = OnList

-- Idozito (amig az AH nyitva): a kovetkezo lekerdezes, ha a szerver enged
local function Tick()
    if not ahOpen then return end
    local now = Now()
    if active and now - active.sent > QUERY_TIMEOUT then
        local q = active
        active = nil
        if q.purpose == "buy" then
            if BuyTimeout then BuyTimeout(q) end
        else
            if q.tries < 1 then table.insert(queue, 1, { id = q.id, name = q.name, page = q.page, tries = q.tries + 1 })
            else FinishScan(q.id) end
            if Refresh then Refresh() end
        end
    end
    if buy and buy.waitPrice and now - buy.waitPrice > QUERY_TIMEOUT and BuyTimeout then BuyTimeout() end
    if active or not CanQuery() then return end
    if buy and buy.wantQuery then
        local st = buy.items[buy.cur]
        if st and Send({ id = st.id, name = st.name, page = st.pages[st.pageIdx] or 0, tries = buy.wantQuery }, "buy") then
            buy.wantQuery = nil
        end
        return
    end
    if buy or now < pauseUntil then return end
    local q = table.remove(queue, 1)
    if q then
        if not Send(q, "scan") then table.insert(queue, 1, q) end
    end
end
A.Tick = Tick

function A.Scan(items, force)
    for _, e in ipairs(items or {}) do
        local p = prices[e.id]
        if force or not p or (not p.scanning and (not p.time or Now() - p.time > RESCAN_AGE)) then QueueScan(e) end
    end
end

---------------------------------------------------------------------------
-- Kereses az AH-ban (sorra kattintas): Blizzard Browse, kulonben Auctionator, kulonben sima lekerdezes
---------------------------------------------------------------------------
function A.Search(name)
    if not name then return end
    pauseUntil = Now() + SEARCH_PAUSE
    -- modern AH (Forever): a Buy ful keresoje; idezojelben = pontos egyezes
    local ahf = rawget(_G, "AuctionHouseFrame")
    local bar = type(ahf) == "table" and rawget(ahf, "SearchBar")
    if type(bar) == "table" and type(rawget(bar, "SearchBox")) == "table" and bar.StartSearch then
        local mode = rawget(_G, "AuctionHouseFrameDisplayMode")
        if ahf.SetDisplayMode and type(mode) == "table" and mode.Buy then pcall(ahf.SetDisplayMode, ahf, mode.Buy) end
        bar.SearchBox:SetText('"' .. name .. '"')
        if pcall(bar.StartSearch, bar) then return "Blizzard" end
    end
    local box, search = rawget(_G, "BrowseName"), rawget(_G, "AuctionFrameBrowse_Search")
    if type(box) == "table" and box.SetText and type(search) == "function" then
        local browse, tab1 = rawget(_G, "AuctionFrameBrowse"), rawget(_G, "AuctionFrameTab1")
        if type(browse) == "table" and browse.IsShown and not browse:IsShown() and type(tab1) == "table" and tab1.Click then
            pcall(tab1.Click, tab1)
        end
        box:SetText(name)
        if pcall(search) then return "Blizzard" end
    end
    local Au = rawget(_G, "Auctionator")
    local api = type(Au) == "table" and Au.API and Au.API.v1
    if api and type(api.MultiSearchExact) == "function" and pcall(api.MultiSearchExact, ADDON_NAME, { name }) then
        return "Auctionator"
    end
    if type(QueryAuctionItems) == "function" and pcall(QueryAuctionItems, name, nil, nil, 0, false, -1, false, true) then
        return "Query"
    end
end

---------------------------------------------------------------------------
-- Vasarlas: egy megerosites, utana kattintasonkent egy aukcio
---------------------------------------------------------------------------
local popup -- megerosito ablak (lent)
local UpdatePopup

-- items: { { entry, plan } }
local function StartBuy(list)
    local b = { items = {}, cur = 1, bought = 0, spentAll = 0, capAll = 0 }
    for _, x in ipairs(list) do
        local e, plan = x.entry, x.plan
        if plan and plan.cost > 0 then
            local pages, seen = {}, {}
            for _, l in ipairs(plan.picks) do
                local pg = l.page or 0
                if not seen[pg] then seen[pg] = true; pages[#pages + 1] = pg end
            end
            table.sort(pages)
            b.items[#b.items + 1] = {
                id = e.id, name = e.name, need = math.min(e.need, plan.covered), cap = plan.cost,
                maxUnit = plan.maxUnit, spent = 0, got = 0, pages = pages, pageIdx = 1, count = plan.covered,
                auctions = #plan.picks, commodity = plan.commodity,
            }
            b.capAll = b.capAll + plan.cost
        end
    end
    if #b.items == 0 then return end
    buy = b
    A.buy = b
    return b
end

local function BuyNextItem(reason)
    local st = buy.items[buy.cur]
    if reason and st then buy.note = reason end
    buy.cur = buy.cur + 1
    buy.ready, buy.waitPrice, buy.needStart = nil, nil, nil
    local nxt = buy.items[buy.cur]
    if not nxt then buy.done = true
    elseif nxt.commodity then buy.needStart = true -- az ar kerese is kattintasra megy (mint a Blizzard UI-ban)
    else buy.wantQuery = 1 end
end

-- Commodity: ar kerese a szervertol (StartCommoditiesPurchase); kattintasbol hivjuk.
-- Valasz: COMMODITY_PRICE_UPDATED (egysegar, osszesen) vagy COMMODITY_PRICE_UNAVAILABLE.
function A.StartCommodity()
    local C, st = Modern(), buy and buy.items[buy.cur]
    if not (C and st and st.commodity) then return end
    buy.needStart, buy.ready = nil, nil
    st.qty = st.need - st.got
    if type(C.StartCommoditiesPurchase) ~= "function" or not pcall(C.StartCommoditiesPurchase, st.id, st.qty) then
        BuyNextItem(L["The game refused the purchase."])
    else
        buy.waitPrice = Now()
    end
    if UpdatePopup then UpdatePopup() end
end

function A.OnCommodityPrice(unit, total)
    if not (buy and buy.waitPrice) then return end
    local st = buy.items[buy.cur]
    buy.waitPrice = nil
    if not st then return end
    total = tonumber(total) or ((tonumber(unit) or 0) * (st.qty or 0))
    if total > 0 and st.spent + total <= st.cap then
        buy.ready = { commodity = true, count = st.qty, buyout = total }
    else
        local C = Modern()
        if C and type(C.CancelCommoditiesPurchase) == "function" then pcall(C.CancelCommoditiesPurchase) end
        BuyNextItem((L["%s now costs %s, more than you confirmed; skipped."]):format(st.name, A.FormatCoins(total)))
    end
    if UpdatePopup then UpdatePopup() end
end

BuyOnList = function(mine, q)
    if not buy or buy.done then return end
    local st = buy.items[buy.cur]
    if not st or st.id ~= q.id then return end
    local l = A.PickNext(mine, st, Me())
    if l then
        buy.ready = l
        buy.searching = nil
    elseif st.pages[st.pageIdx + 1] then
        st.pageIdx = st.pageIdx + 1
        buy.wantQuery = 1
    else
        BuyNextItem((L["No %s left at or below the confirmed price."]):format(st.name))
    end
    if UpdatePopup then UpdatePopup() end
end

-- tries: hanyadik probalkozas jon (1 = elso); a harmadik utan kihagyjuk az itemet
BuyQueryNeeded = function(tries)
    if not buy then return end
    if tries > 3 then BuyNextItem(L["The auction house did not answer; skipped."]) else buy.wantQuery = tries end
    if UpdatePopup then UpdatePopup() end
end
-- q nelkul: a commodity ar nem jott meg idoben
BuyTimeout = function(q)
    if q then BuyQueryNeeded((q.tries or 1) + 1) return end
    BuyNextItem(L["The auction house did not answer; skipped."])
    if UpdatePopup then UpdatePopup() end
end

-- Egy kattintas: a kivalasztott aukcio megvetele (PlaceAuctionBid kattintast ker)
function A.BuyClick()
    if not buy then return end
    if buy.done then return "done" end
    local st, l = buy.items[buy.cur], buy.ready
    if not (st and l) then return "wait" end
    local C = Modern()
    if not C and l.idx then
        -- klasszikus: az index meg ugyanazt az aukciot mutatja? (kozben frissulhetett a lista)
        local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemId = GetAuctionItemInfo("list", l.idx)
        if (tonumber(itemId) and tonumber(itemId) ~= st.id) or tonumber(count) ~= l.count or tonumber(buyout) ~= l.buyout then
            buy.ready, buy.wantQuery = nil, 1
            if UpdatePopup then UpdatePopup() end
            return "stale"
        end
    end
    if st.spent + l.buyout > st.cap then -- soha nem a megerositett ar folott
        BuyNextItem()
        if UpdatePopup then UpdatePopup() end
        return "cap"
    end
    if GetMoney and GetMoney() < l.buyout then
        buy.note = L["Not enough money."]
        buy.done = true
        if UpdatePopup then UpdatePopup() end
        return "money"
    end
    local ok
    if l.commodity then
        ok = C and type(C.ConfirmCommoditiesPurchase) == "function" and pcall(C.ConfirmCommoditiesPurchase, st.id, l.count)
    elseif l.auctionID then
        ok = C and type(C.PlaceBid) == "function" and pcall(C.PlaceBid, l.auctionID, l.buyout)
    else
        ok = type(PlaceAuctionBid) == "function" and pcall(PlaceAuctionBid, "list", l.idx, l.buyout)
    end
    if not ok then
        buy.note = L["The game refused the purchase."]
        buy.ready = nil
        if l.commodity then BuyNextItem() else buy.wantQuery = 1 end
        if UpdatePopup then UpdatePopup() end
        return "error"
    end
    st.spent, st.got = st.spent + l.buyout, st.got + l.count
    buy.spentAll, buy.bought = buy.spentAll + l.buyout, buy.bought + 1
    pendingMail[st.id] = (pendingMail[st.id] or 0) + l.count
    buy.last = { st = st, l = l, t = Now() }
    buy.ready = nil
    if st.got >= st.need then BuyNextItem() else buy.wantQuery = 1 end
    if UpdatePopup then UpdatePopup() end
    if Refresh then Refresh() end
    return "bought"
end

-- Hibauzenet a vasarlas utan (elkelt kozben, nincs eleg penz): visszavonjuk a szamolast
local function OnBuyError()
    local last = buy and buy.last
    if not (last and Now() - last.t < 5) then return end
    local st, l = last.st, last.l
    st.spent, st.got = st.spent - l.buyout, st.got - l.count
    buy.spentAll, buy.bought = buy.spentAll - l.buyout, buy.bought - 1
    pendingMail[st.id] = math.max(0, (pendingMail[st.id] or 0) - l.count)
    buy.last = nil
    if Refresh then Refresh() end
    if UpdatePopup then UpdatePopup() end
end

local function StopBuy()
    buy, A.buy = nil, nil
    if active and active.purpose == "buy" then active = nil end
    if popup then popup:Hide() end
end
A.StopBuy = StopBuy

---------------------------------------------------------------------------
-- UI: ful az AH mellett + panel + megerosito ablak
---------------------------------------------------------------------------
local W, H, ROW_H = 330, 400, 34
local HOSTS = { "AuctionHouseFrame", "AuctionFrame" } -- modern (Forever), klasszikus
local tab, frame
local rows = {}
local current = {} -- a lathato sorok: { entry, plan }

local function Enabled() return not (QuestFocusDB and QuestFocusDB.noAHTab) end

local function Host()
    for _, n in ipairs(HOSTS) do
        local f = rawget(_G, n)
        if type(f) == "table" and f.IsShown and f:IsShown() then return f end
    end
end

local function PriceOf(e)
    local p = prices[e.id]
    if not p then return nil, "none" end
    if p.scanning and not p.listings then return nil, "scanning" end
    if not p.listings then return nil, "none" end
    local isCom = p.listings[1] and p.listings[1].commodity
    local plan = (isCom and A.PlanCommodity or A.Plan)(p.listings, e.need, Me())
    if not plan then return nil, p.scanning and "scanning" or "empty" end
    return plan, p.scanning and "scanning" or "ok"
end

-- Aukcios addon ara (Auctionator teljes scan / TSM / Auctioneer; Core\Prices.lua), mar a ful
-- megnyitasakor; a sajat lekerdezes finomitja. A sajat scan ("AH scan") itt nem tipp, az a sor maga.
local function AddonHint(e)
    if not NS.ItemPrice then return end
    local _, ah, _, src, age = NS.ItemPrice(e.id)
    if ah and src ~= "AH scan" then return ah, src, age end
end

local function ConfirmText(list)
    if #list == 1 then
        local x = list[1]
        return (L["Buy %d x %s for %s?"]):format(x.plan.covered, x.entry.name, A.FormatCoins(x.plan.cost))
    end
    local cost, n = 0, 0
    for _, x in ipairs(list) do cost, n = cost + x.plan.cost, n + #x.plan.picks end
    return (L["Buy all: %d items (%d auctions) for %s?"]):format(#list, n, A.FormatCoins(cost))
end
A.ConfirmText = ConfirmText

local function BuildPopup()
    if popup then return popup end
    local p = S.Box("AdventurersKitAHBuy", 320, 132, L["BUY QUEST ITEMS"], "DIALOG")
    p:SetPoint("TOP", UIParent, "TOP", 0, -160)
    p:EnableMouse(true)
    p:SetToplevel(true)
    p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.text:SetPoint("TOPLEFT", 12, -26)
    p.text:SetWidth(296)
    p.text:SetJustifyH("LEFT")
    p.text:SetWordWrap(true)
    p.step = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.step:SetPoint("TOPLEFT", p.text, "BOTTOMLEFT", 0, -6)
    p.step:SetWidth(296)
    p.step:SetJustifyH("LEFT")
    p.step:SetWordWrap(true)
    p.hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.hint:SetPoint("BOTTOMLEFT", 12, 36)
    p.hint:SetWidth(296)
    p.hint:SetJustifyH("LEFT")
    p.hint:SetWordWrap(true)
    p.hint:SetText(L["One purchase per click: the game needs a click for every purchase."])
    p.ok = S.FlatButton(p, L["Buy"], 180, 22)
    p.ok.text:SetFontObject("GameFontNormal")
    p.ok:SetPoint("BOTTOMLEFT", 12, 10)
    p.ok:SetScript("OnClick", function()
        if buy and buy.done then StopBuy() return end
        if buy and buy.needStart then A.StartCommodity() return end
        A.BuyClick()
    end)
    p.cancel = S.FlatButton(p, L["Cancel"], 100, 22)
    p.cancel:SetPoint("BOTTOMRIGHT", -12, 10)
    p.cancel:SetScript("OnClick", StopBuy)
    p.close:SetScript("OnClick", StopBuy)
    p:SetScript("OnHide", function() if buy then StopBuy() end end)
    if UISpecialFrames then table.insert(UISpecialFrames, "AdventurersKitAHBuy") end
    popup = p
    return p
end

UpdatePopup = function()
    if not (popup and popup:IsShown() and buy) then return end
    local p = popup
    local hex = S.HEX
    if buy.done then
        p.step:SetText((L["Bought %d auctions for %s."]):format(buy.bought, A.FormatCoins(buy.spentAll))
            .. (buy.note and ("\n|cff" .. hex.WARN .. buy.note .. "|r") or "")
            .. (buy.bought > 0 and ("\n|cff" .. hex.DIM .. L["Bought items arrive in your mailbox."] .. "|r") or ""))
        p.ok.text:SetText(L["Close"])
        p.ok:Enable()
        p.cancel:Hide()
        return
    end
    p.cancel:Show()
    local st, l = buy.items[buy.cur], buy.ready
    local head = ("|cff" .. hex.LABEL .. L["Spent: "] .. "|r%s / %s"):format(A.FormatCoins(buy.spentAll), A.FormatCoins(buy.capAll))
    if st and l then
        p.step:SetText(head .. "\n" .. (L["Next: %d x %s for %s"]):format(l.count, st.name, A.FormatCoins(l.buyout))
            .. (buy.note and ("\n|cff" .. hex.WARN .. buy.note .. "|r") or ""))
        p.ok.text:SetText(l.commodity and L["Buy"] or (L["Buy (%d left)"]):format(math.max(1, st.need - st.got)))
        p.ok:Enable()
    elseif st and buy.needStart then
        p.step:SetText(head .. "\n" .. (L["Next: %d x %s"]):format(st.need - st.got, st.name)
            .. (buy.note and ("\n|cff" .. hex.WARN .. buy.note .. "|r") or ""))
        p.ok.text:SetText(L["Get current price"])
        p.ok:Enable()
    else
        p.step:SetText(head .. "\n|cff" .. hex.DIM .. (L["Looking up %s..."]):format(st and st.name or "?") .. "|r"
            .. (buy.note and ("\n|cff" .. hex.WARN .. buy.note .. "|r") or ""))
        p.ok.text:SetText(L["Searching..."])
        p.ok:Disable()
    end
end

local function OpenConfirm(list)
    if #list == 0 then return end
    if buy then StopBuy() end
    if not StartBuy(list) then return end
    local p = BuildPopup()
    p.text:SetText(ConfirmText(list))
    p:Show()
    if buy.items[1].commodity then
        A.StartCommodity() -- most kattintottal (Buy): az ar kerese mehet rogton
    else
        buy.wantQuery = 1 -- friss lista a vasarlas elott (az indexek / aukciok csak igy jok)
    end
    UpdatePopup()
end
A.OpenConfirm = OpenConfirm

---------------------------------------------------------------------------
-- A lista ablak
---------------------------------------------------------------------------
local function RowTooltip(row)
    local x = row.data
    if not x then return end
    local e, plan = x.entry, x.plan
    local tt = NS.TT.Begin(row, "ANCHOR_RIGHT", e.name, (L["need %d"]):format(e.need))
    NS.TT.Sub(tt, e.quest)
    if plan then
        NS.TT.Info(tt, (L["Lowest buyout: %s each"]):format(Money(plan.lowestUnit)))
        NS.TT.Info(tt, (L["Cheapest way: %d auctions, %d items, %s"]):format(#plan.picks, plan.covered, Money(plan.cost)))
        if plan.partial then NS.TT.Note(tt, (L["Only %d on the auction house."]):format(plan.available)) end
    end
    local hint, src, age = AddonHint(e)
    if hint then
        NS.TT.Info(tt, (L["%s: %s each"]):format(NS.PriceSourceText(src, age), Money(hint)))
        if not plan then NS.TT.Note(tt, L["Estimate until the live lookup finishes; Buy uses live auctions only."]) end
    end
    if (pendingMail[e.id] or 0) > 0 then
        NS.TT.Note(tt, (L["%d bought, waiting in the mailbox."]):format(pendingMail[e.id]))
    end
    NS.TT.Finish(tt, L["Click: search for it in the auction house"], L["Buy: buy the cheapest auctions after a confirmation"])
end

local function MakeRow(parent, i)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + 1))
    r:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    S.RowHighlight(r)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(24, 24)
    r.icon:SetPoint("LEFT", 2, 0)
    r.icon:SetTexCoord(S.TEXCOORD[1], S.TEXCOORD[2], S.TEXCOORD[3], S.TEXCOORD[4])
    r.buy = S.FlatButton(r, L["Buy"], 40, 18)
    r.buy:SetPoint("RIGHT", -2, 0)
    r.buy:SetScript("OnClick", function(self)
        local x = self:GetParent().data
        if x and x.plan then OpenConfirm({ x }) end
    end)
    r.buy:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Buy"], 1, 1, 1)
        GameTooltip:AddLine(L["Buys the cheapest auctions for the missing count after a confirmation, never above the price shown."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    r.buy:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.search = CreateFrame("Button", nil, r)
    r.search:SetSize(14, 14)
    r.search:SetPoint("RIGHT", r.buy, "LEFT", -4, 0)
    r.search.tex = r.search:CreateTexture(nil, "ARTWORK")
    r.search.tex:SetAllPoints()
    r.search.tex:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    r.search:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    r.search:SetScript("OnClick", function(self) self:GetParent():Click() end)
    r.search:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Search"], 1, 1, 1)
        GameTooltip:AddLine(L["Puts the item name into the auction house search and runs it."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    r.search:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.price = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.price:SetPoint("TOPRIGHT", r.search, "TOPLEFT", -6, 6)
    r.price:SetJustifyH("RIGHT")
    r.price:SetWordWrap(false)
    r.hint = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.hint:SetPoint("BOTTOMRIGHT", r.search, "BOTTOMLEFT", -6, -6)
    r.hint:SetJustifyH("RIGHT")
    r.hint:SetWordWrap(false)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 0)
    r.name:SetPoint("RIGHT", r.price, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 6, 0)
    r.sub:SetPoint("RIGHT", r.hint, "LEFT", -6, 0)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)
    r:SetScript("OnClick", function(self)
        local x = self.data
        if x then A.Search(x.entry.name) end
    end)
    r:SetScript("OnEnter", RowTooltip)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function BuildFrame()
    if frame then return frame end
    local f = CreateFrame("Frame", "AdventurersKitAHQuest", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(W, H)
    f:SetFrameStrata("HIGH")
    f:Hide()
    S.Backdrop(f, "window")
    S.Draggable(f, "ahqPos")
    f.iconTex = f:CreateTexture(nil, "ARTWORK")
    f.iconTex:SetSize(20, 20)
    f.iconTex:SetPoint("TOPLEFT", 12, -11)
    f.iconTex:SetTexture(ICON)
    f.iconTex:SetTexCoord(S.TEXCOORD[1], S.TEXCOORD[2], S.TEXCOORD[3], S.TEXCOORD[4])
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("LEFT", f.iconTex, "RIGHT", 6, 0)
    f.title:SetTextColor(S.TITLE[1], S.TITLE[2], S.TITLE[3])
    f.title:SetText(L["Quest items to buy"])
    f.close = S.CloseButton(f, true)
    f.close:SetScript("OnClick", function() A.Toggle(false) end)
    local line = S.Divider(f, 0.35)
    line:SetPoint("TOPLEFT", 12, -36)
    line:SetPoint("TOPRIGHT", -12, -36)
    f.section = S.Section(f, L["STILL NEEDED (QUEST LOG)"])
    f.section:SetPoint("TOPLEFT", 14, -42)

    f.scroll = CreateFrame("ScrollFrame", nil, f)
    f.scroll:SetPoint("TOPLEFT", 12, -60)
    f.scroll:SetPoint("BOTTOMRIGHT", -18, 74)
    f.child = CreateFrame("Frame", nil, f.scroll)
    f.child:SetSize(W - 30, 10)
    f.scroll:SetScrollChild(f.child)
    f.scroll:EnableMouseWheel(true)
    f.bar = NS.AttachScrollBar and NS.AttachScrollBar(f.scroll)
    f.scroll:SetScript("OnMouseWheel", function(self, d)
        local maxS = math.max(0, f.child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxS, self:GetVerticalScroll() - d * (ROW_H + 1) * 2)))
        if f.bar then f.bar.Update() end
    end)

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.empty:SetPoint("TOPLEFT", 14, -64)
    f.empty:SetWidth(W - 28)
    f.empty:SetJustifyH("LEFT")
    f.empty:SetWordWrap(true)

    local foot = S.Divider(f)
    foot:SetPoint("BOTTOMLEFT", 12, 68)
    foot:SetPoint("BOTTOMRIGHT", -12, 68)
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.status:SetPoint("BOTTOMLEFT", 14, 52)
    f.status:SetPoint("RIGHT", -14, 0)
    f.status:SetJustifyH("LEFT")
    f.status:SetWordWrap(false)
    f.total = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.total:SetPoint("BOTTOMLEFT", 14, 36)
    f.total:SetPoint("RIGHT", -14, 0)
    f.total:SetJustifyH("LEFT")
    f.total:SetWordWrap(false)
    f.buyAll = S.FlatButton(f, L["Buy all"], 100, 22)
    f.buyAll:SetPoint("BOTTOMRIGHT", -12, 10)
    f.buyAll:SetScript("OnClick", function()
        local list = {}
        for _, x in ipairs(current) do if x.plan then list[#list + 1] = x end end
        OpenConfirm(list)
    end)
    f.buyAll:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Buy all"], 1, 1, 1)
        GameTooltip:AddLine(L["Buys every item of the list after one confirmation, one auction per click, never above the total shown."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f.buyAll:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.rescan = S.FlatButton(f, L["Rescan prices"], 100, 22)
    f.rescan:SetPoint("BOTTOMLEFT", 12, 10)
    f.rescan:SetScript("OnClick", function()
        pauseUntil = 0
        A.Scan(A.NeededItems(), true)
        Refresh()
    end)
    f.rescan:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Rescan prices"], 1, 1, 1)
        GameTooltip:AddLine(L["Looks up every item of the list again (one search each; the results also show in the auction house list)."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f.rescan:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "AdventurersKitAHQuest") end
    frame = f
    A.frame = f
    return f
end

Refresh = function()
    if not (frame and frame:IsShown()) then return end
    local f = frame
    local items = A.NeededItems()
    wipe(current)
    local total, scanning, priced, empty = 0, 0, 0, 0
    for i, e in ipairs(items) do
        local plan, st = PriceOf(e)
        current[i] = { entry = e, plan = plan, state = st }
        if plan then total, priced = total + plan.cost, priced + 1 end
        if st == "scanning" then scanning = scanning + 1 end
        if st == "empty" then empty = empty + 1 end
    end
    local hex = S.HEX
    for i, x in ipairs(current) do
        local r = rows[i] or MakeRow(f.child, i)
        rows[i] = r
        r.data = x
        local e, plan = x.entry, x.plan
        r.icon:SetTexture(e.icon or 134400)
        r.name:SetText(("|cff%s%d x|r %s"):format(hex.GOLD, e.need, e.name))
        r.sub:SetText(e.quest)
        if plan then
            r.price:SetText(Money(plan.cost) .. (plan.partial and ("|cff" .. hex.WARN .. " *|r") or ""))
            local hint, src = AddonHint(e)
            r.hint:SetText(plan.partial and ((L["only %d"]):format(plan.available))
                or (hint and (("%s %s"):format(src, Money(hint))) or (L["%s each"]):format(Money(plan.lowestUnit))))
            r.buy:Enable()
            r.buy.text:SetFontObject("GameFontNormalSmall")
        else
            local hint, src = AddonHint(e)
            -- nincs meg sajat lekerdezes: az addon ara becsleskent (~, halvany); Buy csak elo adatbol
            r.price:SetText(x.state == "empty" and ("|cff" .. hex.BAD .. L["none"] .. "|r")
                or hint and ("|cff" .. hex.DIM .. "~" .. Money(hint * e.need) .. "|r")
                or x.state == "scanning" and ("|cff" .. hex.DIM .. "...|r") or ("|cff" .. hex.DIM .. "?|r"))
            r.hint:SetText(hint and (("%s %s"):format(src, Money(hint))) or "")
            r.buy:Disable()
            r.buy.text:SetFontObject("GameFontDisableSmall")
        end
        r:Show()
    end
    for i = #current + 1, #rows do rows[i]:Hide(); rows[i].data = nil end
    f.child:SetHeight(math.max(10, #current * (ROW_H + 1)))
    f.child:SetWidth(f.scroll:GetWidth() or (W - 30))
    if f.bar then f.bar.Update() end

    if #current == 0 then
        f.empty:SetText(A.loading > 0 and L["Loading item info..."]
            or L["Nothing to buy: no missing quest item in your log can be sold on the auction house (quest-only and soulbound items are left out)."])
        f.empty:Show()
    else
        f.empty:Hide()
    end
    if scanning > 0 or #queue > 0 or (active and active.purpose == "scan") then
        f.status:SetText((L["Looking up prices... %d / %d"]):format(#current - scanning, #current))
    elseif Now() < pauseUntil then
        f.status:SetText(L["Price lookups paused while you search."])
    else
        f.status:SetText(L["Prices from your last lookup; click a row to search, Buy to buy."])
    end
    f.total:SetText(("|cff%s%s|r %s"):format(hex.LABEL, L["Total if you buy all:"], priced > 0 and Money(total) or "-")
        .. (empty > 0 and ("  |cff" .. hex.DIM .. (L["(%d not on the AH)"]):format(empty) .. "|r") or ""))
    if priced > 0 then f.buyAll:Enable(); f.buyAll.text:SetFontObject("GameFontNormalSmall")
    else f.buyAll:Disable(); f.buyAll.text:SetFontObject("GameFontDisableSmall") end
end
A.Refresh = function() Refresh() end
A.current, A.rows = current, rows

local function PlaceFrame()
    if S.RestorePos(frame, "ahqPos") then return end
    frame:ClearAllPoints()
    if tab and tab:IsShown() then
        frame:SetPoint("TOPLEFT", tab, "TOPRIGHT", 2, 0)
    else
        frame:SetPoint("LEFT", UIParent, "LEFT", 800, 0)
    end
end

function A.Toggle(show)
    if show == nil then show = not (frame and frame:IsShown()) end
    if show then
        BuildFrame()
        PlaceFrame()
        frame:Show()
        A.Scan(A.NeededItems())
        Refresh()
    elseif frame then
        frame:Hide()
        StopBuy()
    end
    if QuestFocusDB then QuestFocusDB.ahqOpen = show and true or nil end
end

local function BuildTab()
    if tab then return tab end
    local t = CreateFrame("Button", "AdventurersKitAHTab", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    t:SetSize(34, 34)
    t:SetFrameStrata("HIGH")
    t:Hide()
    S.Backdrop(t, "box")
    t.tex = t:CreateTexture(nil, "ARTWORK")
    t.tex:SetPoint("TOPLEFT", 5, -5)
    t.tex:SetPoint("BOTTOMRIGHT", -5, 5)
    t.tex:SetTexture(ICON)
    t.tex:SetTexCoord(S.TEXCOORD[1], S.TEXCOORD[2], S.TEXCOORD[3], S.TEXCOORD[4])
    t:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    t:SetScript("OnClick", function() A.Toggle() end)
    t:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Quest items"], 1, 1, 1)
        GameTooltip:AddLine(L["Quest items from your log you can buy here, with prices. Turn the tab off in Options > Auction house."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tab = t
    A.tab = t
    return t
end

local function PlaceTab()
    local host = Host()
    tab:ClearAllPoints()
    if host then
        tab:SetPoint("TOPLEFT", host, "TOPRIGHT", 0, -70)
    else
        tab:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 780, -170)
    end
end

-- Az idozito: a lekerdezesek az AH nyitvatartasa alatt
local driver = CreateFrame("Frame")
driver:Hide()
local acc = 0
driver:SetScript("OnUpdate", function(_, dt)
    acc = acc + (dt or 0)
    if acc < 0.25 then return end
    acc = 0
    Tick()
end)

local function OnShowAH()
    ahOpen = true
    driver:Show()
    if not Enabled() then return end
    BuildTab()
    PlaceTab()
    tab:Show()
    if QuestFocusDB and QuestFocusDB.ahqOpen then A.Toggle(true) end
    -- egyes AH ablakok (Auctionator, sajat UI) kesobb jelennek meg: meg egyszer igazitunk
    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, function()
            if ahOpen and tab and tab:IsShown() then
                PlaceTab()
                if frame and frame:IsShown() then PlaceFrame() end
            end
        end)
    end
end

local function OnCloseAH()
    ahOpen = false
    driver:Hide()
    wipe(queue)
    active = nil
    for _, p in pairs(prices) do if p.scanning then p.scanning = nil end end
    StopBuy()
    local keep = QuestFocusDB and QuestFocusDB.ahqOpen
    if frame then frame:Hide() end
    if QuestFocusDB then QuestFocusDB.ahqOpen = keep end -- nyitva marad a kovetkezo latogatasra
    if tab then tab:Hide() end
end

-- Options kapcsolo
function A.SetEnabled(v)
    QuestFocusDB.noAHTab = not v or nil
    if not v then
        if frame then frame:Hide() end
        StopBuy()
        if tab then tab:Hide() end
    elseif ahOpen then
        OnShowAH()
    end
end

local pendingRefresh
local function SoonRefresh()
    if pendingRefresh or not (frame and frame:IsShown()) then return end
    pendingRefresh = true
    local function go() pendingRefresh = nil; Refresh() end
    if C_Timer and C_Timer.After then C_Timer.After(0.3, go) else go() end
end

local ev = CreateFrame("Frame")
-- Egyenkent, pcall-lal: a kliens nem ismert esemenyre hibat dob (a Forever modern AH-janal nincs
-- AUCTION_ITEM_LIST_UPDATE, a klasszikusnal nincs COMMODITY_*).
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "QUEST_LOG_UPDATE", "BAG_UPDATE_DELAYED",
    "GET_ITEM_INFO_RECEIVED", "UI_ERROR_MESSAGE", "MAIL_CLOSED",
    "AUCTION_ITEM_LIST_UPDATE",                                                   -- klasszikus AH
    "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",            -- modern AH
    "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_FAILED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "AUCTION_HOUSE_SHOW" then
        OnShowAH()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        OnCloseAH()
    elseif event == "AUCTION_ITEM_LIST_UPDATE" then
        OnList()
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        OnList("commodity", a1)
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        OnList("item", a1)
    elseif event == "COMMODITY_PRICE_UPDATED" then
        A.OnCommodityPrice(a1, a2)
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
        if buy and buy.waitPrice then
            BuyNextItem(L["The auction house has no price for it right now; skipped."])
            UpdatePopup()
        end
    elseif event == "UI_ERROR_MESSAGE" or event == "COMMODITY_PURCHASE_FAILED" then
        OnBuyError()
    elseif event == "MAIL_CLOSED" then
        wipe(pendingMail)
        SoonRefresh()
    else
        SoonRefresh()
        if event ~= "GET_ITEM_INFO_RECEIVED" and frame and frame:IsShown() then
            A.Scan(A.NeededItems()) -- uj item a listan: ar lekerdezes
        end
    end
end)

---------------------------------------------------------------------------
-- 47 Auction house (Options)
---------------------------------------------------------------------------
if NS.AddOptionsTab and NS.OptFlow then
    local page = NS.AddOptionsTab(L["Auction house"], 47)
    local o = NS.OptFlow(page)
    o:Header(L["On / off"])
    o:Check(L["Show quest items tab at the auction house"],
        L["A small coin tab on the right of the auction house window. It opens a list of the quest items in your log "]
        .. L["that you still need and can buy there (quest-only and soulbound items are left out), with the cheapest price, "]
        .. L["a search on click, a Buy button and Buy all."],
        function() return not QuestFocusDB.noAHTab end,
        function(v) A.SetEnabled(v) end)
    o:Text(L["Buying asks once for the total, then buys one auction per click (the game needs a click for every "]
        .. L["purchase). It never pays more than the price you confirmed. Bought items arrive in your mailbox."], 2)
    page:HookScript("OnShow", function() o:Refresh() end)
end
