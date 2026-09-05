# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.


## Project Overview

SparkPoint is a World of Warcraft addon that displays cast rings, bar slots, and class power indicators around the player's cursor. Built with a custom lightweight framework (no Ace3).

## Skills

Domain-specific guidance lives in `.claude/skills/`. Key skills:
- `/sparkpoint-architecture` — Core systems, module lifecycle, load order, templates
- `/wow-api` — WoW API patterns, events, power types, Blizzard Settings API
- `/secret-values` — Secret value handling, 12.0 foundations, and 12.1 aura restrictions
- `/texture-guide` — Texture quality, format, and rendering guidance
- `/wow-dev-tooling` — luacheck, stylua, and lua-language-server usage

## Development Commands

```bash
# No build step - addon runs directly from this folder
# Reload in-game after edits:
/reload

# For .toc changes, exit and relaunch WoW

# Enable Lua error reporting:
/console scriptErrors 1

# Access addon configuration:
/sparkpoint           # Opens Blizzard Settings Panel
/sparkpoint unlock    # Unlock position for manual placement
/sparkpoint lock      # Lock position
/sparkpoint reset     # Reset position to defaults
```

## Dev Tooling

```bash
# Lint (must be clean before committing)
luacheck .

# Format check (preview only)
stylua --check .

# Format in place
stylua .

# Verify both .toc files stay in sync (Title and validated icon folder may differ)
bash .scripts/check-toc-sync.sh
```

Config files: `.luacheckrc`, `.luarc.json`, `.stylua.toml`
Full usage guide: `/wow-dev-tooling` skill

## Architecture

### File Structure
```
SparkPoint/
├── Core/
│   ├── Initialization.lua   # Namespace, CallbackRegistry, event loading
│   ├── Util.lua             # Shared texture, numeric, copy, and layering helpers
│   ├── API.lua              # Utility functions (new WoW APIs)
│   ├── IconMask.lua         # Shared masked icon rendering helpers
│   ├── Defaults.lua         # DefaultValues, RootDefaultValues, ProfileModes
│   ├── Database.lua         # GetDBValue/SetDBValue, profile management
│   ├── Transition.lua       # Shared alpha transitions for HUD elements
│   ├── Visibility.lua       # Shared visibility policy (ALWAYS/IN_COMBAT/etc.)
│   ├── ModuleRegistry.lua   # ControlCenter module registration
│   ├── SlotProviders.lua    # Inner ring slot provider registry
│   ├── BarProviders.lua     # Horizontal bar slot data provider registry
│   ├── AnchorFrame.lua      # Cursor-following anchor frame + slash commands
│   ├── HUDLayers.lua        # Centralized z-order layer roots
│   └── MinimapButton.lua    # Native minimap button (no LibDBIcon)
├── Widgets/
│   ├── DonutWidget.lua      # Ring/arc rendering widget
│   ├── SlotRingWidget.lua   # Inner slot arc widget
│   └── BarSlotWidget.lua    # Curved horizontal bar widget
├── Providers/
│   ├── GCD.lua              # Global cooldown slot provider
│   ├── HealthBar.lua        # Health bar provider
│   └── ManaBar.lua          # Mana bar provider
├── Modules/
│   ├── Cast.lua             # Cast ring with latency + inner slots + spell icon
│   ├── BarSlots.lua         # Curved bar slots above/below cast ring
│   ├── ClassResource.lua    # Class resource pips / text display
│   ├── DecorativeRing.lua   # Decorative rotating ring
│   ├── SpellIcon.lua        # Spell icon proxy (delegates to Cast)
│   └── AssistedHighlight.lua # Blizzard assisted highlight next spell
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
3. Add default values to `Core/Defaults.lua` in `DefaultValues`
4. Add localization strings to `Localization/enUS.lua`
5. Register module with `addon.ControlCenter:AddModule()`

## Adding New Providers

- **Slot providers** (inner ring arcs): implement SlotProviders interface, register in `Core/SlotProviders.lua`
- **Bar providers** (curved bar slots): implement BarProviders interface (`GetStatus`, `Enable`, `Disable`), register in `Core/BarProviders.lua`

## WoW API Notes

This addon uses new WoW APIs (C_Spell.*, etc.) without polyfills:
- `C_Spell.GetSpellInfo(spellID)` returns info table
- `C_Spell.GetSpellCooldown(spellID)` returns cooldown info
- `C_Spell.DoesSpellExist(spellID)` for validation

## Secret Value Handling Policy (Non-Negotiable)

See `/secret-values` skill for the complete reference (affected APIs, forbidden/allowed operations, and 12.1 aura restrictions).

Key rules:
- Secret values are **live in current retail** (12.0+ / Midnight).
- Never directly boolean-test, compare, or perform arithmetic on potentially secret fields.
- `tostring`/`tonumber` **do not work** on secret values — use widget APIs that accept secrets (`StatusBar:SetValue()`), Curve objects, or Blizzard formatting functions (`AbbreviateNumbers()`).
- If no stable API path exists, drop/disable the feature rather than shipping unstable behavior.

## Coding Style

- Tab-based indentation
- Prefer `local` scope; avoid globals
- Module files use PascalCase.lua
- Settings keys use prefix pattern: `modulename_settingname`
