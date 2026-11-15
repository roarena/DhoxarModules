-- Module: FPS & Latency
--
-- A small text on the screen with the frame rate and the latency, e.g.
-- "60 fps  45 ms". The latency turns orange when the game starts lagging and
-- shifts towards red the higher it gets. The text can be dragged after
-- Unlock on the module's page.
--
-- Latency is the higher of the home and world values from GetNetStats; the
-- client only refreshes them every few seconds.

local _, ns = ...

local SafeCall = ns.Util.SafeCall
local SafeNumber = ns.Util.SafeNumber

local M = ns:RegisterModule({
    key = "Performance",
    title = "FPS & Latency",
    description = "Shows your frame rate and latency on the screen. The latency turns orange, then red, as the game lags.",
    aliases = { "fps", "latency", "ms" },
    defaults = { showFPS = true, showLatency = true, fontSize = 14, position = {}, lagStart = 150, lagMax = 400 },
})

local TAG = "|cffc8aa88FPS & Latency|r: "
local UPDATE_INTERVAL = 0.5
local FONT_SIZES = { 10, 12, 14, 16, 18, 22 }
local DEFAULT_POSITION = { "TOP", "TOP", 0, -8 }

-- Latency colors: normal below lagStart ms, orange at lagStart, blending to
-- red at lagMax ms and above. Both are set on the module's page.
local LAG_MIN_SETTING, LAG_MAX_SETTING, LAG_STEP = 50, 1000, 10
local NORMAL = { 1, 1, 1 }
local ORANGE = { 1, 0.6, 0.1 }
local RED = { 1, 0.15, 0.15 }

local function Thresholds()
    local start = tonumber(M.db.lagStart) or 150
    local max = tonumber(M.db.lagMax) or 400
    if max <= start then max = start + LAG_STEP end
    return start, max
end

local function LatencyColor(ms)
    local start, max = Thresholds()
    if ms < start then return NORMAL end
    local t = math.min(1, (ms - start) / (max - start))
    return {
        ORANGE[1] + (RED[1] - ORANGE[1]) * t,
        ORANGE[2] + (RED[2] - ORANGE[2]) * t,
        ORANGE[3] + (RED[3] - ORANGE[3]) * t,
    }
end

local function ToHex(c)
    return ("ff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

local function ReadLatency()
    local _, _, home, world = SafeCall(GetNetStats)
    home, world = SafeNumber(home), SafeNumber(world)
    if not home and not world then return nil end
    return math.max(home or 0, world or 0)
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

local frame, text
local unlocked = false

local function ApplyPosition()
    local saved = M.db.position
    frame:ClearAllPoints()
    if type(saved) == "table" and saved.point then
        frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    else
        local d = DEFAULT_POSITION
        frame:SetPoint(d[1], UIParent, d[2], d[3], d[4])
    end
end

local function ApplyFont()
    local file = (GameFontHighlight and GameFontHighlight:GetFont()) or STANDARD_TEXT_FONT
    text:SetFont(file, M.db.fontSize or 14, "OUTLINE")
end

local function Update()
    if not frame then return end
    local parts = {}
    if M.db.showFPS then
        local fps = SafeNumber(SafeCall(GetFramerate))
        parts[#parts + 1] = fps and ("%d fps"):format(math.floor(fps + 0.5)) or "-- fps"
    end
    if M.db.showLatency then
        local ms = ReadLatency()
        if ms then
            parts[#parts + 1] = ("|c%s%d ms|r"):format(ToHex(LatencyColor(ms)), ms)
        else
            parts[#parts + 1] = "-- ms"
        end
    end
    if #parts == 0 then
        parts[1] = unlocked and "FPS & Latency" or ""
    end
    text:SetText(table.concat(parts, "  "))
    frame:SetSize(math.max(text:GetStringWidth() + 12, 40), text:GetStringHeight() + 8)
end

local function CreateDisplay()
    frame = CreateFrame("Frame", "DhoxarModulesPerformance", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()

    -- Only shown while unlocked, to show what can be dragged.
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints(frame)
    frame.bg:SetColorTexture(0.08, 0.26, 0.5, 0.6)
    frame.bg:Hide()

    text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetTextColor(NORMAL[1], NORMAL[2], NORMAL[3])

    frame:SetScript("OnDragStart", function(self)
        if unlocked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        M.db.position = { point = p, relativePoint = rp, x = x, y = y }
    end)

    local elapsed = UPDATE_INTERVAL
    frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= UPDATE_INTERVAL then
            elapsed = 0
            Update()
        end
    end)

    ApplyFont()
    ApplyPosition()
end

local function SetUnlocked(value)
    unlocked = value and true or false
    if not frame then return end
    frame:EnableMouse(unlocked)
    frame.bg:SetShown(unlocked)
    Update()
end

---------------------------------------------------------------------------
-- Module interface
---------------------------------------------------------------------------

function M:OnEnable()
    if not frame then CreateDisplay() end
    ApplyFont()
    ApplyPosition()
    frame:Show()
    Update()
end

function M:OnDisable()
    SetUnlocked(false)
    if frame then frame:Hide() end
end

local function Refresh()
    if frame then
        ApplyFont()
        Update()
    end
end

function M:BuildOptions(page)
    page:Header("Display")
    page:Checkbox({
        label = "Show FPS",
        description = "Frames per second.",
        get = function() return M.db.showFPS end,
        set = function(value) M.db.showFPS = value and true or false; Refresh() end,
    })
    page:Checkbox({
        label = "Show latency",
        description = "Milliseconds to the server, colored by the thresholds below.",
        get = function() return M.db.showLatency end,
        set = function(value) M.db.showLatency = value and true or false; Refresh() end,
    })
    page:Button({
        label = "Text size",
        description = "Click to cycle through sizes.",
        text = function() return ("%d"):format(M.db.fontSize or 14) end,
        onClick = function()
            local nextSize = FONT_SIZES[1]
            for i, size in ipairs(FONT_SIZES) do
                if size == M.db.fontSize then nextSize = FONT_SIZES[i + 1] or FONT_SIZES[1] break end
            end
            M.db.fontSize = nextSize
            Refresh()
        end,
    })

    page:Header("Latency colors")
    page:Slider({
        label = "Orange from",
        description = "Below this the latency is white. At this value it turns orange.",
        min = LAG_MIN_SETTING, max = LAG_MAX_SETTING - LAG_STEP, step = LAG_STEP,
        get = function() return (Thresholds()) end,
        set = function(value)
            M.db.lagStart = value
            -- Keep red above orange.
            if (tonumber(M.db.lagMax) or 0) <= value then M.db.lagMax = value + LAG_STEP end
            Refresh()
        end,
        format = function(value) return value .. " ms" end,
    })
    page:Slider({
        label = "Red at",
        description = "Between the two values the color shifts from orange to red; from this value on it is fully red.",
        min = LAG_MIN_SETTING + LAG_STEP, max = LAG_MAX_SETTING, step = LAG_STEP,
        get = function() return select(2, Thresholds()) end,
        set = function(value)
            M.db.lagMax = value
            -- Keep orange below red.
            if (tonumber(M.db.lagStart) or 0) >= value then M.db.lagStart = value - LAG_STEP end
            Refresh()
        end,
        format = function(value) return value .. " ms" end,
    })
    page:Button({
        label = "Default colors",
        description = "Orange from 150 ms, red at 400 ms.",
        text = "Reset",
        onClick = function()
            M.db.lagStart, M.db.lagMax = 150, 400
            Refresh()
        end,
    })

    page:Header("Position")
    page:Button({
        label = "Move the text",
        description = "Unlocks the text so you can drag it. This window closes so it is not in the way; type /dhoxar and click Lock when done.",
        text = function() return unlocked and "Lock" or "Unlock" end,
        onClick = function()
            if unlocked then
                SetUnlocked(false)
                print(TAG .. "locked.")
            elseif not M.active then
                print(TAG .. "the module is not running. Type /dhoxar list.")
            else
                SetUnlocked(true)
                ns.Options:Close()
                print(TAG .. "unlocked, drag the text to move it. Type /dhoxar and click Lock when done.")
            end
        end,
    })
    page:Button({
        label = "Reset position",
        description = "Moves the text back to the top of the screen.",
        text = "Reset",
        onClick = function()
            M.db.position = {}
            if frame then ApplyPosition() end
        end,
    })
end
