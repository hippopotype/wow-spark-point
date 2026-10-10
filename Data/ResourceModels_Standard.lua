-- SparkPoint Resource Models: retail ("Standard")
-- Spec-keyed class resource ownership. Loaded only on retail via the TOC
-- ([AllowLoadGameType standard]); registers itself with ResourceModel.

local _, addon = ...
local ResourceModel = addon.ResourceModel
local ROLES = ResourceModel.Roles
local ResourceRef = ResourceModel.ResourceRef

local SPEC_MODELS = {
	DRUID = {
		[1] = {
			resources = {
				ResourceRef("LUNAR_POWER"),
				ResourceRef("MANA", ROLES.MANA),
			},
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
			notes = "Balance keeps combo points only in Cat Form and swaps primary power with the active druid form.",
		},
		[2] = {
			resources = {
				ResourceRef("MANA", ROLES.MANA),
			},
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
			notes = "Feral only owns combo points in Cat Form; non-cat forms should fail cleanly.",
		},
		[3] = {
			resources = {
				ResourceRef("MANA", ROLES.MANA),
			},
			formOverrides = {
				BEAR = {
					resources = {
						ResourceRef("RAGE"),
						ResourceRef("MANA", ROLES.SECONDARY),
					},
				},
				CAT = {
					resources = {
						ResourceRef("ENERGY"),
						ResourceRef("DRUID_COMBO_POINTS", ROLES.SECONDARY),
					},
				},
			},
			notes = "Guardian swaps between bear rage and cat combo logic by form.",
		},
		[4] = {
			resources = {
				ResourceRef("MANA", ROLES.MANA),
			},
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
			notes = "Restoration has no generic class power in caster form, but druid form swaps still matter.",
		},
	},
	DEMONHUNTER = {
		[1] = {
			resources = {
				ResourceRef("FURY"),
			},
		},
		[2] = {
			resources = {
				ResourceRef("FURY"),
				ResourceRef("SOUL_FRAGMENTS_VENGEANCE", ROLES.FUTURE_SPECIAL),
			},
			notes = "Vengeance keeps Fury as the generic class power and defers soul-fragment handling.",
		},
		[3] = {
			resources = {
				ResourceRef("VOID_METAMORPHOSIS", ROLES.FUTURE_SPECIAL),
				ResourceRef("FURY", ROLES.SUPPLEMENTAL),
				ResourceRef("SOUL_FRAGMENTS", ROLES.FUTURE_SPECIAL),
			},
			notes = "Devourer requires a dedicated alternate-power provider; generic Fury support remains supplemental only.",
		},
	},
	DEATHKNIGHT = {
		[1] = { resources = { ResourceRef("RUNIC_POWER"), ResourceRef("RUNES", ROLES.SECONDARY) } },
		[2] = { resources = { ResourceRef("RUNIC_POWER"), ResourceRef("RUNES", ROLES.SECONDARY) } },
		[3] = { resources = { ResourceRef("RUNIC_POWER"), ResourceRef("RUNES", ROLES.SECONDARY) } },
	},
	PALADIN = {
		[1] = { resources = { ResourceRef("HOLY_POWER"), ResourceRef("MANA", ROLES.MANA) } },
		[2] = { resources = { ResourceRef("HOLY_POWER"), ResourceRef("MANA", ROLES.MANA) } },
		[3] = { resources = { ResourceRef("HOLY_POWER"), ResourceRef("MANA", ROLES.MANA) } },
	},
	HUNTER = {
		[1] = { resources = { ResourceRef("FOCUS") } },
		[2] = { resources = { ResourceRef("FOCUS") } },
		[3] = {
			resources = {
				ResourceRef("FOCUS"),
				ResourceRef("TIP_OF_THE_SPEAR", ROLES.FUTURE_SPECIAL),
			},
		},
	},
	ROGUE = {
		[1] = { resources = { ResourceRef("ENERGY"), ResourceRef("ROGUE_COMBO_POINTS", ROLES.SECONDARY) } },
		[2] = { resources = { ResourceRef("ENERGY"), ResourceRef("ROGUE_COMBO_POINTS", ROLES.SECONDARY) } },
		[3] = { resources = { ResourceRef("ENERGY"), ResourceRef("ROGUE_COMBO_POINTS", ROLES.SECONDARY) } },
	},
	PRIEST = {
		[1] = { resources = { ResourceRef("MANA", ROLES.MANA) } },
		[2] = { resources = { ResourceRef("MANA", ROLES.MANA) } },
		[3] = { resources = { ResourceRef("INSANITY"), ResourceRef("MANA", ROLES.SECONDARY) } },
	},
	SHAMAN = {
		[1] = { resources = { ResourceRef("MAELSTROM"), ResourceRef("MANA", ROLES.SECONDARY) } },
		[2] = { resources = { ResourceRef("MAELSTROM_WEAPON"), ResourceRef("MANA", ROLES.MANA) } },
		[3] = { resources = { ResourceRef("MANA", ROLES.MANA) } },
	},
	MAGE = {
		[1] = { resources = { ResourceRef("ARCANE_CHARGES"), ResourceRef("MANA", ROLES.MANA) } },
		[2] = { resources = { ResourceRef("MANA", ROLES.MANA) } },
		[3] = {
			resources = {
				ResourceRef("MANA", ROLES.MANA),
				ResourceRef("ICICLES", ROLES.FUTURE_SPECIAL),
			},
		},
	},
	WARLOCK = {
		[1] = { resources = { ResourceRef("SOUL_SHARDS"), ResourceRef("MANA", ROLES.MANA) } },
		[2] = { resources = { ResourceRef("SOUL_SHARDS"), ResourceRef("MANA", ROLES.MANA) } },
		[3] = { resources = { ResourceRef("SOUL_SHARDS"), ResourceRef("MANA", ROLES.MANA) } },
	},
	MONK = {
		[1] = {
			resources = {
				ResourceRef("ENERGY"),
				ResourceRef("STAGGER", ROLES.FUTURE_SPECIAL),
			},
			notes = "Brewmaster keeps Energy as generic power and defers Stagger to a future special provider.",
		},
		[2] = { resources = { ResourceRef("MANA", ROLES.MANA) } },
		[3] = {
			resources = {
				ResourceRef("CHI"),
				ResourceRef("ENERGY", ROLES.SECONDARY),
				ResourceRef("MANA", ROLES.MANA),
			},
		},
	},
	EVOKER = {
		[1] = { resources = { ResourceRef("ESSENCE"), ResourceRef("MANA", ROLES.MANA) } },
		[2] = { resources = { ResourceRef("ESSENCE"), ResourceRef("MANA", ROLES.MANA) } },
		[3] = {
			resources = {
				ResourceRef("ESSENCE"),
				ResourceRef("MANA", ROLES.MANA),
				ResourceRef("EBON_MIGHT", ROLES.FUTURE_SPECIAL),
			},
		},
	},
	WARRIOR = {
		[1] = { resources = { ResourceRef("RAGE") } },
		[2] = {
			resources = {
				ResourceRef("RAGE"),
				ResourceRef("WHIRLWIND", ROLES.FUTURE_SPECIAL),
			},
		},
		[3] = { resources = { ResourceRef("RAGE") } },
	},
}

ResourceModel:SetModelData({ keyedBy = "spec", models = SPEC_MODELS })
