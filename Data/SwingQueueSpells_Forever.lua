-- SparkPoint swing timer queue spells: WoW Forever (Camelot)
-- Next-melee attacks per class, as rank-1 spell IDs; Core/SwingTimer.lua also checks
-- each by name so the player's known rank is found. Loaded only on Forever via the
-- TOC ([AllowLoadGameType camelot]).

local _, addon = ...

-- Retail clients that do not know the camelot game type ignore the TOC tag and load this
-- file anyway; Core/Flavor.lua (loaded first) is the real gate.
if addon.Flavor.game ~= "Forever" then
	return
end

addon.SwingQueueSpells = {
	WARRIOR = { 78, 845 }, -- Heroic Strike, Cleave
	DRUID = { 6807 }, -- Maul
	HUNTER = { 2973 }, -- Raptor Strike
}
