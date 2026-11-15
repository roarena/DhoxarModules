# Dhoxar Modules

WoW addon for WoW Forever 1.60.1 (interface 16001). The addon is the `DhoxarModules/` folder; see `README.md` for the layout and how to add a module.

## Keep the game copy in sync

Every change to `DhoxarModules/` must be copied to the game so it can be tested with `/reload`:

```
node scripts/sync-addon.js
```

It mirrors `DhoxarModules/` into `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\DhoxarModules`.

A PostToolUse hook in `.claude/settings.local.json` runs this automatically after each Edit or Write inside `DhoxarModules/`. Run it by hand after changes the hook cannot see: shell commands that move, delete or rewrite addon files, and git operations such as checkout, merge or reset.
