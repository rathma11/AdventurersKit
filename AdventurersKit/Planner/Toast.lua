local ADDON_NAME, NS = ...
local L = NS.L
local GetItemCount, GetItemInfoInstant, GetItemInfo, GetItemIcon, GetItemSpell = NS.SafeItem.GetItemCount, NS.SafeItem.GetItemInfoInstant, NS.SafeItem.GetItemInfo, NS.SafeItem.GetItemIcon, NS.SafeItem.GetItemSpell -- biztonsagos item API (CoreInit.lua)
NS.P = NS.P or {}
local P = NS.P
local EtaSeconds, FormatTime, state = P.EtaSeconds, P.FormatTime, P.state

---------------------------------------------------------------------------
-- Haladas toast: kis felugro ablak a panel folott, ha nott egy objective
---------------------------------------------------------------------------
local toast = CreateFrame("Frame", "QuestFocusToast", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
toast:SetSize(250, 48)
toast:SetFrameStrata("MEDIUM")
toast:Hide()
if toast.SetBackdrop then
    toast:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    toast:SetBackdropColor(0.04, 0.04, 0.06, 0.92)
    toast:SetBackdropBorderColor(0.95, 0.78, 0.40, 0.9)
end
local accent = toast:CreateTexture(nil, "ARTWORK")
accent:SetPoint("TOPLEFT", 4, -4)
accent:SetPoint("BOTTOMLEFT", 4, 4)
accent:SetWidth(2)
accent:SetColorTexture(0.95, 0.78, 0.40, 1)
toast.label = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
toast.label:SetPoint("TOPLEFT", 12, -7)
toast.label:SetTextColor(0.95, 0.78, 0.40)
toast.label:SetWidth(170)
toast.label:SetJustifyH("LEFT")
toast.label:SetWordWrap(false)
toast.right = toast:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
toast.right:SetPoint("TOPRIGHT", -9, -7)
toast.icon = toast:CreateTexture(nil, "ARTWORK")
toast.icon:SetSize(18, 18)
toast.icon:SetPoint("BOTTOMLEFT", 12, 7)
toast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
toast.text:SetPoint("LEFT", toast.icon, "RIGHT", 6, 0)
toast.text:SetPoint("RIGHT", -9, 0)
toast.text:SetJustifyH("LEFT")
toast.text:SetWordWrap(false)

local TOAST_HOLD, TOAST_FADE = 3.5, 0.6
NS.ToastFrame = toast -- a buff emlekezteto megvarja, amig ez eltunik
local toastQueue = {} -- egyszerre tobb quest haladasa: egymas utan jonnek
local ShowToast -- lent
toast:SetScript("OnUpdate", function(self, dt)
    self.t = (self.t or 0) + dt
    local hold = #toastQueue > 0 and 2 or TOAST_HOLD -- ha var meg valami, rovidebben
    if self.t > hold + TOAST_FADE then
        self:Hide()
        local nxt = table.remove(toastQueue, 1)
        if nxt then ShowToast(nxt[1], nxt[2], nxt[3], true) end
    elseif self.t > hold then
        self:SetAlpha(1 - (self.t - hold) / TOAST_FADE)
    end
end)

-- (a Pace.lua ezt NS.ShowToast-on at hivja)
ShowToast = function(qid, title, o, fromQueue)
    if QuestFocusDB.noToast then return end
    -- Ha mar latszik egy (masik questhez), ez sorba all
    if not fromQueue and toast:IsShown() and toast.qo ~= o then
        for _, q in ipairs(toastQueue) do if q[3] == o then return end end
        toastQueue[#toastQueue + 1] = { qid, title, o }
        return
    end
    toast.qo = o
    -- A kijelolt quest objective-jeiben megvannak a forrasok is (drop rate-hez)
    local entry
    if state.questId == qid then
        for _, e in ipairs(state.objectives or {}) do if e.qo == o then entry = e end end
    end
    entry = entry or { qo = o, qid = qid, itemId = o.Type == "item" and o.Id or nil, sources = {} }
    local c, n = tonumber(o.Collected) or 0, tonumber(o.Needed) or 0
    local desc = tostring(o.Description or o.Text or "?")
    local done = n > 0 and c >= n
    toast.label:SetText((done and L["OBJECTIVE COMPLETE"] or L["QUEST PROGRESS"])
        .. (title and ("  |cffd8c8a0" .. title .. "|r") or ""))
    local sec = not done and EtaSeconds(entry)
    toast.right:SetText(sec and (FormatTime(sec) .. L[" left"]) or "")
    toast.text:SetText((done and "|cff33ff99" or "|cffffffff") .. desc .. "|r  |cffffd100" .. ("%d/%d"):format(c, n) .. "|r")
    local tex = o.Type == "item" and o.Id and GetItemIcon and GetItemIcon(o.Id)
    toast.icon:SetTexture(tex or "Interface\\Icons\\Ability_Hunter_SniperShot")
    toast:ClearAllPoints()
    -- A panel folott (ha a buff emlekezteto kint van, afolott)
    if NS.BuffAlertFrame and NS.BuffAlertFrame:IsShown() then
        toast:SetPoint("BOTTOMRIGHT", NS.BuffAlertFrame, "TOPRIGHT", 0, 4)
    elseif NS.panel:IsShown() then
        toast:SetPoint("BOTTOMRIGHT", NS.panel, "TOPRIGHT", 0, 4)
    else
        toast:SetPoint("TOP", UIParent, "TOP", 0, -190)
    end
    toast.t = 0
    toast:SetAlpha(1)
    toast:Show()
end
NS.ShowToast = ShowToast

