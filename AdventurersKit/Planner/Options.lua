local ADDON_NAME, NS = ...
local L = NS.L
NS.P = NS.P or {}
local P = NS.P
local mobKills, progress, state = P.mobKills, P.progress, P.state

---------------------------------------------------------------------------
-- 30 Route & progress
---------------------------------------------------------------------------
local pageRoute = NS.AddOptionsTab(L["Route & progress"], 30)
local rt = NS.OptFlow(pageRoute)
rt:Header(L["Route"])
rt:Check(L["Suggest quests when none is selected"],
    L["With no quest selected the panel shows a route through your quest log (nearest next stop each time) "]
    .. L["and nearby quests you can pick up. In turn-in mode the next quests of the route are listed at the bottom."],
    function() return not QuestFocusDB.noSuggest end,
    function(v)
        QuestFocusDB.noSuggest = not v
        NS.Panel_Update()
    end)
rt:Check(L["Suggest the next zone"],
    L["On top of the suggestions: 'Go to <zone>' when another zone has at least 5 quests from your log (and more than here), "]
    .. L["otherwise the nearest zone with at least 5 quests to pick up for your level. Travel time counts walking, "]
    .. L["boats, zeppelins, the tram and your Hearthstone (with its cooldown); hover the line for the way."],
    function() return not QuestFocusDB.noZoneSuggest end,
    function(v)
        QuestFocusDB.noZoneSuggest = not v
        NS.Panel_Update()
    end)
rt:Header(L["Progress and time left"])
rt:Check(L["Progress popup"],
    L["A small popup above the panel for a few seconds when an objective progresses, with the estimated time left."],
    function() return not QuestFocusDB.noToast end,
    function(v) QuestFocusDB.noToast = not v end)
rt:Text(L["Time left is learned from your own pace: how fast each objective counter grew, otherwise "]
    .. L["the time between your kills combined with the Questie drop rate. A '?' means there is no kill data yet."], 2)
rt:Button(L["Reset kill pace"], 160,
    L["Forget the learned kill pace (e.g. after a big level or gear jump); it is learned again as you play."],
    function()
        QuestFocusDB.killPace, QuestFocusDB.killSamples = nil, nil
        wipe(progress)
        wipe(mobKills)
        NS.Print(L["Kill pace reset."])
    end, 2)
rt:Header(L["Dungeon prep"])
rt:Check(L["Ask to share dungeon quests on entering"],
    L["In dungeon prep, when you zone into the dungeon in a group, a small window asks whether to share your "]
    .. L["dungeon quests with the party (tick the ones you want). Only out of combat, once per entry."],
    function() return not QuestFocusDB.noShareAsk end,
    function(v) QuestFocusDB.noShareAsk = not v end)
rt:Header(L["Farm session"])
rt:Check(L["Summary window when a farm session stops"],
    L["Stopping a farm session (the clock button or /qf farm stop) opens a window with the duration, kills, XP, "]
    .. L["levels, looted gold, item value and gold per hour. A one-line summary goes to chat either way."],
    function() return not QuestFocusDB.noFarmSummary end,
    function(v) QuestFocusDB.noFarmSummary = not v or nil end)
pageRoute:HookScript("OnShow", function() rt:Refresh() end)

---------------------------------------------------------------------------
-- 40 Quest pickup: felveheto questek kint a vilagban (popup) + szintsav (a city listre is ervenyes)
---------------------------------------------------------------------------
local pagePick = NS.AddOptionsTab(L["Quest pickup"], 40)
local pk = NS.OptFlow(pagePick)
pk:Text(L["Quests you can pick up near you. Out in the world: a popup per quest (this page). "]
    .. L["In a city or inn: one list of every nearby quest instead (City list tab)."], 0)
pk:Header(L["On / off"])
pk:Check(L["Popup for quests you can pick up nearby (out in the world)"],
    L["When a quest you can pick up is within ~300 yards, a popup shows its level, an estimated length and the distance. "]
    .. L["Click it for a marker (TomTom arrow) on the quest giver. Each quest only once per session. In a city or inn the city list replaces it (while the city list is on)."],
    function() return not QuestFocusDB.noQuestPopup end,
    function(v) QuestFocusDB.noQuestPopup = not v end)
pk:Header(L["Which quests (popup, city list and panel suggestions)"])
pk:Number(L["Lowest quest level: your level minus"],
    L["Quests more than this many levels below you are not suggested (grey quests give little XP). Default 2."],
    function() return tonumber(QuestFocusDB.pickupBelow) or 2 end,
    function(v) QuestFocusDB.pickupBelow = v end)
pk:Number(L["Highest quest level: your level plus"],
    L["Quests more than this many levels above you are not suggested. Default 10."],
    function() return tonumber(QuestFocusDB.pickupAbove) or 10 end,
    function(v) QuestFocusDB.pickupAbove = v end)
pagePick:HookScript("OnShow", function() pk:Refresh() end)

---------------------------------------------------------------------------
-- 45 City list: a varosi / fogadoi lista (be / ki, magatol nyiljon-e) es a teendok kuszobei
---------------------------------------------------------------------------
local pageCity = NS.AddOptionsTab(L["City list"], 45)
local cl = NS.OptFlow(pageCity)
cl:Text(L["In a city, or in a village with an inn (innkeeper within ~250 yd): a list of every quest you can pick up nearby (XP, chain position, "]
    .. L["dungeon tag), with errands on top (repair, sell, ammo, XP food) and a Directions menu (bank, AH, trainers...). "]
    .. L["The town icon on the quest panel (or /qf city) opens and closes it anywhere."], 0)
cl:Header(L["On / off"])
local autoCb
cl:Check(L["City list"],
    L["Off: the list never opens by itself, and the nearby quest popups (Quest pickup tab) show in towns too. "]
    .. L["The panel icon and /qf city still open it."],
    function() return not QuestFocusDB.noCityMode end,
    function(v)
        QuestFocusDB.noCityMode = not v or nil
        NS.RefreshCityList()
        NS.Panel_Update()
        cl:Refresh()
    end)
autoCb = cl:Check(L["Open automatically in towns"],
    L["On: the list pops up when you arrive in a city or a village with an inn (closing it keeps it closed until you leave). "]
    .. L["Off: only the panel icon or /qf city opens it."],
    function() return not QuestFocusDB.cityNoAuto end,
    function(v)
        QuestFocusDB.cityNoAuto = not v or nil
        if v and not NS.CityListShown() then NS.RefreshCityList() end
    end, 24)
cl:OnRefresh(function()
    -- a lista kikapcsolva: a magatol nyilas sem szamit (szurke)
    if autoCb.SetEnabled then autoCb:SetEnabled(not QuestFocusDB.noCityMode) end
    autoCb.label:SetFontObject(QuestFocusDB.noCityMode and "GameFontDisable" or "GameFontHighlight")
end)
cl:Button(L["Open the list now"], 160, L["Same as the town icon on the panel and /qf city: opens the list here, also outside towns."],
    function() if NS.ShowCityList then NS.ShowCityList() end end, 28)

cl:Header(L["Errands: when to warn"])
cl:Text(L["Errands show at the top of the city list with the nearest NPC for them (click: marker). Bags and repair also warn out in the world, in the buff reminder (Buffs tab). 0 turns a line off."], 2)
cl:Number(L["Bags full: warn at"],
    L["Percent of your bag slots in use, in cities only. Default 70. The nearest vendor to sell to is shown (or Directions > Bank)."],
    function() return NS.CityLimit("bagPct") end,
    function(v) QuestFocusDB.cityBagPct = math.max(0, math.min(100, v)) end, "%")
cl:Number(L["Bags: or at this many free slots"],
    L["Also warns when this many slots or fewer are left, whatever the percent. Default 10. "]
    .. L["Out in the world only free slots count: at this many, when a vendor is within 300 yd; at 5, within 600 yd; at 2 or full, always."],
    function() return NS.CityLimit("bagFree") end,
    function(v) QuestFocusDB.cityBagFree = v end)
cl:Number(L["Repair: warn when an item is below"],
    L["Durability of your most worn item. Default 60."],
    function() return NS.CityLimit("repair") end,
    function(v) QuestFocusDB.cityRepairPct = math.max(0, math.min(100, v)) end, "%")
cl:Number(L["Ammo (hunters): warn below"],
    L["Arrows / bullets in the ammo slot. Default 400."],
    function() return NS.CityLimit("ammo") end,
    function(v) QuestFocusDB.cityAmmo = v end)
pageCity:HookScript("OnShow", function() cl:Refresh() end)
