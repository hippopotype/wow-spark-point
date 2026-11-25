-- SparkPoint range check spell lists: Standard
-- Candidate hostile spells per class for the Decorative Ring out-of-range tint, ordered
-- longest reach first (baseline ~30-40 yd), then shorter or min-range spells; Automatic
-- picks the first known one. A spell with a minimum range also checks the first known
-- candidate with no minimum range that reaches no further than the chosen spell's
-- minimum range (a true melee spell; the melee companion), so being too close counts
-- as in range.
-- Friendly lists (opt-in friendly-target check) are class-keyed, longest reach first;
-- classes without a usable friendly spell are omitted.
-- Loaded only on Standard via the TOC ([AllowLoadGameType standard]).

local _, addon = ...

-- Clients that do not know the game type ignore the TOC tag and load this file anyway;
-- Core/Flavor.lua (loaded first) is the real gate.
if addon.Flavor.game ~= "Standard" then
	return
end

addon.RangeSpells = {
	DEATHKNIGHT = { 47541, 49576 }, -- Death Coil, Death Grip
	DEMONHUNTER = { 185123, 278326 }, -- Throw Glaive, Consume Magic
	DRUID = { 8921, 5176 }, -- Moonfire, Wrath
	EVOKER = { 362969, 361469 }, -- Azure Strike, Living Flame
	HUNTER = { 185358, 259495, 75, 190925 }, -- Arcane Shot, Wildfire Bomb (Survival), Auto Shot, Harpoon (Survival)
	MAGE = { 2139, 116, 133 }, -- Counterspell, Frostbolt, Fireball
	MONK = { 117952, 115546 }, -- Crackling Jade Lightning, Provoke
	PALADIN = { 20271, 20473, 62124 }, -- Judgment, Holy Shock, Hand of Reckoning
	PRIEST = { 589, 585 }, -- Shadow Word: Pain, Smite
	ROGUE = { 185565, 185763, 114014, 36554 }, -- Poisoned Knife (Assassination), Pistol Shot (Outlaw), Shuriken Toss (Subtlety), Shadowstep
	SHAMAN = { 188196, 8042 }, -- Lightning Bolt, Earth Shock
	WARLOCK = { 234153, 686 }, -- Drain Life, Shadow Bolt
	WARRIOR = { 355, 100 }, -- Taunt, Charge
}

addon.FriendlyRangeSpells = {
	DRUID = { 8936, 774 }, -- Regrowth, Rejuvenation
	EVOKER = { 361469, 355913 }, -- Living Flame, Emerald Blossom
	MAGE = { 1459, 475 }, -- Arcane Intellect, Remove Curse
	MONK = { 116670, 115450 }, -- Vivify, Detox
	PALADIN = { 19750, 85673 }, -- Flash of Light, Word of Glory
	PRIEST = { 2061, 17, 21562 }, -- Flash Heal, Power Word: Shield, Power Word: Fortitude
	SHAMAN = { 8004 }, -- Healing Surge
	WARLOCK = { 5697, 20707 }, -- Unending Breath, Soulstone
}
