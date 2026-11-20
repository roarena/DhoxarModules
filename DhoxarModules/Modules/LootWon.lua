-- Module: Loot Won
--
-- Replaces Blizzard's "you won" loot alert with a window of our own when the
-- player wins a roll: the item's icon, its name in its rarity color, and the
-- roll (e.g. "Need roll: 87"). The window can be dragged anywhere, resized
-- from its bottom-right corner, and hides itself after a few seconds.
--
-- Wins come from two places, whichever the client provides:
--   * the LOOT_ITEM_ROLL_WON event (modern clients; it carries the roll), and
--   * the loot chat messages: "You won: [item]" plus the "Need Roll - 87 for
--     [item] by <you>" line before it, which is where the roll comes from.
-- The patterns are built from Blizzard's own global strings, so they work in
-- every client language. The Forever client puts a "[Loot]" link in front of
-- these messages; extra leading tokens are skipped (see Match).

local _, ns = ...

local IsSecret = ns.Util.IsSecret
local SafeCall = ns.Util.SafeCall
local ItemInfo = ns.Util.ItemInfo
local QualityColor = ns.Util.ItemQualityColor
local W = ns.Widgets

local M = ns:RegisterModule({
    key = "LootWon",
    title = "Loot Won",
    description = "Replaces the loot winner alert with a window you can move and resize: the item in its rarity color and your roll.",
    aliases = { "loot", "lootwon", "won" },
    defaults = { duration = 8, sticky = false, hideBlizzard = true, position = {}, width = 300, height = 64 },
})

local TAG = "|cffc8aa88Loot Won|r: "
local DEFAULT_POSITION = { "TOP", "TOP", 0, -180 }
local MIN_W, MIN_H, MAX_W, MAX_H = 180, 40, 700, 180
local FADE_TIME = 0.6
-- A win reported by both the event and the chat is shown once.
local DUPLICATE_WINDOW = 3

local ROLL_LABELS = {
    need = NEED or "Need",
    greed = GREED or "Greed",
    disenchant = ROLL_DISENCHANT or "Disenchant",
}
-- rollType numbers used by LOOT_ITEM_ROLL_WON.
local ROLL_TYPES = { [1] = "need", [2] = "greed", [3] = "disenchant" }

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local frame
local queue = {}
local current -- the win on screen: { link, roll, kind, test }

local function ApplyGeometry()
    local db = M.db
    frame:SetSize(
        math.min(MAX_W, math.max(MIN_W, tonumber(db.width) or 300)),
        math.min(MAX_H, math.max(MIN_H, tonumber(db.height) or 64)))
    frame:ClearAllPoints()
    local saved = db.position
    if type(saved) == "table" and saved.point then
        frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    else
        local d = DEFAULT_POSITION
        frame:SetPoint(d[1], UIParent, d[2], d[3], d[4])
    end
end

local function SavePosition()
    local p, _, rp, x, y = frame:GetPoint()
    M.db.position = { point = p, relativePoint = rp, x = x, y = y }
end

-- Scales the icon and fonts with the window's height.
local function Layout()
    local w, h = frame:GetSize()
    -- Classic has a 2px rim; keep the content inside it.
    local pad = math.max(4, math.floor(h * 0.1)) + (frame.skin and frame.skin.inset or 0)
    local iconSize = h - pad * 2
    frame.icon:SetSize(iconSize, iconSize)
    frame.icon:SetPoint("LEFT", frame, "LEFT", pad, 0)

    local font = (GameFontNormal and GameFontNormal:GetFont()) or STANDARD_TEXT_FONT
    local nameSize = math.max(10, math.floor(h * 0.24))
    local smallSize = math.max(8, math.floor(h * 0.17))
    frame.title:SetFont(font, smallSize, "OUTLINE")
    frame.name:SetFont(font, nameSize, "OUTLINE")
    frame.roll:SetFont(font, smallSize, "OUTLINE")

    local left = pad * 2 + iconSize
    local textW = math.max(20, w - left - pad)
    for _, fs in ipairs({ frame.title, frame.name, frame.roll }) do
        fs:SetWidth(textW)
    end
    frame.name:ClearAllPoints()
    frame.name:SetPoint("LEFT", frame, "LEFT", left, 0)
    frame.title:ClearAllPoints()
    frame.title:SetPoint("BOTTOMLEFT", frame.name, "TOPLEFT", 0, 2)
    frame.roll:ClearAllPoints()
    frame.roll:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -2)
end

local function SetBorderColor(r, g, b)
    for _, edge in ipairs(frame.edges) do
        edge:SetColorTexture(r, g, b, 1)
    end
    frame.glow:SetColorTexture(r, g, b, 0.12)
    frame.iconBorder:SetColorTexture(r, g, b, 1)
end

local ShowNext

local function Render()
    local win = current
    local name, quality, icon = ItemInfo(win.link)
    local r, g, b = QualityColor(quality, win.link)
    frame.icon:SetTexture(icon)
    frame.name:SetText(name)
    frame.name:SetTextColor(r, g, b)
    SetBorderColor(r, g, b)
    frame.title:SetText(win.test and "You won (test)" or "You won")
    if win.roll then
        local label = ROLL_LABELS[win.kind]
        frame.roll:SetText(label and ("%s roll: |cffffffff%d|r"):format(label, win.roll) or ("Roll: |cffffffff%d|r"):format(win.roll))
    else
        frame.roll:SetText("")
    end
    -- Item not cached yet: try again shortly so the real name, color and
    -- icon replace the placeholders.
    if not quality and (win.retries or 0) < 5 then
        win.retries = (win.retries or 0) + 1
        C_Timer.After(0.5, function()
            if current == win and frame:IsShown() then Render() end
        end)
    end
end

local function HideWindow()
    if not frame then return end
    frame:Hide()
    current = nil
    ShowNext()
end

function ShowNext()
    if current or #queue == 0 or not frame then return end
    current = table.remove(queue, 1)
    frame.hideAt = (not current.test and not M.db.sticky) and (GetTime() + (tonumber(M.db.duration) or 8)) or nil
    frame:SetAlpha(1)
    frame.grip:SetShown(current.test == true)
    Render()
    frame:Show()
end

local function CreateWindow()
    frame = CreateFrame("Button", "DhoxarModulesLootWon", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    else
        if frame.SetMinResize then frame:SetMinResize(MIN_W, MIN_H) end
        if frame.SetMaxResize then frame:SetMaxResize(MAX_W, MAX_H) end
    end
    frame:RegisterForDrag("LeftButton")
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:Hide()

    frame.glow = frame:CreateTexture(nil, "BORDER")
    frame.glow:SetAllPoints(frame)

    -- 1px border in the item's rarity color; anchored by the skin, inside
    -- the classic rim.
    frame.edges = {}
    for i = 1, 4 do
        frame.edges[i] = frame:CreateTexture(nil, "ARTWORK")
    end

    frame.icon = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    -- Classic: a rarity-colored frame around the icon, like bag slots.
    frame.iconBorder = frame:CreateTexture(nil, "ARTWORK", nil, 0)
    frame.iconBorder:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", -2, 2)
    frame.iconBorder:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", 2, -2)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetJustifyH("LEFT")
    frame.title:SetTextColor(1, 0.82, 0)
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.name:SetJustifyH("LEFT")
    frame.name:SetWordWrap(false)
    frame.roll = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.roll:SetJustifyH("LEFT")

    -- Modern: dark flat fill, rarity border on the edge. Classic: the game's
    -- rock background in a brown-gold rim, rarity border just inside it, and
    -- a rarity frame around the icon.
    frame.skin = W.PanelSkin(frame, { 0.05, 0.05, 0.06, 0.9 }, function(classic)
        local inset = classic and 2 or 0
        local e = frame.edges
        for _, t in ipairs(e) do t:ClearAllPoints() end
        e[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        e[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
        e[1]:SetHeight(1)
        e[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
        e[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
        e[2]:SetHeight(1)
        e[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        e[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
        e[3]:SetWidth(1)
        e[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
        e[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
        e[4]:SetWidth(1)
        frame.iconBorder:SetShown(classic)
        if classic then
            frame.roll:SetTextColor(0.74, 0.68, 0.57)
        else
            frame.roll:SetTextColor(0.75, 0.75, 0.75)
        end
        if frame.icon:GetWidth() > 0 then Layout() end
    end)

    -- Resize grip in the bottom-right corner; shown on hover and in the test.
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        M.db.width, M.db.height = math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5)
        SavePosition()
    end)
    grip:Hide()
    frame.grip = grip

    frame:SetScript("OnSizeChanged", Layout)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    frame:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            HideWindow()
        elseif current and (IsShiftKeyDown() or IsControlKeyDown()) and HandleModifiedItemClick then
            HandleModifiedItemClick(current.link)
        end
    end)
    frame:SetScript("OnEnter", function(self)
        self.hovered = true
        self:SetAlpha(1)
        grip:Show()
        if current then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            pcall(GameTooltip.SetHyperlink, GameTooltip, current.link)
            GameTooltip:AddLine("Drag to move, drag the corner to resize. Right-click to close.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function(self)
        self.hovered = false
        if not (current and current.test) and not grip:IsMouseOver() then grip:Hide() end
        GameTooltip:Hide()
    end)
    -- Auto-hide, paused while hovered, with a short fade at the end.
    frame:SetScript("OnUpdate", function(self)
        if not self.hideAt or self.hovered then return end
        local left = self.hideAt - GetTime()
        if left <= 0 then
            HideWindow()
        elseif left < FADE_TIME then
            self:SetAlpha(left / FADE_TIME)
        end
    end)

    ApplyGeometry()
    Layout()
end

local function ShowWin(link, roll, kind, test)
    if type(link) ~= "string" or IsSecret(link) then return end
    if not frame then CreateWindow() end
    if not test then
        local now = GetTime()
        M.recent = M.recent or {}
        if M.recent[link] and now - M.recent[link] < DUPLICATE_WINDOW then return end
        M.recent[link] = now
    end
    queue[#queue + 1] = { link = link, roll = roll, kind = kind, test = test }
    ShowNext()
end

---------------------------------------------------------------------------
-- Chat parsing
---------------------------------------------------------------------------

-- Turns a global format string into a Lua pattern and the order of its tokens.
local function Compile(fmt)
    local tokens = {}
    local s = fmt:gsub("%%(%d*)%$?([sd])", function(n, t)
        tokens[#tokens + 1] = { pos = tonumber(n) or (#tokens + 1), t = t }
        return "\1"
    end)
    s = s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    local i = 0
    s = s:gsub("\1", function()
        i = i + 1
        return tokens[i].t == "d" and "(%d+)" or "(.+)"
    end)
    return "^" .. s .. "$", tokens
end

local DEFS = {}
local function Def(global, kind, fields, roll)
    local fmt = _G[global]
    if type(fmt) ~= "string" then return end
    local pat, tokens = Compile(fmt)
    DEFS[#DEFS + 1] = { pat = pat, tokens = tokens, kind = kind, fields = fields, roll = roll }
end

Def("LOOT_ROLL_YOU_WON", "won", { "item" })
Def("LOOT_ROLL_ROLLED_NEED", "rolled", { "roll", "item", "player" }, "need")
Def("LOOT_ROLL_ROLLED_NEED_ROLE_BONUS", "rolled", { "roll", "item", "player" }, "need")
Def("LOOT_ROLL_ROLLED_GREED", "rolled", { "roll", "item", "player" }, "greed")
Def("LOOT_ROLL_ROLLED_DE", "rolled", { "roll", "item", "player" }, "disenchant")

-- Captures by field name. Tokens in front of the documented ones (the
-- Forever client's "[Loot]" link) are skipped.
local function Match(msg, def)
    local caps = { msg:match(def.pat) }
    if #caps == 0 then return nil end
    local skip = math.max(0, #def.tokens - #def.fields)
    local out = {}
    for i, tk in ipairs(def.tokens) do
        local field = def.fields[tk.pos - skip]
        if field then out[field] = caps[i] end
    end
    return out
end

local function IsMe(player)
    if not player then return false end
    if player == YOU or player == "You" then return true end
    local me = UnitName("player")
    return me ~= nil and (player == me or player:match("^([^%-]+)") == me)
end

-- Our latest roll per item link, from the "Need Roll - 87 for ..." lines.
local myRolls = {}

local function OnLootMessage(msg)
    if type(msg) ~= "string" or IsSecret(msg) then return end
    for _, def in ipairs(DEFS) do
        local f = Match(msg, def)
        if f and f.item then
            if def.kind == "rolled" then
                if IsMe(f.player) then
                    myRolls[f.item] = { roll = tonumber(f.roll), kind = def.roll, at = GetTime() }
                end
            else
                local mine = myRolls[f.item]
                myRolls[f.item] = nil
                if mine and GetTime() - mine.at < 600 then
                    ShowWin(f.item, mine.roll, mine.kind)
                else
                    ShowWin(f.item)
                end
            end
            return
        end
    end
end

---------------------------------------------------------------------------
-- Blizzard's alert
---------------------------------------------------------------------------

local blizzardMuted = false

local function MuteBlizzard(mute)
    if not AlertFrame then return end
    if mute and not blizzardMuted then
        local ok, registered = pcall(AlertFrame.IsEventRegistered, AlertFrame, "LOOT_ITEM_ROLL_WON")
        if ok and registered then
            pcall(AlertFrame.UnregisterEvent, AlertFrame, "LOOT_ITEM_ROLL_WON")
            blizzardMuted = true
        end
    elseif not mute and blizzardMuted then
        pcall(AlertFrame.RegisterEvent, AlertFrame, "LOOT_ITEM_ROLL_WON")
        blizzardMuted = false
    end
end

---------------------------------------------------------------------------
-- Module interface
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if not M.active then return end
    if event == "CHAT_MSG_LOOT" then
        OnLootMessage((...))
    elseif event == "LOOT_ITEM_ROLL_WON" then
        local link, _, rollType, roll = ...
        if IsSecret(rollType) then rollType = nil end
        if IsSecret(roll) then roll = nil end
        ShowWin(link, tonumber(roll), ROLL_TYPES[rollType])
    end
end)

function M:OnEnable()
    pcall(events.RegisterEvent, events, "CHAT_MSG_LOOT")
    pcall(events.RegisterEvent, events, "LOOT_ITEM_ROLL_WON")
    MuteBlizzard(M.db.hideBlizzard ~= false)
end

function M:OnDisable()
    events:UnregisterAllEvents()
    MuteBlizzard(false)
    wipe(queue)
    if frame then frame:Hide() end
    current = nil
end

-- One of the player's equipped items, so the test shows something real.
local function SampleLink()
    for _, slot in ipairs({ 16, 5, 1, 7, 17, 18 }) do
        local link = SafeCall(GetInventoryItemLink, "player", slot)
        if type(link) == "string" and not IsSecret(link) then return link end
    end
    local _, link = SafeCall(GetItemInfo, 6948) -- Hearthstone
    return link or "|cffffffff|Hitem:6948::::::::1:::::|h[Hearthstone]|h|r"
end

local function IsTestShown()
    return frame and frame:IsShown() and current and current.test
end

function M:BuildOptions(page)
    page:Header("Window")
    page:Text("Drag the window to move it and drag its bottom-right corner to resize it; the icon and text grow with it. Right-click closes it, Shift-click links the item in chat, and hovering shows the item and keeps it open.")
    page:Button({
        label = "Test window",
        description = "Shows the window with one of your items so you can place and size it. It stays open until you right-click it or click Hide.",
        text = function() return IsTestShown() and "Hide" or "Test" end,
        onClick = function()
            if not M.active then
                print(TAG .. "the module is not running. Type /dhoxar list.")
                return
            end
            if IsTestShown() then
                HideWindow()
            else
                ShowWin(SampleLink(), math.random(1, 100), "need", true)
            end
        end,
    })
    page:Slider({
        label = "Shown for",
        description = "How long the window stays after a win. Hovering it pauses the timer.",
        min = 3, max = 60, step = 1,
        get = function() return tonumber(M.db.duration) or 8 end,
        set = function(value) M.db.duration = value end,
        format = function(value) return value .. " s" end,
    })
    page:Checkbox({
        label = "Keep open until closed",
        description = "The window stays until you right-click it.",
        get = function() return M.db.sticky end,
        set = function(value) M.db.sticky = value and true or false end,
    })
    page:Button({
        label = "Reset position and size",
        description = "Moves the window back to the top of the screen at its default size.",
        text = "Reset",
        onClick = function()
            M.db.position, M.db.width, M.db.height = {}, 300, 64
            if frame then ApplyGeometry() Layout() end
        end,
    })

    page:Header("Blizzard alert")
    page:Checkbox({
        label = "Hide Blizzard's \"you won\" alert",
        description = "Only this window is shown when you win a roll.",
        get = function() return M.db.hideBlizzard ~= false end,
        set = function(value)
            M.db.hideBlizzard = value and true or false
            if M.active then MuteBlizzard(M.db.hideBlizzard) end
        end,
    })
end
