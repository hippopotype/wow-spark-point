-- SparkPoint default overrides: WoW Forever (Camelot)
-- Per-game defaults live here, never as branches in Core/Defaults.lua. Loaded only on
-- Forever via the TOC ([AllowLoadGameType camelot]), after Core/Defaults.lua and before
-- Core/Database.lua applies defaults.

local _, addon = ...

-- Swing timers matter more than the GCD on Forever; the Outer Ring Slot shows Swing (Auto).
addon.DefaultValues.innerslot_outer_provider = "SWING"
