-- Dhoxar Modules - core
--
-- The main module: every feature module registers itself here, and the core
-- owns the saved variables, decides which modules run, and exposes the
-- options panel (Core/Options.lua) and the /dhoxar slash command.
--
-- A module is a table passed to ns:RegisterModule:
--
--   key          (string, required) unique id; also the saved-variable key
--   title        display name
--   description  one-line tooltip shown next to the enable checkbox
--   class        optional class token ("WARRIOR"); module only runs on it
--   defaults     optional table of default settings, copied into module.db
--   aliases      optional list of extra names accepted by /dhoxar enable
--   legacy       optional { addon = "...", savedVariable = "..." } naming the
--                standalone addon this module replaces
--   OnEnable(self)            start doing work (may run more than once)
--   OnDisable(self)           stop doing work
--   BuildOptions(self, page)  add settings to the module's page in the
--                             configuration window (API in Core/Options.lua)
--   ImportLegacy(self, old)   copy settings from the standalone addon's table
--   OnUserToggle(self, enabled)  the user switched the module on or off
--                             (not called at login)
--
-- The core fills in:
--   module.db      the module's saved settings (module.db.enabled is the
--                  user's choice; valid once ADDON_LOADED has fired)
--   module.active  true while the module is actually running

local ADDON_NAME, ns = ...

ns.name = ADDON_NAME
ns.title = "Dhoxar Modules"
ns.modules = {}    -- key -> module
ns.moduleList = {} -- registration order
ns.started = false

local PREFIX = "|cffc8aa88Dhoxar Modules|r: "

function ns:Print(msg)
    print(PREFIX .. tostring(msg))
end

local function CopyValue(v)
    if type(v) ~= "table" then return v end
    local copy = {}
    for k, inner in pairs(v) do
        copy[k] = CopyValue(inner)
    end
    return copy
end

local function ApplyDefaults(target, defaults)
    for k, v in pairs(defaults or {}) do
        if target[k] == nil then
            target[k] = CopyValue(v)
        end
    end
end

---------------------------------------------------------------------------
-- Registry
---------------------------------------------------------------------------

function ns:RegisterModule(module)
    assert(type(module) == "table" and type(module.key) == "string", "Dhoxar Modules: a module needs a key")
    assert(not self.modules[module.key], "Dhoxar Modules: duplicate module key " .. module.key)
    module.title = module.title or module.key
    module.active = false
    -- Placeholder settings until the saved variables load.
    module.db = {}
    ApplyDefaults(module.db, module.defaults)
    self.modules[module.key] = module
    self.moduleList[#self.moduleList + 1] = module
    return module
end

-- Case-insensitive lookup by key, title or alias.
function ns:FindModule(name)
    name = tostring(name or ""):lower():gsub("%s+", "")
    if name == "" then return nil end
    for _, module in ipairs(self.moduleList) do
        if module.key:lower() == name or module.title:lower():gsub("%s+", "") == name then
            return module
        end
        for _, alias in ipairs(module.aliases or {}) do
            if alias:lower() == name then
                return module
            end
        end
    end
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------

local function InitDB()
    if type(DhoxarModulesDB) ~= "table" then
        DhoxarModulesDB = {}
    end
    local db = DhoxarModulesDB
    if type(db.modules) ~= "table" then
        db.modules = {}
    end
    for _, module in ipairs(ns.moduleList) do
        local mdb = db.modules[module.key]
        if type(mdb) ~= "table" then
            mdb = {}
            db.modules[module.key] = mdb
        end
        if mdb.enabled == nil then
            mdb.enabled = module.enabledByDefault ~= false
        end
        ApplyDefaults(mdb, module.defaults)
        module.db = mdb
    end
    ns.db = db
    -- The saved look (Modern or Classic), before any module builds frames.
    if ns.Widgets then
        pcall(ns.Widgets.ApplyTheme, db.theme or "modern")
    end
end

-- One-time copy of settings from the standalone addon a module replaces.
-- Only possible while that addon is still enabled, since its saved variables
-- are not loaded otherwise.
local function ImportLegacy(module)
    local legacy = module.legacy
    if not legacy or module.db.legacyImported or type(module.ImportLegacy) ~= "function" then
        return
    end
    local old = _G[legacy.savedVariable]
    if type(old) ~= "table" then return end
    if pcall(module.ImportLegacy, module, old) then
        module.db.legacyImported = true
        ns:Print(("%s: imported your settings from the standalone %s addon."):format(module.title, legacy.addon))
    end
end

---------------------------------------------------------------------------
-- Starting and stopping modules
---------------------------------------------------------------------------

local function IsAddOnLoadedSafe(name)
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if type(fn) ~= "function" then return false end
    local ok, loaded = pcall(fn, name)
    return ok and loaded and true or false
end

-- Why a module may not run right now: reason text, and whether that reason
-- is routine (not worth a chat message at login). nil when it may run.
-- False for a class module on a character of another class. Such a module
-- counts as disabled there, whatever was saved by the account's other
-- characters.
function ns:IsAvailable(module)
    if not module.class then return true end
    local ok, _, class = pcall(UnitClass, "player")
    return ok and class == module.class
end

-- Whether the module is switched on for this character.
function ns:IsModuleOn(module)
    return module.db.enabled == true and self:IsAvailable(module)
end

function ns:GetBlockReason(module)
    if not self:IsAvailable(module) then
        return ("only runs on %s characters."):format(module.class:lower()), true
    end
    if module.legacy and IsAddOnLoadedSafe(module.legacy.addon) then
        return ("the standalone %s addon is still enabled. Disable it and /reload to use this module."):format(module.legacy.addon), false
    end
end

function ns:StartModule(module, verbose)
    if module.active then return true end
    local reason, routine = self:GetBlockReason(module)
    if reason then
        if verbose or not routine then
            self:Print(module.title .. ": " .. reason)
        end
        return false
    end
    module.active = true
    if type(module.OnEnable) == "function" then
        local ok, err = pcall(module.OnEnable, module)
        if not ok then
            module.active = false
            self:Print(("%s failed to start: %s"):format(module.title, tostring(err)))
            return false
        end
    end
    return true
end

function ns:StopModule(module)
    if not module.active then return end
    if type(module.OnDisable) == "function" then
        local ok, err = pcall(module.OnDisable, module)
        if not ok then
            self:Print(("%s failed to stop cleanly: %s"):format(module.title, tostring(err)))
        end
    end
    module.active = false
end

-- Records the user's choice and applies it.
function ns:SetModuleEnabled(key, enabled, verbose)
    local module = self.modules[key]
    if not module then return end
    enabled = enabled and true or false
    -- Never save a choice from a character the module does not run on.
    if not self:IsAvailable(module) then
        self:Print(module.title .. ": " .. self:GetBlockReason(module))
        if self.Options then self.Options:Refresh() end
        return
    end
    local changed = module.db.enabled ~= enabled
    module.db.enabled = enabled
    if self.started then
        if enabled then
            self:StartModule(module, verbose)
        else
            self:StopModule(module)
        end
    end
    if changed and type(module.OnUserToggle) == "function" then
        pcall(module.OnUserToggle, module, enabled)
    end
    if self.Options then
        self.Options:Refresh()
    end
end

local dbReady = false

-- Runs once every addon has loaded, so standalone copies of a module can be
-- detected whatever their load order.
local function Start()
    if ns.started or not dbReady then return end
    ns.started = true
    for _, module in ipairs(ns.moduleList) do
        ImportLegacy(module)
        if ns:IsModuleOn(module) then
            ns:StartModule(module, false)
        end
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        InitDB()
        dbReady = true
        if ns.Options then
            local ok, err = pcall(ns.Options.Build, ns.Options)
            if not ok then
                ns:Print("could not build the options panel: " .. tostring(err))
            end
        end
        if type(IsLoggedIn) == "function" and IsLoggedIn() then
            Start()
        end
    elseif event == "PLAYER_LOGIN" then
        Start()
    end
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

local function PrintStatus()
    ns:Print("modules:")
    for _, module in ipairs(ns.moduleList) do
        local state
        if module.active then
            state = "|cff40ff40running|r"
        elseif not ns:IsAvailable(module) then
            state = "|cffff4040disabled|r - " .. ns:GetBlockReason(module)
        elseif module.db.enabled then
            local reason = ns:GetBlockReason(module)
            state = "|cffffd040enabled, not running|r" .. (reason and (" - " .. reason) or "")
        else
            state = "|cffff4040disabled|r"
        end
        print(("  %s (%s): %s"):format(module.title, module.key, state))
    end
end

-- /dhoxar mouse: what is under the cursor, for finding frames that block
-- clicks on the world. Waits a moment so the cursor can be moved there.
local function FrameLabel(f)
    local ok, name = pcall(function() return f.GetDebugName and f:GetDebugName() or f:GetName() end)
    if ok and type(name) == "string" and not ns.Util.IsSecret(name) and name ~= "" then return name end
    return tostring(f)
end

local function MouseReport()
    local lines = {}
    local function Add(s) lines[#lines + 1] = s end
    local foci = {}
    if GetMouseFoci then
        local ok, list = pcall(GetMouseFoci)
        if ok and type(list) == "table" then foci = list end
    elseif GetMouseFocus then
        local ok, f = pcall(GetMouseFocus)
        if ok and f then foci = { f } end
    end
    Add("Mouse focus:")
    if #foci == 0 then Add("  (none)") end
    for _, f in ipairs(foci) do Add("  " .. FrameLabel(f)) end

    Add("")
    Add("Shown frames under the cursor that take the mouse:")
    local count, guard = 0, 0
    local okEnum, f = pcall(EnumerateFrames)
    if not okEnum then f = nil end
    while f and guard < 200000 do
        guard = guard + 1
        local cur = f
        local ok, line = pcall(function()
            local takesMouse = (cur.IsMouseEnabled and cur:IsMouseEnabled())
                or (cur.IsMouseClickEnabled and cur:IsMouseClickEnabled())
            if cur == WorldFrame or not (cur:IsVisible() and takesMouse and cur:IsMouseOver()) then return nil end
            local strata, alpha = cur:GetFrameStrata(), cur:GetEffectiveAlpha()
            if ns.Util.IsSecret(strata) then strata = "?" end
            if ns.Util.IsSecret(alpha) then alpha = nil end
            return ("  %s  strata=%s alpha=%.2f"):format(FrameLabel(cur), tostring(strata), tonumber(alpha) or -1)
        end)
        if ok and line then
            count = count + 1
            Add(line)
        end
        local okNext, nextFrame = pcall(EnumerateFrames, cur)
        f = okNext and nextFrame or nil
    end
    if count == 0 then Add("  (none)") end

    Add("")
    local function State(label, fn)
        local ok, text = pcall(function()
            local v = fn()
            if ns.Util.IsSecret(v) then return "?" end
            return tostring(v)
        end)
        Add(("%s: %s"):format(label, ok and text or "?"))
    end
    State("Mouselook", function() return IsMouselooking and IsMouselooking() end)
    State("Cursor holds", function() return GetCursorInfo and GetCursorInfo() or "nothing" end)
    State("Spell targeting", function() return SpellIsTargeting and SpellIsTargeting() end)
    for i = 1, 4 do
        local g = _G["GroupLootFrame" .. i]
        if g then State("GroupLootFrame" .. i .. " shown", function() return g:IsShown() end) end
    end
    if GroupLootContainer then State("GroupLootContainer shown", function() return GroupLootContainer:IsShown() end) end
    local report = table.concat(lines, "\n")
    -- Also in chat, in case the window cannot open.
    for _, line in ipairs(lines) do
        if line ~= "" then print("|cff33ff99Dhoxar mouse|r " .. line) end
    end
    local okShow, err = pcall(ns.Util.ShowCopyableText, "Dhoxar Modules: under the mouse", report)
    if not okShow then ns:Print("could not open the report window: " .. tostring(err)) end
end

local function SafeMouseReport()
    local ok, err = xpcall(MouseReport, function(e) return tostring(e) end)
    if not ok then ns:Print("/dhoxar mouse failed: " .. tostring(err)) end
end

local function PrintHelp()
    ns:Print("commands:")
    print("  /dhoxar - open or close the configuration window")
    print("  /dhoxar list - show every module and its state")
    print("  /dhoxar enable <module> - turn a module on")
    print("  /dhoxar disable <module> - turn a module off")
    print("  /dhoxar mouse - after 3 seconds, show what is under the cursor")
end

SLASH_DHOXARMODULES1 = "/dhoxar"
SLASH_DHOXARMODULES2 = "/dhx"
SlashCmdList["DHOXARMODULES"] = function(msg)
    msg = strtrim(msg or "")
    local command, rest = msg:match("^(%S*)%s*(.-)$")
    command = (command or ""):lower()

    if command == "" or command == "options" or command == "config" then
        if not (ns.Options and ns.Options:Toggle()) then
            PrintStatus()
            PrintHelp()
        end
    elseif command == "list" or command == "status" then
        PrintStatus()
    elseif command == "mouse" then
        ns:Print("put the cursor where clicks don't reach the world; checking in 3 seconds.")
        C_Timer.After(3, SafeMouseReport)
    elseif command == "enable" or command == "disable" then
        local module = ns:FindModule(rest)
        if not module then
            ns:Print(("unknown module '%s'. Type /dhoxar list."):format(rest))
            return
        end
        ns:SetModuleEnabled(module.key, command == "enable", true)
        if command == "disable" then
            ns:Print(module.title .. " disabled.")
        elseif module.active then
            ns:Print(module.title .. " enabled.")
        end
    else
        PrintHelp()
    end
end
