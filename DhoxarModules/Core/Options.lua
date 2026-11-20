-- Dhoxar Modules - configuration window
--
-- The main module's own UI: a movable window (/dhoxar) with an Overview page
-- that turns modules on and off, and one page per module. Modules fill their
-- page in BuildOptions(page) through these Page methods, so they never deal
-- with frames or layout:
--
--   page:Header(text)
--   page:Text(text)
--   page:Checkbox({ label = ..., description = ..., get = fn, set = fn(value) })
--   page:Button({ label = ..., description = ..., text = string or fn, onClick = fn })
--   page:Slider({ label = ..., description = ..., min = n, max = n, step = n,
--                 get = fn, set = fn(value), format = fn(value) })
--
-- Every control re-reads its value on Options:Refresh(), which runs when the
-- window opens, when a page is shown, and after any control is used.
--
-- Interface Options > AddOns > Dhoxar Modules only holds a button that opens
-- this window.

local ADDON_NAME, ns = ...

local W = ns.Widgets
local C = W.colors

local Options = {}
ns.Options = Options

local WIDTH, HEIGHT = 800, 540
local HEADER_H = 46
local SIDEBAR_W = 220
local PAD = 22
local SCROLLBAR_W = 4
local CONTENT_W = WIDTH - SIDEBAR_W - PAD * 2 - SCROLLBAR_W - 8
local VIEW_H = HEIGHT - HEADER_H - PAD * 2
local GAP = 14
local NAV_H = 30
local OVERVIEW = "overview"

local frame, scroll, track, thumb
local pages = {}
local navItems = {}
local currentKey = OVERVIEW

local function ReportError(what, err)
    ns:Print(("%s: %s"):format(what, tostring(err)))
end

-- Status text and color for a module.
local function ModuleStatus(module)
    if module.active then
        return "Running", C.good
    end
    if not ns:IsAvailable(module) then
        return "Disabled - " .. ns:GetBlockReason(module), C.off
    end
    if module.db.enabled then
        local reason = ns:GetBlockReason(module)
        return "Enabled, not running" .. (reason and (" - " .. reason) or ""), C.warn
    end
    return "Disabled", C.off
end

---------------------------------------------------------------------------
-- Page: a vertical stack of controls inside the scrolling content area
---------------------------------------------------------------------------

local Page = {}
Page.__index = Page

local function NewPage(key)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_W, 1)
    content:Hide()
    return setmetatable({ key = key, frame = content, y = 0, refreshers = {} }, Page)
end

-- Stacks a region below the previous one.
function Page:Place(region, height, gapAfter)
    region:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -self.y)
    self.y = self.y + height + (gapAfter or GAP)
end

function Page:OnRefresh(fn)
    self.refreshers[#self.refreshers + 1] = fn
end

function Page:Refresh()
    for _, fn in ipairs(self.refreshers) do
        local ok, err = pcall(fn)
        if not ok then
            ReportError("could not refresh the configuration window", err)
        end
    end
end

function Page:Finish()
    self.frame:SetHeight(math.max(self.y, 1))
end

function Page:Title(text, subtitle)
    local title = W.Text(self.frame, "GameFontHighlightLarge", C.title, CONTENT_W)
    title:SetText(text)
    self:Place(title, title:GetStringHeight(), subtitle and 6 or GAP)
    if subtitle then
        local sub = W.Text(self.frame, "GameFontHighlightSmall", C.muted, CONTENT_W)
        sub:SetText(subtitle)
        self:Place(sub, sub:GetStringHeight(), 16)
    end
end

function Page:Header(text)
    if self.y > 0 then
        self.y = self.y + 8
    end
    local f = CreateFrame("Frame", nil, self.frame)
    f:SetSize(CONTENT_W, 20)
    local classic = W.IsClassic()
    local label = W.Text(f, classic and "GameFontNormal" or "GameFontNormalSmall", C.accent)
    label:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 6)
    label:SetText(classic and tostring(text) or tostring(text):upper())
    local line = f:CreateTexture(nil, "ARTWORK")
    W.SetColor(line, C.border)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    self:Place(f, 20, 12)
end

function Page:Text(text)
    local fs = W.Text(self.frame, "GameFontHighlightSmall", C.muted, CONTENT_W)
    fs:SetText(text)
    self:Place(fs, fs:GetStringHeight())
    return fs
end

-- Label plus optional description stacked in a column; returns total height.
local function LabelBlock(parent, x, width, label, description)
    local title = W.Text(parent, "GameFontHighlight", C.text, width)
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -2)
    title:SetText(label or "")
    local height = 2 + title:GetStringHeight()
    local desc
    if description and description ~= "" then
        desc = W.Text(parent, "GameFontHighlightSmall", C.muted, width)
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
        desc:SetText(description)
        height = height + 3 + desc:GetStringHeight()
    end
    return title, desc, height
end

function Page:Checkbox(opts)
    local row = CreateFrame("Button", nil, self.frame)
    local title, _, textHeight = LabelBlock(row, 48, CONTENT_W - 48, opts.label, opts.description)
    local classic = W.IsClassic()
    local height = math.max(textHeight, classic and 24 or 20)
    row:SetSize(CONTENT_W, height)

    local function Flip()
        local ok, value = pcall(opts.get)
        local okSet, err = pcall(opts.set, not (ok and value))
        if not okSet then
            ReportError("could not change " .. tostring(opts.label), err)
        end
        Options:Refresh()
    end

    local toggle = W.Toggle(row, Flip)
    -- The checkbox art has transparent padding; nudge it to line up with the label.
    toggle:SetPoint("TOPLEFT", row, "TOPLEFT", classic and -4 or 0, classic and 4 or 0)
    row:SetScript("OnClick", Flip)
    row:SetScript("OnEnter", function() title:SetTextColor(1, 1, 1) end)
    row:SetScript("OnLeave", function() title:SetTextColor(C.text[1], C.text[2], C.text[3]) end)

    self:OnRefresh(function()
        local ok, value = pcall(opts.get)
        toggle:SetChecked(ok and value)
    end)
    self:Place(row, height)
    return row
end

function Page:Button(opts)
    local row = CreateFrame("Frame", nil, self.frame)
    local _, _, textHeight = LabelBlock(row, 0, CONTENT_W - 140, opts.label, opts.description)
    local height = math.max(textHeight, 24)
    row:SetSize(CONTENT_W, height)

    local function ButtonText()
        if type(opts.text) == "function" then
            local ok, text = pcall(opts.text)
            return ok and text or ""
        end
        return opts.text or "Run"
    end

    local button = W.Button(row, ButtonText(), 120, 24, function()
        local ok, err = pcall(opts.onClick)
        if not ok then
            ReportError(tostring(opts.label) .. " failed", err)
        end
        Options:Refresh()
    end)
    button:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)

    self:OnRefresh(function() button:SetLabel(ButtonText()) end)
    self:Place(row, height)
    return row
end

-- A draggable slider with the current value next to it.
-- opts: label, description, min, max, step (default 1), get, set(value),
-- format(value) (optional, text shown next to the slider).
function Page:Slider(opts)
    local step = opts.step or 1
    local row = CreateFrame("Frame", nil, self.frame)
    local _, _, textHeight = LabelBlock(row, 0, CONTENT_W - 230, opts.label, opts.description)
    local height = math.max(textHeight, 24)
    row:SetSize(CONTENT_W, height)

    local valueText = W.Text(row, "GameFontHighlight", C.text, 64)
    valueText:SetJustifyH("RIGHT")
    valueText:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -4)

    local slider = CreateFrame("Slider", nil, row)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(150, 18)
    slider:SetPoint("TOPRIGHT", row, "TOPRIGHT", -72, -1)
    slider:SetMinMaxValues(opts.min, opts.max)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:SetHitRectInsets(0, 0, -4, -4)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    W.SetColor(track, C.track)
    track:SetHeight(4)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    if W.IsClassic() then
        -- Dark groove with a brown rim, like the game's sliders.
        track:SetHeight(6)
        local rim = slider:CreateTexture(nil, "BACKGROUND", nil, -1)
        W.SetColor(rim, C.border)
        rim:SetPoint("TOPLEFT", track, "TOPLEFT", -1, 1)
        rim:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 1, -1)
        thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        thumb:SetSize(32, 32)
    else
        W.SetColor(thumb, C.accent)
        thumb:SetSize(8, 16)
    end
    slider:SetThumbTexture(thumb)

    local function Format(v)
        if opts.format then
            local ok, text = pcall(opts.format, v)
            if ok and text then return text end
        end
        return tostring(v)
    end

    local updating = false
    self:OnRefresh(function()
        local ok, v = pcall(opts.get)
        if not ok or type(v) ~= "number" then return end
        updating = true
        slider:SetValue(v)
        updating = false
        valueText:SetText(Format(v))
    end)

    slider:SetScript("OnValueChanged", function(_, v)
        if updating then return end
        v = math.floor(v / step + 0.5) * step
        local ok, err = pcall(opts.set, v)
        if not ok then
            ReportError("could not change " .. tostring(opts.label), err)
        end
        Options:Refresh()
    end)

    self:Place(row, height)
    return row
end

---------------------------------------------------------------------------
-- Overview and module pages
---------------------------------------------------------------------------

local function AddModuleCard(page, module)
    local inset = 14
    local card = W.Inset(page.frame)

    local textW = CONTENT_W - inset * 2 - 50
    local title = W.Text(card, "GameFontNormal", C.title, textW)
    title:SetPoint("TOPLEFT", card, "TOPLEFT", inset, -inset)
    title:SetText(module.title)

    local desc = W.Text(card, "GameFontHighlightSmall", C.muted, textW)
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetText(module.description or "")

    -- Room for two lines, as a "not running" reason can wrap.
    local dot = W.Dot(card, 7)
    dot:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -12)
    local status = W.Text(card, "GameFontHighlightSmall", C.text, CONTENT_W - inset * 2 - 130)
    status:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 13, -10)

    local toggle = W.Toggle(card, function()
        ns:SetModuleEnabled(module.key, not ns:IsModuleOn(module), true)
        Options:Refresh()
    end)
    toggle:SetPoint("TOPRIGHT", card, "TOPRIGHT", -inset, -inset)

    local open = W.Button(card, "Settings", 96, 22, function()
        Options:Select(module.key)
    end)
    open:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -inset, inset)

    local height = inset + title:GetStringHeight() + 4 + desc:GetStringHeight() + 10 + 24 + inset
    card:SetSize(CONTENT_W, height)

    page:OnRefresh(function()
        toggle:SetChecked(ns:IsModuleOn(module))
        local text, color = ModuleStatus(module)
        status:SetText(text)
        status:SetTextColor(color[1], color[2], color[3])
        W.SetColor(dot, color)
    end)
    page:Place(card, height, 10)
end

local function BuildOverview(page)
    page:Title("Modules", "Turn modules on or off here. Pick a module on the left, or its Settings button, to change how it works.")
    page:Button({
        label = "Look",
        description = "Modern: flat dark panels. Classic: the game's own window style, with gold text, red buttons and checkboxes.",
        text = function() return W.THEME_NAMES[W.style] or "Modern" end,
        onClick = function()
            Options:SetTheme(W.IsClassic() and "modern" or "classic")
        end,
    })
    for _, module in ipairs(ns.moduleList) do
        AddModuleCard(page, module)
    end
end

local function BuildModulePage(page, module)
    page:Title(module.title, module.description)

    local row = CreateFrame("Frame", nil, page.frame)
    row:SetSize(CONTENT_W, 26)
    local dot = W.Dot(row, 7)
    dot:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -3)
    local status = W.Text(row, "GameFontHighlightSmall", C.text, CONTENT_W - 14)
    status:SetPoint("TOPLEFT", row, "TOPLEFT", 13, -1)
    page:OnRefresh(function()
        local text, color = ModuleStatus(module)
        status:SetText(text)
        status:SetTextColor(color[1], color[2], color[3])
        W.SetColor(dot, color)
    end)
    page:Place(row, 26, 6)

    page:Header("Module")
    page:Checkbox({
        label = "Enabled",
        description = module.class and ("Only runs on " .. module.class:lower() .. " characters.") or nil,
        get = function() return ns:IsModuleOn(module) end,
        set = function(value) ns:SetModuleEnabled(module.key, value, true) end,
    })

    if type(module.BuildOptions) == "function" then
        local ok, err = pcall(module.BuildOptions, module, page)
        if not ok then
            page:Text("Could not build this module's settings: " .. tostring(err))
            ReportError("could not build the settings for " .. module.title, err)
        end
    end
end

-- Pages are built the first time they are shown.
local function GetPage(key)
    if pages[key] then return pages[key] end
    local module = ns.modules[key]
    if key ~= OVERVIEW and not module then return nil end
    local page = NewPage(key)
    if module then
        BuildModulePage(page, module)
    else
        BuildOverview(page)
    end
    page:Finish()
    pages[key] = page
    return page
end

---------------------------------------------------------------------------
-- Scrolling
---------------------------------------------------------------------------

local function MaxScroll()
    local child = scroll:GetScrollChild()
    return child and math.max(0, child:GetHeight() - VIEW_H) or 0
end

local function UpdateScrollbar()
    local maxScroll = MaxScroll()
    if maxScroll <= 0 then
        scroll:SetVerticalScroll(0)
        track:Hide()
        thumb:Hide()
        return
    end
    track:Show()
    thumb:Show()
    local total = VIEW_H + maxScroll
    local thumbH = math.max(24, VIEW_H * VIEW_H / total)
    local fraction = scroll:GetVerticalScroll() / maxScroll
    thumb:SetHeight(thumbH)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", track, "TOP", 0, -(VIEW_H - thumbH) * fraction)
end

local function OnMouseWheel(self, delta)
    local target = self:GetVerticalScroll() - delta * 40
    self:SetVerticalScroll(math.min(MaxScroll(), math.max(0, target)))
    UpdateScrollbar()
end

---------------------------------------------------------------------------
-- Sidebar
---------------------------------------------------------------------------

local function UpdateNav()
    for _, item in ipairs(navItems) do
        item.selected = item.key == currentKey
        item.bar:SetShown(item.selected)
        W.SetColor(item.bg, item.selected and C.navSelected or C.navItem)
        local color = item.selected and C.navTextOn or C.navText
        item.label:SetTextColor(color[1], color[2], color[3])
        if item.module then
            local _, statusColor = ModuleStatus(item.module)
            W.SetColor(item.dot, statusColor)
        end
    end
end

-- x and width: classic items are bars inset from the sidebar's edges, like
-- the quest log's zone headers; modern items span the sidebar.
local function CreateNavItem(parent, key, text, module, y, x, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or (SIDEBAR_W - 1), NAV_H)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, -y)
    b.key, b.module = key, module
    b.bg = W.Fill(b, "BACKGROUND", C.navItem)
    if W.IsClassic() then
        W.Border(b, C.border)
    end

    b.bar = b:CreateTexture(nil, "ARTWORK")
    W.SetColor(b.bar, C.accent)
    b.bar:SetWidth(3)
    b.bar:SetPoint("TOPLEFT")
    b.bar:SetPoint("BOTTOMLEFT")

    b.label = W.Text(b, W.IsClassic() and "GameFontNormal" or "GameFontHighlight", C.navText)
    b.label:SetPoint("LEFT", b, "LEFT", W.IsClassic() and 12 or 18, 0)
    b.label:SetWidth((width or SIDEBAR_W) - 48)
    b.label:SetWordWrap(false)
    b.label:SetText(text)

    if module then
        b.dot = W.Dot(b, 6)
        b.dot:SetPoint("RIGHT", b, "RIGHT", -16, 0)
    end

    b:SetScript("OnEnter", function(self)
        if not self.selected then W.SetColor(self.bg, C.navHover) end
    end)
    b:SetScript("OnLeave", function(self)
        if not self.selected then W.SetColor(self.bg, C.navItem) end
    end)
    b:SetScript("OnClick", function(self) Options:Select(self.key) end)

    navItems[#navItems + 1] = b
    return b
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function GetVersion()
    local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if type(getter) ~= "function" then return nil end
    local ok, version = pcall(getter, ADDON_NAME, "Version")
    return ok and version or nil
end

local function SavePosition(f)
    local point, _, relativePoint, x, y = f:GetPoint()
    if ns.db and point then
        ns.db.window = { point = point, relativePoint = relativePoint, x = x, y = y }
    end
end

local function RestorePosition(f)
    local saved = ns.db and ns.db.window
    f:ClearAllPoints()
    if type(saved) == "table" and saved.point then
        f:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
end

local CLASSIC_TOP = 62 -- classic: title bar and portrait above the panels

local function MakeDragHandle(f, region)
    region:EnableMouse(true)
    region:RegisterForDrag("LeftButton")
    region:SetScript("OnDragStart", function() f:StartMoving() end)
    region:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        SavePosition(f)
    end)
end

-- Modern: flat header with the logo, title, version and an X button.
-- Returns the y offset where the panels start.
local function BuildModernChrome(f)
    W.Fill(f, "BACKGROUND", C.window)
    W.Border(f)

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H - 1)
    W.Fill(header, "BACKGROUND", C.header)
    MakeDragHandle(f, header)

    local accent = header:CreateTexture(nil, "ARTWORK")
    W.SetColor(accent, C.accent)
    accent:SetHeight(2)
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("TOPRIGHT")

    local divider = header:CreateTexture(nil, "ARTWORK")
    W.SetColor(divider, C.border)
    divider:SetHeight(1)
    divider:SetPoint("BOTTOMLEFT")
    divider:SetPoint("BOTTOMRIGHT")

    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(32, 32)
    logo:SetPoint("LEFT", header, "LEFT", 12, 0)
    logo:SetTexture(W.LOGO)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetTextColor(1, 1, 1)
    title:SetText("|cffc8aa88Dhoxar|r Modules")

    local version = GetVersion()
    if version then
        local v = W.Text(header, "GameFontHighlightSmall", C.muted)
        v:SetPoint("LEFT", title, "RIGHT", 8, -1)
        v:SetText("v" .. version)
    end

    local close = W.Button(header, "X", 24, 24, function() f:Hide() end)
    close:SetPoint("RIGHT", header, "RIGHT", -11, 0)
    return HEADER_H
end

-- Classic: the game's window frame (gold metal border, round portrait with
-- the logo, centered title, red X). `templated` is true when f was created
-- from PortraitFrameTemplate; otherwise the same look is drawn by hand.
local function BuildClassicChrome(f, templated)
    local titleText = "Dhoxar Modules"
    if templated then
        if not f.Bg then W.RockBackground(f) end
        local titleSet = false
        if f.SetTitle then titleSet = pcall(f.SetTitle, f, titleText) end
        if not titleSet then
            local t = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
            if t then t:SetText(titleText) end
        end
        local portraitSet = false
        if f.SetPortraitToAsset then portraitSet = pcall(f.SetPortraitToAsset, f, W.LOGO) end
        if not portraitSet then
            local p = f.portrait or (f.PortraitContainer and f.PortraitContainer.portrait)
            if p then
                if not (SetPortraitToTexture and pcall(SetPortraitToTexture, p, W.LOGO)) then p:SetTexture(W.LOGO) end
            end
        end
        if f.CloseButton then
            f.CloseButton:SetScript("OnClick", function() f:Hide() end)
        end
    else
        W.RockBackground(f)
        W.Border(f, C.border, 2)
        local bar = f:CreateTexture(nil, "BORDER")
        W.SetColor(bar, C.header)
        bar:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
        bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
        bar:SetHeight(22)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", f, "TOP", 0, -6)
        title:SetText(titleText)
        local logo = f:CreateTexture(nil, "ARTWORK")
        logo:SetSize(44, 44)
        logo:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
        logo:SetTexture(W.LOGO)
        local close = W.CloseButton(f, function() f:Hide() end)
            or W.Button(f, "X", 22, 22, function() f:Hide() end)
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    end

    -- The title bar drags the window (left of the close button).
    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT", f, "TOPLEFT", 60, 0)
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, 0)
    drag:SetHeight(24)
    MakeDragHandle(f, drag)

    local version = GetVersion()
    if version then
        local v = W.Text(f, "GameFontHighlightSmall", C.muted)
        v:SetPoint("TOPLEFT", f, "TOPLEFT", 72, -36)
        v:SetText("Version " .. version)
    end
    return CLASSIC_TOP
end

local function CreateWindow()
    W.ApplyTheme(ns.db and ns.db.theme or "modern")
    local classic = W.IsClassic()

    local f, templated
    if classic then
        f = W.TryTemplate("Frame", UIParent, "PortraitFrameTemplate", "DhoxarModulesConfigFrame")
        templated = f ~= nil
    end
    f = f or CreateFrame("Frame", "DhoxarModulesConfigFrame", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()
    RestorePosition(f)

    local top
    if classic then
        top = BuildClassicChrome(f, templated)
    else
        top = BuildModernChrome(f)
    end
    -- Same content area in both looks; only the chrome above it differs.
    f:SetSize(WIDTH, VIEW_H + top + PAD * 2)

    -- Sidebar navigation.
    local sidebar, navX, navW, navGap, textX
    if classic then
        sidebar = W.Inset(f)
        sidebar:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -top)
        sidebar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 8)
        sidebar:SetWidth(SIDEBAR_W - 10)
        navX, navW, navGap, textX = 6, SIDEBAR_W - 22, 3, 12

        -- The content area sits in its own inset panel.
        local content = W.Inset(f)
        content:SetPoint("TOPLEFT", f, "TOPLEFT", SIDEBAR_W + 2, -top)
        content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    else
        sidebar = CreateFrame("Frame", nil, f)
        sidebar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -HEADER_H)
        sidebar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
        sidebar:SetWidth(SIDEBAR_W)
        W.Fill(sidebar, "BACKGROUND", C.sidebar)
        local edge = sidebar:CreateTexture(nil, "ARTWORK")
        W.SetColor(edge, C.border)
        edge:SetWidth(1)
        edge:SetPoint("TOPRIGHT")
        edge:SetPoint("BOTTOMRIGHT")
        navX, navW, navGap, textX = 0, SIDEBAR_W - 1, 0, 18
    end

    local y = classic and 8 or 14
    CreateNavItem(sidebar, OVERVIEW, "Overview", nil, y, navX, navW)
    y = y + NAV_H + 16
    local section = W.Text(sidebar, "GameFontNormalSmall", C.muted)
    section:SetPoint("TOPLEFT", sidebar, "TOPLEFT", textX, -y)
    section:SetText(classic and "Modules" or "MODULES")
    y = y + 18
    for _, module in ipairs(ns.moduleList) do
        CreateNavItem(sidebar, module.key, module.title, module, y, navX, navW)
        y = y + NAV_H + navGap
    end

    local hint = W.Text(sidebar, "GameFontHighlightSmall", C.muted)
    hint:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", textX, classic and 10 or 14)
    hint:SetText("/dhoxar to open or close")

    -- Scrolling content area.
    scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", SIDEBAR_W + PAD, -(top + PAD))
    scroll:SetSize(CONTENT_W, VIEW_H)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", OnMouseWheel)

    track = f:CreateTexture(nil, "ARTWORK")
    W.SetColor(track, classic and C.track or C.control)
    track:SetSize(SCROLLBAR_W, VIEW_H)
    track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, 0)
    thumb = f:CreateTexture(nil, "OVERLAY")
    W.SetColor(thumb, C.thumb)
    thumb:SetWidth(SCROLLBAR_W)

    f:SetScript("OnShow", function() Options:Refresh() end)
    local listed = false
    for _, name in ipairs(UISpecialFrames) do
        if name == "DhoxarModulesConfigFrame" then listed = true end
    end
    if not listed then
        table.insert(UISpecialFrames, "DhoxarModulesConfigFrame") -- Esc closes it
    end
    frame = f
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function Options:Select(key)
    if not frame then return end
    local page = GetPage(key) or GetPage(OVERVIEW)
    for _, other in pairs(pages) do
        if other ~= page then other.frame:Hide() end
    end
    currentKey = page.key
    scroll:SetScrollChild(page.frame)
    page.frame:Show()
    scroll:SetVerticalScroll(0)
    self:Refresh()
end

-- Re-reads every value shown in the window.
function Options:Refresh()
    if not (frame and frame:IsShown()) then return end
    UpdateNav()
    local page = pages[currentKey]
    if page then page:Refresh() end
    UpdateScrollbar()
end

-- Returns true if the window is now open.
function Options:Open(key)
    if not ns.db then return false end -- saved variables not loaded yet
    if not frame then
        local ok, err = pcall(CreateWindow)
        if not ok then
            ReportError("could not create the configuration window", err)
            return false
        end
    end
    frame:Show()
    frame:Raise()
    self:Select(key or currentKey)
    return true
end

function Options:Close()
    if frame then frame:Hide() end
end

-- Switches between the "modern" and "classic" looks. Frames can't be
-- restyled in place, so the window is built again and reopened on the same
-- page; the old one is hidden and left unused.
function Options:SetTheme(name)
    if not ns.db then return end
    ns.db.theme = W.themes[name] and name or "modern"
    local wasShown = frame and frame:IsShown()
    local key = currentKey
    if frame then
        frame:Hide()
        frame:SetScript("OnShow", nil)
    end
    frame, scroll, track, thumb = nil, nil, nil, nil
    pages, navItems = {}, {}
    W.ApplyTheme(ns.db.theme)
    if wasShown then
        self:Open(key)
    end
end

function Options:Toggle()
    if frame and frame:IsShown() then
        self:Close()
        return true
    end
    return self:Open()
end

-- Adds an entry under Interface Options > AddOns with a button that opens the
-- window, so the addon can still be found there.
function Options:Build()
    if self.launcher then return end
    local panel = CreateFrame("Frame")
    panel.name = ns.title

    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(48, 48)
    logo:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    logo:SetTexture(W.LOGO)

    local title = W.Text(panel, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -6)
    title:SetText(ns.title)

    local text = W.Text(panel, "GameFontHighlight", nil, 480)
    text:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -14)
    text:SetText("Dhoxar Modules has its own configuration window. You can also open it at any time with /dhoxar.")

    local button = W.Button(panel, "Open configuration", 160, 26, function()
        for _, blizzard in ipairs({ _G.SettingsPanel, _G.InterfaceOptionsFrame }) do
            if blizzard and blizzard:IsShown() then pcall(HideUIPanel, blizzard) end
        end
        Options:Open()
    end)
    button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, ns.title))
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
    self.launcher = panel
end
