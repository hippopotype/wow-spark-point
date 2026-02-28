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
	offset_x = 56,
	offset_y = -44,
	position_x = 400,
	position_y = 400,
	showMinimapButton = true,
	fadeMinimapButtonWhenNotHovered = false,
	minimapButtonFadeOpacity = 0,
	minimapButtonAngle = 225,
	visibility_mode = { ALWAYS = true },

	-- Module enable flags
	moduleEnabled_Cast = true,
	moduleEnabled_ClassResource = true,
	moduleEnabled_Ring = true,
	moduleEnabled_SpellIcon = true,
	moduleEnabled_AssistedHighlight = true,

	-- Cast module settings
	cast_radius = 40,
	cast_thickness = 20,
	cast_barColor = { r = 1, g = 1, b = 1, a = 0.8 },
	cast_backgroundOpacity = 0.8,
	cast_frameOpacity = 0.8,
	cast_glowOpacity = 0.8,
	cast_clickFeedbackEnabled = false,
	cast_clickFeedbackLeft = true,
	cast_clickFeedbackRight = true,
	cast_clickFeedbackOpacity = 0.55,
	cast_clickFeedbackUseClassColor = true,
	cast_clickFeedbackLeftColor = { r = 0.35, g = 0.35, b = 0.75, a = 0.75 },
	cast_clickFeedbackRightColor = { r = 0.35, g = 0.75, b = 0.35, a = 0.75 },
	cast_sparkColor = { r = 1, g = 0.82, b = 0.44, a = 0.72 },
	cast_sparkScale = 0.5,
	cast_latencyColor = { r = 1, g = 0.30, b = 0.44, a = 0.82 },
	cast_reverseChanneling = true,
	cast_useClassColor = true,
	cast_visibilitySource = "INHERIT",
	cast_visibility = { ALWAYS = true },
	cast_spellTextEnabled = false,
	cast_spellTextFont = "Fonts\\FRIZQT__.TTF",
	cast_spellTextSize = 12,
	cast_spellTextOutline = "OUTLINE",
	cast_spellTextColor = { r = 1, g = 1, b = 1, a = 0.8 },
	cast_spellTextOffsetX = 0,
	cast_spellTextOffsetY = 0,

	-- Inner ring slot settings (visuals are per-slot, regardless of provider)
	slot1_provider = "GCD",
	slot2_provider = "NONE",
	slot3_provider = "NONE",
	slot1_barColor = { r = 1, g = 1, b = 1, a = 0.18 },
	slot1_useClassColor = false,
	slot1_backgroundOpacity = 0.5,
	slot2_barColor = { r = 1, g = 1, b = 1, a = 0.18 },
	slot2_useClassColor = false,
	slot2_backgroundOpacity = 0.5,
	slot3_barColor = { r = 1, g = 1, b = 1, a = 0.18 },
	slot3_useClassColor = false,
	slot3_backgroundOpacity = 0.5,

	-- ClassResource module settings
	classresource_mode = "PIPS",
	classresource_visibilitySource = "INHERIT",
	classresource_visibility = { ALWAYS = true },
	classresource_font = "Fonts\\FRIZQT__.TTF",
	classresource_fontSize = 16,
	classresource_fontOutline = "",
	classresource_fontColor = { r = 1, g = 1, b = 1, a = 1 },
	classresource_useClassColor = false,
	classresource_textOffsetX = 0,
	classresource_textOffsetY = 0,
	classresource_scale = 1,
	classresource_opacity = 1,
	classresource_fillUseClassColor = true,
	classresource_offsetX = 0,
	classresource_offsetY = -50,

	-- Ring module settings
	ring_texture = "decorative_ring_1",
	ring_color = { r = 1, g = 1, b = 1, a = 0.18 },
	ring_width = 126,
	ring_rotate = true,
	ring_useClassColor = false,
	ring_classColorAlpha = 0.6,
	ring_visibilitySource = "INHERIT",
	ring_visibility = { ALWAYS = true },

	-- SpellIcon module settings
	spellicon_size = 40,
	spellicon_offsetX = 0,
	spellicon_offsetY = 0,
	spellicon_castProgressSwipe = false,
	spellicon_showInstantCasts = false,

	-- AssistedHighlight module settings
	assistedhighlight_size = 40,
	assistedhighlight_offsetX = 28,
	assistedhighlight_offsetY = 28,
	assistedhighlight_glowEnabled = true,
	assistedhighlight_visibilitySource = "INHERIT",
	assistedhighlight_visibility = { ALWAYS = true },
}
