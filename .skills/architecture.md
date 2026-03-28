# SparkPoint Architecture Patterns

## Overview
SparkPoint uses a custom lightweight framework inspired by Plumber, DialogueUI, and Narcissus addons. No external library dependencies (no Ace3).

## Core Systems

### 1. CallbackRegistry (Core/Initialization.lua)
Plumber-style event system for decoupled communication.

```lua
-- Register a callback
addon.CallbackRegistry:Register("EventName", function(arg1, arg2)
    -- handle event
end, owner)

-- Trigger an event
addon.CallbackRegistry:Trigger("EventName", arg1, arg2)

-- Register for setting changes
addon.CallbackRegistry:RegisterSettingCallback("cast_radius", function(newValue, userInput)
    -- react to setting change
end, owner)

-- Unregister all callbacks for an owner
addon.CallbackRegistry:UnregisterOwner(owner)
```

### 2. Database System (Core/Defaults.lua + Core/Database.lua)
Settings are split across two files:
- **Defaults.lua**: `DefaultValues` table (profile-scoped), `RootDefaultValues` (non-profile), `ProfileModes`
- **Database.lua**: Functional getters/setters, profile management

```lua
-- DefaultValues table contains all profile-scoped settings
addon.DefaultValues = {
    cast_radius = 22,
    cast_barColor = {r = 1, g = 1, b = 1, a = 0.8},
    moduleEnabled_Cast = true,
}

-- Root defaults (non-profile-scoped)
addon.RootDefaultValues = {
    profileMode = addon.ProfileModes.GLOBAL,
    profileCopySource = "NONE",
}

-- Functional access (triggers callbacks on change)
local radius = addon.GetDBValue("cast_radius")
addon.SetDBValue("cast_radius", 30, true)  -- true = userInput

-- Boolean helpers
if addon.GetDBBool("cast_sparkOnly") then ... end
addon.FlipDBBool("cast_sparkOnly")

-- Color helpers
local r, g, b, a = addon.GetDBColor("cast_barColor")
local colorTable = addon.GetDBColorTable("cast_barColor")
addon.SetDBColor("cast_barColor", 1, 0, 0, 1)
```

### 3. Module Registry (Core/ModuleRegistry.lua)
Plumber-style ControlCenter for module lifecycle.

```lua
-- Register a module (at end of module file)
addon.ControlCenter:AddModule({
    name = "Display Name",
    dbKey = "moduleEnabled_ModuleName",
    description = "What this module does",
    toggleFunc = function(enabled)
        if enabled then
            -- initialize, register events
        else
            -- cleanup, unregister events
        end
    end,
    categoryID = 1,
    uiOrder = 1,
})

-- Module lifecycle
addon.ControlCenter:EnableModule("moduleEnabled_Cast")
addon.ControlCenter:DisableModule("moduleEnabled_Cast")
addon.ControlCenter:ToggleModule("moduleEnabled_Cast")

-- Query module state
if addon.ControlCenter:IsModuleEnabled("moduleEnabled_Cast") then ... end

-- Get module data
local moduleData = addon.ControlCenter:GetModule("moduleEnabled_Cast")
local allModules = addon.ControlCenter:GetModulesSorted()
```

### 4. AnchorFrame (Core/AnchorFrame.lua)
Shared cursor-following frame with show/hide request system.

```lua
-- Show/hide requests (multiple modules can request visibility)
addon.AnchorFrame:Show("cast")   -- "cast" is the requester ID
addon.AnchorFrame:Hide("cast")   -- anchor hides only when ALL requesters release

-- Get the actual frame for parenting
local anchor = addon.AnchorFrame:GetFrame()
myFrame:SetParent(anchor)
myFrame:SetAllPoints()

-- Position management
addon.AnchorFrame:Unlock()  -- enables manual positioning
addon.AnchorFrame:Lock()    -- saves position
```

### 5. HUDLayers (Core/HUDLayers.lua)
Centralized z-order layer roots under the shared anchor frame.

```lua
-- Layer names (ordered back-to-front)
HUDLayers.Names = {
    CAST_SHADOW = "CAST_SHADOW",
    DECORATIVE_RING = "DECORATIVE_RING",
    CAST_FEEDBACK = "CAST_FEEDBACK",
    BAR_SLOTS = "BAR_SLOTS",
    CAST_BASE = "CAST_BASE",
    CLASS_RESOURCE = "CLASS_RESOURCE",
    ASSISTED_HIGHLIGHT = "ASSISTED_HIGHLIGHT",
}

-- Get a layer root frame for parenting
local layerFrame = addon.HUDLayers:GetLayer(HUDLayers.Names.CAST_BASE)
myFrame:SetParent(layerFrame)
```

### 6. Transition (Core/Transition.lua)
Shared alpha transition service for smooth show/hide.

```lua
-- Fade a frame in/out
addon.Transition:FadeTo(frame, targetAlpha, duration, easing)
```

### 7. IconMask (Core/IconMask.lua)
Shared helpers for masked circular icon rendering.

```lua
-- Get the mask texture path
local maskPath = addon.IconMask:GetMaskPath()

-- Calculate proportional expand for a given icon size
local expand = addon.IconMask:CalculateExpand(iconSize, baseExpand, baseSize)

-- Layout a region (border, glow, etc.) relative to an icon
addon.IconMask:LayoutToIcon(region, icon, baseExpand, baseSize)
```

### 8. DonutWidget (Widgets/DonutWidget.lua)
Encapsulated ring rendering widget.

```lua
-- Create a donut
local donut = addon.DonutWidget:Create({
    direction = true,       -- true = clockwise
    radius = 22,
    thickness = 25,         -- 15, 20, 25, 30, or 35
    barColor = {r = 1, g = 1, b = 1, a = 0.8},
    backgroundColor = {r = 0.4, g = 0.4, b = 0.4, a = 0.8},
    parent = optionalParentFrame,
})

-- Attach to anchor
donut:AttachTo(addon.AnchorFrame:GetFrame())

-- Update properties
donut:SetAngle(180)         -- 0-360 degrees
donut:SetRadius(30)
donut:SetThickness(25)
donut:SetDirection(false)   -- counter-clockwise
donut:SetBarColor({r = 1, g = 0, b = 0, a = 1})
donut:SetBackgroundColor({r = 0.2, g = 0.2, b = 0.2, a = 0.5})

-- Visibility
donut:Show()
donut:Hide()
if donut:IsShown() then ... end

-- Get underlying frame
local frame = donut:GetFrame()
```

### 9. BarSlotWidget (Widgets/BarSlotWidget.lua)
Curved horizontal bar widget for HUD bar slots.

```lua
-- Used by the BarSlots module to render health/mana bars
-- Renders using 1024x512 curved bar textures with fit bounds
local bar = addon.BarSlotWidget:Create(parent, options)
```

### 10. Provider Registries

**SlotProviders** (Core/SlotProviders.lua) — Inner ring arc data:
```lua
addon.SlotProviders:Register(id, provider)
addon.SlotProviders:Get(id)
addon.SlotProviders:GetAll()
```

**BarProviders** (Core/BarProviders.lua) — Horizontal bar slot data:
```lua
-- Provider interface:
--   provider.id           (string)
--   provider.displayName  (string)
--   provider:GetStatus() -> { current, max, active, show, barColor }
--   provider:Enable()
--   provider:Disable()

addon.BarProviders:Register(id, provider)
addon.BarProviders:Get(id)
addon.BarProviders:GetAll()
```

## Module Structure Template

```lua
-- Modules/ModuleName.lua
local addonName, addon = ...
local L = addon.L
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local HUDLayers = addon.HUDLayers
local Visibility = addon.Visibility
local Transition = addon.Transition
local GetDBValue = addon.GetDBValue
local GetDBBool = addon.GetDBBool
local GetDBColor = addon.GetDBColor

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------
local moduleFrame
local isActive = false

--------------------------------------------------------------------------------
-- Event Frame
--------------------------------------------------------------------------------
local EL = CreateFrame("Frame")

--------------------------------------------------------------------------------
-- Module Object
--------------------------------------------------------------------------------
local Module = {}
addon.Modules.ModuleNameObj = Module

--------------------------------------------------------------------------------
-- Core Functions
--------------------------------------------------------------------------------
function Module:Show()
    if not moduleFrame then return end
    isActive = true
    AnchorFrame:Show("modulename")
    moduleFrame:Show()
end

function Module:Hide()
    if not moduleFrame then return end
    isActive = false
    moduleFrame:Hide()
    AnchorFrame:Hide("modulename")
end

function Module:ApplyOptions()
    if not moduleFrame then return end
    -- Update visuals from settings
end

function Module:Initialize()
    local anchor = AnchorFrame:GetFrame()
    if not anchor then return end

    -- Get the appropriate HUD layer for z-ordering
    local layerRoot = HUDLayers:GetLayer(HUDLayers.Names.CAST_BASE)

    moduleFrame = CreateFrame("Frame", nil, layerRoot)
    moduleFrame:SetAllPoints()
    moduleFrame:Hide()

    -- Create visual elements...

    self:ApplyOptions()
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------
function Module:SOME_EVENT(event, ...)
    -- handle event
end

--------------------------------------------------------------------------------
-- Enable/Disable
--------------------------------------------------------------------------------
local function EnableModule(enabled)
    if enabled then
        if not moduleFrame then
            Module:Initialize()
        end
        EL:RegisterEvent("SOME_EVENT")
    else
        EL:UnregisterAllEvents()
        Module:Hide()
    end
end

--------------------------------------------------------------------------------
-- Event Dispatcher
--------------------------------------------------------------------------------
EL:SetScript("OnEvent", function(self, event, ...)
    if Module[event] then
        Module[event](Module, event, ...)
    end
end)

--------------------------------------------------------------------------------
-- Register Setting Callbacks
--------------------------------------------------------------------------------
local settingKeys = {"modulename_setting1", "modulename_setting2"}
for _, key in ipairs(settingKeys) do
    CallbackRegistry:RegisterSettingCallback(key, function()
        Module:ApplyOptions()
    end)
end

--------------------------------------------------------------------------------
-- Register Module
--------------------------------------------------------------------------------
addon.ControlCenter:AddModule({
    name = L["Module Name"] or "Module Name",
    dbKey = "moduleEnabled_ModuleName",
    description = L["Module Description"] or "What this module does",
    toggleFunc = EnableModule,
    categoryID = 1,
    uiOrder = 1,
})
```

## Load Order

1. `Core/Initialization.lua` - Creates namespace, CallbackRegistry
2. `Core/API.lua` - Utility functions
3. `Core/IconMask.lua` - Shared masked icon rendering helpers
4. `Core/Defaults.lua` - DefaultValues, RootDefaultValues, ProfileModes
5. `Core/Database.lua` - DB access functions, profile management
6. `Core/Transition.lua` - Shared alpha transition service
7. `Core/Visibility.lua` - Shared visibility policy service
8. `Core/ModuleRegistry.lua` - ControlCenter
9. `Core/SlotProviders.lua` - Inner ring slot provider registry
10. `Core/BarProviders.lua` - Horizontal bar slot data provider registry
11. `Core/AnchorFrame.lua` - Anchor frame system + slash commands
12. `Core/HUDLayers.lua` - Centralized z-order layer roots
13. `Core/MinimapButton.lua` - Native minimap button
14. `Widgets/DonutWidget.lua` - Ring/arc rendering widget
15. `Widgets/SlotRingWidget.lua` - Inner slot arc widget
16. `Widgets/BarSlotWidget.lua` - Curved horizontal bar widget
17. `Providers/GCD.lua` - GCD slot provider
18. `Providers/HealthBar.lua` - Health bar provider
19. `Providers/ManaBar.lua` - Mana bar provider
20. `Modules/Cast.lua` - Cast ring (owns slots + spell icon)
21. `Modules/BarSlots.lua` - Curved bar slots above/below cast ring
22. `Modules/ClassResource.lua` - Class resource pips / text
23. `Modules/DecorativeRing.lua` - Decorative rotating ring
24. `Modules/SpellIcon.lua` - Spell icon proxy
25. `Modules/AssistedHighlight.lua` - Blizzard assisted highlight
26. `Settings/SettingsTemplates.xml` - Color picker XML mixin
27. `Settings/ColorOverrides.lua` - Color override widget logic
28. `Settings/SettingsPanel.lua` - Blizzard Settings Panel integration
29. `Localization/enUS.lua` - Strings

## Event Flow

```
ADDON_LOADED
    └─> addon:LoadDatabase()
    └─> CallbackRegistry:Trigger("ADDON_LOADED")
        └─> AnchorFrame initializes
        └─> HUDLayers initializes layer roots
        └─> MinimapButton initializes
        └─> SettingsPanel builds (after 0.1s delay)

PLAYER_ENTERING_WORLD
    └─> addon.ControlCenter:InitializeModules()
        └─> For each module: toggleFunc(enabled)
            └─> Module:Initialize() if enabled
            └─> Register events
    └─> CallbackRegistry:Trigger("PLAYER_ENTERING_WORLD")

Setting Changed (via SetDBValue)
    └─> CallbackRegistry:Trigger("SettingChanged.{dbKey}", value, userInput)
        └─> Module:ApplyOptions() responds
```

## Inter-Module Communication

Modules communicate through:

1. **Direct object access** (for tightly coupled modules):
   ```lua
   if addon.Modules.RingObj and addon.Modules.RingObj.Show then
       addon.Modules.RingObj:Show("cast")
   end
   ```

2. **CallbackRegistry** (for decoupled events):
   ```lua
   -- In Cast module
   CallbackRegistry:Trigger("CastModule.CastStarted", spellName)

   -- In another module
   CallbackRegistry:Register("CastModule.CastStarted", function(spellName)
       -- react
   end)
   ```

3. **Setting callbacks** (for configuration changes):
   ```lua
   CallbackRegistry:RegisterSettingCallback("cast_radius", function(newValue)
       -- update something that depends on cast radius
   end)
   ```
