# Repository Guidelines

## Agent Startup & Skill Loading
- Load all files in `.skills/` for WoW addon development guidance.
- Include `.skills/textures.md` for texture quality, format, and rendering guidance.
- Include `.skills/tooling.md` for luacheck, stylua, and lua-language-server usage.
- Include `.skills/wow-api.md` for WoW API usage guidance.
- Include `.skills/secret-values.md` for secret value handling (12.0+).
- Include `.skills/architecture.md` for architecture guidance.
- Include `.skills/.private/` load every file in the `.private/` folder for guidance.
- Reference `.clones/wow-ui-source/` for Blizzard's official UI source (12.1.0) — authoritative API docs, secret value annotations, and reference implementations.

## Project Structure & Module Organization

```
SparkPoint/
├── SparkPoint.toc           # Metadata and load order
├── Core/                    # Core infrastructure
│   ├── Initialization.lua   # Namespace, CallbackRegistry, event loading
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
├── Modules/                 # Feature modules
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
├── Localization/
│   └── enUS.lua             # English strings
└── Textures/                # Art assets
```

## Build, Test, and Development Commands
- No build step; the addon runs directly from this folder.
- Reload in-game after edits: `/reload` (or `/reloadui`).
- For `.toc` changes, exit and relaunch WoW to ensure load order updates apply.
- Enable Lua error reporting: `/console scriptErrors 1`
- Access settings: `/sparkpoint`
- Unlock position: `/sparkpoint unlock` (right-click to lock)

## Dev Tooling (CLI)

Run before every commit:
```bash
luacheck .                          # Must report 0 warnings / 0 errors
stylua --check .                    # Preview formatting changes
stylua .                            # Apply formatting
bash .scripts/check-toc-sync.sh     # SparkPoint.toc / SparkPoint_Dev.toc must match
```

- Config: `.luacheckrc` (lint rules + WoW globals), `.luarc.json` (LSP), `.stylua.toml` (formatter)
- Full reference: `.skills/tooling.md`

## Coding Style & Naming Conventions
- Language: Lua (WoW API, custom lightweight framework - no Ace3).
- Indentation is tab-based; keep it consistent.
- Prefer `local` scope; avoid leaking globals.
- Module files use `PascalCase.lua` (e.g., `Modules/ClassResource.lua`).
- Settings keys use prefix pattern: `modulename_settingname` (e.g., `cast_radius`).

## Testing Guidelines
- No automated tests are defined for addon code.
- Manual testing is required; enable Lua error reporting with `/console scriptErrors 1`.
- Test each module can be enabled/disabled without errors.
- Test cursor-attached mode and fixed position mode.

## Commit & Pull Request Guidelines
- Run `luacheck .` and `stylua --check .` before committing — both must be clean.
- Use clear, imperative commit messages (e.g., "Add cast ring smoothing").
- PRs should include a short summary, verification steps, and screenshots/clips for UI changes.
- Call out any saved variable schema changes (`SparkPointDB`).
- If adding new settings, update `Core/Defaults.lua` DefaultValues.
- If using a new WoW API global, add it to both `.luacheckrc` globals and `.luarc.json` diagnostics.globals.

## Configuration Tips
- Saved variables are declared in `SparkPoint.toc` as `SparkPointDB`.
- When adding modules:
  1. Create `Modules/ModuleName.lua`
  2. Add to `SparkPoint.toc` load order
  3. Add default values to `Core/Defaults.lua` DefaultValues table
  4. Add localization strings to `Localization/enUS.lua`
  5. Register module with `addon.ControlCenter:AddModule()`
- When adding providers:
  - **Slot providers** (inner ring arcs): implement SlotProviders interface in `Core/SlotProviders.lua`
  - **Bar providers** (curved bar slots): implement BarProviders interface (`GetStatus`, `Enable`, `Disable`) in `Core/BarProviders.lua`

## Architecture Patterns
- **CallbackRegistry**: Plumber-style event system for decoupled communication
- **Module Registration**: Each module registers with ControlCenter for enable/disable
- **Database Access**: Functional getters/setters that trigger setting change callbacks
- **DonutWidget**: Encapsulated ring rendering with clean API
- **BarSlotWidget**: Curved horizontal bar widget for HUD bar slots
- **AnchorFrame**: Shared cursor-following frame that all modules parent to
- **HUDLayers**: Centralized z-order layer roots under the anchor frame
- **Transition**: Shared alpha transition service for smooth show/hide

## Secret Value Handling Policy (Non-Negotiable)

Full reference: `.skills/secret-values.md` (affected APIs, forbidden/allowed operations, and 12.1 aura restrictions).

Key rules:
- Secret values are **live in current retail** (12.0+ / Midnight).
- Never directly boolean-test, compare, or perform arithmetic on potentially secret fields.
- `tostring`/`tonumber` **do not work** on secret values — use widget APIs that accept secrets (`StatusBar:SetValue()`), Curve objects, or Blizzard formatting functions (`AbbreviateNumbers()`).
- If no stable API path exists, disable/drop the feature rather than shipping unstable behavior.
- When blocked: report the exact API field and call site, propose alternatives, escalate if no stable path exists.
