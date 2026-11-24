-- Module: Enhanced Graphics
--
-- Off by default. When the user turns it on, it writes a set of graphics
-- CVars past what the options menu allows (denser and farther grass,
-- sharpening, water reflections, weather, draw distances, camera zoom).
-- Before the first write it saves the user's current value of each one in
-- the saved variables (module.db.backup), and turning the module off writes
-- those values back and drops the backup. CVars are stored in WTF\Config.wtf,
-- so the options page warns about that.
--
-- CVars the client doesn't know are skipped. Nothing is written in combat:
-- the change waits for the end of combat. If the module is off at login but
-- a backup is still there (turned off in combat, then logged out), the
-- backup is put back then.

local _, ns = ...

local M = ns:RegisterModule({
    key = "Graphics",
    title = "Enhanced Graphics",
    description = "Raises graphics settings past the options menu: grass, sharpening, reflections, weather, draw distance and camera zoom. Off by default; turning it off puts your settings back.",
    aliases = { "graphics", "gfx", "cvars" },
    enabledByDefault = false,
    defaults = {},
})

local TAG = "|cffc8aa88Enhanced Graphics|r: "

-- { cvar, value, what it does }
local TWEAKS = {
    { "groundEffectDensity", "256", "Grass density (menu maximum is 48)" },
    { "groundEffectDist", "500", "Grass draw distance" },
    { "groundEffectFade", "370", "Grass fade range" },
    { "resampleAlwaysSharpen", "1", "Screen sharpening" },
    { "HDRFactor", "1.3", "Lighting contrast and brightness" },
    { "reflectionMode", "3", "Water reflection detail" },
    { "weatherDensity", "3", "Weather particles" },
    { "lodObjectFadeScale", "200", "Object draw distance" },
    { "terrainLodDist", "1000", "Terrain and mountain detail distance" },
    { "farClip", "2000", "Horizon view distance" },
    { "cameraDistanceMaxZoomFactor", "4.0", "Maximum camera distance" },
}

local pending -- "apply" or "restore", waiting for the end of combat

local function GetCVarSafe(name)
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    if not get then return nil end
    local ok, value = pcall(get, name)
    if not ok or ns.Util.IsSecret(value) then return nil end
    return value
end

local function SetCVarSafe(name, value)
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if not set then return false end
    local ok, result = pcall(set, name, value)
    return ok and result ~= false
end

-- Saves the current values (once), then writes ours.
local function Apply()
    if InCombatLockdown() then
        pending = "apply"
        return
    end
    pending = nil
    M.db.backup = type(M.db.backup) == "table" and M.db.backup or {}
    local backup = M.db.backup
    local skipped = {}
    for _, t in ipairs(TWEAKS) do
        local name, value = t[1], t[2]
        local current = GetCVarSafe(name)
        if current == nil then
            skipped[#skipped + 1] = name
        else
            if backup[name] == nil then backup[name] = current end
            if current ~= value then SetCVarSafe(name, value) end
        end
    end
    M.skipped = skipped
end

-- Writes the saved values back and drops the backup.
local function Restore(verbose)
    local backup = M.db.backup
    if type(backup) ~= "table" then return end
    if InCombatLockdown() then
        pending = "restore"
        return
    end
    pending = nil
    for name, value in pairs(backup) do
        SetCVarSafe(name, value)
    end
    M.db.backup = nil
    if verbose then print(TAG .. "your previous graphics settings are back.") end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending == "apply" and M.active then
            Apply()
        elseif pending == "restore" and not M.active then
            Restore(true)
        end
    elseif event == "PLAYER_LOGIN" then
        -- Off, with a backup left over: put it back.
        if M.db.enabled ~= true and type(M.db.backup) == "table" then Restore(true) end
    end
end)
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_LOGIN")

function M:OnEnable()
    Apply()
end

function M:OnDisable()
    Restore(false)
end

function M:OnUserToggle(enabled)
    if enabled then
        print(TAG .. (pending and "settings will be applied after combat." or "settings applied. Your previous values are saved and come back when you turn this off. Some changes (like grass) show after /reload."))
    else
        print(TAG .. (pending and "your previous settings will be put back after combat." or "your previous graphics settings are back."))
    end
end

local function Report()
    local lines = { "CVar: current value (your saved value)", "" }
    local backup = type(M.db.backup) == "table" and M.db.backup or {}
    for _, t in ipairs(TWEAKS) do
        local current = GetCVarSafe(t[1])
        lines[#lines + 1] = ("%s: %s%s  - %s"):format(t[1],
            current == nil and "not available on this client" or current,
            backup[t[1]] ~= nil and (" (saved: " .. backup[t[1]] .. ")") or "",
            t[3])
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = type(M.db.backup) == "table" and "A backup is saved." or "No backup saved (the module is off)."
    ns.Util.ShowCopyableText("Enhanced Graphics", table.concat(lines, "\n"))
end

function M:BuildOptions(page)
    page:Header("Warning")
    page:Text("|cffff5555These settings are written to your Config.wtf file|r (World of Warcraft\\_forever_\\WTF\\Config.wtf). If you want to be able to go back to your own settings by hand, make a copy of that file before turning this on.")
    page:Text("When you turn this on, the addon saves your current values first, and turning it off puts them back. Higher settings cost frame rate, grass density and draw distances most of all. Some changes, like grass, show after /reload.")

    page:Header("What it changes")
    local list = {}
    for _, t in ipairs(TWEAKS) do
        list[#list + 1] = ("%s: |cffffffff%s|r"):format(t[3], t[2])
    end
    page:Text(table.concat(list, "\n"))

    page:Header("Check")
    page:Button({
        label = "Current values",
        description = "Lists each setting's current value and, while this is on, the value saved to put back.",
        text = "Show",
        onClick = Report,
    })
end
