-- Module: Mage
--
-- Arcane Intellect reminder: an icon in combat when the buff is missing, or
-- with a countdown during its last seconds, like the warrior's Battle Shout
-- reminder. Arcane Brilliance counts too, and so does an Arcane Intellect
-- cast by another mage. The icon shows the best rank you know.
--
-- The tracking and the icon come from Core/BuffReminder.lua.

local _, ns = ...

local M = ns:RegisterModule({
    key = "Mage",
    title = "Mage",
    description = "Arcane Intellect reminder: an icon in combat when Arcane Intellect is missing or about to fade. Mages only.",
    class = "MAGE",
    aliases = { "arcaneintellect", "ai" },
    defaults = { icon = {}, outOfCombat = false },
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

function M:OnEnable() reminder:Enable() end
function M:OnDisable() reminder:Disable() end
function M:BuildOptions(page) reminder:BuildOptions(page) end
