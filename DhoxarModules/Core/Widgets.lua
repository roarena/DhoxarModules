-- Dhoxar Modules - UI widgets
--
-- Small styled building blocks for the configuration window
-- (Core/Options.lua), in two looks:
--   * modern:  flat color textures and stock font objects (the original look)
--   * classic: the game's own frame art - gold text, red panel buttons,
--              checkboxes, brown and gold borders - like the Professions,
--              Character and Bags windows.
-- Classic uses Blizzard templates where the client has them and falls back
-- to drawn textures otherwise, so a missing template never breaks the window.
--
-- W.colors always holds the active palette. It is one table filled in place
-- by W.ApplyTheme, so code that kept a reference to it sees the change.

local _, ns = ...

local W = {}
ns.Widgets = W

W.LOGO = "Interface\\AddOns\\DhoxarModules\\Media\\logo"

W.themes = {
    modern = {
        window       = { 0.055, 0.060, 0.075, 0.97 },
        header       = { 0.080, 0.088, 0.110, 1 },
        sidebar      = { 0.068, 0.074, 0.094, 1 },
        card         = { 0.098, 0.106, 0.132, 1 },
        control      = { 0.130, 0.140, 0.172, 1 },
        controlHover = { 0.170, 0.182, 0.222, 1 },
        navItem      = { 0, 0, 0, 0 },
        navHover     = { 1, 1, 1, 0.04 },
        navSelected  = { 0.18, 0.62, 0.82, 0.12 },
        clear        = { 0, 0, 0, 0 },
        border       = { 0.200, 0.215, 0.265, 1 },
        -- Teal and tan taken from the logo (Media/logo.tga).
        accent       = { 0.18, 0.62, 0.82, 1 },
        gold         = { 0.78, 0.67, 0.53, 1 },
        thumb        = { 0.18, 0.62, 0.82, 0.55 },
        track        = { 0.240, 0.250, 0.290, 1 },
        knob         = { 0.950, 0.950, 0.970, 1 },
        title        = { 0.920, 0.925, 0.940, 1 },
        text         = { 0.920, 0.925, 0.940, 1 },
        muted        = { 0.600, 0.620, 0.670, 1 },
        navText      = { 0.600, 0.620, 0.670, 1 },
        navTextOn    = { 0.920, 0.925, 0.940, 1 },
        good         = { 0.35, 0.85, 0.40, 1 },
        warn         = { 1.00, 0.78, 0.25, 1 },
        off          = { 0.45, 0.46, 0.50, 1 },
    },
    -- Browns and golds of the game's own windows.
    classic = {
        window       = { 0.110, 0.085, 0.060, 0.97 },
        header       = { 0.150, 0.110, 0.070, 1 },
        sidebar      = { 0.080, 0.062, 0.045, 0.90 },
        card         = { 0.075, 0.058, 0.040, 0.88 },
        control      = { 0.200, 0.150, 0.090, 1 },
        controlHover = { 0.280, 0.210, 0.120, 1 },
        navItem      = { 0.180, 0.135, 0.085, 0.85 },
        navHover     = { 0.270, 0.200, 0.115, 0.95 },
        navSelected  = { 0.380, 0.280, 0.120, 0.95 },
        clear        = { 0, 0, 0, 0 },
        border       = { 0.420, 0.330, 0.200, 1 },
        accent       = { 1.00, 0.82, 0.00, 1 },
        gold         = { 1.00, 0.82, 0.00, 1 },
        thumb        = { 0.800, 0.650, 0.300, 0.75 },
        track        = { 0.050, 0.040, 0.030, 1 },
        knob         = { 1.00, 0.82, 0.00, 1 },
        title        = { 1.00, 0.82, 0.00, 1 },
        text         = { 0.960, 0.940, 0.880, 1 },
        muted        = { 0.740, 0.680, 0.570, 1 },
        navText      = { 1.00, 0.82, 0.00, 1 },
        navTextOn    = { 1.00, 1.00, 1.00, 1 },
        good         = { 0.35, 0.85, 0.40, 1 },
        warn         = { 1.00, 0.60, 0.20, 1 },
        off          = { 0.55, 0.50, 0.42, 1 },
    },
}

W.THEME_NAMES = { modern = "Modern", classic = "Classic" }

W.colors = {}
W.style = "modern"

-- Makes `name` ("modern" or "classic") the active look.
-- Functions run after the look changes, so frames that live outside the
-- configuration window (the loot frames) can restyle themselves in place.
local themeListeners = {}

function W.OnThemeChanged(fn)
    themeListeners[#themeListeners + 1] = fn
end

function W.ApplyTheme(name)
    local palette = W.themes[name] and name or "modern"
    wipe(W.colors)
    for k, v in pairs(W.themes[palette]) do
        W.colors[k] = v
    end
    local changed = W.style ~= palette
    W.style = palette
    if changed then
        for _, fn in ipairs(themeListeners) do
            pcall(fn)
        end
    end
end

function W.IsClassic()
    return W.style == "classic"
end

W.ApplyTheme("modern")

-- CreateFrame with a Blizzard template, or nil if this client lacks it.
function W.TryTemplate(frameType, parent, template, name)
    local ok, f = pcall(CreateFrame, frameType, name, parent, template)
    if ok and f then return f end
    return nil
end

function W.SetColor(texture, color)
    texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end

-- A texture filling the whole region.
function W.Fill(region, layer, color)
    local t = region:CreateTexture(nil, layer or "BACKGROUND")
    W.SetColor(t, color)
    t:SetAllPoints(region)
    return t
end

-- Lines on the four edges of a frame (1px, or `size`); returned so callers
-- can recolor them.
function W.Border(frame, color, size)
    color = color or W.colors.border
    size = size or 1
    local edges = {}
    local function Edge(a, b, horizontal)
        local t = frame:CreateTexture(nil, "BORDER")
        W.SetColor(t, color)
        t:SetPoint(a)
        t:SetPoint(b)
        if horizontal then t:SetHeight(size) else t:SetWidth(size) end
        edges[#edges + 1] = t
    end
    Edge("TOPLEFT", "TOPRIGHT", true)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT", "BOTTOMLEFT", false)
    Edge("TOPRIGHT", "BOTTOMRIGHT", false)
    return edges
end

function W.SetBorderColor(edges, color)
    for _, t in ipairs(edges) do
        W.SetColor(t, color)
    end
end

-- The game's tiled dark rock background (classic look).
function W.RockBackground(frame, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, -8)
    t:SetAllPoints(frame)
    local ok = pcall(t.SetTexture, t, "Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
    if ok and t:GetTexture() then
        if t.SetHorizTile then t:SetHorizTile(true) end
        if t.SetVertTile then t:SetVertTile(true) end
    else
        W.SetColor(t, W.colors.window)
    end
    return t
end

-- Background and rim for a standalone frame (loot window, roll panel) that
-- follows the look, now and whenever it changes:
--   modern:  a flat fill in `flatColor` (no rim; the frame draws its own)
--   classic: the game's rock background inside a 2px brown-gold rim
-- `onApply(classic)` runs after each restyle for the frame's own changes.
-- Returns the skin; skin.inset is the rim width in the current look.
function W.PanelSkin(frame, flatColor, onApply)
    local skin = {}
    skin.flat = W.Fill(frame, "BACKGROUND", flatColor)
    skin.rock = W.RockBackground(frame)
    skin.rim = W.Border(frame, W.themes.classic.border, 2)
    function skin:Apply()
        local classic = W.IsClassic()
        self.flat:SetShown(not classic)
        self.rock:SetShown(classic)
        for _, edge in ipairs(self.rim) do
            edge:SetShown(classic)
        end
        self.inset = classic and 2 or 0
        if onApply then pcall(onApply, classic) end
    end
    W.OnThemeChanged(function() skin:Apply() end)
    skin:Apply()
    return skin
end

-- A recessed panel: Blizzard's inset frame in classic, a flat card in modern.
function W.Inset(parent)
    if W.IsClassic() then
        local f = W.TryTemplate("Frame", parent, "InsetFrameTemplate")
        if f then return f end
        f = CreateFrame("Frame", nil, parent)
        W.Fill(f, "BACKGROUND", W.colors.sidebar)
        W.Border(f, W.colors.border)
        return f
    end
    local f = CreateFrame("Frame", nil, parent)
    W.Fill(f, "BACKGROUND", W.colors.card)
    W.Border(f)
    return f
end

-- A FontString. Given a width it wraps, and GetStringHeight is valid at once,
-- which the page layout relies on.
function W.Text(parent, font, color, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    if color then
        fs:SetTextColor(color[1], color[2], color[3])
    end
    if width then
        fs:SetWidth(width)
        fs:SetWordWrap(true)
    end
    return fs
end

-- The red panel button (classic). Uses the client's template, or its
-- textures when the template is missing. Returns nil if neither works.
local function ClassicButton(parent, text, width, height)
    local b = W.TryTemplate("Button", parent, "UIPanelButtonTemplate")
    if not b then
        b = CreateFrame("Button", nil, parent)
        local function Tex(setter, path)
            setter(b, path)
        end
        Tex(b.SetNormalTexture, "Interface\\Buttons\\UI-Panel-Button-Up")
        Tex(b.SetPushedTexture, "Interface\\Buttons\\UI-Panel-Button-Down")
        Tex(b.SetHighlightTexture, "Interface\\Buttons\\UI-Panel-Button-Highlight")
        for _, t in ipairs({ b:GetNormalTexture(), b:GetPushedTexture(), b:GetHighlightTexture() }) do
            t:SetTexCoord(0, 0.625, 0, 0.6875)
        end
        if b:GetHighlightTexture() then b:GetHighlightTexture():SetBlendMode("ADD") end
        b:SetNormalFontObject(GameFontNormalSmall)
        b:SetHighlightFontObject(GameFontHighlightSmall)
    end
    b:SetSize(width or 120, height or 24)
    b:SetText(text or "")
    b.label = b:GetFontString()
    function b:SetLabel(value)
        self:SetText(value or "")
    end
    return b
end

-- Push button: red panel button in classic, flat with an accent border on
-- hover in modern.
function W.Button(parent, text, width, height, onClick)
    if W.IsClassic() then
        local ok, b = pcall(ClassicButton, parent, text, width, height)
        if ok and b then
            if onClick then b:SetScript("OnClick", onClick) end
            return b
        end
    end
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 120, height or 24)
    b.bg = W.Fill(b, "BACKGROUND", W.colors.control)
    b.edges = W.Border(b, W.colors.border)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("CENTER")
    b.label:SetText(text or "")
    b:SetScript("OnEnter", function(self)
        W.SetColor(self.bg, W.colors.controlHover)
        W.SetBorderColor(self.edges, W.colors.accent)
    end)
    b:SetScript("OnLeave", function(self)
        W.SetColor(self.bg, W.colors.control)
        W.SetBorderColor(self.edges, W.colors.border)
    end)
    if onClick then
        b:SetScript("OnClick", onClick)
    end
    function b:SetLabel(value)
        self.label:SetText(value or "")
    end
    return b
end

-- The red close X of the game's windows (classic), or nil.
function W.CloseButton(parent, onClick)
    local b = W.TryTemplate("Button", parent, "UIPanelCloseButton")
    if not b then return nil end
    b:SetScript("OnClick", onClick)
    return b
end

-- On/off control. SetChecked only changes the look; clicks call onClick.
-- Classic: the game's checkbox. Modern: a sliding switch.
function W.Toggle(parent, onClick)
    local t = CreateFrame("Button", nil, parent)
    if W.IsClassic() then
        t:SetSize(26, 26)
        t:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        t:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        t:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
        t.check = t:CreateTexture(nil, "OVERLAY")
        t.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        t.check:SetAllPoints(t)
        function t:SetChecked(on)
            self.checked = on and true or false
            self.check:SetShown(self.checked)
        end
    else
        t:SetSize(34, 18)
        t.track = W.Fill(t, "ARTWORK", W.colors.track)
        t.knob = t:CreateTexture(nil, "OVERLAY")
        t.knob:SetSize(14, 14)
        W.SetColor(t.knob, W.colors.knob)
        function t:SetChecked(on)
            self.checked = on and true or false
            W.SetColor(self.track, self.checked and W.colors.accent or W.colors.track)
            self.knob:ClearAllPoints()
            if self.checked then
                self.knob:SetPoint("RIGHT", self, "RIGHT", -2, 0)
            else
                self.knob:SetPoint("LEFT", self, "LEFT", 2, 0)
            end
        end
    end

    function t:GetChecked()
        return self.checked
    end

    if onClick then
        t:SetScript("OnClick", onClick)
    end
    t:SetChecked(false)
    return t
end

-- Small square status light.
function W.Dot(parent, size)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetSize(size or 8, size or 8)
    W.SetColor(t, W.colors.off)
    return t
end
