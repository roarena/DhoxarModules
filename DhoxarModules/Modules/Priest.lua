-- Module: Priest
--
-- Power Word: Fortitude reminder: an icon in combat when the buff is
-- missing, or with a countdown during its last seconds, like the warrior's
-- Battle Shout reminder. Prayer of Fortitude counts too, and so does a
-- Fortitude cast by another priest. The icon shows the best rank you know.
--
-- The tracking and the icon come from Core/BuffReminder.lua.

local _, ns = ...

local M = ns:RegisterModule({
    key = "Priest",
    title = "Priest",
    description = "Power Word: Fortitude reminder: an icon in combat when Fortitude is missing or about to fade. Priests only.",
    class = "PRIEST",
    aliases = { "fortitude", "pwf" },
    defaults = { icon = {}, outOfCombat = false },
})

local reminder = ns.BuffReminder.New(M, {
    key = "fortitude",
    -- Lowest priority first: Prayer of Fortitude, then Power Word: Fortitude,
    -- so the icon and name are Power Word: Fortitude when it is known.
    spellIDs = { 21562, 21564, 25392, 1243, 1244, 1245, 2791, 10937, 10938, 25389 },
    fallbackName = "Power Word: Fortitude",
    fallbackIcon = "Interface\\Icons\\Spell_Holy_WordFortitude",
    tag = "|cffffffffPriest|r: ",
})

function M:OnEnable() reminder:Enable() end
function M:OnDisable() reminder:Disable() end
function M:BuildOptions(page) reminder:BuildOptions(page) end
