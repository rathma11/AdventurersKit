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
-- 45 City list: a varosi / fogadoi lista, kihagyott helyek, teendok
---------------------------------------------------------------------------
local pageCity = NS.AddOptionsTab(L["City list"], 45)
local cl = NS.OptFlow(pageCity)
cl:Text(L["While resting (city or inn) a list opens with every quest you can pick up nearby (XP, chain position, "]
    .. L["dungeon tag), plus a to-do section on top (repair, sell, ammo, XP food) and Bank / AH / Trainer buttons."], 0)
cl:Header(L["On / off"])
cl:Check(L["City list"],
    L["Off: the list never opens by itself, in any city or inn (same as 'Disable city list everywhere' on the list). "]
    .. L["With it off, the nearby quest popups (Quest pickup tab) show in cities too."],
    function() return not QuestFocusDB.noCityMode end,
    function(v)
        QuestFocusDB.noCityMode = not v
        if v then NS.ShowCityList() end
        NS.Panel_Update()
    end)
cl:Button(L["Open the list now"], 160, L["Same as /qf city: opens the list here, even outside a city or in a skipped place."],
    function() if NS.ShowCityList then NS.ShowCityList() end end, 28)

cl:Header(L["Ignore list: places where it doesn't open by itself"])
local ignInfo = cl:Text(L["Added with 'Don't open here again' on the list (it covers ~500 yards around that spot). "]
    .. L["Remove a place to get the list back there."], 2)
-- Helyek listaja: soronkent nev + Remove gomb (frissiteskor ujraepitve)
local ignBox = CreateFrame("Frame", nil, pageCity)
ignBox:SetSize(420, 20)
cl:Place(ignBox, 28, 8)
local ignRows = {}
local ignAll
local function RebuildIgnore()
    local list = QuestFocusDB.cityIgnore or {}
    for _, r in ipairs(ignRows) do r:Hide() end
    for i, e in ipairs(list) do
        local r = ignRows[i]
        if not r then
            r = CreateFrame("Frame", nil, ignBox)
            r:SetSize(420, 22)
            r.btn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
            r.btn:SetSize(70, 20)
            r.btn:SetPoint("LEFT", 0, 0)
            r.btn:SetText(L["Remove"])
            if r.btn:GetFontString() then r.btn:GetFontString():SetFontObject("GameFontNormalSmall") end
            r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            r.text:SetPoint("LEFT", r.btn, "RIGHT", 8, 0)
            r.text:SetPoint("RIGHT", 0, 0)
            r.text:SetJustifyH("LEFT")
            ignRows[i] = r
        end
        r:SetPoint("TOPLEFT", ignBox, "TOPLEFT", 0, -(i - 1) * 24)
        r.text:SetText("|cffffff00" .. (e.name or "?") .. "|r")
        r.btn:SetScript("OnClick", function()
            local cur = QuestFocusDB.cityIgnore or {}
            for j, x in ipairs(cur) do
                if x == e then
                    table.remove(cur, j)
                    NS.Loud(NS.Print, L["City list: |cffffff00%s|r removed, the list opens there again."], e.name or "?")
                    break
                end
            end
            cl:Refresh()
        end)
        r:Show()
    end
    local n = #list
    if n == 0 then
        ignBox.empty = ignBox.empty or ignBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        ignBox.empty:SetPoint("TOPLEFT", 0, -3)
        ignBox.empty:SetText(L["None - the list opens in every city and inn."])
        ignBox.empty:Show()
    elseif ignBox.empty then
        ignBox.empty:Hide()
    end
    ignBox:SetHeight(math.max(1, n) * 24)
    if ignAll then ignAll:SetShown(n > 1) end
    if pageCity.Remeasure then pageCity.Remeasure() end
end
ignAll = cl:Button(L["Remove all"], 120, nil, function()
    if NS.ResetCityIgnore then NS.ResetCityIgnore() end
    cl:Refresh()
end, 28)
cl:OnRefresh(RebuildIgnore)

cl:Header(L["City to-do (above the quests)"])
cl:Text(L["Shown at the top of the city list with the nearest NPC for it (click: marker). Bags and repair also warn out in the world, in the buff reminder (Buffs tab). 0 turns a line off."], 2)
cl:Number(L["Bags full: warn at"],
    L["Percent of your bag slots in use. Default 70. The nearest vendor to sell to is shown (or Directions > Bank)."],
    function() return NS.CityLimit("bagPct") end,
    function(v) QuestFocusDB.cityBagPct = math.max(0, math.min(100, v)) end, "%")
cl:Number(L["Bags: or fewer free slots than"],
    L["Also warns when this few slots are left, whatever the percent. Default 10."],
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
