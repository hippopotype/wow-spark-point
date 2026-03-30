-- SparkPoint Resource Model
-- Shared class/spec/form ownership for class resource pips and class power bars.
-- Pattern adapted from Blizzard PRD, SenseiClassResourceBar, and EnhanceQoL clone references.

local _, addon = ...

local ResourceModel = {}
addon.ResourceModel = ResourceModel

local GetSpecialization = GetSpecialization
local UnitClass = UnitClass
local UnitPowerType = UnitPowerType

ResourceModel.Owners = {
	CLASS_POWER = "CLASS_POWER",
	CLASS_RESOURCE = "CLASS_RESOURCE",
	MANA = "MANA",
	FUTURE_SPECIAL = "FUTURE_SPECIAL",
}

ResourceModel.SourceTypes = {
	POWER = "POWER",
	RUNES = "RUNES",
	AURA_STACKS = "AURA_STACKS",
	SPELL_COUNT = "SPELL_COUNT",
	SPECIAL = "SPECIAL",
}

ResourceModel.SystemIDs = {
	GENERIC_PIPS = "GENERIC_PIPS",
	DEATH_KNIGHT_RUNES = "DEATH_KNIGHT_RUNES",
	EVOKER_ESSENCE = "EVOKER_ESSENCE",
}

ResourceModel.Roles = {
	MAIN = "MAIN",
	SECONDARY = "SECONDARY",
	MANA = "MANA",
	FUTURE_SPECIAL = "FUTURE_SPECIAL",
	SUPPLEMENTAL = "SUPPLEMENTAL",
}

local OWNERS = ResourceModel.Owners
local SOURCES = ResourceModel.SourceTypes
local ROLES = ResourceModel.Roles
local SYSTEMS = ResourceModel.SystemIDs

local function ResourceRef(key, role)
	return {
		key = key,
		role = role or ROLES.MAIN,
	}
end

local RESOURCE_DEFS = {
	MANA = {
		key = "MANA",
		owner = OWNERS.MANA,
		sourceType = SOURCES.POWER,
		powerEnum = Enum.PowerType.Mana,
		powerToken = "MANA",
		needsFrequent = false,
		secretSensitive = true,
		secretNote = "Primary mana is secret in combat and should stay on the dedicated mana provider.",
	},
	ENERGY = {
		key = "ENERGY",
		owner = OWNERS.CLASS_POWER,
		sourceType = SOURCES.POWER,
		powerEnum = Enum.PowerType.Energy,
		powerToken = "ENERGY",
		needsFrequent = true,
		secretSensitive = true,
		secretNote = "Primary power is secret in combat; display via StatusBar APIs and Blizzard text formatters only.",
	},
	RAGE = {
		key = "RAGE",
		owner = OWNERS.CLASS_POWER,
		sourceType = SOURCES.POWER,
		powerEnum = Enum.PowerType.Rage,
		powerToken = "RAGE",
		needsFrequent = true,
		secretSensitive = true,
		secretNote = "Primary power is secret in combat; display via StatusBar APIs and Blizzard text formatters only.",
	},
	FOCUS = {
		key = "FOCUS",
		owner = OWNERS.CLASS_POWER,
		sourceType = SOURCES.POWER,
		powerEnum = Enum.PowerType.Focus,
		powerToken = "FOCUS",
		needsFrequent = true,
		secretSensitive = true,
		secretNote = "Primary power is secret in combat; display via StatusBar APIs and Blizzard text formatters only.",
	},
	FURY = {
		key = "FURY",
		owner = OWNERS.CLASS_POWER,
		sourceType = SOURCES.POWER,
		powerEnum = Enum.PowerType.Fury,
		powerToken = "FURY",
		needsFrequent = true,
		secretSensitive = true,
		secretNote = "Primary power is secret in combat; display via StatusBar APIs and Blizzard text formatters only.",
	},
	RUNIC_POWER = {
		key = "RUNIC_POWER",
		owner = OWNERS.CLASS_POWER,
		sourceType = SOURCES.POWER,
		powerEnum = Enum.PowerType.RunicPower,
		powerToken = "RUNIC_POWER",
		needsFrequent = false,
		secretSensitive = true,
		secretNote = "Primary power is secret in combat; display via StatusBar APIs and Blizzard text formatters only.",
	},
	LUNAR_POWER = {
		key = "LUNAR_POWER",
		owner = OWNERS.CLASS_POWER,
		sourceType = SOURCES.POWER,
		powerEnum = Enum.PowerType.LunarPower,
		powerToken = "LUNAR_POWER",
		needsFrequent = false,
		secretSensitive = true,
		secretNote = "Primary power is secret in combat; display via StatusBar APIs and Blizzard text formatters only.",
	},
	INSANITY = {
		key = "INSANITY",
		owner = OWNERS.CLASS_POWER,
		sourceType = SOURCES.POWER,
		powerEnum = Enum.PowerType.Insanity,
		powerToken = "INSANITY",
		needsFrequent = false,
		secretSensitive = true,
		secretNote = "Primary power is secret in combat; display via StatusBar APIs and Blizzard text formatters only.",
	},
	MAELSTROM = {
		key = "MAELSTROM",
		owner = OWNERS.CLASS_POWER,
		sourceType = SOURCES.POWER,
		powerEnum = Enum.PowerType.Maelstrom,
		powerToken = "MAELSTROM",
		needsFrequent = false,
		secretSensitive = true,
		secretNote = "Primary power is secret in combat; display via StatusBar APIs and Blizzard text formatters only.",
	},
	ROGUE_COMBO_POINTS = {
		key = "ROGUE_COMBO_POINTS",
		owner = OWNERS.CLASS_RESOURCE,
		systemID = SYSTEMS.GENERIC_PIPS,
		sourceType = SOURCES.POWER,
		powerEnum = Enum.PowerType.ComboPoints,
		powerToken = "COMBO_POINTS",
		maxCount = 5,
		needsFrequent = false,
		fillColor = { r = 1.00, g = 0.96, b = 0.00, a = 1.00 },
		emptyColor = { r = 0.40, g = 0.38, b = 0.00, a = 0.40 },
	},
	DRUID_COMBO_POINTS = {
		key = "DRUID_COMBO_POINTS",
		owner = OWNERS.CLASS_RESOURCE,
		systemID = SYSTEMS.GENERIC_PIPS,
		sourceType = SOURCES.POWER,
		powerEnum = Enum.PowerType.ComboPoints,
		powerToken = "COMBO_POINTS",
		maxCount = 5,
		needsFrequent = false,
		fillColor = { r = 1.00, g = 0.49, b = 0.04, a = 1.00 },
		emptyColor = { r = 0.40, g = 0.20, b = 0.02, a = 0.40 },
	},
	RUNES = {
		key = "RUNES",
		owner = OWNERS.CLASS_RESOURCE,
		systemID = SYSTEMS.DEATH_KNIGHT_RUNES,
		sourceType = SOURCES.RUNES,
		maxCount = 6,
		needsFrequent = false,
		fillColor = { r = 0.77, g = 0.12, b = 0.23, a = 1.00 },
		emptyColor = { r = 0.30, g = 0.06, b = 0.06, a = 0.40 },
	},
	SOUL_SHARDS = {
		key = "SOUL_SHARDS",
		owner = OWNERS.CLASS_RESOURCE,
		systemID = SYSTEMS.GENERIC_PIPS,
		sourceType = SOURCES.POWER,
		powerEnum = Enum.PowerType.SoulShards,
		powerToken = "SOUL_SHARDS",
		maxCount = 5,
		needsFrequent = false,
		fillColor = { r = 0.58, g = 0.51, b = 0.79, a = 1.00 },
		emptyColor = { r = 0.23, g = 0.20, b = 0.32, a = 0.40 },
	},
	HOLY_POWER = {
		key = "HOLY_POWER",
		owner = OWNERS.CLASS_RESOURCE,
		systemID = SYSTEMS.GENERIC_PIPS,
		sourceType = SOURCES.POWER,
		powerEnum = Enum.PowerType.HolyPower,
		powerToken = "HOLY_POWER",
		maxCount = 5,
		needsFrequent = false,
		fillColor = { r = 0.95, g = 0.89, b = 0.59, a = 1.00 },
		emptyColor = { r = 0.30, g = 0.28, b = 0.18, a = 0.40 },
	},
	CHI = {
		key = "CHI",
		owner = OWNERS.CLASS_RESOURCE,
		systemID = SYSTEMS.GENERIC_PIPS,
		sourceType = SOURCES.POWER,
		powerEnum = Enum.PowerType.Chi,
		powerToken = "CHI",
		maxCount = 5,
		needsFrequent = false,
		fillColor = { r = 0.00, g = 1.00, b = 0.59, a = 1.00 },
		emptyColor = { r = 0.00, g = 0.40, b = 0.24, a = 0.40 },
	},
	ARCANE_CHARGES = {
		key = "ARCANE_CHARGES",
		owner = OWNERS.CLASS_RESOURCE,
		systemID = SYSTEMS.GENERIC_PIPS,
		sourceType = SOURCES.POWER,
		powerEnum = Enum.PowerType.ArcaneCharges,
		powerToken = "ARCANE_CHARGES",
		maxCount = 4,
		needsFrequent = false,
		fillColor = { r = 0.41, g = 0.80, b = 0.94, a = 1.00 },
		emptyColor = { r = 0.16, g = 0.32, b = 0.38, a = 0.40 },
	},
	ESSENCE = {
		key = "ESSENCE",
		owner = OWNERS.CLASS_RESOURCE,
		systemID = SYSTEMS.EVOKER_ESSENCE,
		sourceType = SOURCES.POWER,
		powerEnum = Enum.PowerType.Essence,
		powerToken = "ESSENCE",
		maxCount = 6,
		needsFrequent = false,
		needsPointCharge = true,
		fillColor = { r = 0.20, g = 0.58, b = 0.50, a = 1.00 },
		emptyColor = { r = 0.08, g = 0.23, b = 0.20, a = 0.40 },
	},
	MAELSTROM_WEAPON = {
		key = "MAELSTROM_WEAPON",
		owner = OWNERS.CLASS_RESOURCE,
		systemID = SYSTEMS.GENERIC_PIPS,
		sourceType = SOURCES.AURA_STACKS,
		auraSpellID = 344179,
		maxCount = 5,
		needsFrequent = false,
		needsUnitAura = true,
		fillColor = { r = 0.00, g = 0.44, b = 0.87, a = 1.00 },
		emptyColor = { r = 0.00, g = 0.18, b = 0.35, a = 0.40 },
	},
	STAGGER = {
		key = "STAGGER",
		owner = OWNERS.FUTURE_SPECIAL,
		sourceType = SOURCES.SPECIAL,
		futureProvider = "MONK_STAGGER",
		needsFrequent = false,
		secretSensitive = false,
	},
	SOUL_FRAGMENTS_VENGEANCE = {
		key = "SOUL_FRAGMENTS_VENGEANCE",
		owner = OWNERS.FUTURE_SPECIAL,
		sourceType = SOURCES.SPELL_COUNT,
		futureProvider = "DEMON_HUNTER_VENGEANCE_SOUL_FRAGMENTS",
		needsFrequent = false,
		secretSensitive = true,
	},
	SOUL_FRAGMENTS = {
		key = "SOUL_FRAGMENTS",
		owner = OWNERS.FUTURE_SPECIAL,
		sourceType = SOURCES.AURA_STACKS,
		futureProvider = "DEMON_HUNTER_DEVOURER_ALTERNATE_POWER",
		needsFrequent = false,
		needsUnitAura = true,
		secretSensitive = false,
	},
	VOID_METAMORPHOSIS = {
		key = "VOID_METAMORPHOSIS",
		owner = OWNERS.FUTURE_SPECIAL,
		sourceType = SOURCES.SPECIAL,
		futureProvider = "DEMON_HUNTER_DEVOURER_ALTERNATE_POWER",
		needsFrequent = false,
		secretSensitive = false,
	},
	TIP_OF_THE_SPEAR = {
		key = "TIP_OF_THE_SPEAR",
		owner = OWNERS.FUTURE_SPECIAL,
		sourceType = SOURCES.AURA_STACKS,
		futureProvider = "HUNTER_SURVIVAL_TIP_OF_THE_SPEAR",
		needsUnitAura = true,
	},
	ICICLES = {
		key = "ICICLES",
		owner = OWNERS.FUTURE_SPECIAL,
		sourceType = SOURCES.AURA_STACKS,
		futureProvider = "MAGE_FROST_ICICLES",
		needsUnitAura = true,
	},
	WHIRLWIND = {
		key = "WHIRLWIND",
		owner = OWNERS.FUTURE_SPECIAL,
		sourceType = SOURCES.SPECIAL,
		futureProvider = "WARRIOR_FURY_WHIRLWIND",
	},
	EBON_MIGHT = {
		key = "EBON_MIGHT",
		owner = OWNERS.FUTURE_SPECIAL,
		sourceType = SOURCES.AURA_STACKS,
		futureProvider = "EVOKER_AUGMENTATION_EBON_MIGHT",
		needsUnitAura = true,
	},
}

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

local EMPTY_RESOURCES = {}

local function GetCurrentDruidFormKey(context)
	if context.classTag ~= "DRUID" then
		return nil
	end

	local token = context.displayPowerToken
	if token == "ENERGY" then
		return "CAT"
	elseif token == "RAGE" then
		return "BEAR"
	elseif token == "LUNAR_POWER" then
		return "MOONKIN"
	end

	return "HUMANOID"
end

local function ExpandResources(resourceRefs)
	if not resourceRefs then
		return EMPTY_RESOURCES
	end

	local resources = {}
	for _, ref in ipairs(resourceRefs) do
		local def = RESOURCE_DEFS[ref.key]
		if def then
			resources[#resources + 1] = {
				key = ref.key,
				role = ref.role,
				def = def,
			}
		end
	end
	return resources
end

function ResourceModel:GetCurrentContext(unit)
	unit = unit or "player"

	local _, classTag = UnitClass(unit)
	local spec = GetSpecialization() or 0
	local displayPowerEnum, displayPowerToken = UnitPowerType(unit)

	local context = {
		unit = unit,
		classTag = classTag,
		spec = spec,
		displayPowerEnum = displayPowerEnum,
		displayPowerToken = displayPowerToken,
	}
	context.druidForm = GetCurrentDruidFormKey(context)
	return context
end

function ResourceModel:Resolve(unit)
	local context = self:GetCurrentContext(unit)
	local classModels = context.classTag and SPEC_MODELS[context.classTag] or nil
	local specModel = classModels and classModels[context.spec] or nil

	if not specModel then
		return {
			context = context,
			specModel = nil,
			resources = EMPTY_RESOURCES,
		}
	end

	local resourceRefs = specModel.resources
	if context.druidForm and specModel.formOverrides then
		local formModel = specModel.formOverrides[context.druidForm]
		if formModel and formModel.resources then
			resourceRefs = formModel.resources
		end
	end

	return {
		context = context,
		specModel = specModel,
		resources = ExpandResources(resourceRefs),
	}
end

local function FindResourceByOwner(resolved, owner)
	if not resolved or not resolved.resources then
		return nil
	end

	for _, entry in ipairs(resolved.resources) do
		if entry.role ~= ROLES.SUPPLEMENTAL and entry.def.owner == owner then
			return entry.def, entry
		end
	end

	return nil
end

function ResourceModel:GetCurrentClassResource(unit)
	local resolved = self:Resolve(unit)
	local resource = FindResourceByOwner(resolved, OWNERS.CLASS_RESOURCE)
	return resource, resolved
end

function ResourceModel:GetCurrentClassPower(unit)
	local resolved = self:Resolve(unit)
	local resource = FindResourceByOwner(resolved, OWNERS.CLASS_POWER)
	return resource, resolved
end

function ResourceModel:GetCurrentFutureSpecial(unit)
	local resolved = self:Resolve(unit)
	local resource = FindResourceByOwner(resolved, OWNERS.FUTURE_SPECIAL)
	return resource, resolved
end

function ResourceModel:GetResourceDefinition(key)
	return RESOURCE_DEFS[key]
end
