-- Dhoxar Modules - shared helpers for modules.
--
-- This client can hand back protected "secret" values, so modules read
-- game state through these helpers instead of trusting raw API results.

local _, ns = ...

local Util = {}
ns.Util = Util

function Util.IsSecret(v)
    return type(issecretvalue) == "function" and issecretvalue(v) or false
end

-- pcall wrapper: returns the function's results, or nil if it is missing or errors.
function Util.SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e, f, g, h
end

-- The value if it is a plain, readable number; otherwise nil.
function Util.SafeNumber(v)
    if v == nil or Util.IsSecret(v) or type(v) ~= "number" then return nil end
    return v
end

function Util.ToSet(list)
    local set = {}
    for _, value in ipairs(list) do
        set[value] = true
    end
    return set
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------

-- Name, quality and icon of an item link; works before the item is cached
-- (quality is then nil and the name comes from the link).
function Util.ItemInfo(link)
    local name, quality, icon
    if C_Item and C_Item.GetItemInfo then
        local n, _, q, _, _, _, _, _, _, tex = Util.SafeCall(C_Item.GetItemInfo, link)
        name, quality, icon = n, q, tex
    end
    if not name and type(GetItemInfo) == "function" then
        local n, _, q, _, _, _, _, _, _, tex = Util.SafeCall(GetItemInfo, link)
        name, quality, icon = n, q, tex
    end
    if not icon then
        icon = Util.SafeCall(C_Item and C_Item.GetItemIconByID, link) or Util.SafeCall(GetItemIcon, link)
    end
    -- Not cached yet: the link itself still has the name and color.
    name = name or (type(link) == "string" and link:match("%[(.-)%]")) or "Unknown item"
    return name, quality, icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- r, g, b of an item quality, or of the link's own color when quality is nil.
function Util.ItemQualityColor(quality, link)
    if quality then
        if C_Item and C_Item.GetItemQualityColor then
            local r, g, b = Util.SafeCall(C_Item.GetItemQualityColor, quality)
            if r then return r, g, b end
        end
        local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        if c then return c.r, c.g, c.b end
    end
    local hex = type(link) == "string" and link:match("|c%x%x(%x%x%x%x%x%x)")
    if hex then
        return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
    end
    return 1, 1, 1
end

---------------------------------------------------------------------------
-- Copyable text window (for debug dumps)
---------------------------------------------------------------------------

local copyFrame

function Util.ShowCopyableText(title, text)
    if not copyFrame then
        local f = CreateFrame("Frame", "DhoxarModulesCopyFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(520, 420)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG") -- above the configuration window
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true,
                tileSize = 32,
                edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 },
            })
        else
            local bg = f:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(f)
            bg:SetColorTexture(0, 0, 0, 0.85)
        end

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.title:SetPoint("TOP", f, "TOP", 0, -16)

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
        closeBtn:SetScript("OnClick", function()
            f:Hide()
        end)

        local scrollFrame = CreateFrame("ScrollFrame", "DhoxarModulesCopyScroll", f, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -40)
        scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 16)

        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetFontObject(ChatFontNormal)
        editBox:SetWidth(scrollFrame:GetWidth())
        editBox:SetAutoFocus(false)
        editBox:SetScript("OnEscapePressed", function()
            f:Hide()
        end)
        scrollFrame:SetScrollChild(editBox)

        f.editBox = editBox
        copyFrame = f
    end

    copyFrame.title:SetText((title or ns.title) .. " -- Ctrl+A then Ctrl+C to copy, Esc to close")
    copyFrame.editBox:SetText(text or "")
    copyFrame.editBox:HighlightText()
    copyFrame.editBox:SetFocus()
    copyFrame:Show()
end

---------------------------------------------------------------------------
-- Reminder look, shared by every reminder and alert so they all match the
-- warrior's: a gold "marching ants" border (dashes with a lit window running
-- around them) while shown, and a blue outline with a name tag while the
-- user is dragging them.
---------------------------------------------------------------------------

-- Plain 4-edge border just outside the frame.
function Util.EdgeBorder(parent, outset, thickness, r, g, b, a)
    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", -outset, outset)
    box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", outset, -outset)
    local function Edge(p1, p2, horizontal)
        local t = box:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(r, g, b, a or 1)
        t:SetPoint(p1, box, p1)
        t:SetPoint(p2, box, p2)
        if horizontal then t:SetHeight(thickness) else t:SetWidth(thickness) end
    end
    Edge("TOPLEFT", "TOPRIGHT", true)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT", "BOTTOMLEFT", false)
    Edge("TOPRIGHT", "BOTTOMRIGHT", false)
    box:Hide()
    return box
end

-- Blue name tag above a frame, shown while it can be dragged.
function Util.LabelPanel(parent, text)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetHeight(18)
    panel:SetPoint("BOTTOM", parent, "TOP", 0, 6)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(panel)
    bg:SetColorTexture(0.08, 0.26, 0.5, 0.9)
    Util.EdgeBorder(panel, 0, 1, 0.4, 0.7, 1, 0.9):Show()
    panel.text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.text:SetPoint("CENTER", panel, "CENTER", 0, 0)
    panel.text:SetTextColor(1, 1, 1)
    function panel:SetLabel(label)
        self.text:SetText(label or "")
        self:SetWidth(self.text:GetStringWidth() + 16)
    end
    panel:SetLabel(text)
    panel:Hide()
    return panel
end

-- The warrior's marching-dash border, for a frame of any size: the dashes
-- are laid out again whenever the frame is resized. OnUpdate stops while
-- hidden, so it costs nothing when the reminder is not showing.
-- Defaults match the warrior icons: 4px outside, 4x2 dashes, 2px gaps, gold.
function Util.MarchingBorder(parent, opts)
    opts = opts or {}
    local outset, dashLen, dashThick, gap = opts.outset or 4, opts.dashLen or 4, opts.dashThick or 2, opts.gap or 2
    local r, g, b = opts.r or 1, opts.g or 0.82, opts.b or 0.1
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", -outset, outset)
    container:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", outset, -outset)
    container:Hide()

    local dashes, n, builtW, builtH = {}, 0, 0, 0
    local phase, sinceStep = 0, 0
    local STEP_INTERVAL = 0.05

    local function ApplyPhase()
        local lit = math.max(1, math.floor(n / 3))
        for i = 1, n do
            dashes[i]:SetAlpha(((i - 1 - phase) % n) < lit and 1 or 0.15)
        end
    end

    local function Build()
        local w = math.floor(parent:GetWidth() + 0.5) + 2 * outset
        local h = math.floor(parent:GetHeight() + 0.5) + 2 * outset
        if w <= 2 * outset or h <= 2 * outset or (w == builtW and h == builtH) then return end
        builtW, builtH = w, h
        local perimeter = 2 * (w + h)
        local count = math.max(8, math.floor(perimeter / (dashLen + gap)))
        for i = count + 1, #dashes do dashes[i]:Hide() end
        for i = 1, count do
            local tex = dashes[i]
            if not tex then
                tex = container:CreateTexture(nil, "OVERLAY")
                tex:SetColorTexture(r, g, b, 1)
                dashes[i] = tex
            end
            tex:ClearAllPoints()
            local dist = ((i - 1) * perimeter / count) % perimeter
            if dist < w then -- top edge, left to right
                tex:SetSize(dashLen, dashThick)
                tex:SetPoint("TOPLEFT", container, "TOPLEFT", math.min(dist, w - dashLen), 0)
            elseif dist < w + h then -- right edge, top to bottom
                tex:SetSize(dashThick, dashLen)
                tex:SetPoint("TOPLEFT", container, "TOPLEFT", w - dashThick, -math.min(dist - w, h - dashLen))
            elseif dist < 2 * w + h then -- bottom edge, right to left
                local t = dist - w - h
                tex:SetSize(dashLen, dashThick)
                tex:SetPoint("TOPLEFT", container, "TOPLEFT", math.max(0, w - t - dashLen), -(h - dashThick))
            else -- left edge, bottom to top
                local t = dist - 2 * w - h
                tex:SetSize(dashThick, dashLen)
                tex:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -math.max(0, h - t - dashLen))
            end
            tex:Show()
        end
        n = count
        phase = phase % n
        ApplyPhase()
    end

    container:SetScript("OnShow", Build)
    container:SetScript("OnSizeChanged", Build)
    container:SetScript("OnUpdate", function(_, delta)
        sinceStep = sinceStep + delta
        if sinceStep >= STEP_INTERVAL and n > 0 then
            sinceStep = 0
            phase = (phase + 1) % n
            ApplyPhase()
        end
    end)
    return container
end
