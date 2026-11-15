-- Dhoxar Modules - UI widgets
--
-- Small styled building blocks for the configuration window
-- (Core/Options.lua). Everything is drawn with flat color textures and stock
-- font objects, so it needs no templates or art a given client may lack.

local _, ns = ...

local W = {}
ns.Widgets = W

W.LOGO = "Interface\\AddOns\\DhoxarModules\\Media\\logo"

W.colors = {
    window       = { 0.055, 0.060, 0.075, 0.97 },
    header       = { 0.080, 0.088, 0.110, 1 },
    sidebar      = { 0.068, 0.074, 0.094, 1 },
    card         = { 0.098, 0.106, 0.132, 1 },
    control      = { 0.130, 0.140, 0.172, 1 },
    controlHover = { 0.170, 0.182, 0.222, 1 },
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
    text         = { 0.920, 0.925, 0.940, 1 },
    muted        = { 0.600, 0.620, 0.670, 1 },
    good         = { 0.35, 0.85, 0.40, 1 },
    warn         = { 1.00, 0.78, 0.25, 1 },
    off          = { 0.45, 0.46, 0.50, 1 },
}

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

-- 1px lines on the four edges of a frame; returned so callers can recolor them.
function W.Border(frame, color)
    color = color or W.colors.border
    local edges = {}
    local function Edge(a, b, horizontal)
        local t = frame:CreateTexture(nil, "BORDER")
        W.SetColor(t, color)
        t:SetPoint(a)
        t:SetPoint(b)
        if horizontal then t:SetHeight(1) else t:SetWidth(1) end
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

-- Flat push button with an accent border on hover.
function W.Button(parent, text, width, height, onClick)
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

-- On/off switch. SetChecked only changes the look; clicks call onClick.
function W.Toggle(parent, onClick)
    local t = CreateFrame("Button", nil, parent)
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
