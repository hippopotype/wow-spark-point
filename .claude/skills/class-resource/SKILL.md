---
name: class-resource
description: SparkPoint class resource development guide — shared resource model, pluggable resource systems, event selection, Blizzard parity decisions.
user-invocable: true
allowed-tools: Read, Grep, Glob
---

!`cat "${CLAUDE_SKILL_DIR}/../../../.skills/.private/class-resource.md"`

## Target-held combo points (Forever)

- Defs with `comboPoints = true` (`ROGUE_COMBO_POINTS`, `DRUID_COMBO_POINTS`) read through `addon.API.GetComboPoints(maxFallback)`; with `addon.Has("comboPointsOnTarget")` a nil current hides the pips (never the root) and a nil max counts as 0.
- Systems may expose `HandleTargetEvent(event)` for `PLAYER_TARGET_CHANGED` / `COMBO_TARGET_CHANGED`: it re-reads and `Sync`s. `GenericPips` snaps without transitions on `PLAYER_TARGET_CHANGED`; the Rogue and Druid classic systems animate the change. `WantsEvent` accepts these (and `UNIT_POWER_FREQUENT`) only behind the capability.
