-- Module: Simple Warrior Reminders
--
-- In-combat reminder icons with a marching-dash border: Battle Shout
-- missing/expiring, Overpower/Revenge ready, Execute ready, Victory Rush
-- ready. Each reminder can be turned off on the module's options page, and
-- the icons are draggable from there or while Blizzard's Edit Mode is open.
--
-- Aura detection mirrors EllesmereUI AuraBuff Reminders: never enumerate auras
-- (index/slot scans and AuraUtil hard-error under the secret-value system).
-- Instead do a targeted C_UnitAuras.GetPlayerAuraBySpellID(id) lookup, which
-- works in combat for whitelisted "non-secret" IDs like Battle Shout, and
-- fall back to a snapshot taken right before combat if the live query fails.
--
-- The same file runs on clients without the secret-value system (e.g. TBC
-- Anniversary): there every read is plain, so the fallbacks never kick in.

local _, ns = ...

local isSecret = ns.Util.IsSecret
local ToSet = ns.Util.ToSet

local M = ns:RegisterModule({
    key = "WarriorReminders",
    title = "Simple Warrior Reminders",
    description = "In-combat reminder icons: Battle Shout missing or about to fade, Overpower/Revenge ready, Execute ready, Victory Rush ready. Warriors only.",
    class = "WARRIOR",
    aliases = { "reminders" },
    defaults = {
        icons = {},
        -- Which reminders the user wants; see IsReminderOn.
        reminders = { shout = true, overpower = true, revenge = true, execute = true, victoryrush = true },
    },
    legacy = { addon = "SimpleWarriorReminders", savedVariable = "SimpleWarriorRemindersDB" },
})

local TAG = "|cffff4444Simple Warrior Reminders|r: "

-- Whether the user wants a given reminder. Keys: shout, overpower, revenge,
-- execute, victoryrush. Anything not explicitly switched off is on, so a
-- reminder added later is enabled for existing users.
local function IsReminderOn(key)
    local wanted = M.db.reminders
    return type(wanted) ~= "table" or wanted[key] ~= false
end

local function SetReminderOn(key, on)
    if type(M.db.reminders) ~= "table" then
        M.db.reminders = {}
    end
    M.db.reminders[key] = on and true or false
end

local BATTLE_SHOUT_SPELL_ID = 6673
-- 6673 is the id whitelisted on Midnight-style clients; the rest are the
-- classic per-rank ids, in case this client applies the aura under those.
local BATTLE_SHOUT_IDS = { 6673, 5242, 6192, 11549, 11550, 11551, 25289, 2048, 47436 }

local OVERPOWER_SPELL_ID = 7384
local OVERPOWER_IDS = { 7384, 7887, 11584, 11585 }

local REVENGE_SPELL_ID = 6572
-- Classic ranks 1-6, then TBC ranks 7-8.
local REVENGE_IDS = { 6572, 6574, 7379, 11600, 11601, 25288, 25269, 30357 }

local EXECUTE_SPELL_ID = 5308
-- Classic ranks 1-5, TBC ranks 6-7, then the retail Arms/Fury variants.
local EXECUTE_IDS = { 5308, 20658, 20660, 20661, 20662, 25234, 25236, 163201, 280735 }

local VICTORY_RUSH_SPELL_ID = 34428
-- TBC/retail spell, then the Season of Discovery rune version.
local VICTORY_RUSH_IDS = { 34428, 402927 }

local function GetSpellNameAndIcon(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and info then
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

local SHOUT_NAME, SHOUT_ICON = GetSpellNameAndIcon(BATTLE_SHOUT_SPELL_ID)
SHOUT_NAME = SHOUT_NAME or "Battle Shout"
SHOUT_ICON = SHOUT_ICON or "Interface\\Icons\\Ability_Warrior_BattleShout"

local OVERPOWER_NAME, OVERPOWER_ICON = GetSpellNameAndIcon(OVERPOWER_SPELL_ID)
OVERPOWER_NAME = OVERPOWER_NAME or "Overpower"
OVERPOWER_ICON = OVERPOWER_ICON or "Interface\\Icons\\Ability_MeleeDamage"

local REVENGE_NAME, REVENGE_ICON = GetSpellNameAndIcon(REVENGE_SPELL_ID)
REVENGE_NAME = REVENGE_NAME or "Revenge"
REVENGE_ICON = REVENGE_ICON or "Interface\\Icons\\Ability_Warrior_Revenge"

local EXECUTE_NAME, EXECUTE_ICON = GetSpellNameAndIcon(EXECUTE_SPELL_ID)
EXECUTE_NAME = EXECUTE_NAME or "Execute"
EXECUTE_ICON = EXECUTE_ICON or "Interface\\Icons\\INV_Sword_48"

local VICTORY_RUSH_NAME, VICTORY_RUSH_ICON = GetSpellNameAndIcon(VICTORY_RUSH_SPELL_ID)
VICTORY_RUSH_NAME = VICTORY_RUSH_NAME or "Victory Rush"
VICTORY_RUSH_ICON = VICTORY_RUSH_ICON or "Interface\\Icons\\Ability_Warrior_Devastate"

local SHOUT_ID_SET = ToSet(BATTLE_SHOUT_IDS)

---------------------------------------------------------------------------
-- Spell queries
---------------------------------------------------------------------------

local function HasSpellKnownAPI()
    return type(IsPlayerSpell) == "function" or type(IsSpellKnown) == "function"
        or (C_SpellBook and C_SpellBook.IsSpellKnown) ~= nil
end

local function IsIdKnown(id)
    if type(IsPlayerSpell) == "function" then
        local ok, known = pcall(IsPlayerSpell, id)
        if ok and known == true then
            return true
        end
    end
    if type(IsSpellKnown) == "function" then
        local ok, known = pcall(IsSpellKnown, id)
        if ok and known == true then
            return true
        end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
        if ok and known == true then
            return true
        end
    end
    return false
end

-- Highest-priority known id from the list, or nil if none is learned.
local function FirstKnownSpell(ids)
    if not HasSpellKnownAPI() then
        return ids[1]
    end
    for i = #ids, 1, -1 do
        if IsIdKnown(ids[i]) then
            return ids[i]
        end
    end
end

-- true/false, or nil when the client withholds the answer (secret value).
local function QuerySpellUsable(id)
    if C_Spell and C_Spell.IsSpellUsable then
        local ok, usable = pcall(C_Spell.IsSpellUsable, id)
        if ok and usable ~= nil and not isSecret(usable) then
            return usable and true or false
        end
    end
    if type(IsUsableSpell) == "function" then
        local ok, usable = pcall(IsUsableSpell, id)
        if ok and usable ~= nil and not isSecret(usable) then
            return usable and true or false
        end
    end
    return nil
end

-- Seconds left on the cooldown (0 when ready or only on the GCD), or nil if unreadable.
local function QuerySpellCooldownRemaining(id)
    local start, duration
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, id)
        if ok and info ~= nil and not isSecret(info) and type(info) == "table" then
            start, duration = info.startTime, info.duration
        end
    end
    if start == nil and type(GetSpellCooldown) == "function" then
        local ok, s, d = pcall(GetSpellCooldown, id)
        if ok then
            start, duration = s, d
        end
    end
    if start == nil or duration == nil or isSecret(start) or isSecret(duration) then
        return nil
    end
    if start == 0 or duration <= 1.5 then
        return 0
    end
    return math.max(0, start + duration - GetTime())
end

---------------------------------------------------------------------------
-- Battle Shout
---------------------------------------------------------------------------

-- On this client Battle Shout's aura is "secret" during combat: the lookup
-- succeeds but returns nil whether or not the buff is up. So a nil result is
-- only meaningful when the client says the aura is currently readable.
local function IsAuraReadable(id)
    if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldSpellAuraBeSecret, id)
        if not ok or isSecret(secret) then
            return false
        end
        return secret == false
    end
    return true
end

-- Last aura duration read while readable; used to predict expiry in combat.
local lastDuration = nil

-- Plain buff scan for clients without the by-ID lookup. Only reached when
-- GetPlayerAuraBySpellID is missing - secret-value clients always have it,
-- so this never runs where scans are blocked.
local function ScanForBattleShout()
    if type(UnitBuff) ~= "function" then
        return nil
    end
    for i = 1, 40 do
        local ok, name, _, _, _, duration, expirationTime, _, _, _, spellId = pcall(UnitBuff, "player", i)
        if not ok or not name then
            break
        end
        if SHOUT_ID_SET[spellId] then
            if duration and expirationTime and duration > 0 then
                lastDuration = duration
                return true, expirationTime
            end
            return true
        end
    end
    return false
end

-- Returns state, expirationTime. state: true (buff up), false (confirmed
-- absent) or nil (unreadable right now).
local function QueryBattleShoutAura()
    local getter = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    local unitGetter = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
    if not getter and not unitGetter then
        return ScanForBattleShout()
    end

    local anyReadable = false
    for _, id in ipairs(BATTLE_SHOUT_IDS) do
        if IsAuraReadable(id) then
            local ok, result
            if getter then
                ok, result = pcall(getter, id)
            else
                ok, result = pcall(unitGetter, "player", id)
            end
            if ok then
                anyReadable = true
                -- A non-nil result means the aura exists, even if its fields are secret.
                if result ~= nil then
                    local expiration
                    if not isSecret(result) and type(result) == "table" then
                        local e, d = result.expirationTime, result.duration
                        if e and d and not isSecret(e) and not isSecret(d) and d > 0 then
                            expiration = e
                            lastDuration = d
                        end
                    end
                    return true, expiration
                end
            end
        end
    end
    if anyReadable then
        return false
    end
    return nil
end

local inCombat = false
-- Last buff state read while the aura was readable (assume up until proven
-- otherwise so login/reload never nags), and its predicted expiry time.
local preCombatHasBuff = true
local buffExpiry = nil

local function SnapshotBuff()
    local r, expiration = QueryBattleShoutAura()
    if r ~= nil then
        preCombatHasBuff = r
        buffExpiry = r and expiration or nil
    end
end

local function HasBattleShout()
    local r = QueryBattleShoutAura()
    if r ~= nil then
        return r
    end
    -- Unreadable (in combat): trust the last readable snapshot, and treat
    -- the buff as gone once its known expiry has passed.
    if not preCombatHasBuff then
        return false
    end
    if buffExpiry and GetTime() >= buffExpiry then
        return false
    end
    return true
end

-- Battle Shout cast by the player while the aura is unreadable: mark it up
-- and predict the expiry from the last known duration.
local function NoteShoutCast()
    preCombatHasBuff = true
    buffExpiry = lastDuration and (GetTime() + lastDuration) or nil
end

-- How early the icon appears before the buff fades.
local SHOUT_WARNING_SECONDS = 10

-- Seconds until Battle Shout fades, or nil when it isn't up or the expiry is
-- unknown. Uses the live aura when readable, otherwise the predicted expiry.
local function ShoutTimeLeft()
    local up, expiration = QueryBattleShoutAura()
    if up == false then
        return nil
    end
    if up and expiration then
        return expiration - GetTime()
    end
    if preCombatHasBuff and buffExpiry then
        return buffExpiry - GetTime()
    end
    return nil
end

---------------------------------------------------------------------------
-- Reactive procs (Overpower / Revenge)
---------------------------------------------------------------------------

-- Both are reactive: usable only for a few seconds after a dodge (Overpower,
-- Battle Stance) or a block/dodge/parry (Revenge, Defensive Stance), with
-- enough rage - all of which IsSpellUsable already reflects. The action-bar
-- proc glow event is kept as a fallback in case usability reads come back
-- secret in combat. They share one icon slot; stance makes them exclusive.
-- cooldown: the spell's own cooldown in seconds, used to time it ourselves
-- from the last cast when the client won't report the cooldown in combat.
local REACTIVES = {
    { key = "overpower", name = OVERPOWER_NAME, icon = OVERPOWER_ICON, ids = OVERPOWER_IDS, idSet = ToSet(OVERPOWER_IDS), glow = false, cooldown = 5, lastCast = 0 },
    { key = "revenge", name = REVENGE_NAME, icon = REVENGE_ICON, ids = REVENGE_IDS, idSet = ToSet(REVENGE_IDS), glow = false, cooldown = 5, lastCast = 0 },
}

-- Last-resort check when Execute's usability and glow are both unavailable:
-- an attackable target under 20% health. Skipped if health reads are secret.
local function TargetInExecuteRange()
    if not UnitExists("target") or UnitIsDeadOrGhost("target") or not UnitCanAttack("player", "target") then
        return false
    end
    local hp, maxHp = UnitHealth("target"), UnitHealthMax("target")
    if hp == nil or maxHp == nil or isSecret(hp) or isSecret(maxHp) or maxHp <= 0 then
        return false
    end
    return hp / maxHp < 0.2
end

-- Execute: usable on a target under 20% health in Battle/Berserker Stance
-- with enough rage, which IsSpellUsable reflects. It has its own icon.
local EXECUTE = {
    key = "execute", name = EXECUTE_NAME, icon = EXECUTE_ICON, ids = EXECUTE_IDS, idSet = ToSet(EXECUTE_IDS),
    glow = false, cooldown = 0, lastCast = 0, usableFallback = TargetInExecuteRange,
}

-- Victory Rush: usable for a short window after a kill that grants XP or
-- honor, which IsSpellUsable reflects. It has its own icon.
local VICTORY_RUSH = {
    key = "victoryrush", name = VICTORY_RUSH_NAME, icon = VICTORY_RUSH_ICON, ids = VICTORY_RUSH_IDS, idSet = ToSet(VICTORY_RUSH_IDS),
    glow = false, cooldown = 0, lastCast = 0,
}

local ALL_REACTIVES = { REACTIVES[1], REACTIVES[2], EXECUTE, VICTORY_RUSH }

local function FindReactive(spellID)
    for _, r in ipairs(ALL_REACTIVES) do
        if r.idSet[spellID] then
            return r
        end
    end
end

-- Seconds left on the spell's cooldown: the client's value when readable,
-- otherwise our own timer from the last successful cast.
local function ReactiveCooldownLeft(r, id)
    local remaining = QuerySpellCooldownRemaining(id)
    if remaining ~= nil then
        return remaining, "client"
    end
    return math.max(0, r.lastCast + r.cooldown - GetTime()), "own timer"
end

-- Ready = proc active AND off cooldown. Usability ignores cooldowns, so a
-- proc can be lit during the cooldown; that case stays hidden. A reminder
-- the user switched off is never ready.
local function IsReactiveReady(r)
    if not IsReminderOn(r.key) then
        return false
    end
    local id = FirstKnownSpell(r.ids)
    if not id then
        return false
    end
    local usable = QuerySpellUsable(id)
    if usable == nil then
        usable = r.glow
        if not usable and r.usableFallback then
            local ok, inRange = pcall(r.usableFallback)
            usable = ok and inRange == true
        end
    end
    if not usable then
        return false
    end
    return ReactiveCooldownLeft(r, id) <= 0
end

local function ReadyReactive()
    for _, r in ipairs(REACTIVES) do
        if IsReactiveReady(r) then
            return r
        end
    end
end

---------------------------------------------------------------------------
-- Reminder icons
---------------------------------------------------------------------------

local ICON_SIZE = 35
local unlocked = false

local DEFAULT_POSITIONS = {
    shout = { "CENTER", "CENTER", 0, 150 },
    proc = { "CENTER", "CENTER", 80, 150 },
    execute = { "CENTER", "CENTER", 160, 150 },
    victoryrush = { "CENTER", "CENTER", 240, 150 },
}

-- Saved icon positions, keyed like DEFAULT_POSITIONS.
local function GetSavedIcons()
    if type(M.db.icons) ~= "table" then
        M.db.icons = {}
    end
    return M.db.icons
end

local function ApplyPosition(f)
    local saved = GetSavedIcons()[f.key]
    f:ClearAllPoints()
    if saved and saved.point then
        f:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    else
        local d = DEFAULT_POSITIONS[f.key]
        f:SetPoint(d[1], UIParent, d[2], d[3], d[4])
    end
end

-- Plain 4-edge border, drawn exactly on the outer edge of the given frame.
local function CreateEdgeBorder(parent, outset, thickness, r, g, b, a)
    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", -outset, outset)
    box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", outset, -outset)

    local function Edge()
        local t = box:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(r, g, b, a or 1)
        return t
    end

    local top = Edge()
    top:SetPoint("TOPLEFT", box, "TOPLEFT")
    top:SetPoint("TOPRIGHT", box, "TOPRIGHT")
    top:SetHeight(thickness)

    local bottom = Edge()
    bottom:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT")
    bottom:SetHeight(thickness)

    local left = Edge()
    left:SetPoint("TOPLEFT", box, "TOPLEFT")
    left:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT")
    left:SetWidth(thickness)

    local right = Edge()
    right:SetPoint("TOPRIGHT", box, "TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT")
    right:SetWidth(thickness)

    box:Hide()
    return box
end

-- Blue name-tag panel shown above an icon while repositioning, styled after
-- Blizzard's own Edit Mode selection labels.
local function CreateBlueLabelPanel(parent, text)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetHeight(18)
    panel:SetPoint("BOTTOM", parent, "TOP", 0, 6)

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(panel)
    -- SetGradient's signature differs between clients, so fall back to a flat
    -- blue if the color-object form isn't accepted.
    local gradientOk = false
    if bg.SetGradient and CreateColor then
        bg:SetColorTexture(1, 1, 1, 1)
        gradientOk = pcall(bg.SetGradient, bg, "HORIZONTAL",
            CreateColor(0.06, 0.20, 0.42, 0.92), CreateColor(0.12, 0.34, 0.62, 0.92))
    end
    if not gradientOk then
        bg:SetColorTexture(0.08, 0.26, 0.5, 0.9)
    end

    local border = CreateEdgeBorder(panel, 0, 1, 0.4, 0.7, 1, 0.9)
    border:Show()

    local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER", panel, "CENTER", 0, 0)
    fs:SetText(text)
    fs:SetTextColor(1, 1, 1)

    panel:SetWidth(fs:GetStringWidth() + 16)
    panel:Hide()
    return panel
end

-- Marching-ants reminder border: small dashes placed around the icon's
-- perimeter, with a moving "lit" window that circulates continuously to
-- look like dashes running around the icon. WoW stops calling OnUpdate on a
-- hidden frame, so this costs nothing while the reminder isn't showing.
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
            -- top edge, left to right
            tex:SetSize(dashLen, dashThick)
            tex:SetPoint("TOPLEFT", container, "TOPLEFT", dist, 0)
        elseif dist < size * 2 then
            local t = dist - size
            -- right edge, top to bottom
            tex:SetSize(dashThick, dashLen)
            tex:SetPoint("TOPLEFT", container, "TOPLEFT", size - dashThick, -t)
        elseif dist < size * 3 then
            local t = dist - size * 2
            -- bottom edge, right to left
            tex:SetSize(dashLen, dashThick)
            tex:SetPoint("TOPLEFT", container, "TOPLEFT", size - t - dashLen, -(size - dashThick))
        else
            local t = dist - size * 3
            -- left edge, bottom to top
            tex:SetSize(dashThick, dashLen)
            tex:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(size - t - dashLen))
        end

        dashes[#dashes + 1] = tex
    end

    local litSpan = math.max(1, math.floor(n / 3))
    local phase = 0
    local sinceLastStep = 0
    local STEP_INTERVAL = 0.05

    local function ApplyPhase()
        for i, tex in ipairs(dashes) do
            local rel = (i - 1 - phase) % n
            tex:SetAlpha(rel < litSpan and 1 or 0.15)
        end
    end
    ApplyPhase()

    container:SetScript("OnUpdate", function(_, delta)
        sinceLastStep = sinceLastStep + delta
        if sinceLastStep >= STEP_INTERVAL then
            sinceLastStep = 0
            phase = (phase + 1) % n
            ApplyPhase()
        end
    end)

    return container
end

local function CreateReminderIcon(key, texture, label)
    local f = CreateFrame("Frame", "DhoxarModulesReminder_" .. key, UIParent)
    f.key = key
    f:SetSize(ICON_SIZE, ICON_SIZE)
    f:Hide()

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexture(texture)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.selectionBox = CreateEdgeBorder(f, 3, 1, 0.4, 0.7, 1, 0.9)
    f.editPanel = CreateBlueLabelPanel(f, label)
    f.marchBorder = CreateMarchingDashBorder(f, 4, 4, 2, 2, 1, 0.82, 0.1)

    f:SetMovable(true)
    f:EnableMouse(false)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if unlocked then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        GetSavedIcons()[self.key] = { point = p, relativePoint = rp, x = x, y = y }
    end)

    ApplyPosition(f)
    return f
end

-- Frames are built the first time the module is enabled (see Setup).
local ICONS = {}
local shoutIcon, procIcon, executeIcon, victoryRushIcon

local function CreateIcons()
    ICONS = {
        CreateReminderIcon("shout", SHOUT_ICON, SHOUT_NAME),
        CreateReminderIcon("proc", OVERPOWER_ICON, OVERPOWER_NAME .. " / " .. REVENGE_NAME),
        CreateReminderIcon("execute", EXECUTE_ICON, EXECUTE_NAME),
        CreateReminderIcon("victoryrush", VICTORY_RUSH_ICON, VICTORY_RUSH_NAME),
    }
    shoutIcon, procIcon, executeIcon, victoryRushIcon = ICONS[1], ICONS[2], ICONS[3], ICONS[4]

    -- Countdown in the middle of the Battle Shout icon; the ticker that
    -- updates it only runs while shown.
    shoutIcon.cdTicker = CreateFrame("Frame", nil, shoutIcon)
    shoutIcon.cdTicker:SetAllPoints(shoutIcon)
    shoutIcon.cdTicker:Hide()
    shoutIcon.countdownText = shoutIcon.cdTicker:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    shoutIcon.countdownText:SetPoint("CENTER", shoutIcon, "CENTER", 0, 0)
    local file = shoutIcon.countdownText:GetFont()
    shoutIcon.countdownText:SetFont(file, 16, "OUTLINE")
    shoutIcon.cdTicker:SetScript("OnUpdate", function()
        local left = (shoutIcon.countdownEnd or 0) - GetTime()
        shoutIcon.countdownText:SetText(left > 0 and tostring(math.ceil(left)) or "")
    end)
end

local function SetReminderShown(f, show)
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

-- Battle Shout icon: shown when the buff is missing, or with a countdown
-- during its last SHOUT_WARNING_SECONDS.
local function UpdateShoutIcon()
    local show, expiring, left = false, false, nil
    if inCombat and IsReminderOn("shout") and FirstKnownSpell(BATTLE_SHOUT_IDS) ~= nil then
        if not HasBattleShout() then
            show = true
        else
            left = ShoutTimeLeft()
            if left and left > 0 and left <= SHOUT_WARNING_SECONDS then
                show, expiring = true, true
            end
        end
    end
    if expiring then
        shoutIcon.countdownEnd = GetTime() + left
        shoutIcon.cdTicker:Show()
    else
        shoutIcon.cdTicker:Hide()
    end
    SetReminderShown(shoutIcon, show)
end

local function UpdateVisibility()
    if unlocked or not shoutIcon then
        return
    end
    UpdateShoutIcon()
    local ready = inCombat and ReadyReactive() or nil
    if ready and procIcon.current ~= ready then
        procIcon.current = ready
        procIcon.icon:SetTexture(ready.icon)
    end
    SetReminderShown(procIcon, ready ~= nil)
    SetReminderShown(executeIcon, inCombat and IsReactiveReady(EXECUTE))
    SetReminderShown(victoryRushIcon, inCombat and IsReactiveReady(VICTORY_RUSH))
end

local function EnterUnlockMode(silent)
    if unlocked then
        return
    end
    if not M.active then
        if not silent then
            print(TAG .. "the module is not running. Type /dhoxar list.")
        end
        return
    end
    unlocked = true
    shoutIcon.cdTicker:Hide()
    for _, f in ipairs(ICONS) do
        f:EnableMouse(true)
        f.marchBorder:Hide()
        f.editPanel:Show()
        f.selectionBox:Show()
        f:Show()
    end
    if not silent then
        print(TAG .. "unlocked, drag the icons to reposition. Click Unlock / Lock in the options again when done.")
    end
end

local function EnterLockMode(silent)
    if not unlocked then
        return
    end
    unlocked = false
    for _, f in ipairs(ICONS) do
        f:EnableMouse(false)
        f.editPanel:Hide()
        f.selectionBox:Hide()
        f:Hide()
    end
    UpdateVisibility()
    if not silent then
        print(TAG .. "locked.")
    end
end

local function ResetPositions()
    M.db.icons = {}
    for _, f in ipairs(ICONS) do
        ApplyPosition(f)
    end
    print(TAG .. "positions reset.")
end

---------------------------------------------------------------------------
-- Edit Mode integration
---------------------------------------------------------------------------
-- Blizzard's Edit Mode has no public API for addons to register new movable
-- frames into its panel, so these can't appear as a listed "system" there.
-- Instead, piggyback on it being open: unlock automatically when Edit Mode
-- opens and lock again when it closes. The callbacks stay registered for the
-- session and do nothing while the module is off.

local editModeOwner = {}

local function TryHookEditMode()
    if EventRegistry and EventRegistry.RegisterCallback then
        local ok = pcall(function()
            EventRegistry:RegisterCallback("EditMode.Enter", function()
                EnterUnlockMode(true)
            end, editModeOwner)
            EventRegistry:RegisterCallback("EditMode.Exit", function()
                EnterLockMode(true)
            end, editModeOwner)
        end)
        if ok then
            return "EventRegistry"
        end
    end
    if EditModeManagerFrame then
        local ok = pcall(function()
            EditModeManagerFrame:HookScript("OnShow", function()
                EnterUnlockMode(true)
            end)
            EditModeManagerFrame:HookScript("OnHide", function()
                EnterLockMode(true)
            end)
        end)
        if ok then
            return "EditModeManagerFrame"
        end
    end
    return "none"
end

local editModeHookKind = "not hooked yet"

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local watcher
local registeredEvents = {}

-- Some events may not exist on this client; registering an unknown one errors.
local function SafeRegister(event, unit)
    local ok
    if unit then
        ok = pcall(watcher.RegisterUnitEvent, watcher, event, unit)
    else
        ok = pcall(watcher.RegisterEvent, watcher, event)
    end
    registeredEvents[event] = ok
end

local function RegisterEvents()
    SafeRegister("PLAYER_REGEN_DISABLED")
    SafeRegister("PLAYER_REGEN_ENABLED")
    SafeRegister("PLAYER_ENTERING_WORLD")
    SafeRegister("SPELLS_CHANGED")
    SafeRegister("UNIT_AURA", "player")
    SafeRegister("UNIT_SPELLCAST_SUCCEEDED", "player")
    SafeRegister("SPELL_UPDATE_USABLE")
    SafeRegister("SPELL_UPDATE_COOLDOWN")
    SafeRegister("ACTIONBAR_UPDATE_USABLE")
    SafeRegister("UPDATE_SHAPESHIFT_FORM")
    SafeRegister("PLAYER_TARGET_CHANGED")
    SafeRegister("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    SafeRegister("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
end

local function IsInCombatNow()
    return (type(InCombatLockdown) == "function" and InCombatLockdown()) and true or false
end

local function OnEvent(_, event, arg1, _, arg3)
    if event == "PLAYER_REGEN_DISABLED" then
        -- No snapshot here: the aura is already secret at this point.
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        for _, r in ipairs(ALL_REACTIVES) do
            r.glow = false
        end
        SnapshotBuff()
        -- The aura may still read as secret for a moment after combat ends.
        C_Timer.After(1, function()
            if M.active and not inCombat then
                SnapshotBuff()
                UpdateVisibility()
            end
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        inCombat = IsInCombatNow()
        SnapshotBuff()
    elseif event == "UNIT_AURA" then
        if not inCombat then
            SnapshotBuff()
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local spellID = arg3
        if spellID ~= nil and not isSecret(spellID) then
            if SHOUT_ID_SET[spellID] and not IsAuraReadable(BATTLE_SHOUT_SPELL_ID) then
                NoteShoutCast()
            else
                local r = FindReactive(spellID)
                if r then
                    r.glow = false
                    r.lastCast = GetTime()
                end
            end
        end
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        if arg1 ~= nil and not isSecret(arg1) then
            local r = FindReactive(arg1)
            if r then
                r.glow = (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
            end
        end
    end
    UpdateVisibility()
end

-- Safety-net poll while in combat; fast enough for Overpower's short window.
local elapsedSinceCheck = 0
local function OnUpdate(_, elapsed)
    if not inCombat then
        return
    end
    elapsedSinceCheck = elapsedSinceCheck + elapsed
    if elapsedSinceCheck >= 0.2 then
        elapsedSinceCheck = 0
        UpdateVisibility()
    end
end

---------------------------------------------------------------------------
-- Debug dump
---------------------------------------------------------------------------

local function Describe(v)
    if v == nil then
        return "nil"
    end
    if isSecret(v) then
        return "SECRET"
    end
    if type(v) == "table" then
        return "table"
    end
    return tostring(v)
end

local function DescribeRawUsable(id)
    local parts = {}
    if C_Spell and C_Spell.IsSpellUsable then
        local ok, usable, noPower = pcall(C_Spell.IsSpellUsable, id)
        parts[#parts + 1] = ("C_Spell.IsSpellUsable ok=%s usable=%s noPower=%s"):format(tostring(ok), Describe(usable), Describe(noPower))
    end
    if type(IsUsableSpell) == "function" then
        local ok, usable, noPower = pcall(IsUsableSpell, id)
        parts[#parts + 1] = ("IsUsableSpell ok=%s usable=%s noPower=%s"):format(tostring(ok), Describe(usable), Describe(noPower))
    end
    if #parts == 0 then
        return "no usability API"
    end
    return table.concat(parts, "; ")
end

local function DescribeRawCooldown(id)
    local parts = {}
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, id)
        if ok and type(info) == "table" and not isSecret(info) then
            parts[#parts + 1] = ("C_Spell.GetSpellCooldown start=%s duration=%s isEnabled=%s isActive=%s now=%.1f"):format(
                Describe(info.startTime), Describe(info.duration), Describe(info.isEnabled), Describe(info.isActive), GetTime())
        else
            parts[#parts + 1] = ("C_Spell.GetSpellCooldown ok=%s result=%s"):format(tostring(ok), Describe(info))
        end
    end
    if type(GetSpellCooldown) == "function" then
        local ok, s, d = pcall(GetSpellCooldown, id)
        parts[#parts + 1] = ("GetSpellCooldown ok=%s start=%s duration=%s"):format(tostring(ok), Describe(s), Describe(d))
    end
    -- Newer clients expose cooldowns as duration objects meant to be fed
    -- straight into a Cooldown widget when the raw numbers are secret.
    parts[#parts + 1] = ("GetSpellCooldownDuration=%s"):format(
        tostring(C_Spell ~= nil and C_Spell.GetSpellCooldownDuration ~= nil))
    return table.concat(parts, "\n  ")
end

local function BuildDebugText()
    local lines = {
        ("moduleActive=%s, inCombat=%s, editModeHook=%s"):format(tostring(M.active), tostring(inCombat), editModeHookKind),
        "",
        "== Battle Shout ==",
        ("reminderOn=%s, learned=%s, hasBuff=%s, preCombatHasBuff=%s"):format(
            tostring(IsReminderOn("shout")), tostring(FirstKnownSpell(BATTLE_SHOUT_IDS) ~= nil), tostring(HasBattleShout()), tostring(preCombatHasBuff)),
        ("timeLeft=%s (icon shows at %ds or less)"):format(
            ShoutTimeLeft() and ("%.0f"):format(ShoutTimeLeft()) or "unknown", SHOUT_WARNING_SECONDS),
        ("auraReadable=%s, lastDuration=%s, secondsUntilPredictedExpiry=%s"):format(
            tostring(IsAuraReadable(BATTLE_SHOUT_SPELL_ID)), tostring(lastDuration),
            buffExpiry and ("%.0f"):format(buffExpiry - GetTime()) or "n/a"),
    }
    for _, r in ipairs(ALL_REACTIVES) do
        local id = FirstKnownSpell(r.ids)
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("== %s =="):format(r.name)
        lines[#lines + 1] = ("reminderOn=%s, knownId=%s, ready=%s, procGlow=%s"):format(
            tostring(IsReminderOn(r.key)), tostring(id), tostring(IsReactiveReady(r)), tostring(r.glow))
        if id then
            local left, source = ReactiveCooldownLeft(r, id)
            lines[#lines + 1] = ("usable=%s, cooldownLeft=%.1f (from %s)"):format(tostring(QuerySpellUsable(id)), left, source)
            lines[#lines + 1] = "  " .. DescribeRawUsable(id)
            lines[#lines + 1] = "  " .. DescribeRawCooldown(id)
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("events: SPELL_UPDATE_USABLE=%s, SPELL_ACTIVATION_OVERLAY_GLOW_SHOW=%s"):format(
        tostring(registeredEvents.SPELL_UPDATE_USABLE), tostring(registeredEvents.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW))
    lines[#lines + 1] = ""
    lines[#lines + 1] = "== Battle Shout per-id lookup (shouldBeSecret / call ok / result) =="
    for _, id in ipairs(BATTLE_SHOUT_IDS) do
        local secret = "n/a"
        if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
            local ok, s = pcall(C_Secrets.ShouldSpellAuraBeSecret, id)
            secret = ok and Describe(s) or "error"
        end
        local ok, result = false, nil
        if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
            ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        end
        lines[#lines + 1] = ("  %d: secret=%s, ok=%s, result=%s"):format(id, secret, tostring(ok), ok and Describe(result) or tostring(result))
    end
    return table.concat(lines, "\n")
end

local function ShowDebug()
    ns.Util.ShowCopyableText(M.title .. " debug", BuildDebugText())
end

---------------------------------------------------------------------------
-- Module interface
---------------------------------------------------------------------------

local function Setup()
    if watcher then return end
    CreateIcons()
    editModeHookKind = TryHookEditMode()
    watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", OnEvent)
    watcher:SetScript("OnUpdate", OnUpdate)
end

function M:OnEnable()
    Setup()
    for _, f in ipairs(ICONS) do
        ApplyPosition(f)
    end
    RegisterEvents()
    inCombat = IsInCombatNow()
    SnapshotBuff()
    UpdateVisibility()
end

function M:OnDisable()
    EnterLockMode(true)
    if watcher then watcher:UnregisterAllEvents() end
    inCombat = false
    for _, r in ipairs(ALL_REACTIVES) do
        r.glow = false
    end
    UpdateVisibility() -- out of combat, so this hides every icon
end

-- One checkbox per reminder, in the order shown on the options page.
local REMINDER_OPTIONS = {
    { key = "shout", name = SHOUT_NAME, tooltip = "Shows an icon in combat when Battle Shout is missing, and a countdown during its last 10 seconds." },
    { key = "overpower", name = OVERPOWER_NAME, tooltip = "Shows an icon in combat when Overpower is usable and off cooldown." },
    { key = "revenge", name = REVENGE_NAME, tooltip = "Shows an icon in combat when Revenge is usable and off cooldown. Shares its icon slot with Overpower." },
    { key = "execute", name = EXECUTE_NAME, tooltip = "Shows an icon in combat when Execute is usable on your target." },
    { key = "victoryrush", name = VICTORY_RUSH_NAME, tooltip = "Shows an icon in combat when Victory Rush is usable." },
}

function M:BuildOptions(page)
    for _, option in ipairs(REMINDER_OPTIONS) do
        local key = option.key
        page:Checkbox("REMINDERS_" .. key, option.name .. " reminder", option.tooltip, true,
            function() return IsReminderOn(key) end,
            function(value)
                SetReminderOn(key, value)
                if M.active then UpdateVisibility() end
            end)
    end

    page:Button("Icon positions", "Unlock / Lock", function()
        if unlocked then
            EnterLockMode(false)
        else
            EnterUnlockMode(false)
        end
    end, "Unlocks the reminder icons so you can drag them; click again to lock. Close this panel to see them. Opening Edit Mode also unlocks them.")
    page:Button("Reset positions", "Reset", ResetPositions,
        "Moves every reminder icon back to its default position.")
    page:Button("Debug info", "Show", ShowDebug,
        "Opens a window with the module's current state, to copy into a bug report.")
end

-- Copies icon positions saved by the standalone addon, including its two
-- older layouts: 1.0 kept the single icon's position at the top level, and
-- 1.1 called the proc slot "overpower".
function M:ImportLegacy(old)
    local oldIcons = type(old.icons) == "table" and old.icons or {}
    local icons = GetSavedIcons()
    for key in pairs(DEFAULT_POSITIONS) do
        local source = oldIcons[key]
        if not source and key == "proc" then
            source = oldIcons.overpower
        end
        if not source and key == "shout" and old.point then
            source = old
        end
        if type(source) == "table" and source.point and icons[key] == nil then
            icons[key] = { point = source.point, relativePoint = source.relativePoint, x = source.x, y = source.y }
        end
    end
end
