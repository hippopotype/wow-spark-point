-- SparkPoint range check spell lists: Forever
-- Candidate hostile spells per class for the Decorative Ring out-of-range tint, ordered
-- longest reach first; Automatic picks the first known one. A spell with a minimum range
-- also checks the first known candidate with no minimum range that reaches no further
-- than the chosen spell's minimum range (a true melee spell, the melee companion: Taunt,
-- Sinister Strike, Raptor Strike), so being too close counts as in range.
-- All IDs are unverified in game; see docs/superpowers/plans/range-spells-check.txt.
-- Friendly lists (opt-in friendly-target check) are class-keyed, longest reach first;
-- classes without a usable friendly spell are omitted.
-- Loaded only on Forever via the TOC ([AllowLoadGameType camelot]).

local _, addon = ...

-- Clients that do not know the game type ignore the TOC tag and load this file anyway;
-- Core/Flavor.lua (loaded first) is the real gate.
if addon.Flavor.game ~= "Forever" then
	return
end

-- Rank-1 spell IDs; Shoot IDs from Blizzard's HostileTargetingActionBar.
addon.RangeSpells = {
	WARRIOR = { 2480, 7918, 2764, 7919, 355 }, -- Shoot Bow, Shoot Gun, Throw, Shoot Crossbow, Taunt
	ROGUE = { 2480, 7918, 2764, 7919, 1752 }, -- Shoot Bow, Shoot Gun, Throw, Shoot Crossbow, Sinister Strike
	HUNTER = { 3044, 5116, 75, 2973 }, -- Arcane Shot, Concussive Shot, Auto Shot, Raptor Strike
	MAGE = { 133, 116, 5019 }, -- Fireball, Frostbolt, Shoot (wand)
	PRIEST = { 585, 589, 5019 }, -- Smite, Shadow Word: Pain, Shoot (wand)
	WARLOCK = { 686, 348, 5019 }, -- Shadow Bolt, Immolate, Shoot (wand)
	DRUID = { 5176, 8921 }, -- Wrath, Moonfire
	SHAMAN = { 403, 8042 }, -- Lightning Bolt, Earth Shock
	PALADIN = { 24275, 20271, 853 }, -- Hammer of Wrath, Judgement, Hammer of Justice
}

-- Rank-1 friendly spell IDs.
addon.FriendlyRangeSpells = {
	DRUID = { 5185, 774, 8936 }, -- Healing Touch, Rejuvenation, Regrowth
	PRIEST = { 2050, 17 }, -- Lesser Heal, Power Word: Shield
	PALADIN = { 635, 19750 }, -- Holy Light, Flash of Light
	SHAMAN = { 331, 8004 }, -- Healing Wave, Lesser Healing Wave
	MAGE = { 1459 }, -- Arcane Intellect
	WARLOCK = { 5697 }, -- Unending Breath
}
