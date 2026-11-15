# Dhoxar Modules

A single World of Warcraft addon that bundles several small UI modules behind one options panel.

Built for WoW Forever 1.60.1 (interface version `16001`).

| Module | What it does |
| --- | --- |
| Simplified Warrior Ragebar | One centered text (value or percentage) on the Personal Resource Display's health and rage bars. Warriors only. |
| Simple Warrior Reminders | In-combat icons: Battle Shout missing or fading, Overpower/Revenge ready, Execute ready, Victory Rush ready. Warriors only. |
| Quest XP Bar | Shades the XP bar green with the XP your completed quests will award. |

## Install

Copy (or symlink) the `DhoxarModules` folder into `Interface/AddOns`. The folder must keep the name `DhoxarModules`.

Disable the old standalone addons (`SimplifiedWarriorRagebar`, `SimpleWarriorReminders`, `QuestXPBar`). A module refuses to run while its standalone version is loaded. If you log in once with both enabled, the module copies your old settings (icon positions, percentage option) before you disable the standalone addon.

## Use

- `/dhoxar` opens the options panel (also under Interface Options > AddOns > Dhoxar Modules). The main page enables or disables each module; each module has its own sub-page.
- `/dhoxar list`, `/dhoxar enable <module>`, `/dhoxar disable <module>`.

`/dhoxar` is the only slash command; everything else is on the module pages:

| Module page | Options |
| --- | --- |
| Simplified Warrior Ragebar | Show percentage instead of value. |
| Simple Warrior Reminders | A checkbox per reminder (Battle Shout, Overpower, Revenge, Execute, Victory Rush). Buttons to unlock/lock the icons for dragging, reset their positions, and show debug info. Opening Edit Mode also unlocks the icons. |
| Quest XP Bar | Show the completed-quest list when hovering the XP bar. Button to print the list to chat. |

## Layout

```
DhoxarModules/
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
