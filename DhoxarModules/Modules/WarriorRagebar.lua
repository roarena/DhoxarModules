-- Module: Simplified Warrior Ragebar
--
-- Hides one of the two texts on the Personal Resource Display's health/rage
-- bars (percentage or raw value) and centers the one that remains.
--
-- The Personal Resource Display is drawn by a separate Blizzard frame,
-- PersonalResourceDisplayFrame (Interface/AddOns/Blizzard_PersonalResourceDisplay),
-- not the nameplate/CompactUnitFrame system. It has HealthBar and PowerBar
-- children; whichever is shown has left/right text FontStrings for the
-- percentage and the raw value.
--
-- This client hands back protected/"secret" values and marks some nested
-- tables (combat-log aura lists, etc.) fully "forbidden" - even a read
-- through them under pcall can spam a taint error. So this only ever
-- touches known widget fields on PersonalResourceDisplayFrame's own bars
-- (Hide/SetPoint) - never a generic walk of the whole frame tree.

local _, ns = ...

local M = ns:RegisterModule({
    key = "WarriorRagebar",
    title = "Simplified Warrior Ragebar",
    description = "Shows a single centered text on the Personal Resource Display's health and rage bars instead of the percentage and the value side by side. Warriors only.",
    class = "WARRIOR",
    aliases = { "ragebar" },
    defaults = { showPercentage = false },
    legacy = { addon = "SimplifiedWarriorRagebar", savedVariable = "SimplifiedWarriorRagebarDB" },
})

local BAR_NAMES = { "HealthBar", "PowerBar" }

local function IsPercentMode()
    return M.db.showPercentage == true
end

local hooked = setmetatable({}, { __mode = "k" })
local recentering = setmetatable({}, { __mode = "k" })

local function FindLeftRight(bar)
    if type(bar) ~= "table" then return nil, nil end
    local left = bar.LeftText or bar.leftText
    local right = bar.RightText or bar.rightText
    return left, right
end

local function Recenter(fs, bar)
    if not fs or recentering[fs] then return end
    recentering[fs] = true
    pcall(function()
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", bar, "CENTER", 0, 0)
    end)
    recentering[fs] = false
end

-- installs, once per FontString, hooks that keep re-applying whichever
-- role (shown+centered vs hidden) the current setting assigns to it -
-- isLeft is fixed for the widget's life, but which role wins the current
-- setting can change any time the user flips the option. Hooks cannot be
-- removed, so they do nothing while the module is off.
local function InstallHooks(fs, bar, isLeft)
    if not fs or hooked[fs] or not hooksecurefunc then return end
    hooked[fs] = true
    hooksecurefunc(fs, "Show", function(self)
        if M.active and isLeft ~= IsPercentMode() then pcall(self.Hide, self) end
    end)
    hooksecurefunc(fs, "SetPoint", function(self)
        if M.active and isLeft == IsPercentMode() then Recenter(self, bar) end
    end)
end

local function IsOnScreen(frame)
    if type(frame) ~= "table" or not frame.IsShown then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown and true or false
end

local function CleanBar(bar)
    if not IsOnScreen(bar) then return end
    local left, right = FindLeftRight(bar)
    if not IsOnScreen(left) and not IsOnScreen(right) then return end
    InstallHooks(left, bar, true)
    InstallHooks(right, bar, false)
    local shown, hidden = right, left
    if IsPercentMode() then shown, hidden = left, right end
    if hidden then pcall(hidden.Hide, hidden) end
    Recenter(shown, bar)
end

local function CleanNow()
    if not M.active then return end
    local prd = _G.PersonalResourceDisplayFrame
    if not IsOnScreen(prd) then return end
    for _, key in ipairs(BAR_NAMES) do
        CleanBar(prd[key])
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local EVENTS = {
    "ADDON_LOADED",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_DISABLED", -- entering combat
    "UNIT_HEALTH",
    "UNIT_POWER_FREQUENT",
}

local watcher

local function OnEvent(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg == "Blizzard_PersonalResourceDisplay" then CleanNow() end
        return
    end
    if (event == "UNIT_HEALTH" or event == "UNIT_POWER_FREQUENT") and arg ~= "player" then
        return
    end
    CleanNow()
end

---------------------------------------------------------------------------
-- Module interface
---------------------------------------------------------------------------

function M:OnEnable()
    if not watcher then
        watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", OnEvent)
    end
    for _, event in ipairs(EVENTS) do
        pcall(watcher.RegisterEvent, watcher, event)
    end
    CleanNow()
end

function M:OnDisable()
    if watcher then watcher:UnregisterAllEvents() end
    -- The texts were already moved/hidden; Blizzard only lays them out again
    -- on its own schedule.
    ns:Print(self.title .. ": /reload to restore the default bar texts.")
end

function M:BuildOptions(page)
    page:Header("Display")
    page:Checkbox({
        label = "Show percentage instead of value",
        description = "When on, the Personal Resource Display shows the percentage centered in the bar. When off, it shows the raw value instead.",
        get = IsPercentMode,
        set = function(value)
            M.db.showPercentage = value and true or false
            CleanNow()
        end,
    })
end

function M:ImportLegacy(old)
    if type(old.showPercentage) == "boolean" then
        self.db.showPercentage = old.showPercentage
    end
end
