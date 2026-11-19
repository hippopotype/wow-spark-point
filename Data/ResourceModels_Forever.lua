-- SparkPoint Resource Models: WoW Forever (Camelot)
-- Forever has no specializations, so models are keyed by class (with druid form
-- overrides). Loaded only on Forever via the TOC ([AllowLoadGameType camelot]).

local _, addon = ...

-- Retail clients that do not know the camelot game type ignore the TOC tag and load this
-- file anyway; Core/Flavor.lua (loaded first) is the real gate.
if addon.Flavor.game ~= "Forever" then
	return
end

local ResourceModel = addon.ResourceModel
local ROLES = ResourceModel.Roles
local ResourceRef = ResourceModel.ResourceRef

local function ManaModel(notes)
	return {
		resources = { ResourceRef("MANA", ROLES.MANA) },
		notes = notes,
	}
end

local CLASS_MODELS = {
	WARRIOR = {
		resources = { ResourceRef("RAGE") },
		notes = "Warriors use Rage as their only resource.",
	},
	ROGUE = {
		resources = {
			ResourceRef("ENERGY"),
			ResourceRef("ROGUE_COMBO_POINTS", ROLES.SECONDARY),
		},
		notes = "Rogue combo points are target-bound on Forever.",
	},
	DRUID = {
		resources = { ResourceRef("MANA", ROLES.MANA) },
		formOverrides = {
			CAT = {
				resources = {
					ResourceRef("ENERGY"),
					ResourceRef("DRUID_COMBO_POINTS", ROLES.SECONDARY),
				},
			},
			BEAR = {
				resources = {
					ResourceRef("RAGE"),
					ResourceRef("MANA", ROLES.SECONDARY),
				},
			},
		},
		notes = "Druid swaps primary power with the active form; combo points only in Cat Form. The Bear Mana entry is a model marker only: nothing renders for it.",
	},
	HUNTER = ManaModel("Hunters use Mana."),
	PALADIN = ManaModel("Paladins use Mana."),
	PRIEST = ManaModel("Priests use Mana."),
	SHAMAN = ManaModel("Shamans use Mana."),
	MAGE = ManaModel("Mages use Mana."),
	WARLOCK = ManaModel("Warlocks use Mana."),
}

ResourceModel:SetModelData({ keyedBy = "class", models = CLASS_MODELS })
