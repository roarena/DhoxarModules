# Dhoxar Modules

A single World of Warcraft addon that bundles several small UI modules behind one configuration window.

Built for WoW Forever 1.60.1 (interface version `16001`).

| Module | What it does |
| --- | --- |
| Warrior | Warriors only, and shown as disabled on other classes. Two features, each with its own switch: **Simplified Warrior Ragebar** (one centered text, value or percentage, on the Personal Resource Display's health and rage bars) and **Simple Warrior Reminders** (in-combat icons: Battle Shout missing or fading, Overpower/Revenge ready, Execute ready, Victory Rush ready, Whirlwind ready). |
| Warlock | In-combat icon when Demon Skin is missing or about to fade (Demon Armor and Fel Armor count too). Warlocks only. |
| Priest | In-combat icon when Power Word: Fortitude is missing or about to fade (Prayer of Fortitude and another priest's Fortitude count too). Priests only. |
| Mage | In-combat icon when Arcane Intellect is missing or about to fade (Arcane Brilliance and another mage's Arcane Intellect count too). Proc alerts: an icon with stacks and time left while Fingers of Frost, Heating Up, Missile Barrage or Clearcasting is up, or while your target has your Frostbite freeze or Impact stun. Mages only. |
| Hunter | In-combat icon when Mongoose Bite is ready (after you dodge, off cooldown), and "Missing aspect buff" on the screen while no Aspect is active. Hunters only. |
| Quest XP Bar | Shades the XP bar green with the XP your completed quests will award. |
| FPS & Latency | Shows your frame rate and latency on the screen. The latency turns orange, then red, as it rises (by default orange from 150 ms, red at 400 ms). |
| Loot Won | Replaces Blizzard's "you won" alert when you win a roll with a window you can drag and resize: the item's icon, its name in its rarity color, and your roll. |
| Loot Rolls | Replaces Blizzard's roll frames with one panel you can drag and resize, listing every open roll with its item in its rarity color, the time left, and Need, Greed and Pass buttons. After you choose Need or Greed, the item's card opens to show your roll and the rest of the group's, and stays until the item goes to someone. |
| Quest Item Sparkles | Keeps the loot sparkle on quest items showing: graphics presets turn it off, this turns it back on. Does not change your outline mode. |

## Install

**Windows, automatic:** download [`Install-DhoxarModules.bat`](https://github.com/roarena/DhoxarModules/raw/main/Install-DhoxarModules.bat) and double-click it. It asks for the full path of your AddOns folder (for example `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns`), downloads the latest release and installs it there, replacing the old version; your settings are kept. Run it again any time to update: it remembers the folder, so Enter is enough. You can also pass the folder as an argument: `Install-DhoxarModules.bat "D:\Games\World of Warcraft\_forever_\Interface\AddOns"`.

**Manual:** download the zip from the [latest release](https://github.com/roarena/DhoxarModules/releases/latest) and extract it into `Interface/AddOns`. The folder must keep the name `DhoxarModules`.

Disable the old standalone addons (`SimplifiedWarriorRagebar`, `SimpleWarriorReminders`, `QuestXPBar`). A module or feature refuses to run while its standalone version is loaded. If you log in once with both enabled, the module copies your old settings (icon positions, percentage option) before you disable the standalone addon.

## Development

`node scripts/sync-addon.js` mirrors `DhoxarModules` into the game's AddOns folder (`C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns` by default, or `WOW_ADDONS_DIR` if set). Then `/reload` in game. When working with Claude Code, a local hook runs it after every edit to the addon.

## Use

- `/dhoxar` opens or closes the configuration window. Interface Options > AddOns > Dhoxar Modules has a button that opens it too.
- `/dhoxar list`, `/dhoxar enable <module>`, `/dhoxar disable <module>`.

The window has an **Overview** page with a card per module (status, on/off switch, link to its settings) and a page per module in the sidebar. It can be dragged by its title bar, remembers where you left it, and closes with Esc. The **Look** button on the Overview page switches between two styles: **Modern** (flat dark panels) and **Classic** (the game's own window style: gold metal frame with the logo as portrait, gold text, red buttons, checkboxes). The choice is saved for the account. `/dhoxar` is the only slash command; everything else is on the module pages:

| Module page | Options |
| --- | --- |
| Warrior | Rage bar: on/off, show percentage instead of value. Reminders: on/off, a switch per reminder (Battle Shout, Overpower, Revenge, Execute, Victory Rush, Whirlwind), and Overpower in any stance (after a dodge, as a cue to switch stance). Buttons to unlock/lock the icons for dragging, reset their positions, and show debug info. Opening Edit Mode also unlocks the icons. |
| Mage | Proc alerts: a switch per proc, play a sound, show names, icon size, preview and move, reset position, proc debug info. |
| Warlock, Priest, Mage | Also show the icon out of combat. Buttons to unlock/lock the icon for dragging, reset its position, and show debug info. Opening Edit Mode also unlocks it. |
| Hunter | A switch for each reminder, show the aspect warning only in combat, aspect text size. Buttons to unlock/lock both reminders for dragging, reset their positions, and show debug info. |
| Quest XP Bar | Show the completed-quest list when hovering the XP bar. Button to print the list to chat. |
| FPS & Latency | Show FPS, show latency, text size. Sliders for where the latency turns orange and where it is fully red, and a button to restore the defaults. Buttons to unlock/lock the text for dragging and reset its position. |
| Loot Won | Test button that shows the window so you can place and size it, how long it stays, keep it open until closed, reset position and size, hide Blizzard's alert. |
| Loot Rolls | Show everyone's rolls (on by default). Test button that shows the panel with a few of your items so you can place and size it, reset position and size, hide Blizzard's roll frames. |
| Quest Item Sparkles | None besides the module switch. Changing it shows a reminder that the change takes effect after you log out and back in. |

## Layout

```
DhoxarModules/
  DhoxarModules.toc
  Core/
    Core.lua      registry, saved variables, start/stop, /dhoxar
    Util.lua      secret-value helpers, copyable text window
    BuffReminder.lua  "missing buff" icon used by the Warlock, Priest and Mage modules
    ProcAlerts.lua    proc alert icons used by the Mage module
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
    Hunter.lua
    Performance.lua
    LootWon.lua
    LootRolls.lua
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

`page:Text(text)` adds a paragraph. `page:Slider({ label, description, min, max, step, get, set, format })` adds a slider with its value shown next to it. The page re-reads every `get` and button label whenever it is shown or a control is used.

Hooks installed with `hooksecurefunc` or `HookScript` cannot be removed, so guard them with `if M.active then ... end`.

## License

MIT. See [LICENSE](LICENSE).
