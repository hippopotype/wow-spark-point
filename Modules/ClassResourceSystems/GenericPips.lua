-- SparkPoint Generic Pips Class Resource System
-- Shared implementation for discrete pip-style resources.

local _, addon = ...
local API = addon.API
local ResourceModel = addon.ResourceModel
local ClassResourceSystems = addon.ClassResourceSystems
local GetDBValue = addon.GetDBValue
local GetDBColor = addon.GetDBColor

local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local GetRuneCooldown = GetRuneCooldown

local PIP_TEXTURE_FRAME_PATH = "Interface\\AddOns\\SparkPoint\\Textures\\class_resource_frame.png"
local PIP_TEXTURE_BG_PATH = "Interface\\AddOns\\SparkPoint\\Textures\\class_resource_background.png"
local PIP_TEXTURE_FILL_PATH = "Interface\\AddOns\\SparkPoint\\Textures\\class_resource_fill.png"
local PIP_TEXTURE_FALLBACK = "Interface\\Buttons\\WHITE8x8"

local PIP_SIZE = 18
local PIP_SPACING = 4

local function NormalizePowerValue(value)
	if value == nil then
		return 0
	end
	if type(value) == "number" then
		return value
	end

	local s = tostring(value) or "0"
	local n = tonumber(s)
	if n then
		return n
	end

	local token = s:match("[-+]?%d+%.?%d*")
	return tonumber(token) or 0
end

local function SetTextureSmooth(tex, path)
	local ok = pcall(tex.SetTexture, tex, path, nil, nil, "TRILINEAR")
	if not ok then
		tex:SetTexture(path)
	end
	if tex.SetSnapToPixelGrid then
		tex:SetSnapToPixelGrid(false)
	end
	if tex.SetTexelSnappingBias then
		tex:SetTexelSnappingBias(0)
	end
end

local GenericPips = {}
GenericPips.__index = GenericPips

function GenericPips:Initialize(parentFrame)
	self.parentFrame = parentFrame

	if self.root then
		return
	end

	self.root = CreateFrame("Frame", nil, parentFrame)
	self.root:SetPoint("CENTER")
	self.root:SetSize(1, 1)
	self.root:Hide()
end

function GenericPips:Shutdown()
	self.activeResource = nil
	self.resolved = nil
	self.pipMax = 0

	if self.root then
		self.root:Hide()
	end
end

function GenericPips:SetResource(resourceDef, resolved)
	self.activeResource = resourceDef
	self.resolved = resolved
	self.pipMax = 0

	for i = 1, #self.pips do
		self.pips[i].styleReady = false
	end
end

function GenericPips:GetPip(index)
	if self.pips[index] then
		return self.pips[index]
	end

	if not self.root then
		return nil
	end

	local pip = {
		frame = self.root:CreateTexture(nil, "ARTWORK", nil, 2),
		bg = self.root:CreateTexture(nil, "ARTWORK", nil, 0),
		fill = self.root:CreateTexture(nil, "ARTWORK", nil, 1),
		styleReady = false,
	}

	pip.frame:Hide()
	pip.bg:Hide()
	pip.fill:Hide()
	self.pips[index] = pip
	return pip
end

function GenericPips:ConfigurePipTextures(pip, resource)
	if not pip then
		return
	end

	pip.frame:SetTexCoord(0, 1, 0, 1)
	pip.bg:SetTexCoord(0, 1, 0, 1)
	pip.fill:SetTexCoord(0, 1, 0, 1)

	SetTextureSmooth(pip.frame, PIP_TEXTURE_FRAME_PATH)
	SetTextureSmooth(pip.bg, PIP_TEXTURE_BG_PATH)
	SetTextureSmooth(pip.fill, PIP_TEXTURE_FILL_PATH)

	if not pip.frame:GetTexture() then
		pip.frame:SetTexture(PIP_TEXTURE_FALLBACK)
	end
	if not pip.bg:GetTexture() then
		pip.bg:SetTexture(PIP_TEXTURE_FALLBACK)
	end
	if not pip.fill:GetTexture() then
		pip.fill:SetTexture(PIP_TEXTURE_FALLBACK)
	end

	local function GetPipFillColor()
		local fillSource = tostring(GetDBValue("classresource_fillColorSource") or "CLASS")
		if fillSource == "CLASS" then
			return API.GetPlayerClassColor()
		end

		if GetDBValue("classresource_fillColor") then
			return GetDBColor("classresource_fillColor")
		end

		local fillColor = resource and resource.fillColor
		if fillColor then
			return fillColor.r, fillColor.g, fillColor.b, fillColor.a
		end

		return 1, 1, 1, 1
	end

	local fr, fg, fb, fa = GetPipFillColor()
	local emptyColor = resource and resource.emptyColor or { r = 0, g = 0, b = 0, a = 0.4 }
	local br, bg, bb, ba = GetDBColor("classresource_backgroundColor")
	if br == nil then
		br = 1
	end
	if bg == nil then
		bg = 1
	end
	if bb == nil then
		bb = 1
	end
	if ba == nil then
		ba = 1
	end

	local usingDefaultBackgroundTint = br == 1 and bg == 1 and bb == 1 and ba == 1
	pip.frame:SetVertexColor(1, 1, 1, 0.95)
	if usingDefaultBackgroundTint then
		pip.bg:SetVertexColor(emptyColor.r, emptyColor.g, emptyColor.b, emptyColor.a)
	else
		pip.bg:SetVertexColor(br, bg, bb, emptyColor.a * ba)
	end
	pip.fill:SetVertexColor(fr, fg, fb, fa)
	pip.styleReady = true
end

function GenericPips:HideAllPips()
	for i = 1, #self.pips do
		local pip = self.pips[i]
		if pip then
			pip.frame:Hide()
			pip.bg:Hide()
			pip.fill:Hide()
		end
	end
end

function GenericPips:LayoutPips(count)
	if not self.root or count < 1 then
		self:HideAllPips()
		if self.parentFrame then
			self.parentFrame:SetSize(1, 1)
		end
		return
	end

	local total = count * PIP_SIZE + (count - 1) * PIP_SPACING
	local x0 = -(total / 2) + (PIP_SIZE / 2)

	for i = 1, count do
		local pip = self:GetPip(i)
		if pip then
			local x = x0 + (i - 1) * (PIP_SIZE + PIP_SPACING)

			pip.frame:SetSize(PIP_SIZE, PIP_SIZE)
			pip.frame:ClearAllPoints()
			pip.frame:SetPoint("CENTER", self.root, "CENTER", x, 0)

			pip.bg:SetSize(PIP_SIZE, PIP_SIZE)
			pip.bg:ClearAllPoints()
			pip.bg:SetPoint("CENTER", self.root, "CENTER", x, 0)

			pip.fill:SetSize(PIP_SIZE, PIP_SIZE)
			pip.fill:ClearAllPoints()
			pip.fill:SetPoint("CENTER", self.root, "CENTER", x, 0)

			if not pip.styleReady then
				self:ConfigurePipTextures(pip, self.activeResource)
			end
		end
	end

	for i = count + 1, #self.pips do
		local pip = self.pips[i]
		if pip then
			pip.frame:Hide()
			pip.bg:Hide()
			pip.fill:Hide()
		end
	end

	self.root:SetSize(total, PIP_SIZE)
	if self.parentFrame then
		self.parentFrame:SetSize(total, PIP_SIZE)
	end
	self.pipMax = count
end

function GenericPips:ApplyVisualOptions()
	if not self.activeResource then
		return
	end

	for i = 1, #self.pips do
		local pip = self.pips[i]
		if pip then
			self:ConfigurePipTextures(pip, self.activeResource)
		end
	end
end

function GenericPips:ApplyLayout()
	if not self.root then
		return
	end

	self.root:ClearAllPoints()
	self.root:SetPoint("CENTER")
	self.root:SetScale(1)
	self.root:SetAlpha(1)
	self:LayoutPips(self.activeResource and (self.activeResource.maxCount or 0) or 0)
end

function GenericPips:SetVisible(visible)
	if not self.root then
		return
	end

	if visible then
		self.root:Show()
	else
		self.root:Hide()
	end
end

function GenericPips:ReadAuraStackPower()
	local resource = self.activeResource
	if not resource or not resource.auraSpellID then
		return 0, 0
	end

	local aura = C_UnitAuras.GetPlayerAuraBySpellID(resource.auraSpellID)
	if not aura then
		return 0, resource.maxCount or 0
	end

	return aura.applications or 0, resource.maxCount or 0
end

function GenericPips:ReadPower()
	local resource = self.activeResource
	if not resource then
		return 0, 0
	end

	if resource.sourceType == ResourceModel.SourceTypes.AURA_STACKS then
		return self:ReadAuraStackPower()
	end

	if resource.sourceType == ResourceModel.SourceTypes.RUNES then
		local readyRunes = 0
		local maxRunes = resource.maxCount or 0

		for runeIndex = 1, maxRunes do
			local _, _, runeReady = GetRuneCooldown(runeIndex)
			if runeReady then
				readyRunes = readyRunes + 1
			end
		end

		return readyRunes, maxRunes
	end

	if resource.sourceType ~= ResourceModel.SourceTypes.POWER or not resource.powerEnum then
		return 0, 0
	end

	local current = NormalizePowerValue(UnitPower("player", resource.powerEnum))
	local maxValue = NormalizePowerValue(UnitPowerMax("player", resource.powerEnum))
	return current, maxValue
end

function GenericPips:ApplyPipState(current, maxValue)
	if not self.root or not self.activeResource then
		self:HideAllPips()
		return
	end

	if maxValue ~= self.pipMax then
		if maxValue > 0 then
			self:LayoutPips(maxValue)
		else
			self:HideAllPips()
			return
		end
	end

	if maxValue <= 0 then
		self:HideAllPips()
		return
	end

	for i = 1, maxValue do
		local pip = self.pips[i]
		if pip then
			pip.frame:Show()
			pip.bg:Show()
			if i <= current then
				pip.fill:Show()
			else
				pip.fill:Hide()
			end
		end
	end

	for i = maxValue + 1, #self.pips do
		local pip = self.pips[i]
		if pip then
			pip.frame:Hide()
			pip.bg:Hide()
			pip.fill:Hide()
		end
	end
end

function GenericPips:Sync()
	if not self.activeResource then
		self:HideAllPips()
		return
	end

	local current, maxValue = self:ReadPower()
	self:ApplyPipState(current, maxValue)
end

function GenericPips:WantsEvent(event)
	if not self.activeResource then
		return false
	end

	if self.activeResource.sourceType == ResourceModel.SourceTypes.RUNES then
		return event == "RUNE_POWER_UPDATE"
	end

	if self.activeResource.sourceType == ResourceModel.SourceTypes.AURA_STACKS then
		return event == "UNIT_AURA"
	end

	if event == "UNIT_AURA" then
		return self.activeResource.needsUnitAura and true or false
	end

	if event == "UNIT_POWER_POINT_CHARGE" then
		return self.activeResource.needsPointCharge and true or false
	end

	if event == "UNIT_POWER_FREQUENT" then
		return self.activeResource.needsFrequent and true or false
	end

	return event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER"
end

function GenericPips:HandleEvent(event, unit, powerToken)
	if not self.activeResource then
		return
	end

	if self.activeResource.sourceType == ResourceModel.SourceTypes.RUNES then
		if event == "RUNE_POWER_UPDATE" then
			self:Sync()
		end
		return
	end

	if event == "UNIT_AURA" then
		if unit == "player" and self.activeResource.needsUnitAura then
			self:Sync()
		end
		return
	end

	if unit ~= "player" then
		return
	end

	if event == "UNIT_POWER_POINT_CHARGE" and not self.activeResource.needsPointCharge then
		return
	end

	if powerToken and self.activeResource.powerToken and powerToken ~= self.activeResource.powerToken then
		return
	end

	self:Sync()
end

local function CreateGenericPips()
	return setmetatable({
		root = nil,
		parentFrame = nil,
		pips = {},
		pipMax = 0,
		activeResource = nil,
	}, GenericPips)
end

ClassResourceSystems:Register(ResourceModel.SystemIDs.GENERIC_PIPS, CreateGenericPips)
