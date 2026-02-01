-- SparkPoint API Utilities
-- Common utility functions using new WoW APIs (C_Spell.*, etc.)

local addonName, addon = ...

local API = {}
addon.API = API

--------------------------------------------------------------------------------
-- Spell Info (using new C_Spell API)
--------------------------------------------------------------------------------
function API.GetSpellInfo(spellID)
    if not spellID then return nil end
    local info = C_Spell.GetSpellInfo(spellID)
    if info then
        return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID
    end
    return nil
end

function API.GetSpellName(spellID)
    if not spellID then return nil end
    local info = C_Spell.GetSpellInfo(spellID)
    return info and info.name
end

function API.GetSpellTexture(spellID)
    if not spellID then return nil end
    local info = C_Spell.GetSpellInfo(spellID)
    return info and info.iconID
end

--------------------------------------------------------------------------------
-- Spell Cooldown (using new C_Spell API)
--------------------------------------------------------------------------------
function API.GetSpellCooldown(spellID)
    if not spellID then return 0, 0, 0 end
    if not C_Spell or not C_Spell.GetSpellCooldown then
        if GetSpellCooldown then
            local s, d, e = GetSpellCooldown(spellID)
            return s or 0, d or 0, e or 0
        end
        return 0, 0, 0
    end

    local a, b, c, d = C_Spell.GetSpellCooldown(spellID)
    if type(a) == "table" then
        local info = a
        return info.startTime or info.start or 0,
            info.duration or 0,
            (info.isEnabled and 1 or 0),
            info.modRate
    end

    return a or 0, b or 0, c or 0, d
end

--------------------------------------------------------------------------------
-- Class/Spec Detection
--------------------------------------------------------------------------------
function API.GetPlayerClass()
    local _, class = UnitClass("player")
    return class
end

function API.GetPlayerClassColor()
    local class = API.GetPlayerClass()
    if not class then
        return 1, 1, 1, 1
    end

    if CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class] then
        local c = CUSTOM_CLASS_COLORS[class]
        return c.r or 1, c.g or 1, c.b or 1, c.a or 1
    end

    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return c.r or 1, c.g or 1, c.b or 1, c.a or 1
    end

    if C_ClassColor and C_ClassColor.GetClassColor then
        local c = C_ClassColor.GetClassColor(class)
        if c and c.GetRGBA then
            return c:GetRGBA()
        elseif c and c.GetRGB then
            local r, g, b = c:GetRGB()
            return r, g, b, 1
        end
    end

    return 1, 1, 1, 1
end

function API.GetPlayerSpec()
    return GetSpecialization()
end

function API.GetPlayerSpecID()
    local spec = GetSpecialization()
    if spec then
        return GetSpecializationInfo(spec)
    end
    return nil
end

--------------------------------------------------------------------------------
-- Power Types
--------------------------------------------------------------------------------
local POWER_TYPES = {
    -- [className] = {[specIndex] = powerType, default = powerType}
    ROGUE = {default = Enum.PowerType.ComboPoints},
    DRUID = {
        [2] = Enum.PowerType.ComboPoints,  -- Feral
        [4] = Enum.PowerType.ComboPoints,  -- Guardian (cat form)
        [1] = Enum.PowerType.LunarPower,   -- Balance
        default = nil
    },
    PALADIN = {
        [3] = Enum.PowerType.HolyPower,    -- Retribution
        default = nil
    },
    MONK = {
        [3] = Enum.PowerType.Chi,          -- Windwalker
        default = nil
    },
    DEATHKNIGHT = {default = Enum.PowerType.Runes},
    WARLOCK = {default = Enum.PowerType.SoulShards},
    MAGE = {
        [1] = Enum.PowerType.ArcaneCharges, -- Arcane
        default = nil
    },
    DEMONHUNTER = {
        [1] = Enum.PowerType.Fury,         -- Havoc
        [2] = Enum.PowerType.Pain,         -- Vengeance
        default = Enum.PowerType.Fury
    },
    EVOKER = {default = Enum.PowerType.Essence},
    PRIEST = {
        [3] = Enum.PowerType.Insanity,     -- Shadow
        default = nil
    },
    SHAMAN = {
        [1] = Enum.PowerType.Maelstrom,    -- Elemental
        [2] = Enum.PowerType.Maelstrom,    -- Enhancement (Maelstrom Weapon stacks)
        default = nil
    },
}

function API.GetClassPowerType()
    local class = API.GetPlayerClass()
    local spec = API.GetPlayerSpec()

    local classPowers = POWER_TYPES[class]
    if not classPowers then return nil end

    local powerType = classPowers[spec] or classPowers.default

    -- Verify this power type is valid for the player
    if powerType then
        local maxPower = UnitPowerMax("player", powerType)
        if maxPower and maxPower > 0 then
            return powerType
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- Table Utilities
--------------------------------------------------------------------------------
function API.CopyTable(src, dest)
    dest = dest or {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            dest[k] = API.CopyTable(v)
        else
            dest[k] = v
        end
    end
    return dest
end

function API.TableContains(tbl, value)
    for _, v in pairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Math Utilities
--------------------------------------------------------------------------------
local rad, sin, cos = math.rad, math.sin, math.cos

function API.PointOnCircle(angle, radius, centerX, centerY)
    centerX = centerX or 0
    centerY = centerY or 0
    local radian = rad(angle)
    return centerX + cos(radian) * radius, centerY + sin(radian) * radius
end

--------------------------------------------------------------------------------
-- Color Utilities
--------------------------------------------------------------------------------
function API.RGBToHex(r, g, b)
    return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

function API.HexToRGB(hex)
    hex = hex:gsub("#", "")
    return tonumber(hex:sub(1,2), 16) / 255,
           tonumber(hex:sub(3,4), 16) / 255,
           tonumber(hex:sub(5,6), 16) / 255
end
