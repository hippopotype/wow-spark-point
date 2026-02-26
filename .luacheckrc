std = "lua51"
max_line_length = false
exclude_files = { ".clones/**", ".git/**" }
ignore = {
    "11./SLASH_.*",
    "211", "212", "213",
    "42.", "43.",
    "512",  -- loop executed at most once (intentional early-break pattern)
}
globals = {
    "_G", "bit",
    -- WoW API
    "C_ClassColor", "C_Spell", "C_Timer", "C_UnitAuras",
    "CreateColor", "CreateFrame", "CreateFramePool", "CreateFromMixins",
    "CUSTOM_CLASS_COLORS",
    "ColorPickerFrame", "DEFAULT_CHAT_FRAME",
    "EditModeManagerFrame",
    "GameTooltip",
    "EventRegistry",
    "GetCursorPosition", "GetNetStats", "GetRuneCooldown", "GetSpecialization", "GetTime",
    "GetMinimapShape",
    "GRAY_FONT_COLOR",
    "InCombatLockdown",
    "IsInGroup",
    "IsInInstance",
    "IsInRaid",
    "IsMouseButtonDown",
    "LOCALIZED_CLASS_NAMES_FEMALE", "LOCALIZED_CLASS_NAMES_MALE",
    "MinimalSliderWithSteppersMixin",
    "Minimap",
    "RAID_CLASS_COLORS", "ReloadUI",
    "Settings", "SettingsListElementMixin",
    "SLASH_SPARKPOINT1", "SLASH_SPARKPOINT2", "SlashCmdList", "SparkPointDB",
    "StaticPopup_Show", "StaticPopupDialogs", "STATICPOPUP_NUMDIALOGS",
    "UIParent",
    "UnitAffectingCombat", "UnitCastingInfo", "UnitChannelInfo", "UnitClass", "UnitExists",
    "UnitPower", "UnitPowerMax",
    -- WoW locale strings
    "ACCEPT", "CANCEL", "Enum",
    -- WoW font objects
    "GameFontNormalSmall", "GameFontDisableSmall",
    -- Addon XML mixin
    "SparkPointColorOverridesMixin",
}
