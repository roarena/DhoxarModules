-- Module: Hunter
--
-- Mongoose Bite reminder: an icon in combat while Mongoose Bite is usable
-- (after you dodge an attack) and off cooldown, found the same way as the
-- warrior's Overpower: the client's usability and cooldown, the action-bar
-- proc highlight when those come back secret, and our own cooldown timer
-- from the last cast.
--
-- Aspect reminder: "Missing aspect buff" on the screen while no Aspect is
-- active. Both have the warrior reminders' marching-dash border. Aura reads follow the same
-- rules as the other reminders: a targeted lookup per spell id while the
-- client says the aura is readable, then by name, then the stance bar (some
-- clients put aspects there), then a snapshot taken while it was readable.

local _, ns = ...

local isSecret = ns.Util.IsSecret
local ToSet = ns.Util.ToSet

local TAG = "|cffabd473Hunter|r: "

local M = ns:RegisterModule({
    key = "Hunter",
    title = "Hunter",
    description = "Mongoose Bite reminder (an icon in combat when it is ready) and \"Missing aspect buff\" on the screen when no Aspect is active. Hunters only.",
    class = "HUNTER",
    aliases = { "mongoose", "aspect", "aspects" },
    defaults = {
        reminders = { mongoose = true, aspect = true },
        aspectCombatOnly = false,
        textSize = 28,
        positions = {},
    },
})

---------------------------------------------------------------------------
-- Spells
---------------------------------------------------------------------------

local MONGOOSE_IDS = { 1495, 14269, 14270, 14271, 36916, 53339 }
local MONGOOSE_ID_SET = ToSet(MONGOOSE_IDS)
local MONGOOSE_COOLDOWN = 5

-- Every rank of every aspect, lowest first within each.
local ASPECTS = {
    { name = "Aspect of the Monkey", ids = { 13163 } },
    { name = "Aspect of the Hawk", ids = { 13165, 14318, 14319, 14320, 14321, 14322, 25296, 27044 } },
    { name = "Aspect of the Cheetah", ids = { 5118 } },
    { name = "Aspect of the Pack", ids = { 13159 } },
    { name = "Aspect of the Beast", ids = { 13161 } },
    { name = "Aspect of the Wild", ids = { 20043, 20190, 27045, 49071 } },
    { name = "Aspect of the Viper", ids = { 34074 } },
    { name = "Aspect of the Dragonhawk", ids = { 61846, 61847 } },
}
local ASPECT_IDS = {}
for _, a in ipairs(ASPECTS) do
    for _, id in ipairs(a.ids) do ASPECT_IDS[#ASPECT_IDS + 1] = id end
end
local ASPECT_ID_SET = ToSet(ASPECT_IDS)

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

local function IsIdKnown(id)
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

local function HasSpellKnownAPI()
    return type(IsPlayerSpell) == "function" or type(IsSpellKnown) == "function"
        or (C_SpellBook and C_SpellBook.IsSpellKnown) ~= nil
end

-- Highest known id from the list, or nil if none is learned.
local function BestKnown(ids)
    if not HasSpellKnownAPI() then return ids[#ids] end
    for i = #ids, 1, -1 do
        if IsIdKnown(ids[i]) then return ids[i] end
    end
end

local function KnowsAnyAspect()
    if not HasSpellKnownAPI() then return true end
    for _, id in ipairs(ASPECT_IDS) do
        if IsIdKnown(id) then return true end
    end
    return false
end

-- true/false, or nil when the client withholds the answer.
local function QueryUsable(id)
    if C_Spell and C_Spell.IsSpellUsable then
        local ok, usable = pcall(C_Spell.IsSpellUsable, id)
        if ok and usable ~= nil and not isSecret(usable) then return usable and true or false end
    end
    if type(IsUsableSpell) == "function" then
        local ok, usable = pcall(IsUsableSpell, id)
        if ok and usable ~= nil and not isSecret(usable) then return usable and true or false end
    end
    return nil
end

-- Seconds left on the cooldown (0 when ready or only on the GCD), or nil.
local function QueryCooldownLeft(id)
    local start, duration
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, id)
        if ok and type(info) == "table" and not isSecret(info) then start, duration = info.startTime, info.duration end
    end
    if start == nil and type(GetSpellCooldown) == "function" then
        local ok, s, d = pcall(GetSpellCooldown, id)
        if ok then start, duration = s, d end
    end
    if start == nil or duration == nil or isSecret(start) or isSecret(duration) then return nil end
    if start == 0 or duration <= 1.5 then return 0 end
    return math.max(0, start + duration - GetTime()), duration
end

local function IsAuraReadable(id)
    if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldSpellAuraBeSecret, id)
        if not ok or isSecret(secret) then return false end
        return secret == false
    end
    return true
end

local function InCombat()
    return (type(InCombatLockdown) == "function" and InCombatLockdown()) and true or false
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local state = {
    inCombat = false,
    glow = false,           -- Mongoose Bite highlighted on the action bar
    lastCast = 0,           -- last Mongoose Bite cast, for our own cooldown timer
    learnedCooldown = nil,  -- cooldown last seen while the client reported it
    hasAspect = true,       -- last readable answer; assume up so login never nags
    aspectSource = "not checked yet",
}

local function IsOn(key)
    return M.db.reminders[key] ~= false
end

local function MongooseReady()
    if not IsOn("mongoose") then return false end
    local id = BestKnown(MONGOOSE_IDS)
    if not id then return false end
    local usable = QueryUsable(id)
    if usable == nil then usable = state.glow end
    if not usable then return false end
    local left, duration = QueryCooldownLeft(id)
    if left ~= nil then
        if duration then state.learnedCooldown = duration end
        return left <= 0
    end
    return GetTime() >= state.lastCast + (state.learnedCooldown or MONGOOSE_COOLDOWN)
end

-- true/false, or nil when nothing could be read right now.
local function QueryAspect()
    local getter = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    local anyReadable = false
    if getter then
        for _, id in ipairs(ASPECT_IDS) do
            if IsAuraReadable(id) then
                local ok, aura = pcall(getter, id)
                if ok then
                    anyReadable = true
                    if aura ~= nil then return true, "aura by id " .. id end
                end
            end
        end
    elseif type(UnitBuff) == "function" then
        for i = 1, 40 do
            local ok, name, _, _, _, _, _, _, _, _, spellId = pcall(UnitBuff, "player", i)
            if not ok or not name then break end
            if ASPECT_ID_SET[spellId] then return true, "buff scan" end
        end
        return false, "buff scan"
    end
    -- By name: covers ids this client numbers differently.
    local byName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    if byName then
        for _, a in ipairs(ASPECTS) do
            local name = SpellNameAndIcon(a.ids[1]) or a.name
            local ok, aura = pcall(byName, "player", name, "HELPFUL")
            if ok and aura ~= nil then return true, "aura by name (" .. name .. ")" end
        end
    end
    -- Some clients put aspects on the stance bar.
    if type(GetNumShapeshiftForms) == "function" and type(GetShapeshiftFormInfo) == "function" then
        for i = 1, (GetNumShapeshiftForms() or 0) do
            local ok, _, active, _, spellID = pcall(GetShapeshiftFormInfo, i)
            if ok and active == true and not isSecret(spellID) and spellID and ASPECT_ID_SET[spellID] then
                return true, "stance bar"
            end
        end
    end
    if anyReadable then return false, "aura by id" end
    return nil
end

local function HasAspect()
    local up, source = QueryAspect()
    if up ~= nil then
        state.hasAspect, state.aspectSource = up, source
        return up
    end
    state.aspectSource = "snapshot (auras unreadable right now)"
    return state.hasAspect
end

local function AspectMissing()
    if not IsOn("aspect") or not KnowsAnyAspect() then return false end
    if M.db.aspectCombatOnly and not state.inCombat then return false end
    if UnitIsDeadOrGhost("player") then return false end
    if UnitOnTaxi and UnitOnTaxi("player") then return false end
    if UnitInVehicle and UnitInVehicle("player") then return false end
    return not HasAspect()
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local DEFAULT_POSITIONS = {
    mongoose = { "CENTER", "CENTER", -60, 150 },
    aspect = { "CENTER", "CENTER", 0, 220 },
}
local ICON_SIZE = 35 -- same as the warrior icons
local frames = {}
local unlocked = false

local function ApplyPosition(key)
    local f = frames[key]
    f:ClearAllPoints()
    local saved = M.db.positions[key]
    if type(saved) == "table" and saved.point then
        f:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    else
        local d = DEFAULT_POSITIONS[key]
        f:SetPoint(d[1], UIParent, d[2], d[3], d[4])
    end
end

local function MakeDraggable(f, key)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if unlocked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        M.db.positions[key] = { point = p, relativePoint = rp, x = x, y = y }
    end)
    -- Setting drag scripts can turn the mouse on; it stays off until
    -- unlocked so the reminders never block clicks on the world.
    f:EnableMouse(false)
end

-- Every reminder looks like the warrior's: the gold marching-dash border
-- while shown, and while unlocked a blue outline with a name tag.
local function AddReminderLook(f, label)
    f.marchBorder = ns.Util.MarchingBorder(f)
    f.marchBorder:Show()
    f.selectionBox = ns.Util.EdgeBorder(f, 3, 1, 0.4, 0.7, 1, 0.9)
    f.editPanel = ns.Util.LabelPanel(f, label)
end

local function CreateMongooseIcon()
    local f = CreateFrame("Frame", "DhoxarModulesHunterMongoose", UIParent)
    f:SetSize(ICON_SIZE, ICON_SIZE)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local id = BestKnown(MONGOOSE_IDS) or MONGOOSE_IDS[1]
    local name, tex = SpellNameAndIcon(id)
    f.icon:SetTexture(tex or "Interface\\Icons\\Ability_Hunter_SwiftStrike")
    AddReminderLook(f, name or "Mongoose Bite")
    MakeDraggable(f, "mongoose")
    f:Hide()
    return f
end

local function CreateAspectText()
    local f = CreateFrame("Frame", "DhoxarModulesHunterAspect", UIParent)
    f:SetSize(320, 50)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.text:SetText("Missing aspect buff")
    f.text:SetTextColor(1, 0.3, 0.2)
    f.text:SetShadowColor(0, 0, 0, 1)
    f.text:SetShadowOffset(2, -2)
    AddReminderLook(f, "Missing aspect")
    MakeDraggable(f, "aspect")
    f:Hide()
    return f
end

local function ApplyTextSize()
    local f = frames.aspect
    if not f then return end
    local size = math.max(14, math.min(60, tonumber(M.db.textSize) or 28))
    local file = (GameFontNormalHuge and GameFontNormalHuge:GetFont()) or STANDARD_TEXT_FONT
    f.text:SetFont(file, size, "OUTLINE")
    local w = math.max(120, (f.text:GetStringWidth() or size * 10) + 20)
    f:SetSize(w, size + 16)
end

local function CreateFrames()
    if frames.mongoose then return end
    frames.mongoose = CreateMongooseIcon()
    frames.aspect = CreateAspectText()
    ApplyPosition("mongoose")
    ApplyPosition("aspect")
    ApplyTextSize()
end

local function Update()
    if not frames.mongoose then return end
    local active = M.active
    local showMongoose = active and (unlocked and IsOn("mongoose") or (state.inCombat and MongooseReady()))
    local showAspect = active and (unlocked and IsOn("aspect") or AspectMissing())
    frames.mongoose:SetShown(showMongoose and true or false)
    if showAspect and not frames.aspect:IsShown() then frames.aspect:Show()
    elseif not showAspect then frames.aspect:Hide() end
end

local function Unlock()
    if not M.active or not frames.mongoose then
        print(TAG .. "the module is not running. Type /dhoxar list.")
        return
    end
    unlocked = true
    for _, f in pairs(frames) do
        f:EnableMouse(true)
        f.selectionBox:Show()
        f.editPanel:Show()
    end
    Update()
    print(TAG .. "reminders unlocked: drag them to move. Type /dhoxar and click Lock when done.")
end

local function Lock()
    if not unlocked then return end
    unlocked = false
    for _, f in pairs(frames) do
        f:EnableMouse(false)
        f.selectionBox:Hide()
        f.editPanel:Hide()
    end
    Update()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg1, _, arg3)
    if event == "PLAYER_REGEN_DISABLED" then
        state.inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        state.inCombat = false
        state.glow = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        state.inCombat = InCombat()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local spellID = arg3
        if spellID ~= nil and not isSecret(spellID) then
            if MONGOOSE_ID_SET[spellID] then
                state.glow = false
                state.lastCast = GetTime()
            elseif ASPECT_ID_SET[spellID] then
                -- Casting an aspect turns it on, even while auras are unreadable.
                state.hasAspect = true
            end
        end
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        if arg1 ~= nil and not isSecret(arg1) and MONGOOSE_ID_SET[arg1] then
            state.glow = (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        end
    end
    Update()
end)

local poll = 0
events:SetScript("OnUpdate", function(_, dt)
    poll = poll + dt
    if poll >= 0.2 then
        poll = 0
        if M.active then Update() end
    end
end)
events:Hide()

function M:OnEnable()
    CreateFrames()
    for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
        "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" }) do
        pcall(events.RegisterEvent, events, e)
    end
    pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player")
    pcall(events.RegisterUnitEvent, events, "UNIT_AURA", "player")
    state.inCombat = InCombat()
    events:Show()
    Update()
end

function M:OnDisable()
    Lock()
    events:UnregisterAllEvents()
    events:Hide()
    for _, f in pairs(frames) do f:Hide() end
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

local function DebugText()
    local lines = {}
    local function Add(s) lines[#lines + 1] = s end
    local id = BestKnown(MONGOOSE_IDS)
    Add("Mongoose Bite id: " .. tostring(id))
    if id then
        Add("  usable: " .. tostring(QueryUsable(id)))
        Add("  cooldown left: " .. tostring((QueryCooldownLeft(id))))
    end
    Add("  highlight: " .. tostring(state.glow))
    Add("  last cast: " .. (state.lastCast > 0 and ("%.1fs ago"):format(GetTime() - state.lastCast) or "never"))
    Add("  ready: " .. tostring(MongooseReady()))
    Add("")
    Add("Knows an aspect: " .. tostring(KnowsAnyAspect()))
    local up, source = QueryAspect()
    Add("Aspect up (live read): " .. tostring(up) .. (source and (" via " .. source) or ""))
    Add("Aspect up (used): " .. tostring(HasAspect()) .. " via " .. tostring(state.aspectSource))
    Add("In combat: " .. tostring(state.inCombat))
    return table.concat(lines, "\n")
end

function M:BuildOptions(page)
    page:Header("Reminders")
    page:Checkbox({
        label = "Mongoose Bite",
        description = "An icon in combat when Mongoose Bite is usable (after you dodge an attack) and off cooldown.",
        get = function() return IsOn("mongoose") end,
        set = function(value) M.db.reminders.mongoose = value and true or false Update() end,
    })
    page:Checkbox({
        label = "Missing aspect",
        description = "\"Missing aspect buff\" on the screen, with an animation, while no Aspect is active. Hidden while dead, on a flight path or in a vehicle.",
        get = function() return IsOn("aspect") end,
        set = function(value) M.db.reminders.aspect = value and true or false Update() end,
    })
    page:Checkbox({
        label = "Missing aspect only in combat",
        description = "Show the aspect warning only while you are in combat.",
        get = function() return M.db.aspectCombatOnly == true end,
        set = function(value) M.db.aspectCombatOnly = value and true or false Update() end,
    })
    page:Slider({
        label = "Aspect text size",
        description = "Size of the \"Missing aspect buff\" text.",
        min = 14, max = 60, step = 1,
        get = function() return tonumber(M.db.textSize) or 28 end,
        set = function(value) M.db.textSize = value ApplyTextSize() end,
    })

    page:Header("Position")
    page:Button({
        label = "Move the reminders",
        description = "Shows both reminders so you can drag them. This window closes so they are not hidden behind it; type /dhoxar and click Lock when done.",
        text = function() return unlocked and "Lock" or "Unlock" end,
        onClick = function()
            if unlocked then
                Lock()
            else
                Unlock()
                if unlocked then ns.Options:Close() end
            end
        end,
    })
    page:Button({
        label = "Reset positions",
        description = "Moves both reminders back to their default places.",
        text = "Reset",
        onClick = function()
            M.db.positions = {}
            if frames.mongoose then
                ApplyPosition("mongoose")
                ApplyPosition("aspect")
            end
        end,
    })

    page:Header("Troubleshooting")
    page:Button({
        label = "Debug info",
        description = "Opens a window with what the reminders currently read, to copy into a bug report.",
        text = "Show",
        onClick = function() ns.Util.ShowCopyableText("Hunter debug", DebugText()) end,
    })
end
