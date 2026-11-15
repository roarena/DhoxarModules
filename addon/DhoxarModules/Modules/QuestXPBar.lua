-- Module: Quest XP Bar
--
-- Sums the reward XP of every completed quest in the quest log and paints
-- that amount onto the XP bar as a faint green segment, starting where the
-- current XP fill ends.
--
-- The overlay is a texture on the XP StatusBar itself, one draw sublevel
-- below the fill texture: the purple fill covers it where they overlap, and
-- it sits above the rested (exhaustion) bar, which lives on a lower frame or
-- a lower draw layer.
--
-- This client can hand back "secret" values, so every API read goes through
-- pcall and is type-checked before use.

local _, ns = ...

local IsSecret = ns.Util.IsSecret
local SafeCall = ns.Util.SafeCall
local SafeNumber = ns.Util.SafeNumber

local M = ns:RegisterModule({
    key = "QuestXPBar",
    title = "Quest XP Bar",
    description = "Shades the XP bar faint green with the XP you will earn by turning in your completed quests.",
    aliases = { "questxp", "qxp" },
})

local COLOR = { 0.25, 1.0, 0.25, 0.45 } -- faint green
local TAG = "|cff66ff66Quest XP Bar|r: "

---------------------------------------------------------------------------
-- Quest log scan
---------------------------------------------------------------------------

local function GetNumEntries()
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        return SafeNumber(SafeCall(C_QuestLog.GetNumQuestLogEntries)) or 0
    end
    return SafeNumber(SafeCall(GetNumQuestLogEntries)) or 0
end

-- Returns title, isHeader, isComplete, questID for a log index.
local function GetEntry(index)
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = SafeCall(C_QuestLog.GetInfo, index)
        if type(info) == "table" then
            local complete = SafeCall(C_QuestLog.IsComplete, info.questID)
            return info.title, info.isHeader, complete, info.questID
        end
        return nil
    end
    local title, _, _, isHeader, _, isComplete, _, questID = SafeCall(GetQuestLogTitle, index)
    return title, isHeader, isComplete, questID
end

local function IsQuestComplete(index, isComplete, questID)
    if IsSecret(isComplete) then return false end
    if isComplete == 1 or isComplete == true then return true end
    if isComplete == -1 then return false end -- failed
    -- Quests without objectives (talk to / deliver) are turn-in ready.
    local numObjectives = SafeNumber(SafeCall(GetNumQuestLeaderBoards, index))
    if numObjectives == 0 then
        if C_QuestLog and C_QuestLog.ReadyForTurnIn then
            local ready = SafeCall(C_QuestLog.ReadyForTurnIn, questID)
            if ready ~= nil and not IsSecret(ready) then return ready == true end
        end
        return true
    end
    return false
end

local function GetQuestXP(index, questID)
    local xp
    if questID then
        xp = SafeNumber(SafeCall(GetQuestLogRewardXP, questID))
    end
    if not xp or xp == 0 then
        -- Older API reads the currently selected entry.
        local selected = SafeCall(GetQuestLogSelection)
        if type(SelectQuestLogEntry) == "function" then
            SafeCall(SelectQuestLogEntry, index)
            xp = SafeNumber(SafeCall(GetQuestLogRewardXP)) or xp
            if SafeNumber(selected) then SafeCall(SelectQuestLogEntry, selected) end
        end
    end
    return xp or 0
end

-- Returns total XP and a list of {title, xp} for completed quests.
local function ScanCompletedQuests()
    local total, list = 0, {}
    for i = 1, GetNumEntries() do
        local title, isHeader, isComplete, questID = GetEntry(i)
        if title and not IsSecret(title) and not isHeader then
            if IsQuestComplete(i, isComplete, questID) then
                local xp = GetQuestXP(i, questID)
                if xp > 0 then
                    total = total + xp
                    list[#list + 1] = { title = title, xp = xp }
                end
            end
        end
    end
    return total, list
end

---------------------------------------------------------------------------
-- Locating the XP bar
---------------------------------------------------------------------------

local function IsStatusBar(f)
    return type(f) == "table" and type(f.GetObjectType) == "function"
        and SafeCall(f.GetObjectType, f) == "StatusBar"
end

-- Returns the XP StatusBar and the frame that owns the tooltip.
local function FindXPBar()
    -- Classic-style UI.
    if IsStatusBar(MainMenuExpBar) then return MainMenuExpBar, MainMenuExpBar end

    -- Modern status tracking UI.
    local containers = { MainStatusTrackingBarContainer, SecondaryStatusTrackingBarContainer, StatusTrackingBarManager }
    for _, container in pairs(containers) do
        if type(container) == "table" and type(container.bars) == "table" then
            for _, bar in pairs(container.bars) do
                local isExp = (ExpBarMixin and bar.OnLoad == ExpBarMixin.OnLoad)
                    or bar.ExhaustionTick or bar.ExhaustionLevelFillBar
                if isExp then
                    if IsStatusBar(bar.StatusBar) then return bar.StatusBar, bar end
                    if IsStatusBar(bar) then return bar, bar end
                end
            end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Overlay
---------------------------------------------------------------------------

local xpBar, hoverFrame, overlay
local lastTotal, lastList = 0, {}
local Update -- defined below

-- Script hooks cannot be removed, so each one checks M.active.
local function EnsureOverlay()
    if overlay and xpBar then return true end
    xpBar, hoverFrame = FindXPBar()
    if not xpBar then return false end

    overlay = xpBar:CreateTexture(nil, "ARTWORK")
    overlay:SetColorTexture(unpack(COLOR))

    local fill = xpBar:GetStatusBarTexture()
    if fill then
        local layer, sublevel = fill:GetDrawLayer()
        sublevel = math.max((sublevel or 0) - 1, -8)
        overlay:SetDrawLayer(layer or "ARTWORK", sublevel)
    end

    xpBar:HookScript("OnSizeChanged", function()
        if M.active then Update() end
    end)

    if hoverFrame and hoverFrame.HookScript then
        hoverFrame:HookScript("OnEnter", function(self)
            if not M.active or lastTotal <= 0 then return end
            if not (GameTooltip:IsShown() and GameTooltip:GetOwner() == self) then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:ClearLines()
            else
                GameTooltip:AddLine(" ")
            end
            GameTooltip:AddDoubleLine("Completed quests XP:", BreakUpLargeNumbers and BreakUpLargeNumbers(lastTotal) or lastTotal, 0.4, 1, 0.4, 0.4, 1, 0.4)
            for _, q in ipairs(lastList) do
                GameTooltip:AddDoubleLine("  " .. q.title, q.xp, 1, 1, 1, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        hoverFrame:HookScript("OnLeave", function()
            if M.active then GameTooltip:Hide() end
        end)
    end
    return true
end

local function IsMaxLevel()
    if IsPlayerAtEffectiveMaxLevel then
        local maxed = SafeCall(IsPlayerAtEffectiveMaxLevel)
        if maxed ~= nil and not IsSecret(maxed) then return maxed end
    end
    local level = SafeNumber(UnitLevel("player"))
    local cap = SafeNumber(SafeCall(GetMaxPlayerLevel)) or SafeNumber(MAX_PLAYER_LEVEL)
    return level and cap and level >= cap
end

function Update()
    if not M.active or not EnsureOverlay() then return end

    lastTotal, lastList = ScanCompletedQuests()

    local cur = SafeNumber(UnitXP("player"))
    local max = SafeNumber(UnitXPMax("player"))
    local width = SafeNumber(xpBar:GetWidth())

    if lastTotal <= 0 or not cur or not max or max <= 0 or not width or IsMaxLevel() then
        overlay:Hide()
        return
    end

    local startFrac = math.min(cur / max, 1)
    local endFrac = math.min((cur + lastTotal) / max, 1)
    local segment = (endFrac - startFrac) * width
    if segment < 1 then
        overlay:Hide()
        return
    end

    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", xpBar, "TOPLEFT", startFrac * width, 0)
    overlay:SetPoint("BOTTOMLEFT", xpBar, "BOTTOMLEFT", startFrac * width, 0)
    overlay:SetWidth(segment)
    overlay:Show()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local EVENTS = {
    "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN",
    "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "UI_SCALE_CHANGED",
}

local pending = false
local function QueueUpdate()
    if pending then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        Update()
    end)
end

local watcher

---------------------------------------------------------------------------
-- Module interface
---------------------------------------------------------------------------

local function PrintReport()
    if not M.active then
        print(TAG .. "the module is disabled. Type /dhoxar enable questxp.")
        return
    end
    Update()
    if not xpBar then
        print(TAG .. "could not find the XP bar frame.")
        return
    end
    print((TAG .. "%d completed quest(s) worth %d XP."):format(#lastList, lastTotal))
    for _, q in ipairs(lastList) do
        print(("  %s - %d XP"):format(q.title, q.xp))
    end
end

function M:OnEnable()
    if not watcher then
        watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", QueueUpdate)
    end
    for _, event in ipairs(EVENTS) do
        pcall(watcher.RegisterEvent, watcher, event)
    end
    QueueUpdate()
end

function M:OnDisable()
    if watcher then watcher:UnregisterAllEvents() end
    if overlay then overlay:Hide() end
    lastTotal, lastList = 0, {}
end

function M:BuildOptions(page)
    page:Button("Completed quests", "Print to chat", PrintReport,
        "Lists every completed quest in your log and the XP it will award. Same as typing /qxp.")
end

SLASH_DHOXARQUESTXPBAR1 = "/qxp"
SlashCmdList["DHOXARQUESTXPBAR"] = PrintReport
