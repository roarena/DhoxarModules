# Dhoxar Modules

A single World of Warcraft addon that bundles several small UI modules behind one options panel.

| Module | What it does |
| --- | --- |
| Simplified Warrior Ragebar | One centered text (value or percentage) on the Personal Resource Display's health and rage bars. Warriors only. |
| Simple Warrior Reminders | In-combat icons: Battle Shout missing or fading, Overpower/Revenge ready, Execute ready, Victory Rush ready. Warriors only. |
| Quest XP Bar | Shades the XP bar green with the XP your completed quests will award. |

## Install

Copy (or symlink) `addon/DhoxarModules` into `Interface/AddOns`. The folder must keep the name `DhoxarModules`.

Disable the old standalone addons (`SimplifiedWarriorRagebar`, `SimpleWarriorReminders`, `QuestXPBar`). A module refuses to run while its standalone version is loaded. If you log in once with both enabled, the module copies your old settings (icon positions, percentage option) before you disable the standalone addon.

## Use

- `/dhoxar` opens the options panel (also under Interface Options > AddOns > Dhoxar Modules). The main page enables or disables each module; each module has its own sub-page.
- `/dhoxar list`, `/dhoxar enable <module>`, `/dhoxar disable <module>`.
- `/swr unlock | lock | reset | debug` for the reminder icons, `/qxp` for the quest XP report.

## Layout

```
addon/DhoxarModules/
  DhoxarModules.toc
  Core/
    Core.lua      registry, saved variables, start/stop, /dhoxar
    Util.lua      secret-value helpers, copyable text window
    Options.lua   options panel
  Modules/
    WarriorRagebar.lua
    WarriorReminders.lua
    QuestXPBar.lua
```

Settings live in `DhoxarModulesDB.modules[<key>]`.

## Adding a module

1. Create `Modules/MyModule.lua` and add it to the `.toc`.
2. Register it and implement the callbacks you need (the full contract is documented at the top of `Core/Core.lua`):

```lua
local _, ns = ...

local M = ns:RegisterModule({
    key = "MyModule",
    title = "My Module",
    description = "Shown as the tooltip of the enable checkbox.",
    defaults = { someOption = true },
})

function M:OnEnable()  end -- register events, show frames
function M:OnDisable() end -- unregister events, hide frames

function M:BuildOptions(page)
    page:Checkbox("MYMODULE_SOME_OPTION", "Some option", "Tooltip.", true,
        function() return M.db.someOption end,
        function(value) M.db.someOption = value end)
end
```

Hooks installed with `hooksecurefunc` or `HookScript` cannot be removed, so guard them with `if M.active then ... end`.
