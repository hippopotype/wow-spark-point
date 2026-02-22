-- SparkPoint Defaults
-- Single source of default settings for all profile-scoped addon options.

local _, addon = ...

addon.ProfileModes = {
	GLOBAL = "GLOBAL",
	CLASS = "CLASS",
}

-- Root SavedVariables defaults (non-profile-scoped)
addon.RootDefaultValues = {
	profileMode = addon.ProfileModes.GLOBAL,
	profileCopySource = "NONE",
}

-- Profile-scoped defaults
addon.DefaultValues = {
	-- Global/anchor settings
	attachToMouse = true,
	offset_x = 12,
	offset_y = -12,
	position_x = 400,
	position_y = 400,
	visibility_mode = "ALWAYS",

	-- Module enable flags
	moduleEnabled_Cast = true,
	moduleEnabled_ClassResource = true,
	moduleEnabled_Ring = true,
	moduleEnabled_SpellIcon = true,

	-- Cast module settings
	cast_radius = 22,
	cast_thickness = 20,
	cast_barColor = {r = 1, g = 1, b = 1, a = 0.8},
	cast_backgroundOpacity = 0.8,
	cast_frameOpacity = 0.8,
	cast_glowOpacity = 0.8,
	cast_sparkColor = {r = 0.9, g = 0.8, b = 1, a = 1},
	cast_sparkScale = 0.5,
	cast_latencyColor = {r = 1, g = 0, b = 0, a = 1},
	cast_reverseChanneling = false,
	cast_useClassColor = false,
	cast_visibilitySource = "INHERIT",
	cast_visibility = "ALWAYS",
	cast_spellTextEnabled = false,
	cast_spellTextFont = "Fonts\\FRIZQT__.TTF",
	cast_spellTextSize = 12,
	cast_spellTextOutline = "",
	cast_spellTextColor = {r = 1, g = 1, b = 1, a = 0.8},
	cast_spellTextOffsetX = 0,
	cast_spellTextOffsetY = 0,

	-- GCD provider settings
	gcd_sparkColor = {r = 0.9, g = 0.8, b = 1, a = 1},
	gcd_useClassColor = false,

	-- Inner ring slot settings
	slot1_provider = "GCD",
	slot2_provider = "NONE",
	slot3_provider = "NONE",
	slot1_barColor = {r = 1, g = 1, b = 1, a = 0.8},
	slot1_useClassColor = false,
	slot1_backgroundOpacity = 0.8,
	slot2_barColor = {r = 1, g = 1, b = 1, a = 0.8},
	slot2_useClassColor = false,
	slot2_backgroundOpacity = 0.8,
	slot3_barColor = {r = 1, g = 1, b = 1, a = 0.8},
	slot3_useClassColor = false,
	slot3_backgroundOpacity = 0.8,

	-- ClassResource module settings
	classresource_mode = "PIPS",
	classresource_visibilitySource = "INHERIT",
	classresource_visibility = "ALWAYS",
	classresource_font = "Fonts\\FRIZQT__.TTF",
	classresource_fontSize = 16,
	classresource_fontOutline = "",
	classresource_fontColor = {r = 1, g = 1, b = 1, a = 1},
	classresource_useClassColor = false,
	classresource_textOffsetX = 0,
	classresource_textOffsetY = 0,
	classresource_scale = 1,
	classresource_opacity = 1,
	classresource_fillUseClassColor = false,
	classresource_offsetX = 0,
	classresource_offsetY = 0,

	-- Ring module settings
	ring_texture = "decorative_ring_1",
	ring_color = {r = 0, g = 1, b = 0, a = 0.5},
	ring_width = 75,
	ring_rotate = true,
	ring_useClassColor = false,
	ring_classColorAlpha = 0.5,
	ring_visibilitySource = "INHERIT",
	ring_visibility = "ALWAYS",

	-- SpellIcon module settings
	spellicon_size = 32,
	spellicon_offsetX = 0,
	spellicon_offsetY = -40,
	spellicon_castProgressSwipe = true,
}
