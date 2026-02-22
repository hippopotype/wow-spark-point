# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.


## Project Overview

SparkPoint is a World of Warcraft addon that displays cast rings and class power indicators around the player's cursor. Built with a custom lightweight framework.

## Agent Startup & Skill Loading
- Load all files in `.skills/` for WoW addon development guidance.
- Include `.skills/textures.md` for texture quality, format, and rendering guidance.
- Include `.skills/tooling.md` for luacheck, stylua, and lua-language-server usage.
- Include `.skills/wow-api.md` for WoW API usage guidance.
- Include `.skills/architecture.md` for architecture guidance.
- Include `.skills/.private/` load every file in the `.private/` folder for guidance.

## Development Commands

```bash
# No build step - addon runs directly from this folder
# Reload in-game after edits:
/reload

# For .toc changes, exit and relaunch WoW

# Enable Lua error reporting:
/console scriptErrors 1

# Access addon configuration:
/sp           # Opens Blizzard Settings Panel
/sparkpoint   # Same as /sp
/sp unlock    # Unlock position for manual placement
/sp lock      # Lock position
/sp reset     # Reset position to defaults
```

## Dev Tooling

```bash
# Lint (must be clean before committing)
luacheck .

# Format check (preview only)
stylua --check .

# Format in place
stylua .
```

Config files: `.luacheckrc`, `.luarc.json`, `.stylua.toml`
Full usage guide: `.skills/tooling.md`

## Architecture

### File Structure
```
SparkPoint/
├── Core/
│   ├── Initialization.lua   # Namespace, CallbackRegistry, event loading
│   ├── API.lua              # Utility functions (new WoW APIs)
│   ├── Database.lua         # DefaultValues, GetDBValue/SetDBValue
│   ├── Visibility.lua       # Shared visibility policy (ALWAYS/IN_COMBAT/etc.)
│   ├── ModuleRegistry.lua   # ControlCenter module registration
│   ├── SlotProviders.lua    # Inner ring slot provider registry
│   └── AnchorFrame.lua      # Cursor-following anchor frame
├── Widgets/
│   ├── DonutWidget.lua      # Ring/arc rendering widget
│   └── SlotRingWidget.lua   # Inner slot arc widget
├── Providers/
│   └── GCD.lua              # Global cooldown slot provider
├── Modules/
│   ├── Cast.lua             # Cast ring with latency + inner slots + spell icon
│   ├── ClassResource.lua    # Class resource pips / text display
│   ├── DecorativeRing.lua   # Decorative rotating ring
│   └── SpellIcon.lua        # Spell icon proxy (delegates to Cast)
├── Settings/
│   ├── SettingsTemplates.xml  # Color picker XML mixin
│   ├── ColorOverrides.lua     # Color override widget logic
│   └── SettingsPanel.lua      # Blizzard Settings Panel integration
└── Localization/
    └── enUS.lua             # English strings
```

### Core Systems

**CallbackRegistry** (Plumber-style event system):
```lua
addon.CallbackRegistry:Register(event, func, owner)
addon.CallbackRegistry:Trigger(event, ...)
addon.CallbackRegistry:RegisterSettingCallback(dbKey, func, owner)
```

**Module Registration** (each module ends with):
```lua
addon.ControlCenter:AddModule({
    name = "Display Name",
    dbKey = "moduleEnabled_Cast",
    description = "...",
    toggleFunc = function(enabled) end,
    categoryID = 1,
    uiOrder = 1,
})
```

**Database Access**:
```lua
addon.GetDBValue(dbKey)
addon.SetDBValue(dbKey, value, userInput)  -- triggers SettingChanged.{dbKey}
addon.GetDBColor(dbKey) -> r, g, b, a
addon.GetDBColorTable(dbKey) -> {r, g, b, a}
```

**DonutWidget API**:
```lua
local donut = addon.DonutWidget:Create({
    direction = true,      -- clockwise
    radius = 22,
    thickness = 25,
    barColor = {r=1, g=1, b=1, a=0.8},
    backgroundColor = {r=0.4, g=0.4, b=0.4, a=0.8},
})
donut:AttachTo(parentFrame)
donut:SetAngle(180)  -- 0-360
donut:Show() / donut:Hide()
```

### Module Lifecycle
- `Initialize()`: Create frames, set up visuals
- `ApplyOptions()`: Update visuals from settings
- `toggleFunc(enabled)`: Called when module is enabled/disabled

### Event Handling
Modules create their own event frames and use `RegisterUnitEvent` for player-specific events:
```lua
EL:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
EL:SetScript("OnEvent", function(self, event, ...)
    if Module[event] then Module[event](Module, event, ...) end
end)
```

## Adding New Modules

1. Create `Modules/ModuleName.lua` following existing patterns
2. Add to `SparkPoint.toc` load order
3. Add default values to `Core/Database.lua` in `DefaultValues`
4. Add localization strings to `Localization/enUS.lua`
5. Register module with `addon.ControlCenter:AddModule()`


## WoW API Notes

This addon uses new WoW APIs (C_Spell.*, etc.) without polyfills:
- `C_Spell.GetSpellInfo(spellID)` returns info table
- `C_Spell.GetSpellCooldown(spellID)` returns cooldown info
- `C_Spell.DoesSpellExist(spellID)` for validation

## Coding Style

- Tab-based indentation
- Prefer `local` scope; avoid globals
- Module files use PascalCase.lua
- Settings keys use prefix pattern: `modulename_settingname`
