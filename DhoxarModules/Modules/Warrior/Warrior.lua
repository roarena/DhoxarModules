-- Module: Warrior
--
-- One module in the configuration window for every warrior feature. Each
-- feature lives in its own file in this folder and registers itself with
-- ns.Warrior:AddFeature, using the same fields and callbacks as a module
-- (key, title, description, defaults, legacy, OnEnable, OnDisable,
-- BuildOptions, ImportLegacy). This file fills in feature.db and
-- feature.active, and runs a feature while both the Warrior module and the
-- feature's own switch are on.
--
-- Settings live in DhoxarModulesDB.modules.Warrior.features[<feature key>].
-- The features used to be separate modules; their old settings are moved
-- here the first time.

local _, ns = ...

local Warrior = ns:RegisterModule({
    key = "Warrior",
    title = "Warrior",
    description = "Warrior features: a simplified rage bar and in-combat reminder icons. Warriors only.",
    class = "WARRIOR",
    aliases = { "warr", "ragebar", "reminders" },
    defaults = { features = {} },
})
ns.Warrior = Warrior
Warrior.features = {}

local function ApplyDefaults(target, defaults)
    for k, v in pairs(defaults or {}) do
        if target[k] == nil then
            if type(v) == "table" then
                local copy = {}
                ApplyDefaults(copy, v)
                target[k] = copy
            else
                target[k] = v
            end
        end
    end
end

function Warrior:AddFeature(feature)
    assert(type(feature) == "table" and type(feature.key) == "string", "Dhoxar Modules: a warrior feature needs a key")
    feature.title = feature.title or feature.key
    feature.active = false
    feature.db = { enabled = true } -- placeholder until the saved variables load
    ApplyDefaults(feature.db, feature.defaults)
    self.features[#self.features + 1] = feature
    return feature
end

-- Points every feature at its saved table, moving settings saved when the
-- features were separate modules (same keys) on first use.
local bound = false
local function BindFeatures()
    if bound or not ns.db then return end
    bound = true
    if type(Warrior.db.features) ~= "table" then Warrior.db.features = {} end
    local saved = Warrior.db.features
    local oldModules = ns.db.modules
    for _, feature in ipairs(Warrior.features) do
        local fdb = saved[feature.key]
        if type(fdb) ~= "table" then
            local old = oldModules[feature.key]
            fdb = type(old) == "table" and old or {}
            saved[feature.key] = fdb
        end
        oldModules[feature.key] = nil
        if fdb.enabled == nil then fdb.enabled = true end
        ApplyDefaults(fdb, feature.defaults)
        feature.db = fdb
    end
end

local function IsAddOnLoadedSafe(name)
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if type(fn) ~= "function" then return false end
    local ok, loaded = pcall(fn, name)
    return ok and loaded and true or false
end

-- Why a feature cannot run, or nil.
function Warrior:GetFeatureBlockReason(feature)
    if feature.legacy and IsAddOnLoadedSafe(feature.legacy.addon) then
        return ("the standalone %s addon is still enabled. Disable it and /reload to use this feature."):format(feature.legacy.addon)
    end
end

-- One-time copy of settings from the standalone addon a feature replaces.
local function ImportLegacy(feature)
    local legacy = feature.legacy
    if not legacy or feature.db.legacyImported or type(feature.ImportLegacy) ~= "function" then return end
    local old = _G[legacy.savedVariable]
    if type(old) ~= "table" then return end
    if pcall(feature.ImportLegacy, feature, old) then
        feature.db.legacyImported = true
        ns:Print(("%s: imported your settings from the standalone %s addon."):format(feature.title, legacy.addon))
    end
end

local function StartFeature(feature)
    if feature.active or not Warrior.active or not feature.db.enabled then return end
    ImportLegacy(feature)
    local reason = Warrior:GetFeatureBlockReason(feature)
    if reason then
        ns:Print(feature.title .. ": " .. reason)
        return
    end
    feature.active = true
    if type(feature.OnEnable) == "function" then
        local ok, err = pcall(feature.OnEnable, feature)
        if not ok then
            feature.active = false
            ns:Print(("%s failed to start: %s"):format(feature.title, tostring(err)))
        end
    end
end

local function StopFeature(feature)
    if not feature.active then return end
    if type(feature.OnDisable) == "function" then
        local ok, err = pcall(feature.OnDisable, feature)
        if not ok then
            ns:Print(("%s failed to stop cleanly: %s"):format(feature.title, tostring(err)))
        end
    end
    feature.active = false
end

function Warrior:SetFeatureEnabled(feature, enabled)
    BindFeatures()
    feature.db.enabled = enabled and true or false
    if feature.db.enabled then
        StartFeature(feature)
    else
        StopFeature(feature)
    end
    if ns.Options then ns.Options:Refresh() end
end

function Warrior:OnEnable()
    BindFeatures()
    for _, feature in ipairs(self.features) do
        StartFeature(feature)
    end
end

function Warrior:OnDisable()
    for _, feature in ipairs(self.features) do
        StopFeature(feature)
    end
end

local function FeatureStatus(feature)
    if feature.active then return "Running." end
    if not feature.db.enabled then return "Off." end
    if not Warrior.active then return "Starts when the Warrior module is running." end
    return "Not running: " .. (Warrior:GetFeatureBlockReason(feature) or "see chat for the error.")
end

function Warrior:BuildOptions(page)
    BindFeatures()
    for _, feature in ipairs(self.features) do
        page:Header(feature.title)
        page:Checkbox({
            label = "Enabled",
            description = feature.description,
            get = function() return feature.db.enabled == true end,
            set = function(value) Warrior:SetFeatureEnabled(feature, value) end,
        })
        local status = page:Text(FeatureStatus(feature))
        page:OnRefresh(function() status:SetText(FeatureStatus(feature)) end)
        if type(feature.BuildOptions) == "function" then
            local ok, err = pcall(feature.BuildOptions, feature, page)
            if not ok then
                page:Text("Could not build these settings: " .. tostring(err))
            end
        end
    end
end
