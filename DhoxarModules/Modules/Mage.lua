-- Module: Mage
--
-- Arcane Intellect reminder: an icon in combat when the buff is missing, or
-- with a countdown during its last seconds, like the warrior's Battle Shout
-- reminder. Arcane Brilliance counts too, and so does an Arcane Intellect
-- cast by another mage. The icon shows the best rank you know.
--
-- Proc alerts: an icon while a talent proc is up (Fingers of Frost, Heating
-- Up, Missile Barrage, Clearcasting) or while your target has the freeze or
-- stun your talents put on it (Frostbite, Impact).
--
-- The reminder comes from Core/BuffReminder.lua, the alerts from
-- Core/ProcAlerts.lua.

local _, ns = ...

local M = ns:RegisterModule({
    key = "Mage",
    title = "Mage",
    description = "Arcane Intellect reminder and proc alerts (Fingers of Frost, Frostbite, Heating Up, Impact, Missile Barrage, Clearcasting). Mages only.",
    class = "MAGE",
    aliases = { "arcaneintellect", "ai", "procs" },
    defaults = {
        icon = {}, outOfCombat = false,
        procs = {}, procIds = {}, procPosition = {}, procSize = 40, procSound = false, procNames = true,
    },
})

local reminder = ns.BuffReminder.New(M, {
    key = "arcaneintellect",
    -- Lowest priority first: Arcane Brilliance, then Arcane Intellect, so
    -- the icon and name are Arcane Intellect when it is known.
    spellIDs = { 23028, 27127, 1459, 1460, 1461, 10156, 10157, 27126 },
    fallbackName = "Arcane Intellect",
    fallbackIcon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
    tag = "|cff69ccf0Mage|r: ",
})

-- Spell ids are the ones these auras have had in Blizzard's versions of the
-- game; WoW Forever's talents may use others, so every proc is also found by
-- name (and the id it turns out to have is remembered).
local FROST = { 0.45, 0.78, 1 }
local FIRE = { 1, 0.55, 0.1 }
local ARCANE = { 0.82, 0.55, 1 }

local procs = ns.ProcAlerts.New(M, {
    tag = "|cff69ccf0Mage|r: ",
    procs = {
        {
            key = "fingersoffrost", name = "Fingers of Frost", unit = "player",
            ids = { 44544, 74396 }, glow = { 30455, "Ice Lance" }, color = FROST,
            icon = "Interface\\Icons\\Ability_Mage_WintersGrasp",
            description = "Your next spells treat the target as frozen, even bosses: follow up with Ice Lance or a Frost spell for Shatter crits.",
        },
        {
            key = "frostbite", name = "Frostbite", unit = "target",
            ids = { 12494, 378760 }, color = FROST,
            icon = "Interface\\Icons\\Spell_Frost_FrostArmor",
            description = "Your chill froze the target: Ice Lance or Cone of Cold now for Shatter crits. Shows while your target is frozen by it.",
        },
        {
            key = "heatingup", name = "Heating Up", unit = "player",
            ids = { 48107 }, glow = { 11366, "Pyroblast" }, color = FIRE,
            icon = "Interface\\Icons\\Ability_Mage_HotStreak",
            description = "Each stack makes your next Pyroblast 25% faster, up to 3. The stack count shows on the icon: cast Pyroblast at 3, or at 2 when it is about to fade.",
        },
        {
            key = "impact", name = "Impact", unit = "target",
            ids = { 12355 }, color = FIRE,
            icon = "Interface\\Icons\\Spell_Fire_MeteorStorm",
            description = "Your Fire spell stunned the target for 2 seconds. Shows while your target is stunned by it.",
        },
        {
            key = "missilebarrage", name = "Missile Barrage", unit = "player",
            ids = { 44401, 79683 }, glow = { 5143, "Arcane Missiles" }, color = ARCANE,
            icon = "Interface\\Icons\\Ability_Mage_MissileBarrage",
            description = "Your next Arcane Missiles costs no mana and channels twice as fast.",
        },
        {
            key = "clearcasting", name = "Clearcasting", unit = "player",
            ids = { 12536 }, color = ARCANE,
            icon = "Interface\\Icons\\Spell_Shadow_ManaBurn",
            description = "Arcane Concentration: your next damage spell costs no mana.",
        },
    },
})

function M:OnEnable()
    reminder:Enable()
    procs:Enable()
end

function M:OnDisable()
    reminder:Disable()
    procs:Disable()
end

function M:BuildOptions(page)
    reminder:BuildOptions(page)
    procs:BuildOptions(page)
end
