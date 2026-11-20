-- Module: Loot Rolls
--
-- Replaces Blizzard's group loot roll frames (one frame per item) with a
-- single panel that lists every open roll. Each row has the item's icon,
-- its name in its rarity color, a bind-on-pickup tag, the time left, and
-- Need / Greed / Pass buttons (plus Disenchant when the client offers it).
-- The panel can be dragged anywhere and resized from its bottom-right
-- corner: the width is free, the height sets the row height.
--
-- Rolls arrive with START_LOOT_ROLL and leave with CANCEL_LOOT_ROLL. The
-- choice goes to RollOnLoot; bind-on-pickup confirmations are still asked by
-- Blizzard's own pop-up (UIParent handles CONFIRM_LOOT_ROLL).

local _, ns = ...

local IsSecret = ns.Util.IsSecret
local SafeCall = ns.Util.SafeCall
local ItemInfo = ns.Util.ItemInfo
local QualityColor = ns.Util.ItemQualityColor

local M = ns:RegisterModule({
    key = "LootRolls",
    title = "Loot Rolls",
    description = "Replaces the loot roll frames with one panel listing every open roll, with Need, Greed and Pass on each.",
    aliases = { "rolls", "roll", "lootrolls" },
    defaults = { hideBlizzard = true, position = {}, width = 360, rowHeight = 44 },
})

local TAG = "|cffc8aa88Loot Rolls|r: "
local DEFAULT_POSITION = { "TOP", "TOP", 0, -240 }
local HEADER_H = 22
local PAD = 4
local MIN_W, MAX_W = 240, 800
local MIN_ROW, MAX_ROW = 28, 90
local TEST_TIME = 60

-- rollType values for RollOnLoot. (Named ROLL_* so Blizzard's NEED, GREED
-- and PASS strings stay usable as labels.)
local ROLL_PASS, ROLL_NEED, ROLL_GREED, ROLL_DE = 0, 1, 2, 3
local CHOICES = {
    { type = ROLL_NEED, label = NEED or "Need", tex = "Interface\\Buttons\\UI-GroupLoot-Dice-Up" },
    { type = ROLL_GREED, label = GREED or "Greed", tex = "Interface\\Buttons\\UI-GroupLoot-Coin-Up" },
    { type = ROLL_DE, label = ROLL_DISENCHANT or "Disenchant", tex = "Interface\\Buttons\\UI-GroupLoot-DE-Up" },
    { type = ROLL_PASS, label = PASS or "Pass", tex = "Interface\\Buttons\\UI-GroupLoot-Pass-Up" },
}
local CHOICE_LABEL = {}
for _, c in ipairs(CHOICES) do CHOICE_LABEL[c.type] = c.label end

---------------------------------------------------------------------------
-- Roll data
---------------------------------------------------------------------------

local rolls = {}   -- open rolls in arrival order: { id, link, name, icon, quality, count, bop, can = {}, reason = {}, endsAt, duration, chosen, test }
local testShown = false

local function FindRoll(id)
    for i, r in ipairs(rolls) do
        if r.id == id then return r, i end
    end
end

local function ReasonText(reason)
    if not reason or reason == 0 or IsSecret(reason) then return nil end
    return _G["LOOT_ROLL_INELIGIBLE_REASON" .. reason]
end

-- Reads a real roll from the client. Returns nil if the roll is gone.
local function ReadRoll(id, rollTime)
    local texture, name, count, quality, bop, canNeed, canGreed, canDE, reasonNeed, reasonGreed, reasonDE = SafeCall(GetLootRollItemInfo, id)
    if not name or IsSecret(name) then return nil end
    local link = SafeCall(GetLootRollItemLink, id)
    if IsSecret(link) then link = nil end
    local left = tonumber(SafeCall(GetLootRollTimeLeft, id))
    local duration = tonumber(rollTime) or left or 60000
    return {
        id = id, link = link, name = name, icon = texture, quality = quality, count = count, bop = bop and true or false,
        can = { [ROLL_NEED] = canNeed and true or false, [ROLL_GREED] = canGreed and true or false, [ROLL_DE] = canDE and true or false, [ROLL_PASS] = true },
        reason = { [ROLL_NEED] = ReasonText(reasonNeed), [ROLL_GREED] = ReasonText(reasonGreed), [ROLL_DE] = ReasonText(reasonDE) },
        showDE = canDE and true or false,
        endsAt = GetTime() + (left or duration) / 1000,
        duration = duration / 1000,
    }
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

local panel
local rowPool, rowFrames = {}, {}
local Refresh

local function RowHeight()
    return math.min(MAX_ROW, math.max(MIN_ROW, tonumber(M.db.rowHeight) or 44))
end

local function PanelWidth()
    return math.min(MAX_W, math.max(MIN_W, tonumber(M.db.width) or 360))
end

local function SavePosition()
    local p, _, rp, x, y = panel:GetPoint()
    M.db.position = { point = p, relativePoint = rp, x = x, y = y }
end

local function ApplyPosition()
    panel:ClearAllPoints()
    local saved = M.db.position
    if type(saved) == "table" and saved.point then
        panel:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    else
        local d = DEFAULT_POSITION
        panel:SetPoint(d[1], UIParent, d[2], d[3], d[4])
    end
end

local function Font()
    return (GameFontNormal and GameFontNormal:GetFont()) or STANDARD_TEXT_FONT
end

local function Choose(row, choice)
    local r = row.roll
    if not r or r.chosen ~= nil then return end
    if r.test then
        r.chosen = choice
        C_Timer.After(1.5, function()
            local _, i = FindRoll(r.id)
            if i then table.remove(rolls, i) Refresh() end
        end)
        Refresh()
        return
    end
    local ok = pcall(RollOnLoot, r.id, choice)
    if not ok then
        print(TAG .. "could not roll on " .. (r.link or r.name) .. ".")
        return
    end
    -- Bind-on-pickup: the choice only counts once Blizzard's pop-up is
    -- confirmed, and CANCEL_LOOT_ROLL removes the row then. Until that the
    -- buttons stay, in case the pop-up is declined.
    if not r.bop then
        r.chosen = choice
        Refresh()
    end
end

local function ButtonTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self.label)
    if self.reason then GameTooltip:AddLine(self.reason, 1, 0.3, 0.3, true) end
    GameTooltip:Show()
end

local function ItemTooltip(self)
    local r = self:GetParent().roll
    if not r then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not r.test and type(GameTooltip.SetLootRollItem) == "function" then
        pcall(GameTooltip.SetLootRollItem, GameTooltip, r.id)
    elseif r.link then
        pcall(GameTooltip.SetHyperlink, GameTooltip, r.link)
    end
    GameTooltip:Show()
end

local function ForwardDrag(child)
    child:RegisterForDrag("LeftButton")
    child:SetScript("OnDragStart", function() panel:StartMoving() end)
    child:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
        SavePosition()
    end)
end

local function NewRow()
    local row = CreateFrame("Frame", nil, panel)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetColorTexture(1, 1, 1, 0.04)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.iconBorder = row:CreateTexture(nil, "BORDER")
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.count:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.info:SetJustifyH("LEFT")
    row.info:SetWordWrap(false)
    row.info:SetTextColor(0.7, 0.7, 0.7)

    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetHeight(3)
    row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.bar:SetMinMaxValues(0, 1)
    row.bar.bg = row.bar:CreateTexture(nil, "BACKGROUND")
    row.bar.bg:SetAllPoints(row.bar)
    row.bar.bg:SetColorTexture(0, 0, 0, 0.6)

    -- Item hover / Shift-click area over the icon and name.
    row.hit = CreateFrame("Button", nil, row)
    row.hit:SetScript("OnEnter", ItemTooltip)
    row.hit:SetScript("OnLeave", GameTooltip_Hide)
    row.hit:SetScript("OnClick", function(self)
        local r = self:GetParent().roll
        if r and r.link and (IsShiftKeyDown() or IsControlKeyDown()) and HandleModifiedItemClick then
            HandleModifiedItemClick(r.link)
        end
    end)
    ForwardDrag(row.hit)

    row.buttons = {}
    for _, c in ipairs(CHOICES) do
        local b = CreateFrame("Button", nil, row)
        b:SetNormalTexture(c.tex)
        b:SetPushedTexture((c.tex:gsub("Up$", "Down")))
        b:SetHighlightTexture((c.tex:gsub("Up$", "Highlight")), "ADD")
        b:SetMotionScriptsWhileDisabled(true)
        b.choice, b.label = c.type, c.label
        b:SetScript("OnClick", function(self) Choose(self:GetParent(), self.choice) end)
        b:SetScript("OnEnter", ButtonTooltip)
        b:SetScript("OnLeave", GameTooltip_Hide)
        row.buttons[#row.buttons + 1] = b
    end

    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.status:SetJustifyH("RIGHT")
    row.status:SetTextColor(1, 0.82, 0)
    return row
end

-- Sizes and places everything in a row for the current width and row height.
local function LayoutRow(row, width, h)
    row:SetSize(width - PAD * 2, h)
    local iconSize = h - 8
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 1)
    row.icon:SetSize(iconSize, iconSize)
    row.iconBorder:ClearAllPoints()
    row.iconBorder:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -1, 1)
    row.iconBorder:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)
    row.count:ClearAllPoints()
    row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", -1, 2)

    local font = Font()
    row.name:SetFont(font, math.max(10, math.floor(h * 0.3)), "OUTLINE")
    row.info:SetFont(font, math.max(8, math.floor(h * 0.22)), "OUTLINE")
    row.count:SetFont(font, math.max(8, math.floor(h * 0.24)), "OUTLINE")
    row.status:SetFont(font, math.max(9, math.floor(h * 0.28)), "OUTLINE")

    -- Buttons on the right, as many as this row shows.
    local size = math.floor(h * 0.62)
    local x = -4
    for i = #row.buttons, 1, -1 do
        local b = row.buttons[i]
        b:SetSize(size, size)
        if b:IsShown() then
            b:ClearAllPoints()
            b:SetPoint("RIGHT", row, "RIGHT", x, 1)
            x = x - size - 2
        end
    end
    row.status:ClearAllPoints()
    row.status:SetPoint("RIGHT", row, "RIGHT", -6, 1)

    local textLeft = 4 + iconSize + 6
    local textRight = -x + 4
    row.name:ClearAllPoints()
    row.name:SetPoint("BOTTOMLEFT", row, "LEFT", textLeft, 1)
    row.name:SetPoint("RIGHT", row, "RIGHT", -textRight, 0)
    row.info:ClearAllPoints()
    row.info:SetPoint("TOPLEFT", row, "LEFT", textLeft, -2)
    row.info:SetPoint("RIGHT", row, "RIGHT", -textRight, 0)

    row.hit:ClearAllPoints()
    row.hit:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.hit:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -textRight, 0)

    row.bar:ClearAllPoints()
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
end

local function FormatTime(seconds)
    seconds = math.max(0, math.ceil(seconds))
    if seconds >= 60 then return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60) end
    return seconds .. "s"
end

local function UpdateRowTimer(row)
    local r = row.roll
    local left = r.endsAt - GetTime()
    row.bar:SetValue(r.duration > 0 and math.max(0, left / r.duration) or 0)
    local parts = {}
    if r.bop then parts[#parts + 1] = "|cffff5555" .. (ITEM_BIND_ON_PICKUP or "Binds when picked up") .. "|r" end
    parts[#parts + 1] = FormatTime(left)
    row.info:SetText(table.concat(parts, "  "))
end

local function FillRow(row, r)
    row.roll = r
    -- Refresh the item data once the client has it cached.
    if not r.quality or not r.icon then
        local name, quality, icon = ItemInfo(r.link or r.name)
        r.quality = r.quality or quality
        r.icon = r.icon or icon
        if r.name == nil then r.name = name end
    end
    local cr, cg, cb = QualityColor(r.quality, r.link)
    row.icon:SetTexture(r.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.iconBorder:SetColorTexture(cr, cg, cb, 1)
    row.name:SetText(r.name or "?")
    row.name:SetTextColor(cr, cg, cb)
    row.count:SetText((r.count and r.count > 1) and r.count or "")
    row.bar:SetStatusBarColor(cr, cg, cb)

    local chosen = r.chosen ~= nil
    for _, b in ipairs(row.buttons) do
        local show = not chosen and (b.choice ~= ROLL_DE or r.showDE)
        b:SetShown(show)
        local can = r.can[b.choice] ~= false
        b:SetEnabled(can)
        b.reason = r.reason[b.choice]
        local tex = b:GetNormalTexture()
        if tex then
            tex:SetDesaturated(not can)
            tex:SetAlpha(can and 1 or 0.4)
        end
    end
    row.status:SetShown(chosen)
    row.status:SetText(chosen and (CHOICE_LABEL[r.chosen] or "") or "")
    UpdateRowTimer(row)
end

function Refresh()
    if not panel then return end
    local n = #rolls
    if n == 0 then
        panel:Hide()
        testShown = false
        if M.optionsRefresh then M.optionsRefresh() end
        return
    end
    local width, h = PanelWidth(), RowHeight()
    panel.sizing = true
    panel:SetSize(width, HEADER_H + n * (h + 2) + PAD)
    panel.sizing = false
    panel.title:SetText(("%s |cffffffff(%d)|r"):format(LOOT_ROLLS or "Loot rolls", n))
    for i, r in ipairs(rolls) do
        local row = rowFrames[i]
        if not row then
            row = table.remove(rowPool) or NewRow()
            rowFrames[i] = row
        end
        FillRow(row, r)
        LayoutRow(row, width, h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -HEADER_H - (i - 1) * (h + 2))
        row:Show()
    end
    for i = #rowFrames, n + 1, -1 do
        local row = table.remove(rowFrames, i)
        row:Hide()
        row.roll = nil
        rowPool[#rowPool + 1] = row
    end
    panel:Show()
end

local function CreatePanel()
    panel = CreateFrame("Frame", "DhoxarModulesLootRolls", UIParent)
    panel:SetFrameStrata("HIGH")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:SetResizable(true)
    if panel.SetResizeBounds then
        panel:SetResizeBounds(MIN_W, HEADER_H + MIN_ROW, MAX_W, 2000)
    else
        if panel.SetMinResize then panel:SetMinResize(MIN_W, HEADER_H + MIN_ROW) end
        if panel.SetMaxResize then panel:SetMaxResize(MAX_W, 2000) end
    end
    panel:EnableMouse(true)
    ForwardDrag(panel)
    panel:Hide()

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(panel)
    bg:SetColorTexture(0.05, 0.05, 0.06, 0.92)
    local headerBg = panel:CreateTexture(nil, "BORDER")
    headerBg:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    headerBg:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    headerBg:SetHeight(HEADER_H - 2)
    headerBg:SetColorTexture(1, 0.82, 0, 0.08)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetFont(Font(), 12, "OUTLINE")
    panel.title:SetTextColor(1, 0.82, 0)
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -4)

    -- Resize grip: the width is free; the height is split into rows.
    local grip = CreateFrame("Button", nil, panel)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(panel:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        panel.userSizing = true
        panel:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        panel:StopMovingOrSizing()
        panel.userSizing = false
        SavePosition()
        Refresh()
    end)

    -- While the user drags the grip, turn the new size into width and row height.
    panel:SetScript("OnSizeChanged", function(self, w, h)
        if not self.userSizing or self.sizing then return end
        local n = math.max(1, #rolls)
        M.db.width = math.floor(math.min(MAX_W, math.max(MIN_W, w)) + 0.5)
        M.db.rowHeight = math.floor(math.min(MAX_ROW, math.max(MIN_ROW, (h - HEADER_H - PAD) / n - 2)) + 0.5)
        local width, rh = PanelWidth(), RowHeight()
        for _, row in ipairs(rowFrames) do
            LayoutRow(row, width, rh)
        end
        for i, row in ipairs(rowFrames) do
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -HEADER_H - (i - 1) * (rh + 2))
        end
    end)

    local elapsed = 0
    panel:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.1 then return end
        elapsed = 0
        local expired = false
        for _, row in ipairs(rowFrames) do
            if row.roll then
                UpdateRowTimer(row)
                -- Test rows end on their own; real ones end with CANCEL_LOOT_ROLL.
                if row.roll.test and row.roll.endsAt <= GetTime() then expired = true end
            end
        end
        if expired then
            for i = #rolls, 1, -1 do
                if rolls[i].test and rolls[i].endsAt <= GetTime() then table.remove(rolls, i) end
            end
            Refresh()
        end
    end)

    ApplyPosition()
end

---------------------------------------------------------------------------
-- Blizzard's roll frames
---------------------------------------------------------------------------

local blizzardMuted = false
local hookedFrames = {}

local function HideBlizzardFrame(f)
    if M.active and M.db.hideBlizzard ~= false and f:IsShown() then f:Hide() end
end

local function MuteBlizzard(mute)
    if mute and not blizzardMuted then
        local ok, registered = pcall(UIParent.IsEventRegistered, UIParent, "START_LOOT_ROLL")
        if ok and registered then
            pcall(UIParent.UnregisterEvent, UIParent, "START_LOOT_ROLL")
            blizzardMuted = true
        end
    elseif not mute and blizzardMuted then
        pcall(UIParent.RegisterEvent, UIParent, "START_LOOT_ROLL")
        blizzardMuted = false
    end
    -- In case the client opens them some other way: hide them on show.
    for i = 1, 4 do
        local f = _G["GroupLootFrame" .. i]
        if f and not hookedFrames[f] then
            hookedFrames[f] = true
            f:HookScript("OnShow", HideBlizzardFrame)
        end
        if f and mute then HideBlizzardFrame(f) end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function AddRoll(id, rollTime)
    if id == nil or IsSecret(id) or FindRoll(id) then return end
    local r = ReadRoll(id, rollTime)
    if not r then return end
    if not panel then CreatePanel() end
    rolls[#rolls + 1] = r
    Refresh()
end

local function RemoveRoll(id)
    local _, i = FindRoll(id)
    if i then
        table.remove(rolls, i)
        Refresh()
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, a, b)
    if not M.active then return end
    if event == "START_LOOT_ROLL" then
        AddRoll(a, b)
    elseif event == "CANCEL_LOOT_ROLL" then
        RemoveRoll(a)
    elseif event == "CANCEL_ALL_LOOT_ROLLS" then
        for i = #rolls, 1, -1 do
            if not rolls[i].test then table.remove(rolls, i) end
        end
        Refresh()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if panel and panel:IsShown() then Refresh() end
    end
end)

-- Rolls already open (after /reload), when the client can list them.
local function PickUpOpenRolls()
    local ids = SafeCall(GetActiveLootRollIDs)
    if type(ids) ~= "table" then return end
    for _, id in ipairs(ids) do AddRoll(id) end
end

function M:OnEnable()
    for _, e in ipairs({ "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS", "GET_ITEM_INFO_RECEIVED" }) do
        pcall(events.RegisterEvent, events, e)
    end
    MuteBlizzard(M.db.hideBlizzard ~= false)
    PickUpOpenRolls()
end

function M:OnDisable()
    events:UnregisterAllEvents()
    MuteBlizzard(false)
    wipe(rolls)
    testShown = false
    Refresh()
end

---------------------------------------------------------------------------
-- Test and options
---------------------------------------------------------------------------

-- A few of the player's equipped items, so the test shows real names and colors.
local function SampleLinks()
    local links = {}
    for _, slot in ipairs({ 16, 1, 5, 7, 3, 10, 17, 18 }) do
        local link = SafeCall(GetInventoryItemLink, "player", slot)
        if type(link) == "string" and not IsSecret(link) then links[#links + 1] = link end
        if #links == 3 then break end
    end
    if #links == 0 then
        links[1] = select(2, SafeCall(GetItemInfo, 6948)) or "|cffffffff|Hitem:6948::::::::1:::::|h[Hearthstone]|h|r"
    end
    return links
end

local testCounter = 0

local function ShowTest()
    if not panel then CreatePanel() end
    for i, link in ipairs(SampleLinks()) do
        testCounter = testCounter + 1
        local name, quality, icon = ItemInfo(link)
        rolls[#rolls + 1] = {
            id = "test" .. testCounter, test = true, link = link, name = name, icon = icon, quality = quality,
            count = 1, bop = (i == 1),
            can = { [ROLL_NEED] = (i ~= 3), [ROLL_GREED] = true, [ROLL_DE] = true, [ROLL_PASS] = true },
            reason = { [ROLL_NEED] = (i == 3) and "Test: you can't need this item." or nil },
            showDE = false,
            endsAt = GetTime() + TEST_TIME - (i - 1) * 10, duration = TEST_TIME,
        }
    end
    testShown = true
    Refresh()
end

local function HideTest()
    for i = #rolls, 1, -1 do
        if rolls[i].test then table.remove(rolls, i) end
    end
    testShown = false
    Refresh()
end

function M:BuildOptions(page)
    M.optionsRefresh = function() page:Refresh() end

    page:Header("Panel")
    page:Text("Every open roll is a row: the item in its rarity color, \"Binds when picked up\" in red when it does, the time left, and the Need, Greed and Pass buttons (Disenchant too when the client offers it). A greyed-out button can't be used; hover it for the reason. Hover an item for its tooltip, Shift-click to link it. Drag the panel to move it and drag its bottom-right corner to resize it: the width is free and the height sets the row size.")
    page:Button({
        label = "Test panel",
        description = "Shows the panel with a few of your items so you can place and size it. The buttons work on the test rows but roll on nothing; the rows end after a minute, or click Hide.",
        text = function() return testShown and "Hide" or "Test" end,
        onClick = function()
            if not M.active then
                print(TAG .. "the module is not running. Type /dhoxar list.")
            elseif testShown then
                HideTest()
            else
                ShowTest()
            end
        end,
    })
    page:Button({
        label = "Reset position and size",
        description = "Moves the panel back to the top of the screen at its default size.",
        text = "Reset",
        onClick = function()
            M.db.position, M.db.width, M.db.rowHeight = {}, 360, 44
            if panel then ApplyPosition() Refresh() end
        end,
    })

    page:Header("Blizzard frames")
    page:Checkbox({
        label = "Hide Blizzard's roll frames",
        description = "Only this panel is shown. Off: both are shown, and a roll made in either counts.",
        get = function() return M.db.hideBlizzard ~= false end,
        set = function(value)
            M.db.hideBlizzard = value and true or false
            if M.active then MuteBlizzard(M.db.hideBlizzard) end
        end,
    })
end
