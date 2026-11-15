# Dhoxar Modules

A single World of Warcraft addon that bundles several small UI modules behind one configuration window.

Built for WoW Forever 1.60.1 (interface version `16001`).

| Module | What it does |
| --- | --- |
| Warrior | Warriors only, and shown as disabled on other classes. Two features, each with its own switch: **Simplified Warrior Ragebar** (one centered text, value or percentage, on the Personal Resource Display's health and rage bars) and **Simple Warrior Reminders** (in-combat icons: Battle Shout missing or fading, Overpower/Revenge ready, Execute ready, Victory Rush ready). |
| Warlock | In-combat icon when Demon Skin is missing or about to fade (Demon Armor and Fel Armor count too). Warlocks only. |
| Priest | In-combat icon when Power Word: Fortitude is missing or about to fade (Prayer of Fortitude and another priest's Fortitude count too). Priests only. |
| Mage | In-combat icon when Arcane Intellect is missing or about to fade (Arcane Brilliance and another mage's Arcane Intellect count too). Mages only. |
| Quest XP Bar | Shades the XP bar green with the XP your completed quests will award. |
| Quest Item Sparkles | Keeps the loot sparkle on quest items showing: graphics presets turn it off, this turns it back on. Does not change your outline mode. |

## Install

Copy (or symlink) the `DhoxarModules` folder into `Interface/AddOns`. The folder must keep the name `DhoxarModules`.

Disable the old standalone addons (`SimplifiedWarriorRagebar`, `SimpleWarriorReminders`, `QuestXPBar`). A module or feature refuses to run while its standalone version is loaded. If you log in once with both enabled, the module copies your old settings (icon positions, percentage option) before you disable the standalone addon.

## Development

`node scripts/sync-addon.js` mirrors `DhoxarModules` into the game's AddOns folder (`C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns` by default, or `WOW_ADDONS_DIR` if set). Then `/reload` in game. When working with Claude Code, a local hook runs it after every edit to the addon.

## Use

- `/dhoxar` opens or closes the configuration window. Interface Options > AddOns > Dhoxar Modules has a button that opens it too.
- `/dhoxar list`, `/dhoxar enable <module>`, `/dhoxar disable <module>`.

The window has an **Overview** page with a card per module (status, on/off switch, link to its settings) and a page per module in the sidebar. It can be dragged by its title bar, remembers where you left it, and closes with Esc. `/dhoxar` is the only slash command; everything else is on the module pages:

| Module page | Options |
| --- | --- |
| Warrior | Rage bar: on/off, show percentage instead of value. Reminders: on/off, a switch per reminder (Battle Shout, Overpower, Revenge, Execute, Victory Rush). Buttons to unlock/lock the icons for dragging, reset their positions, and show debug info. Opening Edit Mode also unlocks the icons. |
| Warlock, Priest, Mage | Also show the icon out of combat. Buttons to unlock/lock the icon for dragging, reset its position, and show debug info. Opening Edit Mode also unlocks it. |
| Quest XP Bar | Show the completed-quest list when hovering the XP bar. Button to print the list to chat. |
| Quest Item Sparkles | None besides the module switch. Changing it shows a reminder that the change takes effect after you log out and back in. |

## Layout

```
DhoxarModules/
  DhoxarModules.toc
  Core/
    Core.lua      registry, saved variables, start/stop, /dhoxar
    Util.lua      secret-value helpers, copyable text window
    BuffReminder.lua  "missing buff" icon used by the Warlock, Priest and Mage modules
    Widgets.lua   styled buttons, switches and colors for the UI
    Options.lua   configuration window and the page API modules use
  Media/
    logo.tga      addon icon (128x128, made from logo.jpg)
  Modules/
    Warrior/
      Warrior.lua     the Warrior module; runs the features below
      Ragebar.lua
      Reminders.lua
    QuestXPBar.lua
    QuestSparkles.lua
    Warlock.lua
    Priest.lua
    Mage.lua
```

Settings live in `DhoxarModulesDB.modules[<key>]`; warrior features in `DhoxarModulesDB.modules.Warrior.features[<key>]`. A warrior feature registers with `ns.Warrior:AddFeature({...})`, which takes the same fields and callbacks as a module.

## Adding a module

1. Create `Modules/MyModule.lua` and add it to the `.toc`.
2. Register it and implement the callbacks you need (the full contract is documented at the top of `Core/Core.lua`):

```lua
local _, ns = ...

local M = ns:RegisterModule({
    key = "MyModule",
    title = "My Module",
    description = "Shown on the module's card and page.",
    defaults = { someOption = true },
})

function M:OnEnable()  end -- register events, show frames
function M:OnDisable() end -- unregister events, hide frames
function M:OnUserToggle(enabled) end -- optional: the user switched it (not called at login)

-- Optional: settings on the module's page in the configuration window.
function M:BuildOptions(page)
    page:Header("Options")
    page:Checkbox({
        label = "Some option",
        description = "What it does.",
        get = function() return M.db.someOption end,
        set = function(value) M.db.someOption = value end,
    })
    page:Button({
        label = "Do something",
        description = "What clicking it does.",
        text = "Run", -- or a function returning the label
        onClick = function() end,
    })
end
```

`page:Text(text)` adds a paragraph. The page re-reads every `get` and button label whenever it is shown or a control is used.

Hooks installed with `hooksecurefunc` or `HookScript` cannot be removed, so guard them with `if M.active then ... end`.
