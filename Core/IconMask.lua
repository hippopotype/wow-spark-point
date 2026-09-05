-- SparkPoint Icon Mask Utilities
-- Shared helpers for masked icon rendering used by multiple modules.

local _, addon = ...

local IconMask = {}
addon.IconMask = IconMask

local MASK_PATH = addon.addonFolder .. "\\Textures\\spell_icon_mask.png"
local DEFAULT_BASE_SIZE = 32
local DEFAULT_BASE_EXPAND = 6

function IconMask:CalculateExpand(iconSize, baseExpand, baseSize)
	local resolvedSize = tonumber(iconSize) or DEFAULT_BASE_SIZE
	local resolvedBaseSize = tonumber(baseSize) or DEFAULT_BASE_SIZE
	local resolvedBaseExpand = tonumber(baseExpand) or DEFAULT_BASE_EXPAND

	local expand = math.floor((resolvedSize / resolvedBaseSize) * resolvedBaseExpand + 0.5)
	if expand < 0 then
		expand = 0
	end
	return expand
end

function IconMask:LayoutToIcon(region, icon, baseExpand, baseSize)
	if not region or not icon then
		return
	end

	local iconSize = icon:GetWidth() or DEFAULT_BASE_SIZE
	local expand = self:CalculateExpand(iconSize, baseExpand, baseSize)

	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", icon, "TOPLEFT", -expand, expand)
	region:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", expand, -expand)
end

function IconMask:ApplyToIconFrame(iconFrame, baseExpand, baseSize)
	if not iconFrame or not iconFrame.icon then
		return false
	end

	local icon = iconFrame.icon
	if not icon.AddMaskTexture then
		return false
	end

	iconFrame.iconMask = iconFrame.iconMask or iconFrame:CreateMaskTexture()
	local mask = iconFrame.iconMask
	if not mask then
		return false
	end

	mask:SetTexture(MASK_PATH, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	self:LayoutToIcon(mask, icon, baseExpand, baseSize)

	if not iconFrame.iconMaskAttached then
		local ok = pcall(icon.AddMaskTexture, icon, mask)
		if not ok then
			return false
		end
		iconFrame.iconMaskAttached = true
	end

	if iconFrame.cooldown and not iconFrame.cooldownMaskAttached then
		local maskedAny = false
		local regionCount = select("#", iconFrame.cooldown:GetRegions())
		for i = 1, regionCount do
			local region = select(i, iconFrame.cooldown:GetRegions())
			if region and region.GetObjectType and region:GetObjectType() == "Texture" and region.AddMaskTexture then
				local ok = pcall(region.AddMaskTexture, region, mask)
				if ok then
					maskedAny = true
				end
			end
		end
		if maskedAny then
			iconFrame.cooldownMaskAttached = true
		end
	end

	return true
end
