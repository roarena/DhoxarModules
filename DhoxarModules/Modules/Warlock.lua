-- Module: Warlock
--
-- Demon Skin reminder: an icon in combat when your armor buff is missing,
-- or with a countdown during its last seconds, like the warrior's Battle
-- Shout reminder. Demon Armor (which replaces Demon Skin from level 20) and
-- Fel Armor count too, so a higher-level warlock is not nagged for using
-- the better spell. The icon shows the best rank you know.
--
-- The tracking and the icon come from Core/BuffReminder.lua.

local _, ns = ...

local M = ns:RegisterModule({
    key = "Warlock",
    title = "Warlock",
    description = "Demon Skin reminder: an icon in combat when Demon Skin (or Demon Armor) is missing or about to fade. Warlocks only.",
    class = "WARLOCK",
    aliases = { "lock", "demonskin" },
    defaults = { icon = {}, outOfCombat = false },
})

local reminder = ns.BuffReminder.New(M, {
    key = "demonskin",
    -- Lowest priority first: Demon Skin, Demon Armor, Fel Armor.
    spellIDs = { 687, 696, 706, 1086, 11733, 11734, 11735, 27260, 28176, 28189 },
    fallbackName = "Demon Skin",
    fallbackIcon = "Interface\\Icons\\Spell_Shadow_RagingScream",
    tag = "|cff9482c9Warlock|r: ",
})

function M:OnEnable() reminder:Enable() end
function M:OnDisable() reminder:Disable() end
function M:BuildOptions(page) reminder:BuildOptions(page) end
