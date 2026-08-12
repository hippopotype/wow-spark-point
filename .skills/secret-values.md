# WoW Secret Values — Complete Reference

## What Are Secret Values?

Secret values are a Blizzard security mechanism that wraps certain API return values in opaque containers. Insecure (tainted) addon code can receive and pass secrets but cannot inspect, compare, or perform arithmetic on them. The goal is to prevent addons from making automated combat decisions while still allowing them to display information.

## Version Timeline

### 11.x (The War Within) — Previous
Secret values did not exist in 11.x. All APIs returned normal values.

### 12.0 (Midnight) — Secret Value Foundation
Secret values are **live in production**. The `tostring`/`tonumber` workaround **no longer works** — these functions cannot convert secret values. Blizzard provides new APIs (Curves, Duration objects, widget secret support) as replacements.

### 12.1.0 (Curse of Ula'tek) — Current Retail
Aura restrictions are stricter. While auras are restricted, the complete `UNIT_AURA` payload is secret and index-, slot-, or instance-based aura queries require unit-aura access that addons do not have. Spell ID and spell name queries remain callable, but only explicitly non-secret auras are returned to addon code.

---

## Forbidden Operations on Secret Values (Tainted Code)

These will error or return nil when performed on a secret value:

- **Arithmetic**: `+`, `-`, `*`, `/`, `%`, `^`, unary `-`
- **Comparison**: `==`, `~=`, `<`, `>`, `<=`, `>=`
- **Boolean test**: `if secretVal then` — forbidden
- **Conversion**: `tostring(secret)`, `tonumber(secret)` — **fails**
- **Length**: `#secretVal`
- **Table key**: `tbl[secretVal] = ...`
- **Index access**: `secretVal.foo`, `secretVal["bar"]`
- **Call as function**: `secretVal()`

## Allowed Operations on Secret Values (Tainted Code)

- Store in variables, upvalues, or as table values
- Pass to Lua functions as arguments
- String concatenation: `"HP: " .. secretValue` works
- `string.format`, `string.join` with secrets
- `type(secret)` — returns the real underlying type (e.g. `"number"`)
- Pass to widget APIs that accept secrets (e.g. `StatusBar:SetValue()`)
- Pass to Blizzard formatting functions (e.g. `AbbreviateNumbers()`)

---

## Detection & Introspection APIs

| Function | Purpose |
|---|---|
| `issecretvalue(value)` | Returns `true` if the value is secret |
| `canaccessvalue(value)` | Returns `true` if the calling function can operate on the secret |
| `issecrettable(value)` | Returns `true` if a table is secret |
| `canaccesstable(table)` | Returns `true` if the table is accessible |
| `secretwrap(values)` | Wraps values as secrets (for testing) |
| `dropsecretaccess()` | Removes secret access from the calling function |
| `FrameScriptObject:CanBeAccessedInContext()` | Checks whether the current execution context may inspect a UI object (12.1+) |

---

## Which APIs Return Secret Values

### Health & Power

| API | Secret? | Notes |
|---|---|---|
| `UnitHealth("player")` | **Yes** in combat | Absolute health is secret |
| `UnitHealthMax("player")` | **No** | Max health is non-secret for player |
| `UnitHealthPercent("player")` | **Yes** | Returns 0–1 (not 0–100); secret but passable to widgets |
| `UnitPower("player", type)` | **Conditional** | Primary resources secret; **secondary resources non-secret** (see below) |
| `UnitPowerMax("player", type)` | **No** | Non-secret for player |
| `UnitPowerPercent("player", type)` | **Yes** | Returns secret 0–1 |
| `UnitStagger("player")` | **No** | Non-secret for player |

### Non-Secret Secondary Resources (Player Only)

These are explicitly whitelisted and remain non-secret:
- Combo Points, Runes, Soul Shards, Holy Power, Chi, Arcane Charges, Essence
- Maelstrom Weapon (via aura stacks, already handled by SparkPoint)

### Cooldowns

| API | Secret? | Notes |
|---|---|---|
| `C_Spell.GetSpellCooldown()` | **Yes** in combat/instances | `startTime`, `duration`, `modRate` are secret |
| `GetActionCooldown()` | **Yes** in combat/instances | Same fields |
| `C_Spell.GetSpellCharges()` | **Yes** in combat/instances | Charge fields are secret |

### Auras

| API | Secret? | Notes |
|---|---|---|
| `UNIT_AURA` payload | **Fully secret** while restricted | Register for the correct unit and treat the event as a signal only |
| `C_UnitAuras.GetAuraDataByIndex()` | **Unavailable** while restricted | Addon calls requiring unit-aura access Lua error |
| `C_UnitAuras.GetAuraDataBySlot()` | **Unavailable** while restricted | Same restriction as index access |
| `C_UnitAuras.GetAuraDataByAuraInstanceID()` | **Unavailable** while restricted | Same restriction as index access |
| `C_UnitAuras.GetPlayerAuraBySpellID()` | **Conditional** | Callable, but returns only explicitly non-secret auras |
| Aura `applications` field | **Varies** | Some whitelisted spells remain non-secret |

For player-filtered `UNIT_AURA` handlers, never inspect `unitTarget` or `updateInfo` in addon code. `RegisterUnitEvent("UNIT_AURA", "player")` supplies the required scope; use the notification to re-read an explicitly non-secret spell through its spell-ID API.

### Unit Identity

| API | Secret? | Notes |
|---|---|---|
| `UnitName()` | **Yes** in instances | Regardless of combat |
| `UnitGUID()` | **Yes** in instances | Regardless of combat |
| `UnitIsUnit()` | **Relaxed** | Non-secret for target/focus/mouseover/softenemy/softfriend |

### Spellcasts

| API | Secret? | Notes |
|---|---|---|
| Player's own casts | **No** | Non-secret |
| Enemy casts | **Yes** in restricted scenarios | |

### Combat Log (CLEU)

**Completely removed** from addon access in 12.0+. No workaround.

### Whitelisted Non-Secret Spells

Blizzard explicitly whitelists these as non-secret:
- Skyriding spells
- Global Cooldown spell
- Maelstrom Weapon (Shaman)
- Devourer resource spells (Demon Hunter)
- Combat Resurrection spells
- Ebon Might aura (Augmentation Evoker)

---

## Replacement APIs (12.0+)

### Curve Objects (Primary Replacement)

Map secret numeric values to display-safe values without inspecting them:

```lua
-- Create a curve that maps a secret 0-1 range to a visual property
local curve = C_CurveUtil.CreateCurve()

-- Create color curves for dynamic coloring
local colorCurve = C_CurveUtil.CreateColorCurve()

-- Boolean-to-color for secret booleans
C_CurveUtil.EvaluateColorFromBoolean(secretBool, trueColor, falseColor)
```

### Duration Objects

For time-based secret data (cooldowns, aura durations):

```lua
local duration = C_DurationUtil.CreateDuration()
-- Pass to StatusBar:SetTimerDuration()
```

### Widget Secret Support

```lua
-- StatusBar natively accepts secret values (SparkPoint already pcall-wraps this)
statusBar:SetValue(secretValue)
statusBar:SetMinMaxValues(0, secretMax)

-- Timer-based cooldown display
statusBar:SetTimer(startTime, duration)

-- Boolean-driven alpha/color
frame:SetAlphaFromBoolean(secretBool, trueAlpha, falseAlpha)
texture:SetVertexColorFromBoolean(secretBool, trueColor, falseColor)
```

### Formatting Functions That Accept Secrets

```lua
-- These accept secret values
AbbreviateNumbers(secretValue)           -- returns formatted string
AbbreviateLargeNumbers(secretValue)
BreakUpLargeNumbers(secretValue)
WrapTextInColorCode(secretString, color)
C_StringUtil.TruncateWhenZero(secretValue)
C_StringUtil.RoundToNearestString(secretValue)
```

### New Cooldown Helpers

```lua
GetActionCooldownRemaining()
GetActionCooldownRemainingPercent()
GetActionCooldownRemainingColor()
ActionButton_ApplyCooldown(cooldownFrame, actionSlot)  -- secure delegate
```

### New Aura Helpers

These helpers are not a general replacement for restricted aura access in 12.1. Instance-based helpers require valid unit-aura access and may error for addon code while auras are restricted. Use Aura Containers for arbitrary aura displays, or spell-ID/name queries only for explicitly non-secret auras.

```lua
C_UnitAuras.GetAuraDurationRemainingPercent(auraInstanceID)
C_UnitAuras.GetAuraDurationRemainingColor(auraInstanceID)
C_UnitAuras.GetAuraDispelTypeColor(auraInstanceID)
C_UnitAuras.GetAuraApplicationDisplayCount(auraInstanceID)
```

### Restriction Query APIs

```lua
-- Check if secret restrictions are currently active
C_Secrets.HasSecretRestrictions()
C_Secrets.ShouldUnitSpellCastBeSecret(unit)
C_Secrets.ShouldUnitComparisonBeSecret(unit1, unit2)
C_Secrets.ShouldUnitAuraInstanceBeSecret(unit, auraInstanceID)

-- Restriction state change events
C_RestrictedActions -- namespace with restriction type queries
```

---

## SparkPoint Impact Assessment

### Safe (No Changes Needed)

| Component | Why Safe |
|---|---|
| **Cast ring** (player casts) | Player's own spellcast data is non-secret |
| **Class resources** (combo pts, holy power, runes, etc.) | Secondary resources whitelisted as non-secret |
| **Maelstrom Weapon** (Enhancement Shaman) | Uses aura stacks (`applications` field), whitelisted |

### Needs Migration (Currently Broken)

| Component | Current Pattern | Why It Breaks | Migration Path |
|---|---|---|---|
| **`API.SafeNumber()`** | `pcall(tostring, v)` → `tonumber()` | `tostring` fails on secrets | Use `issecretvalue()` to branch: pass secrets directly to widget APIs or use `AbbreviateNumbers()` for display |
| **`API.NormalizeCooldownInfo()`** | `SafeNumber()` on startTime/duration | Same | Use `StatusBar:SetTimer()` or Curve objects for cooldown display |
| **`API.FormatBarTextValue()`** | Falls back to `SafeNumber()` | Same | `AbbreviateNumbers()` already works (line 88); ensure it's the primary path, not the fallback |
| **`API.FormatBarTextPercent()`** | `pcall(tostring, v)` fallback | Same | `C_StringUtil.RoundToNearestString()` already used (line 120); make it primary |
| **Health bar provider** | `UnitHealth()` → `SafeReadableNumber()` | Health is secret in combat | Pass secret directly to `StatusBar:SetValue()`; use `UnitHealthPercent()` with Curves for display text |
| **Mana bar provider** | `UnitPower()` → `SafeReadableNumber()` | Mana is secret in combat | Same as health |
| **GCD provider** | `API.GetSpellCooldownInfo()` normalizes | Cooldown fields secret in combat | GCD spell is whitelisted; verify. If not, use `StatusBar:SetTimer()` |
| **SlotRingWidget.SetValueRange()** | `pcall(statusBar.SetValue)` | Already works — `SetValue` accepts secrets | Keep pcall wrapper; remove `IsSecretNumber` → spark suppression if Curves handle spark position |
| **BarSlotWidget.SetValueRange()** | `pcall(statusBar.SetValue)` | Already works | Same as above |

### Already Compatible

| Pattern | Location | Notes |
|---|---|---|
| `pcall(statusBar:SetValue, secret)` | SlotRingWidget, BarSlotWidget | Correct — widgets accept secrets |
| `issecretvalue()` detection | API.lua, SlotRingWidget | Correct — used to branch behavior |
| `AbbreviateNumbers(secret)` | API.FormatBarTextValue | Correct — accepts secrets in 12.0+ |
| `C_StringUtil.RoundToNearestString(secret)` | API.FormatBarTextPercent | Correct — accepts secrets in 12.0+ |

---

## Current SparkPoint Patterns (Needs Update)

### BROKEN: `SafeNumber()` in `Core/API.lua`
```lua
-- BROKEN in 12.0++ — tostring/tonumber fail on secret values
local function SafeNumber(value, fallback)
    if value == nil then return fallback end
    local ok, stringValue = pcall(tostring, value)
    if not ok then return fallback end
    return tonumber(stringValue) or fallback
end
```

### OK: Detection via `IsSecretReadableValue()` in `Core/API.lua`
```lua
-- Works — issecretvalue() is the correct detection API
local function IsSecretReadableValue(value)
    return value ~= nil and issecretvalue and issecretvalue(value)
end
```

### OK: Widget-safe passing in `Widgets/SlotRingWidget.lua`
```lua
-- Works — StatusBar natively accepts secret values
local okRange = pcall(self.statusBar.SetMinMaxValues, self.statusBar, 0, maxValue)
local okValue = pcall(self.statusBar.SetValue, self.statusBar, value)
```

---

## Development Policy

### Non-Negotiable Rules

1. **Never directly boolean-test a potentially secret field**: `if info.isEnabled then` is forbidden.
2. **Never perform arithmetic on a potentially secret value**: `secret + 1` will error.
3. **Never use secret values as table keys**: `cache[secretGUID] = data` will error.
4. **Never inspect the 12.1 `UNIT_AURA` payload while restricted**: use a unit-filtered event as a signal only.
5. **Never inspect a foreign UI object before checking access in 12.1**: use `CanBeAccessedInContext()` and reject secret results.

### Decision Flow When Encountering a Secret API

1. **Check if the value is actually secret** for the player unit — many values are non-secret for `"player"`.
2. **Check if a whitelisted alternative exists** (e.g., aura stacks instead of `UnitPower` for Maelstrom).
3. **Check if a Blizzard formatting/widget API accepts the secret** (e.g., `StatusBar:SetValue()`, `AbbreviateNumbers()`).
4. **If display-only**: use string concat or Curve objects.
5. **If logic-dependent**: check `C_Secrets.HasSecretRestrictions()` and branch behavior.
6. **If no stable path exists**: disable/drop the feature rather than shipping unstable behavior.

### Escalation Protocol

When blocked by secret values during development:
1. Identify and report the exact API field and call site.
2. Propose supported alternatives (different API, event, or narrower feature scope).
3. If no stable path exists, drop/disable the feature.

---

## Testing CVars (Non-Persistent)

Use these in-game to force secret behavior during development:

```
/console addonChatRestrictionsForced 1
/console secretAurasForced 1
/console secretCooldownsForced 1
/console secretUnitIdentityForced 1
/console secretSpellcastsForced 1
/console secretUnitPowerForced 1
/console secretUnitPowerMaxForced 1
/console secretUnitComparisonForced 1
```

These CVars do not persist across sessions.

---

## External References

- [Secret Values — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Secret_Values)
- [Patch 12.0.0 API Changes — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)
- [Patch 12.1.0 API Changes — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Patch_12.1.0/API_changes)
- [Combat Philosophy and Addon Disarmament — Blizzard](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight)
- [issecretvalue API — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_issecretvalue)
