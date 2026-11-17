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
pageRoute:HookScript("OnShow", function() rt:Refresh() end)

---------------------------------------------------------------------------
-- 40 Quest pickup
---------------------------------------------------------------------------
local pagePick = NS.AddOptionsTab(L["Quest pickup"], 40)
local pk = NS.OptFlow(pagePick)
pk:Header(L["Which quests"])
pk:Number(L["Lowest quest level: your level minus"],
    L["Quests more than this many levels below you are not suggested (grey quests give little XP). Default 2."],
    function() return tonumber(QuestFocusDB.pickupBelow) or 2 end,
    function(v) QuestFocusDB.pickupBelow = v end)
pk:Number(L["Highest quest level: your level plus"],
    L["Quests more than this many levels above you are not suggested. Default 10."],
    function() return tonumber(QuestFocusDB.pickupAbove) or 10 end,
    function(v) QuestFocusDB.pickupAbove = v end)
pk:Header(L["Out in the world"])
pk:Check(L["Popup for quests you can pick up nearby"],
    L["When a quest you can pick up is within ~300 yards, a popup shows its level, an estimated length and the distance. "]
    .. L["Click it for a marker (TomTom arrow) on the quest giver. Each quest only once per session."],
    function() return not QuestFocusDB.noQuestPopup end,
    function(v) QuestFocusDB.noQuestPopup = not v end)
pk:Header(L["In a city or inn"])
pk:Check(L["City mode"],
    L["While resting (city or inn): no popup per quest, one scrollable list of every quest you can pick up nearby instead "]
    .. L["(XP, chain position, item start). The panel boxes show distance / travel time / best way home."],
    function() return not QuestFocusDB.noCityMode end,
    function(v)
        QuestFocusDB.noCityMode = not v
        if v then NS.ShowCityList() end
        NS.Panel_Update()
    end)
local ignBtn = pk:Button(L["Clear ignored places"], 160, "", function()
    if NS.ResetCityIgnore then NS.ResetCityIgnore() end
    pk:Refresh()
end, 28)
pk:OnRefresh(function()
    local list = QuestFocusDB.cityIgnore or {}
    local names = {}
    for _, e in ipairs(list) do names[#names + 1] = e.name or "?" end
    ignBtn.desc:SetText((L["Places where the list doesn't open by itself (button on the list: Ignore this place). Now: %s"])
        :format(#names > 0 and ("|cffffff00" .. table.concat(names, ", ") .. "|r") or L["none"]))
    ignBtn:SetEnabled(#names > 0)
end)
pk:Button(L["Open the list now"], 160, L["Same as /qf city: opens the list here, even outside a city or in an ignored place."],
    function() if NS.ShowCityList then NS.ShowCityList() end end, 28)
pagePick:HookScript("OnShow", function() pk:Refresh() end)
