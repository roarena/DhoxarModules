-- Module: Quest Item Sparkles
--
-- The loot sparkle on quest items is controlled by one CVar,
-- outlineModeShowLootEffectWhenDisabled, which must be "1" for it to show.
-- Graphics presets reset it to "0", so the sparkle silently disappears.
-- This module draws nothing: it only keeps that CVar at "1".
--
-- It never touches graphicsOutlineMode (that would remove the Self Highlight
-- outline) or any soft-targeting CVar, and never writes CVars in combat.
--
-- The module's enable switch is the "Show quest item sparkles" option
-- (module.db.enabled, on by default).

local _, ns = ...

local M = ns:RegisterModule({
    key = "QuestSparkles",
    title = "Quest Item Sparkles",
    description = "Shows quest item sparkles: keeps the loot sparkle setting on when a graphics preset turns it off. Does not change your outline mode.",
    aliases = { "sparkles" },
})

local CVAR = "outlineModeShowLootEffectWhenDisabled"
local WATCHED = {
    graphicsquality = true,
    raidgraphicsquality = true,
    outlinemodeshowlooteffectwhendisabled = true,
}

local applying = false           -- our own write is in progress
local pendingAfterCombat = false -- a write was skipped because of combat

local function IsEnabled()
    return M.db == nil or M.db.enabled ~= false
end

-- Writes the CVar if it differs. Never in combat.
local function WriteCVar(value)
    if InCombatLockdown() then
        pendingAfterCombat = true
        return
    end
    if not (C_CVar and C_CVar.GetCVar and C_CVar.SetCVar) then return end
    local current = C_CVar.GetCVar(CVAR)
    if current == nil or current == value then return end
    applying = true
    pcall(C_CVar.SetCVar, CVAR, value)
    applying = false
end

local function Apply()
    if not M.active or not IsEnabled() then return end
    WriteCVar("1")
end

---------------------------------------------------------------------------
-- Delayed apply: one hidden frame, re-scheduling overwrites applyAt.
---------------------------------------------------------------------------

local timer = CreateFrame("Frame")
timer:Hide()
local applyAt = 0
timer:SetScript("OnUpdate", function(self)
    if GetTime() >= applyAt then
        self:Hide()
        Apply()
    end
end)

local function ScheduleApply(delay)
    applyAt = GetTime() + delay
    timer:Show()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(_, event, name)
    if event == "CVAR_UPDATE" then
        if not applying and type(name) == "string" and WATCHED[name:lower()] then
            ScheduleApply(1) -- let the preset finish writing first
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingAfterCombat then
            pendingAfterCombat = false
            if M.active then
                Apply()
            else
                WriteCVar("0") -- the module was turned off in combat
            end
        end
    end
end)
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")

---------------------------------------------------------------------------
-- Module interface
---------------------------------------------------------------------------

-- Runs at PLAYER_LOGIN (when enabled) and whenever the user turns it on.
function M:OnEnable()
    pcall(watcher.RegisterEvent, watcher, "CVAR_UPDATE")
    Apply()
    ScheduleApply(5) -- account-synced settings can arrive late
end

function M:OnDisable()
    pcall(watcher.UnregisterEvent, watcher, "CVAR_UPDATE")
    pendingAfterCombat = false
    timer:Hide()
    WriteCVar("0")
end

local RESTART_TEXT = "Quest Item Sparkles\n\nLog out and log back in (a full game load) for this change to take effect. /reload is not enough."

local RESTART_POPUP = {
    text = RESTART_TEXT,
    button1 = OKAY or "OK",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    -- Above the configuration window, which shares the DIALOG strata.
    OnShow = function(self) self:SetFrameStrata("FULLSCREEN_DIALOG") end,
    OnHide = function(self) self:SetFrameStrata("DIALOG") end,
}

-- Any change by the user needs a full game load to show or hide the sparkles.
function M:OnUserToggle()
    if StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs.DHOXAR_SPARKLES_RESTART = RESTART_POPUP
        StaticPopup_Show("DHOXAR_SPARKLES_RESTART")
    else
        ns:Print((RESTART_TEXT:gsub("\n\n", ": ")))
    end
end

function M:BuildOptions(page)
    page:Text("Turn this module on or off with the switch above to show or hide quest item sparkles. The change takes effect after you log out and log back in.")
end
