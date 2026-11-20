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
