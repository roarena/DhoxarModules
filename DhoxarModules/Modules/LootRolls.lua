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
--
-- "Show everyone's rolls" (on by default): when the player chooses Need,
-- Greed or Disenchant, the item's card opens downwards and lists every
-- choice and roll in the group, read from the loot chat lines ("X has
-- selected Need", "Need Roll - 87 for [item] by X", "X won: [item]"). The
-- card stays after the roll closes, until the item goes to someone (or
-- everyone passed), then leaves a few seconds later.

local _, ns = ...

local IsSecret = ns.Util.IsSecret
local SafeCall = ns.Util.SafeCall
local ItemInfo = ns.Util.ItemInfo
local QualityColor = ns.Util.ItemQualityColor
local W = ns.Widgets

local M = ns:RegisterModule({
    key = "LootRolls",
    title = "Loot Rolls",
    description = "Replaces the loot roll frames with one panel listing every open roll, with Need, Greed and Pass on each.",
    aliases = { "rolls", "roll", "lootrolls" },
    defaults = { hideBlizzard = true, showRolls = true, position = {}, width = 360, rowHeight = 44 },
})

local TAG = "|cffc8aa88Loot Rolls|r: "
local DEFAULT_POSITION = { "TOP", "TOP", 0, -240 }
local STALE_GRACE = 5 -- seconds a real roll stays after its timer ran out
local HEADER_H = 22
local PAD = 4
local MIN_W, MAX_W = 240, 800
local MIN_ROW, MAX_ROW = 28, 90
local TEST_TIME = 60
local WINNER_LINGER = 5  -- seconds a card stays after its item went to someone
local KEEP_MAX = 120     -- a kept card with no result leaves this long after its timer ran out
local MAX_ROLL_LINES = 8 -- roll lines on a card; the rest are counted

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
local KIND_HEX = { [ROLL_NEED] = "ff9933", [ROLL_GREED] = "40c0ff", [ROLL_DE] = "c080ff", [ROLL_PASS] = "999999" }
-- Need beats Greed and Disenchant; ties go to the higher number.
local RANK = { [ROLL_NEED] = 3, [ROLL_GREED] = 2, [ROLL_DE] = 2 }

---------------------------------------------------------------------------
-- Roll data
---------------------------------------------------------------------------

-- Rolls in arrival order: { id, link, name, icon, quality, count, bop,
-- can = {}, reason = {}, endsAt, duration, chosen, pending, test,
-- entries = { [player] = { name, kind, roll, me } }, closed, winner,
-- allPassed, removeAt }
local rolls = {}
local testShown = false

local function FindRoll(id)
    for i, r in ipairs(rolls) do
        if r.id == id then return r, i end
    end
end

local function ShowRolls() return M.db.showRolls ~= false end

-- The player rolled on it (Need, Greed or Disenchant) and the option is on:
-- its card lists everyone's rolls and stays until the item goes to someone.
local function Expanded(r)
    local c = r.chosen
    return ShowRolls() and (c == ROLL_NEED or c == ROLL_GREED or c == ROLL_DE)
end

local function MyName()
    local name = UnitName("player")
    if IsSecret(name) then return nil end
    return name
end

local function ShortName(name)
    return type(name) == "string" and (name:match("^([^%-]+)") or name) or "?"
end

local function IsMe(player)
    if type(player) ~= "string" then return false end
    if player == YOU or player == "You" then return true end
    local me = MyName()
    return me ~= nil and ShortName(player) == me
end

-- Records what `player` did on roll r: the choice (a ROLL_* type) and,
-- once rolled, the number.
local function SetEntry(r, player, kind, roll)
    if type(player) ~= "string" then return end
    local me = IsMe(player)
    if me then player = MyName() or player end
    r.entries = r.entries or {}
    local e = r.entries[player]
    if not e then
        e = { name = player, me = me }
        r.entries[player] = e
    end
    if kind ~= nil then e.kind = kind end
    if roll ~= nil then e.roll = roll end
end

-- player nil: everyone passed.
local function SetWinner(r, player)
    if player then
        r.winner = IsMe(player) and (MyName() or player) or player
    else
        r.allPassed = true
    end
    r.closed = true
    r.removeAt = GetTime() + WINNER_LINGER
end

local function RollBeats(a, b)
    local ra, rb = RANK[a.kind] or 0, RANK[b.kind] or 0
    if ra ~= rb then return ra > rb end
    return (a.roll or 0) > (b.roll or 0)
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
        entries = {},
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

-- Test rows: a few made-up group members choose and roll, then one wins.
local TEST_NAMES = { "Aldren", "Brisa", "Corvin" }

local function SimulateTest(r)
    local me = MyName() or "You"
    SetEntry(r, me, r.chosen)
    r.closed = true
    local people = { { name = me, kind = r.chosen } }
    local kinds = { ROLL_NEED, ROLL_GREED, ROLL_PASS }
    for i, name in ipairs(TEST_NAMES) do
        local p = { name = name, kind = kinds[math.random(1, #kinds)] }
        people[#people + 1] = p
        C_Timer.After(0.4 * i, function()
            SetEntry(r, p.name, p.kind)
            Refresh()
        end)
    end
    C_Timer.After(2, function()
        local best
        for _, p in ipairs(people) do
            if p.kind ~= ROLL_PASS then
                p.roll = math.random(1, 100)
                SetEntry(r, p.name, p.kind, p.roll)
                if not best or RollBeats(p, best) then best = p end
            end
        end
        Refresh()
        C_Timer.After(1.5, function()
            SetWinner(r, best and best.name)
            Refresh()
        end)
    end)
end

local function Choose(row, choice)
    local r = row.roll
    if not r or r.chosen ~= nil then return end
    if r.test then
        r.chosen = choice
        if Expanded(r) then
            SimulateTest(r)
        else
            C_Timer.After(1.5, function()
                local _, i = FindRoll(r.id)
                if i then table.remove(rolls, i) Refresh() end
            end)
        end
        Refresh()
        return
    end
    local ok = pcall(RollOnLoot, r.id, choice)
    if not ok then
        print(TAG .. "could not roll on " .. (r.link or r.name) .. ".")
        return
    end
    -- Bind-on-pickup: the choice only counts once Blizzard's pop-up is
    -- confirmed, and CANCEL_LOOT_ROLL comes then. Until that the buttons
    -- stay, in case the pop-up is declined.
    if r.bop then
        r.pending = choice
    else
        r.chosen = choice
        SetEntry(r, MyName(), choice)
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
    -- Classic only: a brown-gold outline, like the quest log's headers.
    row.edges = W.Border(row, W.themes.classic.border)

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

    -- The expanded part under the row: one line per roll.
    row.details = CreateFrame("Frame", nil, row)
    row.details.bg = row.details:CreateTexture(nil, "BACKGROUND")
    row.details.bg:SetAllPoints(row.details)
    row.details.edges = W.Border(row.details, W.themes.classic.border)
    row.details:Hide()
    row.lines = {}
    row.nLines = 0
    return row
end

local function GetLine(row, i)
    local line = row.lines[i]
    if not line then
        line = {
            left = row.details:CreateFontString(nil, "OVERLAY", "GameFontNormal"),
            right = row.details:CreateFontString(nil, "OVERLAY", "GameFontNormal"),
        }
        line.left:SetJustifyH("LEFT")
        line.left:SetWordWrap(false)
        line.right:SetJustifyH("RIGHT")
        line.right:SetWordWrap(false)
        row.lines[i] = line
    end
    return line
end

local function LineHeight(h) return math.max(12, math.floor(h * 0.34)) end

local function DetailsHeight(nLines, h) return nLines * LineHeight(h) + 6 end

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

    -- Roll lines, lined up with the item name.
    row.details:ClearAllPoints()
    row.details:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, 0)
    row.details:SetSize(width - PAD * 2, DetailsHeight(row.nLines, h))
    local lineH = LineHeight(h)
    local lineFont = math.max(9, math.floor(h * 0.25))
    for i, line in ipairs(row.lines) do
        line.left:SetFont(font, lineFont, "OUTLINE")
        line.right:SetFont(font, lineFont, "OUTLINE")
        local y = -3 - (i - 1) * lineH
        line.right:ClearAllPoints()
        line.right:SetPoint("TOPRIGHT", row.details, "TOPRIGHT", -8, y)
        line.left:ClearAllPoints()
        line.left:SetPoint("TOPLEFT", row.details, "TOPLEFT", textLeft, y)
        line.left:SetPoint("RIGHT", line.right, "LEFT", -8, 0)
    end
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
    if r.winner then
        row.info:SetText(IsMe(r.winner) and "|cff40ff40You won|r"
            or ("Won by |cffffffff%s|r"):format(ShortName(r.winner)))
        return
    elseif r.allPassed then
        row.info:SetText("Everyone passed")
        return
    elseif Expanded(r) and (r.closed or left <= 0) then
        row.info:SetText("Waiting for the result...")
        return
    end
    local parts = {}
    if r.bop then parts[#parts + 1] = "|cffff5555" .. (ITEM_BIND_ON_PICKUP or "Binds when picked up") .. "|r" end
    parts[#parts + 1] = FormatTime(left)
    row.info:SetText(table.concat(parts, "  "))
end

-- Row background for the current look (see W.PanelSkin for the panel).
local function StyleRow(row)
    local classic = W.IsClassic()
    if classic then
        W.SetColor(row.bg, W.themes.classic.navItem)
        W.SetColor(row.details.bg, W.themes.classic.navItem)
    else
        row.bg:SetColorTexture(1, 1, 1, 0.04)
        row.details.bg:SetColorTexture(1, 1, 1, 0.025)
    end
    for _, edge in ipairs(row.edges) do
        edge:SetShown(classic)
    end
    for _, edge in ipairs(row.details.edges) do
        edge:SetShown(classic)
    end
    row.info:SetTextColor(classic and 0.74 or 0.7, classic and 0.68 or 0.7, classic and 0.57 or 0.7)
end

local function ClassColor(e)
    local ok, _, file = pcall(UnitClass, e.me and "player" or e.name)
    if ok and type(file) == "string" and not IsSecret(file) then
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
        if c then return c.r, c.g, c.b end
    end
    return 1, 1, 1
end

-- The expanded card's lines: rolls best first, then who passed.
local function DetailLines(r)
    local rollers, passed = {}, {}
    for _, e in pairs(r.entries or {}) do
        if e.kind == ROLL_PASS then
            passed[#passed + 1] = ShortName(e.name)
        elseif e.kind ~= nil then
            rollers[#rollers + 1] = e
        end
    end
    table.sort(rollers, function(a, b)
        if RollBeats(a, b) then return true end
        if RollBeats(b, a) then return false end
        return a.name < b.name
    end)
    table.sort(passed)

    local lines = {}
    local winner = r.winner and ShortName(r.winner)
    for i, e in ipairs(rollers) do
        if i > MAX_ROLL_LINES then
            lines[#lines + 1] = { left = ("+%d more"):format(#rollers - MAX_ROLL_LINES), dim = true }
            break
        end
        local roll = e.roll and ("|cffffffff%d|r"):format(e.roll) or "|cff888888...|r"
        local right = ("|cff%s%s|r %s"):format(KIND_HEX[e.kind] or "ffffff", CHOICE_LABEL[e.kind] or "?", roll)
        if winner and ShortName(e.name) == winner then right = "|cff40ff40Won|r  " .. right end
        local cr, cg, cb = ClassColor(e)
        lines[#lines + 1] = {
            left = ShortName(e.name) .. (e.me and " |cffaaaaaa(you)|r" or ""),
            right = right, r = cr, g = cg, b = cb,
        }
    end
    if #passed > 0 then
        lines[#lines + 1] = { left = (PASS or "Pass") .. ": " .. table.concat(passed, ", "), dim = true }
    end
    if #lines == 0 then lines[1] = { left = "Waiting for the rolls...", dim = true } end
    return lines
end

local function FillRow(row, r)
    row.roll = r
    StyleRow(row)
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
    local status = chosen and (CHOICE_LABEL[r.chosen] or "") or ""
    local mine = chosen and r.entries and r.entries[MyName() or ""]
    if mine and mine.roll then status = ("%s |cffffffff%d|r"):format(status, mine.roll) end
    row.status:SetShown(chosen)
    row.status:SetText(status)

    -- Everyone's rolls, when the card is expanded.
    row.expanded = Expanded(r)
    local lines = row.expanded and DetailLines(r) or {}
    row.nLines = #lines
    for i, info in ipairs(lines) do
        local line = GetLine(row, i)
        line.left:SetText(info.left)
        line.right:SetText(info.right or "")
        if info.dim then
            line.left:SetTextColor(0.6, 0.6, 0.6)
        else
            line.left:SetTextColor(info.r or 1, info.g or 1, info.b or 1)
        end
        line.left:Show()
        line.right:Show()
    end
    for i = #lines + 1, #row.lines do
        row.lines[i].left:Hide()
        row.lines[i].right:Hide()
    end
    row.details:SetShown(row.expanded)
    UpdateRowTimer(row)
end

-- Places the rows from the top, each followed by its expanded part.
-- Returns the height they take.
local function PlaceRows(width, h)
    local y = 0
    for _, row in ipairs(rowFrames) do
        if row.roll then
            LayoutRow(row, width, h)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -HEADER_H - y)
            y = y + h + (row.expanded and DetailsHeight(row.nLines, h) or 0) + 2
        end
    end
    return y
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
    panel.title:SetText(("%s |cffffffff(%d)|r"):format(LOOT_ROLLS or "Loot rolls", n))
    for i, r in ipairs(rolls) do
        local row = rowFrames[i]
        if not row then
            row = table.remove(rowPool) or NewRow()
            rowFrames[i] = row
        end
        FillRow(row, r)
        row:Show()
    end
    for i = #rowFrames, n + 1, -1 do
        local row = table.remove(rowFrames, i)
        row:Hide()
        row.roll = nil
        rowPool[#rowPool + 1] = row
    end
    local used = PlaceRows(width, h)
    panel.sizing = true
    panel:SetSize(width, HEADER_H + used + PAD)
    panel.sizing = false
    panel:Show()
end

-- Kept cards leave a few seconds after the item went to someone (or after
-- KEEP_MAX if that never shows). Test rows end on their own; other real ones
-- end with CANCEL_LOOT_ROLL, or a few seconds after their time ran out if
-- that never comes.
local function ShouldRemove(r, now)
    if r.removeAt then return now >= r.removeAt end
    if Expanded(r) then return now >= r.endsAt + KEEP_MAX end
    return r.endsAt + (r.test and 0 or STALE_GRACE) <= now
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

    local headerBg = panel:CreateTexture(nil, "BORDER", nil, 1)
    headerBg:SetHeight(HEADER_H - 2)
    -- Classic only: a brown-gold line under the title bar.
    local divider = panel:CreateTexture(nil, "BORDER", nil, 2)
    W.SetColor(divider, W.themes.classic.border)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", headerBg, "BOTTOMLEFT", 0, 0)
    divider:SetPoint("TOPRIGHT", headerBg, "BOTTOMRIGHT", 0, 0)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetFont(Font(), 12, "OUTLINE")
    panel.title:SetTextColor(1, 0.82, 0)
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -4)

    -- Modern: dark flat panel with a faint gold title bar. Classic: the
    -- game's rock background in a brown-gold rim, a brown title bar and
    -- outlined rows.
    panel.skin = W.PanelSkin(panel, { 0.05, 0.05, 0.06, 0.92 }, function(classic)
        local inset = classic and 2 or 0
        headerBg:ClearAllPoints()
        headerBg:SetPoint("TOPLEFT", panel, "TOPLEFT", inset, -inset)
        headerBg:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -inset, -inset)
        if classic then
            W.SetColor(headerBg, W.themes.classic.header)
        else
            headerBg:SetColorTexture(1, 0.82, 0, 0.08)
        end
        divider:SetShown(classic)
        if panel:IsShown() then Refresh() end
    end)

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
        -- Expanded parts take their share first; the rest is split into rows.
        local extra, oldRh = 0, RowHeight()
        for _, row in ipairs(rowFrames) do
            if row.roll and row.expanded then extra = extra + DetailsHeight(row.nLines, oldRh) end
        end
        M.db.width = math.floor(math.min(MAX_W, math.max(MIN_W, w)) + 0.5)
        M.db.rowHeight = math.floor(math.min(MAX_ROW, math.max(MIN_ROW, (h - HEADER_H - PAD - extra) / n - 2)) + 0.5)
        PlaceRows(PanelWidth(), RowHeight())
    end)

    local elapsed = 0
    panel:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.1 then return end
        elapsed = 0
        local now = GetTime()
        local expired = false
        for _, row in ipairs(rowFrames) do
            if row.roll then
                UpdateRowTimer(row)
                if ShouldRemove(row.roll, now) then expired = true end
            end
        end
        if expired then
            for i = #rolls, 1, -1 do
                if ShouldRemove(rolls[i], now) then table.remove(rolls, i) end
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

local function Muting()
    return M.active and M.db.hideBlizzard ~= false
end

-- Blizzard's GroupLootContainer holds the roll frames and takes the mouse.
-- Hiding a roll frame directly skips the code that hides the container once
-- it is empty, so it stayed shown, invisible, over the middle of the screen
-- and ate clicks meant for the world. While muted: hide it when nothing in
-- it is shown, and keep it from taking the mouse either way.
local containerMouse -- its original EnableMouse state, while we own it

local function ContainerHasShownFrame(c)
    local ok, shown = pcall(function()
        for _, child in ipairs({ c:GetChildren() }) do
            if child:IsShown() then return true end
        end
        return false
    end)
    return ok and shown
end

local function TidyContainer()
    local c = GroupLootContainer
    if not c then return end
    if Muting() then
        if containerMouse == nil then
            local ok, enabled = pcall(c.IsMouseEnabled, c)
            containerMouse = ok and enabled or false
        end
        pcall(c.EnableMouse, c, false)
        if c:IsShown() and not ContainerHasShownFrame(c) then pcall(c.Hide, c) end
    elseif containerMouse ~= nil then
        pcall(c.EnableMouse, c, containerMouse)
        containerMouse = nil
    end
end

local function HideBlizzardFrame(f)
    if Muting() and f:IsShown() then f:Hide() end
    TidyContainer()
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
    local c = GroupLootContainer
    if c and not hookedFrames[c] then
        hookedFrames[c] = true
        c:HookScript("OnShow", TidyContainer)
    end
    TidyContainer()
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

-- The roll closed for the player. A card the player rolled on stays, to
-- show the rolls until the item goes to someone.
local function RemoveRoll(id)
    local r, i = FindRoll(id)
    if not i then return end
    if r.chosen == nil and r.pending ~= nil then
        -- Bind-on-pickup: the pop-up was confirmed.
        r.chosen = r.pending
        SetEntry(r, MyName(), r.chosen)
    end
    if Expanded(r) then
        r.closed = true
    else
        table.remove(rolls, i)
    end
    Refresh()
end

---------------------------------------------------------------------------
-- Everyone's choices and rolls, from the loot chat lines
---------------------------------------------------------------------------

local CHAT = {}
local function Chat(global, kind, fields, choice)
    local def = ns.Util.ChatPattern(global, fields)
    if not def then return end
    def.kind, def.choice = kind, choice
    CHAT[#CHAT + 1] = def
end

-- The more specific strings come first: "(.+) passed on: (.+)" would also
-- match "Everyone passed on: ..." and "X automatically passed on: ...".
Chat("LOOT_ROLL_YOU_WON", "won", { "item" })
Chat("LOOT_ROLL_ALL_PASSED", "allpassed", { "item" })
Chat("LOOT_ROLL_WON", "won", { "player", "item" })
Chat("LOOT_ROLL_ROLLED_NEED_ROLE_BONUS", "rolled", { "roll", "item", "player" }, ROLL_NEED)
Chat("LOOT_ROLL_ROLLED_NEED", "rolled", { "roll", "item", "player" }, ROLL_NEED)
Chat("LOOT_ROLL_ROLLED_GREED", "rolled", { "roll", "item", "player" }, ROLL_GREED)
Chat("LOOT_ROLL_ROLLED_DE", "rolled", { "roll", "item", "player" }, ROLL_DE)
Chat("LOOT_ROLL_NEED_SELF", "selected", { "item" }, ROLL_NEED)
Chat("LOOT_ROLL_GREED_SELF", "selected", { "item" }, ROLL_GREED)
Chat("LOOT_ROLL_DISENCHANT_SELF", "selected", { "item" }, ROLL_DE)
Chat("LOOT_ROLL_PASSED_SELF_AUTO", "selected", { "item" }, ROLL_PASS)
Chat("LOOT_ROLL_PASSED_SELF", "selected", { "item" }, ROLL_PASS)
Chat("LOOT_ROLL_NEED", "selected", { "player", "item" }, ROLL_NEED)
Chat("LOOT_ROLL_GREED", "selected", { "player", "item" }, ROLL_GREED)
Chat("LOOT_ROLL_DISENCHANT", "selected", { "player", "item" }, ROLL_DE)
Chat("LOOT_ROLL_PASSED_AUTO", "selected", { "player", "item" }, ROLL_PASS)
Chat("LOOT_ROLL_PASSED_AUTO_FEMALE", "selected", { "player", "item" }, ROLL_PASS)
Chat("LOOT_ROLL_PASSED", "selected", { "player", "item" }, ROLL_PASS)

local function ItemID(link)
    return type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) or nil
end

local function SameItem(r, item)
    local id = ItemID(item)
    if id and r.link then return ItemID(r.link) == id end
    local name = item:match("%[(.-)%]") or item
    return name == r.name
end

-- The open roll a chat line is about. With several copies of one item, the
-- first that doesn't have this news yet.
local function RollFor(item, player, kind)
    local fallback
    for _, r in ipairs(rolls) do
        if not r.test and not r.winner and not r.allPassed and SameItem(r, item) then
            local e = player and r.entries and r.entries[player]
            if kind == "selected" and not e then return r end
            if kind == "rolled" and not (e and e.roll) then return r end
            if kind == "won" and e and e.roll then return r end
            fallback = fallback or r
        end
    end
    return fallback
end

local function OnLootMessage(msg)
    if #rolls == 0 or type(msg) ~= "string" or IsSecret(msg) then return end
    for _, def in ipairs(CHAT) do
        local f = ns.Util.MatchChat(msg, def)
        if f and f.item then
            local player = f.player or MyName()
            if IsMe(player) then player = MyName() or player end
            local r = RollFor(f.item, player, def.kind)
            if not r then return end
            if def.kind == "selected" then
                SetEntry(r, player, def.choice)
                -- Rolled from Blizzard's frame, or a confirmed bind-on-pickup.
                if IsMe(player) and r.chosen == nil then
                    r.chosen, r.pending = def.choice, nil
                end
            elseif def.kind == "rolled" then
                SetEntry(r, player, def.choice, tonumber(f.roll))
            elseif def.kind == "won" then
                SetWinner(r, player)
            else
                SetWinner(r, nil)
            end
            Refresh()
            return
        end
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, a, b)
    if not M.active then return end
    if event == "START_LOOT_ROLL" then
        AddRoll(a, b)
    elseif event == "CANCEL_LOOT_ROLL" then
        RemoveRoll(a)
    elseif event == "CHAT_MSG_LOOT" then
        OnLootMessage(a)
    elseif event == "CANCEL_ALL_LOOT_ROLLS" then
        for i = #rolls, 1, -1 do
            local r = rolls[i]
            if not r.test then
                if Expanded(r) then r.closed = true else table.remove(rolls, i) end
            end
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
    for _, e in ipairs({ "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS", "GET_ITEM_INFO_RECEIVED", "CHAT_MSG_LOOT" }) do
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
            showDE = false, entries = {},
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
    page:Text("Every open roll is a row: the item in its rarity color, \"Binds when picked up\" in red when it does, the time left, and the Need, Greed and Pass buttons (Disenchant too when the client offers it). A greyed-out button can't be used; hover it for the reason. With \"Show everyone's rolls\" on, a card you rolled on opens to list everyone's rolls and stays until the item goes to someone. Hover an item for its tooltip, Shift-click to link it. Drag the panel to move it and drag its bottom-right corner to resize it: the width is free and the height sets the row size.")
    page:Checkbox({
        label = "Show everyone's rolls",
        description = "When you choose Need, Greed or Disenchant, the item's card opens to list your roll and the rest of the group's, and stays until the item goes to someone. Off: the card leaves once your roll is done.",
        get = function() return ShowRolls() end,
        set = function(value)
            M.db.showRolls = value and true or false
            if not value then
                -- Cards kept only to show the rolls leave now.
                for i = #rolls, 1, -1 do
                    if rolls[i].closed then table.remove(rolls, i) end
                end
            end
            Refresh()
        end,
    })
    page:Button({
        label = "Test panel",
        description = "Shows the panel with a few of your items so you can place and size it. The buttons work on the test rows but roll on nothing: Need or Greed shows made-up rolls from the group. The rows end after a minute, or click Hide.",
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
