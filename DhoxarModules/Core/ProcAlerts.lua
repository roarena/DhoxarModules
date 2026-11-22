-- Dhoxar Modules - proc alerts
--
-- A row of icons, one per active proc (a talent buff on you, or a debuff you
-- put on your target), with the stack count, the time left and the warrior
-- reminders' marching-dash border, the name in the proc's color. Used by the Mage module; any module can use it:
--
--   local procs = ns.ProcAlerts.New(M, {
--       tag = "|cff...Name|r: ",
--       procs = {
--           { key = "fof", name = "Fingers of Frost",   -- English fallback name
--             ids = { ... },                             -- known aura spell ids
--             unit = "player" or "target",               -- where the aura is
--             glow = { "Ice Lance" },                    -- spells whose proc highlight means it is up
--             color = { r, g, b }, icon = "Interface\\Icons\\...",
--             description = "..." },
--       },
--   })
--   M:OnEnable -> procs:Enable(), M:OnDisable -> procs:Disable(),
--   M:BuildOptions(page) -> procs:BuildOptions(page)
--
-- Finding a proc, in order (this client hides most auras in combat):
--   1. its spell ids (plus ids learned below) with the by-id lookup, when the
--      client says that aura is readable;
--   2. its name with C_UnitAuras.GetAuraDataBySpellName; when that returns a
--      readable spell id, the id is saved, so step 1 knows it next time;
--   3. a plain aura scan, on clients without C_UnitAuras;
--   4. the action-bar proc highlight of one of its `glow` spells.
--
-- Saved in the module's db: procs (key -> false when switched off),
-- procPosition, procSize, procSound, procNames, procIds (learned ids).

local _, ns = ...

local isSecret = ns.Util.IsSecret

local ProcAlerts = {}
ProcAlerts.__index = ProcAlerts
ns.ProcAlerts = ProcAlerts

local DEFAULT_POSITION = { "CENTER", "CENTER", 0, -140 }
local DEFAULT_SIZE = 40
local SPACING = 12 -- room for the dashes around each icon
local POLL = 0.1

---------------------------------------------------------------------------
-- Spell and aura queries
---------------------------------------------------------------------------

local function SpellNameAndIcon(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" and not isSecret(info) then return info.name, info.iconID end
    end
    if type(GetSpellInfo) == "function" then
        local ok, name, _, icon = pcall(GetSpellInfo, id)
        if ok and name then return name, icon end
    end
end

local function IsAuraReadable(id)
    if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldSpellAuraBeSecret, id)
        if not ok or isSecret(secret) then return false end
        return secret == false
    end
    return true
end

local function Plain(v)
    if v == nil or isSecret(v) then return nil end
    return v
end

-- Stacks and expiration time from an aura table, where readable.
local function AuraDetails(aura)
    if type(aura) ~= "table" or isSecret(aura) then return nil, nil end
    local stacks = tonumber(Plain(aura.applications))
    local expires = tonumber(Plain(aura.expirationTime))
    local duration = tonumber(Plain(aura.duration))
    if not duration or duration <= 0 then expires = nil end
    return stacks, expires
end

-- A talent's own always-on aura can share the proc's name; procs always
-- have a duration, so a readable duration of 0 is not the proc.
local function IsPassive(aura)
    if type(aura) ~= "table" or isSecret(aura) then return false end
    local duration = Plain(aura.duration)
    return duration == 0
end

---------------------------------------------------------------------------
-- Object
---------------------------------------------------------------------------

function ProcAlerts.New(module, config)
    local self = setmetatable({}, ProcAlerts)
    self.module = module
    self.tag = config.tag or ""
    self.procs = config.procs
    self.glowing = {}   -- spell name -> true while its proc highlight is on
    self.state = {}     -- proc key -> { active, stacks, expires, source }
    self.unlocked = false
    for _, p in ipairs(self.procs) do
        -- Localized names: the client's name for any of its ids, plus the
        -- English one.
        p.names = {}
        for _, id in ipairs(p.ids) do
            local name, icon = SpellNameAndIcon(id)
            if name and not p.names[name] then
                p.names[name] = true
                p.iconTex = p.iconTex or icon
            end
        end
        p.names[p.name] = true
        p.iconTex = p.iconTex or p.icon
        -- glow: spell ids (resolved to the client's names) and/or names.
        p.glowNames = {}
        for _, spell in ipairs(p.glow or {}) do
            local name = type(spell) == "number" and SpellNameAndIcon(spell) or spell
            if type(name) == "string" then p.glowNames[name] = true end
        end
        self.state[p.key] = { active = false }
    end
    return self
end

function ProcAlerts:DB()
    local db = self.module.db
    if type(db.procs) ~= "table" then db.procs = {} end
    if type(db.procIds) ~= "table" then db.procIds = {} end
    return db
end

function ProcAlerts:IsOn(p)
    return self:DB().procs[p.key] ~= false
end

-- The proc's ids plus those learned from name lookups.
function ProcAlerts:Ids(p)
    local learned = self:DB().procIds[p.key]
    if type(learned) ~= "table" then return p.ids end
    local ids = {}
    for _, id in ipairs(p.ids) do ids[#ids + 1] = id end
    for id in pairs(learned) do ids[#ids + 1] = id end
    return ids
end

function ProcAlerts:Learn(p, id)
    id = tonumber(Plain(id))
    if not id then return end
    for _, known in ipairs(p.ids) do
        if known == id then return end
    end
    local db = self:DB()
    db.procIds[p.key] = db.procIds[p.key] or {}
    db.procIds[p.key][id] = true
end

local function Filter(p)
    return p.unit == "target" and "HARMFUL|PLAYER" or "HELPFUL"
end

-- found, stacks, expires, source
function ProcAlerts:Query(p)
    local unit = p.unit or "player"
    local hasUnit = unit == "player" or (UnitExists(unit) and not UnitIsDeadOrGhost(unit))
    local CU = C_UnitAuras

    if hasUnit and CU then
        -- 1. By id.
        local byId = unit == "player" and CU.GetPlayerAuraBySpellID
        if byId then
            for _, id in ipairs(self:Ids(p)) do
                if IsAuraReadable(id) then
                    local ok, aura = pcall(byId, id)
                    if ok and aura ~= nil and not IsPassive(aura) then
                        local stacks, expires = AuraDetails(aura)
                        return true, stacks, expires, "id " .. id
                    end
                end
            end
        end
        -- 2. By name.
        if CU.GetAuraDataBySpellName then
            for name in pairs(p.names) do
                local ok, aura = pcall(CU.GetAuraDataBySpellName, unit, name, Filter(p))
                if ok and aura ~= nil and not IsPassive(aura) then
                    if type(aura) == "table" and not isSecret(aura) then self:Learn(p, aura.spellId) end
                    local stacks, expires = AuraDetails(aura)
                    return true, stacks, expires, "name"
                end
            end
        end
    elseif hasUnit and type(UnitAura) == "function" then
        -- 3. Plain scan (clients without C_UnitAuras, never secret ones).
        local idSet = {}
        for _, id in ipairs(self:Ids(p)) do idSet[id] = true end
        for i = 1, 40 do
            local ok, name, _, count, _, duration, expires, _, _, _, spellId = pcall(UnitAura, unit, i, Filter(p))
            if not ok or not name then break end
            if (p.names[name] or idSet[spellId]) and duration ~= 0 then
                return true, tonumber(count), (duration and duration > 0) and expires or nil, "scan"
            end
        end
    end

    -- 4. Proc highlight on the action bar.
    for spell in pairs(p.glowNames) do
        if self.glowing[spell] then return true, nil, nil, "highlight" end
    end
    return false
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------

function ProcAlerts:Size()
    return math.max(20, math.min(80, tonumber(self.module.db.procSize) or DEFAULT_SIZE))
end

function ProcAlerts:ApplyPosition()
    local f = self.anchor
    local saved = self.module.db.procPosition
    f:ClearAllPoints()
    if type(saved) == "table" and saved.point then
        f:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    else
        local d = DEFAULT_POSITION
        f:SetPoint(d[1], UIParent, d[2], d[3], d[4])
    end
end

local function CreateIcon(parent, p)
    local f = CreateFrame("Frame", nil, parent)
    f.proc = p
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon:SetTexture(p.iconTex or "Interface\\Icons\\INV_Misc_QuestionMark")

    -- The warrior reminders' marching-dash border; the label keeps the
    -- proc's school color.
    local c = p.color or { 1, 0.82, 0 }
    f.marchBorder = ns.Util.MarchingBorder(f)
    f.marchBorder:Show()

    f.time = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.time:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 2)
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("TOP", f, "BOTTOM", 0, -8) -- below the dashes
    f.label:SetTextColor(c[1], c[2], c[3])
    f.label:SetText(p.name)
    f:Hide()
    return f
end

function ProcAlerts:CreateFrames()
    local alerts = self
    local anchor = CreateFrame("Frame", "DhoxarModulesProcAlerts_" .. self.module.key, UIParent)
    anchor:SetSize(DEFAULT_SIZE, DEFAULT_SIZE)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function(f) if alerts.unlocked then f:StartMoving() end end)
    anchor:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local p, _, rp, x, y = f:GetPoint()
        alerts.module.db.procPosition = { point = p, relativePoint = rp, x = x, y = y }
    end)
    -- Setting drag scripts can turn the mouse on; it stays off until unlocked
    -- so the alerts never block clicks on the world.
    anchor:EnableMouse(false)
    -- Shown while unlocked, to show what can be dragged.
    anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
    anchor.bg:SetPoint("TOPLEFT", anchor, "TOPLEFT", -6, 6)
    anchor.bg:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 6, -20)
    anchor.bg:SetColorTexture(0.08, 0.26, 0.5, 0.5)
    anchor.bg:Hide()
    self.anchor = anchor
    self.icons = {}
    for _, p in ipairs(self.procs) do
        self.icons[#self.icons + 1] = CreateIcon(anchor, p)
    end
    self:ApplyPosition()
end

-- Lays out the shown icons in a row, centered on the anchor.
function ProcAlerts:Layout(shown)
    local size = self:Size()
    local fontFile = (GameFontHighlightLarge and GameFontHighlightLarge:GetFont()) or STANDARD_TEXT_FONT
    local width = math.max(size, #shown * size + (#shown - 1) * SPACING)
    self.anchor:SetSize(width, size)
    for i, f in ipairs(shown) do
        f:SetSize(size, size)
        f.time:SetFont(fontFile, math.max(10, math.floor(size * 0.4)), "OUTLINE")
        f.label:SetShown(self.module.db.procNames ~= false)
        f:ClearAllPoints()
        f:SetPoint("LEFT", self.anchor, "LEFT", (i - 1) * (size + SPACING), 0)
    end
end

local function FormatLeft(left)
    if not left or left <= 0 then return "" end
    if left < 3 then return ("%.1f"):format(left) end
    return tostring(math.ceil(left))
end

function ProcAlerts:Update()
    if not self.anchor then return end
    local shown = {}
    local newlyActive = false
    for i, p in ipairs(self.procs) do
        local f = self.icons[i]
        local st = self.state[p.key]
        local active, stacks, expires, source = false, nil, nil, nil
        if self.unlocked then
            -- Preview: every enabled alert, with sample numbers.
            active, stacks, expires = self:IsOn(p), (p.key == self.procs[1].key) and 2 or nil, GetTime() + 8
        elseif self.module.active and self:IsOn(p) then
            active, stacks, expires, source = self:Query(p)
        end
        if active and not st.active and not self.unlocked then newlyActive = true end
        st.active, st.stacks, st.expires, st.source = active, stacks, expires, source
        if active then
            shown[#shown + 1] = f
            f.count:SetText((stacks and stacks > 1) and stacks or "")
            f.time:SetText(FormatLeft(expires and (expires - GetTime())))
            f:Show()
        else
            f:Hide()
        end
    end
    self:Layout(shown)
    if newlyActive and self.module.db.procSound then
        local kit = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959
        pcall(PlaySound, kit, "Master")
    end
end

function ProcAlerts:Unlock()
    if not self.module.active or not self.anchor then
        print(self.tag .. "the module is not running. Type /dhoxar list.")
        return
    end
    self.unlocked = true
    self.anchor:EnableMouse(true)
    self.anchor.bg:Show()
    self:Update()
    print(self.tag .. "proc alerts unlocked: they show as a preview, drag them to move. Type /dhoxar and click Lock when done.")
end

function ProcAlerts:Lock()
    if not self.unlocked then return end
    self.unlocked = false
    self.anchor:EnableMouse(false)
    self.anchor.bg:Hide()
    self:Update()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

function ProcAlerts:OnEvent(event, spellID)
    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        if spellID == nil or isSecret(spellID) then return end
        local name = SpellNameAndIcon(spellID)
        if name then self.glowing[name] = (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW") or nil end
    end
    self:Update()
end

function ProcAlerts:Enable()
    local alerts = self
    if not self.watcher then
        self:CreateFrames()
        self.watcher = CreateFrame("Frame")
        self.watcher:SetScript("OnEvent", function(_, event, arg1) alerts:OnEvent(event, arg1) end)
        -- Timers and procs whose changes send no event the client lets us read.
        local elapsed = 0
        self.watcher:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            if elapsed >= POLL then
                elapsed = 0
                alerts:Update()
            end
        end)
    end
    local w = self.watcher
    for _, e in ipairs({ "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "PLAYER_TARGET_CHANGED" }) do
        pcall(w.RegisterEvent, w, e)
    end
    pcall(w.RegisterUnitEvent, w, "UNIT_AURA", "player", "target")
    w:Show()
    self.anchor:Show()
    self:ApplyPosition()
    self:Update()
end

function ProcAlerts:Disable()
    self:Lock()
    if self.watcher then
        self.watcher:UnregisterAllEvents()
        self.watcher:Hide()
    end
    wipe(self.glowing)
    if self.anchor then
        for _, f in ipairs(self.icons) do f:Hide() end
        self.anchor:Hide()
    end
end

---------------------------------------------------------------------------
-- Options and debug
---------------------------------------------------------------------------

function ProcAlerts:DebugText()
    local lines = { ("moduleActive=%s, unlocked=%s"):format(tostring(self.module.active), tostring(self.unlocked)) }
    local glowing = {}
    for name in pairs(self.glowing) do glowing[#glowing + 1] = name end
    lines[#lines + 1] = "highlighted spells: " .. (#glowing > 0 and table.concat(glowing, ", ") or "none")
    for _, p in ipairs(self.procs) do
        local found, stacks, expires, source = self:Query(p)
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("== %s (%s) =="):format(p.name, p.unit or "player")
        lines[#lines + 1] = ("on=%s, found=%s via %s, stacks=%s, timeLeft=%s"):format(
            tostring(self:IsOn(p)), tostring(found), tostring(source), tostring(stacks),
            expires and ("%.1f"):format(expires - GetTime()) or "n/a")
        local names = {}
        for name in pairs(p.names) do names[#names + 1] = name end
        lines[#lines + 1] = "names: " .. table.concat(names, ", ")
        for _, id in ipairs(self:Ids(p)) do
            local result = "n/a"
            if (p.unit or "player") == "player" and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
                local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
                result = not ok and "error" or (aura == nil and "nil" or (isSecret(aura) and "SECRET" or "aura"))
            end
            lines[#lines + 1] = ("  id %d: readable=%s, lookup=%s"):format(id, tostring(IsAuraReadable(id)), result)
        end
    end
    return table.concat(lines, "\n")
end

function ProcAlerts:BuildOptions(page)
    local alerts = self
    local db = self:DB()
    page:Header("Proc alerts")
    page:Text("An icon shows while a proc is up, with its stacks and time left. Frostbite and Impact are the freeze and stun you put on your target, so they show while your target has them. Only procs from talents you have can show up.")
    for _, p in ipairs(self.procs) do
        page:Checkbox({
            label = p.name,
            description = p.description,
            get = function() return alerts:IsOn(p) end,
            set = function(value)
                db.procs[p.key] = value and true or false
                alerts:Update()
            end,
        })
    end
    page:Checkbox({
        label = "Play a sound",
        description = "A short alert sound when a proc comes up.",
        get = function() return db.procSound == true end,
        set = function(value) db.procSound = value and true or false end,
    })
    page:Checkbox({
        label = "Show names",
        description = "The proc's name under its icon.",
        get = function() return db.procNames ~= false end,
        set = function(value) db.procNames = value and true or false; alerts:Update() end,
    })
    page:Slider({
        label = "Icon size",
        min = 24, max = 80, step = 2,
        get = function() return alerts:Size() end,
        set = function(value) db.procSize = value; alerts:Update() end,
        format = function(value) return value .. " px" end,
    })
    page:Button({
        label = "Preview and move",
        description = "Shows every alert that is switched on so you can see them and drag them. This window closes so they are not hidden behind it; type /dhoxar and click Lock when done.",
        text = function() return alerts.unlocked and "Lock" or "Unlock" end,
        onClick = function()
            if alerts.unlocked then
                alerts:Lock()
            else
                alerts:Unlock()
                if alerts.unlocked then ns.Options:Close() end
            end
        end,
    })
    page:Button({
        label = "Reset position",
        description = "Moves the proc alerts back below the middle of the screen.",
        text = "Reset",
        onClick = function()
            db.procPosition = {}
            if alerts.anchor then alerts:ApplyPosition() end
        end,
    })
    page:Button({
        label = "Proc debug info",
        description = "Shows how each proc is being found, to copy into a bug report. Useful with a proc up.",
        text = "Show",
        onClick = function() ns.Util.ShowCopyableText(alerts.module.title .. " proc debug", alerts:DebugText()) end,
    })
end
