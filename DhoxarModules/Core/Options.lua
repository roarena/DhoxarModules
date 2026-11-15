-- Dhoxar Modules - options panel
--
-- Interface Options > AddOns > Dhoxar Modules. The main page has one enable
-- checkbox per module; each module that defines BuildOptions gets its own
-- sub-page, which it fills through the small "page" object below so modules
-- never touch the Settings API directly.

local _, ns = ...

local Options = {}
ns.Options = Options

local function HasSettingsAPI()
    return Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting
        and Settings.CreateCheckbox and Settings.RegisterAddOnCategory and true or false
end

---------------------------------------------------------------------------
-- Page: what a module's BuildOptions receives
---------------------------------------------------------------------------

local Page = {}
Page.__index = Page

-- id must be unique across the addon; getter/setter read and write the
-- module's own saved settings.
function Page:Checkbox(id, label, tooltip, default, getter, setter)
    local variable = "DHOXAR_MODULES_" .. id:upper()
    local setting = Settings.RegisterProxySetting(self.category, variable,
        Settings.VarType.Boolean, label, default and true or false, getter, setter)
    Settings.CreateCheckbox(self.category, setting, tooltip)
    return setting
end

-- A labelled push button. Silently skipped on clients without button rows.
function Page:Button(label, buttonText, onClick, tooltip)
    if not (self.layout and self.layout.AddInitializer and CreateSettingsButtonInitializer) then
        return false
    end
    self.layout:AddInitializer(CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, true))
    return true
end

local function NewPage(category, layout)
    return setmetatable({ category = category, layout = layout }, Page)
end

---------------------------------------------------------------------------
-- Building the panel
---------------------------------------------------------------------------

function Options:Build()
    if self.category or not HasSettingsAPI() then return end

    local category, layout = Settings.RegisterVerticalLayoutCategory(ns.title)
    local main = NewPage(category, layout)

    for _, module in ipairs(ns.moduleList) do
        main:Checkbox(module.key .. "_ENABLED", "Enable " .. module.title, module.description, true,
            function() return module.db.enabled == true end,
            function(value) ns:SetModuleEnabled(module.key, value, true) end)
    end

    for _, module in ipairs(ns.moduleList) do
        if type(module.BuildOptions) == "function" then
            -- A broken module page must not take the whole panel down.
            local ok, err = pcall(function()
                local page = main
                if Settings.RegisterVerticalLayoutSubcategory then
                    page = NewPage(Settings.RegisterVerticalLayoutSubcategory(category, module.title))
                end
                module:BuildOptions(page)
            end)
            if not ok then
                ns:Print(("could not build the options for %s: %s"):format(module.title, tostring(err)))
            end
        end
    end

    Settings.RegisterAddOnCategory(category)
    self.category = category
end

-- Returns true if the panel was opened.
function Options:Open()
    if not (self.category and Settings and Settings.OpenToCategory) then
        return false
    end
    local id = self.category.GetID and self.category:GetID() or self.category.ID
    local ok = pcall(Settings.OpenToCategory, id)
    return ok
end
