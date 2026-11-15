-- Dhoxar Modules - self-buff reminder
--
-- A reusable "you are missing your buff" icon, built like the Battle Shout
-- reminder in Modules/Warrior/Reminders.lua: the icon appears in combat when
-- the buff is missing, or with a countdown during its last seconds, inside a
-- marching-dash border. It can be dragged after Unlock, or while Blizzard's
-- Edit Mode is open.
--
-- Aura reads follow the same rules as Battle Shout: never enumerate auras
-- (scans hard-error under the secret-value system); do a targeted
-- C_UnitAuras.GetPlayerAuraBySpellID lookup per id, and when the client marks
-- the aura secret in combat, trust a snapshot taken while it was readable.
--
-- Usage, from a module file:
--
--   local reminder = ns.BuffReminder.New(M, {
--       key = "fortitude",            -- frame name suffix
--       spellIDs = { ... },           -- every id that counts as the buff,
--                                     -- lowest rank first; the best known one
--                                     -- gives the icon and name
--       fallbackName = "...", fallbackIcon = "Interface\\Icons\\...",
--       tag = "|cff...Name|r: ",      -- chat prefix
--   })
--   M:OnEnable  -> reminder:Enable()
--   M:OnDisable -> reminder:Disable()
--   M:BuildOptions(page) -> reminder:BuildOptions(page)
--
-- Saved in the module's db: icon (position) and outOfCombat (boolean).

local _, ns = ...

local isSecret = ns.Util.IsSecret
local ToSet = ns.Util.ToSet

local BuffReminder = {}
BuffReminder.__index = BuffReminder
ns.BuffReminder = BuffReminder

local ICON_SIZE = 35
local WARNING_SECONDS = 10
local DEFAULT_POSITION = { "CENTER", "CENTER", 0, 150 }

---------------------------------------------------------------------------
-- Spell and aura queries
---------------------------------------------------------------------------

local function GetSpellNameAndIcon(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" and not isSecret(info) then
            return info.name, info.iconID
        end
    end
    if type(GetSpellInfo) == "function" then
        local ok, name, _, icon = pcall(GetSpellInfo, spellID)
        if ok and name then
            return name, icon
        end
    end
end

local function HasSpellKnownAPI()
    return type(IsPlayerSpell) == "function" or type(IsSpellKnown) == "function"
        or (C_SpellBook and C_SpellBook.IsSpellKnown) ~= nil
end

local function IsIdKnown(id)
    -- Some of these may be nil, so no ipairs (it would stop at the first nil).
    local checks = { IsPlayerSpell, IsSpellKnown, C_SpellBook and C_SpellBook.IsSpellKnown }
    for i = 1, 3 do
        local fn = checks[i]
        if type(fn) == "function" then
            local ok, known = pcall(fn, id)
            if ok and known == true then return true end
        end
    end
    return false
end

-- Highest known id from the list (lowest rank first), or nil if none is learned.
local function BestKnownSpell(ids)
    if not HasSpellKnownAPI() then return ids[#ids] end
    for i = #ids, 1, -1 do
        if IsIdKnown(ids[i]) then return ids[i] end
    end
end

-- On secret-value clients a lookup can succeed but return nil whether or not
-- the buff is up, so a nil result only counts while the client says the
-- aura is readable.
local function IsAuraReadable(id)
    if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldSpellAuraBeSecret, id)
        if not ok or isSecret(secret) then return false end
        return secret == false
    end
    return true
end

---------------------------------------------------------------------------
-- Reminder object
---------------------------------------------------------------------------

function BuffReminder.New(module, config)
    local self = setmetatable({}, BuffReminder)
    self.module = module
    self.key = config.key
    self.ids = config.spellIDs
    self.idSet = ToSet(config.spellIDs)
    self.fallbackName = config.fallbackName
    self.fallbackIcon = config.fallbackIcon
    self.tag = config.tag or ""
    self.defaultPosition = config.defaultPosition or DEFAULT_POSITION
    self.inCombat = false
    self.unlocked = false
    self.preCombatHasBuff = true -- assume up so login/reload never nags
    self.buffExpiry = nil
    self.lastDuration = nil
    self.editModeHook = "not hooked yet"
    return self
end

-- Name and icon of the best known rank, or of the first id.
function BuffReminder:SpellInfo()
    local id = BestKnownSpell(self.ids) or self.ids[1]
    local name, icon = GetSpellNameAndIcon(id)
    return name or self.fallbackName, icon or self.fallbackIcon
end

function BuffReminder:IsLearned()
    return BestKnownSpell(self.ids) ~= nil
end

-- Plain buff scan, only for clients without the by-id lookup (never the
-- secret-value ones).
function BuffReminder:Scan()
    if type(UnitBuff) ~= "function" then return nil end
    for i = 1, 40 do
        local ok, name, _, _, _, duration, expirationTime, _, _, _, spellId = pcall(UnitBuff, "player", i)
        if not ok or not name then break end
        if self.idSet[spellId] then
            if duration and expirationTime and duration > 0 then
                self.lastDuration = duration
                return true, expirationTime
            end
            return true
        end
    end
    return false
end

-- state, expirationTime. state: true (up), false (confirmed missing) or nil
-- (unreadable right now).
function BuffReminder:Query()
    local getter = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    local unitGetter = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
    if not getter and not unitGetter then return self:Scan() end

    local anyReadable = false
    for _, id in ipairs(self.ids) do
        if IsAuraReadable(id) then
            local ok, result
            if getter then
                ok, result = pcall(getter, id)
            else
                ok, result = pcall(unitGetter, "player", id)
            end
            if ok then
                anyReadable = true
                if result ~= nil then
                    local expiration
                    if not isSecret(result) and type(result) == "table" then
                        local e, d = result.expirationTime, result.duration
                        if e and d and not isSecret(e) and not isSecret(d) and d > 0 then
                            expiration = e
                            self.lastDuration = d
                        end
                    end
                    return true, expiration
                end
            end
        end
    end
    if anyReadable then return false end
    return nil
end

function BuffReminder:Snapshot()
    local up, expiration = self:Query()
    if up ~= nil then
        self.preCombatHasBuff = up
        self.buffExpiry = up and expiration or nil
    end
end

function BuffReminder:HasBuff()
    local up = self:Query()
    if up ~= nil then return up end
    if not self.preCombatHasBuff then return false end
    if self.buffExpiry and GetTime() >= self.buffExpiry then return false end
    return true
end

-- Seconds until the buff fades, or nil when it is not up or the expiry is unknown.
function BuffReminder:TimeLeft()
    local up, expiration = self:Query()
    if up == false then return nil end
    if up and expiration then return expiration - GetTime() end
    if self.preCombatHasBuff and self.buffExpiry then return self.buffExpiry - GetTime() end
    return nil
end

-- The player cast the buff while it is unreadable: mark it up and predict
-- the expiry from the last known duration.
function BuffReminder:NoteCast()
    self.preCombatHasBuff = true
    self.buffExpiry = self.lastDuration and (GetTime() + self.lastDuration) or nil
end

---------------------------------------------------------------------------
-- Icon
---------------------------------------------------------------------------

local function CreateEdgeBorder(parent, outset, thickness, r, g, b, a)
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

-- Name tag shown above the icon while it can be dragged.
local function CreateLabelPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetHeight(18)
    panel:SetPoint("BOTTOM", parent, "TOP", 0, 6)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(panel)
    bg:SetColorTexture(0.08, 0.26, 0.5, 0.9)
    CreateEdgeBorder(panel, 0, 1, 0.4, 0.7, 1, 0.9):Show()
    panel.text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.text:SetPoint("CENTER", panel, "CENTER", 0, 0)
    panel.text:SetTextColor(1, 1, 1)
    function panel:SetLabel(text)
        self.text:SetText(text)
        self:SetWidth(self.text:GetStringWidth() + 16)
    end
    panel:Hide()
    return panel
end

-- Dashes around the icon with a lit window running around them. OnUpdate
-- stops while hidden, so this costs nothing when the icon is not shown.
local function CreateMarchingDashBorder(parent, outset, dashLen, dashThick, gap, r, g, b)
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", -outset, outset)
    container:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", outset, -outset)
    container:Hide()

    local size = ICON_SIZE + 2 * outset
    local perimeter = size * 4
    local n = math.max(8, math.floor(perimeter / (dashLen + gap)))
    local dashes = {}
    for i = 0, n - 1 do
        local dist = (i * perimeter / n) % perimeter
        local tex = container:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(r, g, b, 1)
        if dist < size then
            tex:SetSize(dashLen, dashThick)
            tex:SetPoint("TOPLEFT", container, "TOPLEFT", dist, 0)
        elseif dist < size * 2 then
            tex:SetSize(dashThick, dashLen)
            tex:SetPoint("TOPLEFT", container, "TOPLEFT", size - dashThick, -(dist - size))
        elseif dist < size * 3 then
            tex:SetSize(dashLen, dashThick)
            tex:SetPoint("TOPLEFT", container, "TOPLEFT", size - (dist - size * 2) - dashLen, -(size - dashThick))
        else
            tex:SetSize(dashThick, dashLen)
            tex:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(size - (dist - size * 3) - dashLen))
        end
        dashes[#dashes + 1] = tex
    end

    local litSpan = math.max(1, math.floor(n / 3))
    local phase, sinceStep = 0, 0
    local function ApplyPhase()
        for i, tex in ipairs(dashes) do
            tex:SetAlpha(((i - 1 - phase) % n) < litSpan and 1 or 0.15)
        end
    end
    ApplyPhase()
    container:SetScript("OnUpdate", function(_, delta)
        sinceStep = sinceStep + delta
        if sinceStep >= 0.05 then
            sinceStep = 0
            phase = (phase + 1) % n
            ApplyPhase()
        end
    end)
    return container
end

function BuffReminder:SavedPosition()
    local db = self.module.db
    if type(db.icon) ~= "table" then db.icon = {} end
    return db.icon
end

function BuffReminder:ApplyPosition()
    local f = self.frame
    local saved = self:SavedPosition()
    f:ClearAllPoints()
    if saved.point then
        f:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    else
        local d = self.defaultPosition
        f:SetPoint(d[1], UIParent, d[2], d[3], d[4])
    end
end

function BuffReminder:RefreshLook()
    if not self.frame then return end
    local name, icon = self:SpellInfo()
    self.frame.icon:SetTexture(icon)
    self.frame.editPanel:SetLabel(name)
end

function BuffReminder:CreateFrame()
    local reminder = self
    local f = CreateFrame("Frame", "DhoxarModulesReminder_" .. self.key, UIParent)
    f:SetSize(ICON_SIZE, ICON_SIZE)
    f:Hide()
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.selectionBox = CreateEdgeBorder(f, 3, 1, 0.4, 0.7, 1, 0.9)
    f.editPanel = CreateLabelPanel(f)
    f.marchBorder = CreateMarchingDashBorder(f, 4, 4, 2, 2, 1, 0.82, 0.1)

    f.cdTicker = CreateFrame("Frame", nil, f)
    f.cdTicker:SetAllPoints(f)
    f.cdTicker:Hide()
    f.countdownText = f.cdTicker:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.countdownText:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.countdownText:SetFont((f.countdownText:GetFont()), 16, "OUTLINE")
    f.cdTicker:SetScript("OnUpdate", function()
        local left = (f.countdownEnd or 0) - GetTime()
        f.countdownText:SetText(left > 0 and tostring(math.ceil(left)) or "")
    end)

    f:SetMovable(true)
    f:EnableMouse(false)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(frame)
        if reminder.unlocked then frame:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local p, _, rp, x, y = frame:GetPoint()
        local db = reminder.module.db
        db.icon = { point = p, relativePoint = rp, x = x, y = y }
    end)

    self.frame = f
    self:ApplyPosition()
    self:RefreshLook()
end

function BuffReminder:SetShown(show)
    local f = self.frame
    if show then
        if not f:IsShown() then
            f:Show()
            f.marchBorder:Show()
        end
    elseif f:IsShown() then
        f.marchBorder:Hide()
        f:Hide()
    end
end

function BuffReminder:Update()
    local f = self.frame
    if not f or self.unlocked then return end
    local show, expiring, left = false, false, nil
    local wanted = self.inCombat or self.module.db.outOfCombat
    if self.module.active and wanted and self:IsLearned() then
        if not self:HasBuff() then
            show = true
        else
            left = self:TimeLeft()
            if left and left > 0 and left <= WARNING_SECONDS then
                show, expiring = true, true
            end
        end
    end
    if expiring then
        f.countdownEnd = GetTime() + left
        f.cdTicker:Show()
    else
        f.cdTicker:Hide()
    end
    self:SetShown(show)
end

---------------------------------------------------------------------------
-- Unlocking
---------------------------------------------------------------------------

function BuffReminder:Unlock(silent)
    if self.unlocked then return end
    if not self.module.active or not self.frame then
        if not silent then print(self.tag .. "the module is not running. Type /dhoxar list.") end
        return
    end
    self.unlocked = true
    local f = self.frame
    f.cdTicker:Hide()
    f.marchBorder:Hide()
    f:EnableMouse(true)
    f.editPanel:Show()
    f.selectionBox:Show()
    f:Show()
    if not silent then
        print(self.tag .. "unlocked, drag the icon to reposition. Type /dhoxar and click Lock when done.")
    end
end

function BuffReminder:Lock(silent)
    if not self.unlocked then return end
    self.unlocked = false
    local f = self.frame
    f:EnableMouse(false)
    f.editPanel:Hide()
    f.selectionBox:Hide()
    f:Hide()
    self:Update()
    if not silent then print(self.tag .. "locked.") end
end

function BuffReminder:ResetPosition()
    self.module.db.icon = {}
    if self.frame then self:ApplyPosition() end
    print(self.tag .. "position reset.")
end

-- Edit Mode has no API to add addon frames, so unlock while it is open.
-- Callbacks stay registered for the session and do nothing while the module is off.
function BuffReminder:HookEditMode()
    local reminder = self
    if EventRegistry and EventRegistry.RegisterCallback then
        local ok = pcall(function()
            EventRegistry:RegisterCallback("EditMode.Enter", function() reminder:Unlock(true) end, reminder)
            EventRegistry:RegisterCallback("EditMode.Exit", function() reminder:Lock(true) end, reminder)
        end)
        if ok then return "EventRegistry" end
    end
    if EditModeManagerFrame then
        local ok = pcall(function()
            EditModeManagerFrame:HookScript("OnShow", function() reminder:Unlock(true) end)
            EditModeManagerFrame:HookScript("OnHide", function() reminder:Lock(true) end)
        end)
        if ok then return "EditModeManagerFrame" end
    end
    return "none"
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function InCombatNow()
    return (type(InCombatLockdown) == "function" and InCombatLockdown()) and true or false
end

function BuffReminder:OnEvent(event, _, _, spellID)
    if event == "PLAYER_REGEN_DISABLED" then
        self.inCombat = true -- no snapshot: the aura is already secret here
    elseif event == "PLAYER_REGEN_ENABLED" then
        self.inCombat = false
        self:Snapshot()
        -- The aura may still read as secret for a moment after combat ends.
        C_Timer.After(1, function()
            if self.module.active and not self.inCombat then
                self:Snapshot()
                self:Update()
            end
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        self.inCombat = InCombatNow()
        self:Snapshot()
    elseif event == "UNIT_AURA" then
        if not self.inCombat then self:Snapshot() end
    elseif event == "SPELLS_CHANGED" then
        self:RefreshLook()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if spellID ~= nil and not isSecret(spellID) and self.idSet[spellID] and not IsAuraReadable(spellID) then
            self:NoteCast()
        end
    end
    self:Update()
end

local EVENTS = {
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED",
}

function BuffReminder:Enable()
    local reminder = self
    if not self.watcher then
        self:CreateFrame()
        self.editModeHook = self:HookEditMode()
        self.watcher = CreateFrame("Frame")
        self.watcher:SetScript("OnEvent", function(_, ...) reminder:OnEvent(...) end)
        -- Safety-net poll for the countdown and predicted expiry.
        local elapsed = 0
        self.watcher:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            if elapsed >= 0.5 then
                elapsed = 0
                reminder:Update()
            end
        end)
    end
    local w = self.watcher
    for _, event in ipairs(EVENTS) do pcall(w.RegisterEvent, w, event) end
    pcall(w.RegisterUnitEvent, w, "UNIT_AURA", "player")
    pcall(w.RegisterUnitEvent, w, "UNIT_SPELLCAST_SUCCEEDED", "player")
    w:Show()
    self:ApplyPosition()
    self:RefreshLook()
    self.inCombat = InCombatNow()
    self:Snapshot()
    self:Update()
end

function BuffReminder:Disable()
    self:Lock(true)
    if self.watcher then
        self.watcher:UnregisterAllEvents()
        self.watcher:Hide()
    end
    self.inCombat = false
    if self.frame then
        self.frame.cdTicker:Hide()
        self:SetShown(false)
    end
end

---------------------------------------------------------------------------
-- Options and debug
---------------------------------------------------------------------------

function BuffReminder:DebugText()
    local name = self:SpellInfo()
    local left = self:TimeLeft()
    local lines = {
        ("%s: moduleActive=%s, inCombat=%s, editModeHook=%s"):format(
            name, tostring(self.module.active), tostring(self.inCombat), self.editModeHook),
        ("learned=%s (best id %s), hasBuff=%s, preCombatHasBuff=%s"):format(
            tostring(self:IsLearned()), tostring(BestKnownSpell(self.ids)), tostring(self:HasBuff()), tostring(self.preCombatHasBuff)),
        ("timeLeft=%s (countdown at %ds or less), lastDuration=%s, predictedExpiryIn=%s"):format(
            left and ("%.0f"):format(left) or "unknown", WARNING_SECONDS, tostring(self.lastDuration),
            self.buffExpiry and ("%.0f"):format(self.buffExpiry - GetTime()) or "n/a"),
        "",
        "per-id lookup (shouldBeSecret / call ok / result):",
    }
    for _, id in ipairs(self.ids) do
        local secret = "n/a"
        if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
            local ok, s = pcall(C_Secrets.ShouldSpellAuraBeSecret, id)
            secret = ok and (isSecret(s) and "SECRET" or tostring(s)) or "error"
        end
        local ok, result = false, nil
        if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
            ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        end
        local described = result == nil and "nil" or (isSecret(result) and "SECRET" or type(result))
        lines[#lines + 1] = ("  %d: secret=%s, ok=%s, result=%s"):format(id, secret, tostring(ok), described)
    end
    return table.concat(lines, "\n")
end

function BuffReminder:BuildOptions(page)
    local reminder = self
    local db = self.module.db
    page:Header("Reminder")
    page:Checkbox({
        label = "Also show out of combat",
        description = "By default the icon only shows in combat, like the Battle Shout reminder. Turn this on to see it whenever the buff is missing.",
        get = function() return db.outOfCombat == true end,
        set = function(value)
            db.outOfCombat = value and true or false
            reminder:Update()
        end,
    })

    page:Header("Icon")
    page:Button({
        label = "Icon position",
        description = "Unlocks the icon so you can drag it. This window closes so it is not hidden behind it; type /dhoxar and click Lock when done. Opening Edit Mode also unlocks it.",
        text = function() return reminder.unlocked and "Lock" or "Unlock" end,
        onClick = function()
            if reminder.unlocked then
                reminder:Lock(false)
            else
                reminder:Unlock(false)
                if reminder.unlocked then ns.Options:Close() end
            end
        end,
    })
    page:Button({
        label = "Reset position",
        description = "Moves the icon back to its default position.",
        text = "Reset",
        onClick = function() reminder:ResetPosition() end,
    })

    page:Header("Troubleshooting")
    page:Button({
        label = "Debug info",
        description = "Opens a window with the reminder's current state, to copy into a bug report.",
        text = "Show",
        onClick = function() ns.Util.ShowCopyableText(reminder.module.title .. " debug", reminder:DebugText()) end,
    })
end
