# WoW API Notes (Repository-Focused)

## Primary Documentation
- Warcraft Wiki API index: https://warcraft.wiki.gg/wiki/World_of_Warcraft_API
- Specific API pages (example): https://warcraft.wiki.gg/wiki/API_UnitPower
- In-game: `/api` command for official Blizzard docs

## New C_Spell API (Used in This Addon)

This addon uses modern WoW APIs without polyfills.

```lua
-- Get spell info (returns table)
local info = C_Spell.GetSpellInfo(spellID)
-- info.name, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID

-- Get spell cooldown (returns table)
local cooldownInfo = C_Spell.GetSpellCooldown(spellID)
-- cooldownInfo.startTime, cooldownInfo.duration, cooldownInfo.isEnabled

-- Check if spell exists
if C_Spell.DoesSpellExist(spellID) then
    -- spell is valid
end
```

## Secret Values (Must Convert to Strings)
Some API calls return "secret values" that cannot be compared or stored directly.

```lua
-- Bad: comparing secret values
local power = UnitPower("player", powerType)
if power ~= lastPower then
    -- ERROR: attempt to compare secret value
end

-- Good: convert immediately
local power = UnitPower("player", powerType)
local powerString = tostring(power or 0)
if powerString ~= lastPowerString then
    -- safe
end
```

## Event Registration

### Unit Events (use RegisterUnitEvent)
These events can be filtered to specific units:
- `UNIT_SPELLCAST_START`, `UNIT_SPELLCAST_STOP`, `UNIT_SPELLCAST_CHANNEL_START`
- `UNIT_SPELLCAST_INTERRUPTED`, `UNIT_SPELLCAST_DELAYED`
- `UNIT_SPELLCAST_EMPOWER_START`, `UNIT_SPELLCAST_EMPOWER_STOP` (Evoker)
- `UNIT_POWER_UPDATE`, `UNIT_MAXPOWER`

```lua
-- Correct: unit event with filter
EL:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
```

### Regular Events (use RegisterEvent)
These cannot be filtered and require unit check in handler:
- `UNIT_SPELLCAST_SENT` (no unit filter available)
- `PLAYER_SPECIALIZATION_CHANGED`
- `ACTIONBAR_UPDATE_COOLDOWN`
- `SPELLS_CHANGED`
- `UPDATE_SHAPESHIFT_FORM`

```lua
-- Correct: regular event + unit check
EL:RegisterEvent("UNIT_SPELLCAST_SENT")
function Module:UNIT_SPELLCAST_SENT(event, unit, ...)
    if unit ~= "player" then return end
    -- handle
end
```

## Power Resource Detection
Detect class/spec before selecting power types. Validate `UnitPowerMax` > 0.

```lua
local _, class = UnitClass("player")
local spec = GetSpecialization()

-- Use Enum.PowerType for clarity
local powerType
if class == "ROGUE" then
    powerType = Enum.PowerType.ComboPoints
elseif class == "PALADIN" and spec == 3 then
    powerType = Enum.PowerType.HolyPower
end

local maxPower = UnitPowerMax("player", powerType)
if maxPower and maxPower > 0 then
    -- power type is valid for this character
end
```

Power type enums:
- `Enum.PowerType.ComboPoints` (Rogue, Feral)
- `Enum.PowerType.Runes` (Death Knight)
- `Enum.PowerType.SoulShards` (Warlock)
- `Enum.PowerType.LunarPower` (Balance Druid)
- `Enum.PowerType.HolyPower` (Ret Paladin)
- `Enum.PowerType.Chi` (Windwalker)
- `Enum.PowerType.Insanity` (Shadow Priest)
- `Enum.PowerType.ArcaneCharges` (Arcane Mage)
- `Enum.PowerType.Fury` (Havoc DH)
- `Enum.PowerType.Pain` (Vengeance DH)
- `Enum.PowerType.Essence` (Evoker)
- `Enum.PowerType.Maelstrom` (Elemental/Enhancement Shaman)

## Module Pattern (SparkPoint Custom Framework)

```lua
local addonName, addon = ...
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local GetDBValue = addon.GetDBValue

local Module = {}
addon.Modules.ModuleNameObj = Module

local EL = CreateFrame("Frame")

function Module:Initialize()
    -- Create frames, set up visuals
end

function Module:ApplyOptions()
    -- Update visuals from settings
end

local function EnableModule(enabled)
    if enabled then
        if not initialized then Module:Initialize() end
        EL:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
        -- ...
    else
        EL:UnregisterAllEvents()
        -- cleanup
    end
end

-- Event dispatcher
EL:SetScript("OnEvent", function(self, event, ...)
    if Module[event] then
        Module[event](Module, event, ...)
    end
end)

-- Register setting callbacks
CallbackRegistry:RegisterSettingCallback("module_setting", function()
    Module:ApplyOptions()
end)

-- Register module
addon.ControlCenter:AddModule({
    name = "Module Name",
    dbKey = "moduleEnabled_ModuleName",
    description = "What it does",
    toggleFunc = EnableModule,
    categoryID = 1,
    uiOrder = 1,
})
```

## Events vs Polling
Prefer events; use throttled `OnUpdate` when events are missing.

```lua
-- Throttled OnUpdate pattern (last resort only — prefer events)
local UPDATE_INTERVAL = 0.1
local updateTimer = 0

local function OnUpdate(self, elapsed)
    updateTimer = updateTimer + elapsed
    if updateTimer >= UPDATE_INTERVAL then
        updateTimer = 0
        -- do update
    end
end
```

## Blizzard Settings API

```lua
-- Create category
local category, layout = Settings.RegisterVerticalLayoutCategory("Addon Name")

-- Create subcategory
local subCategory = Settings.RegisterVerticalLayoutSubcategory(category, "Sub Name")

-- Register setting (variableTbl must be the actual DB table)
local setting = Settings.RegisterAddOnSetting(category, displayName, dbKey, DB, type(DB[dbKey]), DB[dbKey])
setting:SetValueChangedCallback(function(_, value)
    -- handle change
end)

-- Create controls
Settings.CreateCheckbox(category, setting, tooltip)

local options = Settings.CreateSliderOptions(min, max, step)
options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
Settings.CreateSlider(category, setting, options, tooltip)

-- Register category
Settings.RegisterAddOnCategory(category)
```
