-- SparkPoint ClassResource Module
-- Displays discrete class resources (pips) near the cursor.

local _, addon = ...
local L = addon.L
local API = addon.API
local ResourceModel = addon.ResourceModel
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local HUDLayers = addon.HUDLayers
local Visibility = addon.Visibility
local Transition = addon.Transition
local GetDBValue = addon.GetDBValue
local GetDBBool = addon.GetDBBool
local GetDBColor = addon.GetDBColor

local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local GetRuneCooldown = GetRuneCooldown

-- Unified pip texture.
-- Place your custom art at these paths (or change constants below).
local PIP_TEXTURE_FRAME_PATH = "Interface\\AddOns\\SparkPoint\\Textures\\class_resource_frame.png"
local PIP_TEXTURE_BG_PATH = "Interface\\AddOns\\SparkPoint\\Textures\\class_resource_background.png"
local PIP_TEXTURE_FILL_PATH = "Interface\\AddOns\\SparkPoint\\Textures\\class_resource_fill.png"
local PIP_TEXTURE_FALLBACK = "Interface\\Buttons\\WHITE8x8"

--------------------------------------------------------------------------------
-- PIP rendering
--------------------------------------------------------------------------------
local PIP_SIZE = 18
local PIP_SPACING = 4

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------
local EL = CreateFrame("Frame")

local ClassResource = {}
addon.Modules.ClassResourceObj = ClassResource

local isEnabled = false
local container = nil
local pips = {}
local pipMax = 0
local activeResource = nil

local function ReleaseAnchorIfUnused()
	if not container or not container:IsShown() then
		AnchorFrame:Hide("classresource")
	end
end

local function ShowContainer()
	if not container then
		return
	end
	AnchorFrame:Show("classresource")
	local targetAlpha = 1
	local opacity = GetDBValue("classresource_opacity")
	if type(opacity) == "number" then
		targetAlpha = math.max(0, math.min(1, opacity))
	end
	if Transition and Transition.ShowFrame then
		Transition:ShowFrame(container, { toAlpha = targetAlpha })
	else
		container:SetAlpha(targetAlpha)
		container:Show()
	end
end

local function HideContainer()
	if not container then
		ReleaseAnchorIfUnused()
		return
	end
	local restoreAlpha = 1
	local opacity = GetDBValue("classresource_opacity")
	if type(opacity) == "number" then
		restoreAlpha = math.max(0, math.min(1, opacity))
	end
	if Transition and Transition.HideFrame then
		Transition:HideFrame(container, { restoreAlpha = restoreAlpha, onComplete = ReleaseAnchorIfUnused })
	else
		container:SetAlpha(restoreAlpha)
		container:Hide()
		ReleaseAnchorIfUnused()
	end
end

--------------------------------------------------------------------------------
-- Shared helpers
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- PIPS Mode
--------------------------------------------------------------------------------
local function GetRunePower()
	local ready = 0
	for i = 1, 6 do
		local start, _, runeReady = GetRuneCooldown(i)
		if runeReady or start == 0 then
			ready = ready + 1
		end
	end
	return ready, 6
end

local function GetAuraStackPower(resource)
	if not resource or not resource.auraSpellID then
		return 0, 0
	end

	local aura = C_UnitAuras.GetPlayerAuraBySpellID(resource.auraSpellID)
	if not aura then
		return 0, resource.maxCount or 0
	end
	return aura.applications or 0, resource.maxCount or 0
end

local function ReadPower()
	if not activeResource then
		return 0, 0
	end

	if activeResource.sourceType == ResourceModel.SourceTypes.RUNES then
		return GetRunePower()
	end

	if activeResource.sourceType == ResourceModel.SourceTypes.AURA_STACKS then
		return GetAuraStackPower(activeResource)
	end

	local pEnum = activeResource.powerEnum
	if not pEnum then
		return 0, 0
	end

	local cur = NormalizePowerValue(UnitPower("player", pEnum))
	local max = NormalizePowerValue(UnitPowerMax("player", pEnum))
	return cur, max
end

local function EnsureContainer()
	if container then
		return
	end
	local anchor = AnchorFrame:GetFrame()
	if not anchor then
		return
	end

	local layerRoot = (HUDLayers and HUDLayers:GetLayerFrame(HUDLayers.Names.CLASS_RESOURCE)) or anchor
	container = CreateFrame("Frame", nil, layerRoot)
	container:SetFrameLevel(layerRoot:GetFrameLevel() or 0)
	container:SetSize(1, 1)
	container:Hide()
end

local function GetPip(i)
	if pips[i] then
		return pips[i]
	end
	if not container then
		return nil
	end
	local p = {
		frame = container:CreateTexture(nil, "ARTWORK", nil, 2),
		bg = container:CreateTexture(nil, "ARTWORK", nil, 0),
		fill = container:CreateTexture(nil, "ARTWORK", nil, 1),
	}
	p.styleReady = false
	p.frame:Hide()
	p.bg:Hide()
	p.fill:Hide()
	pips[i] = p
	return p
end

local function ConfigurePipTextures(p, cfg)
	if not p then
		return
	end

	p.frame:SetTexCoord(0, 1, 0, 1)
	p.bg:SetTexCoord(0, 1, 0, 1)
	p.fill:SetTexCoord(0, 1, 0, 1)

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

	SetTextureSmooth(p.frame, PIP_TEXTURE_FRAME_PATH)
	SetTextureSmooth(p.bg, PIP_TEXTURE_BG_PATH)
	SetTextureSmooth(p.fill, PIP_TEXTURE_FILL_PATH)

	if not p.frame:GetTexture() then
		p.frame:SetTexture(PIP_TEXTURE_FALLBACK)
	end
	if not p.bg:GetTexture() then
		p.bg:SetTexture(PIP_TEXTURE_FALLBACK)
	end
	if not p.fill:GetTexture() then
		p.fill:SetTexture(PIP_TEXTURE_FALLBACK)
	end

	local function GetPipFillColor()
		if GetDBBool("classresource_fillUseClassColor") then
			return API.GetPlayerClassColor()
		end

		local customFill = GetDBValue("classresource_fillColor")
		if customFill then
			return GetDBColor("classresource_fillColor")
		end

		local fc = cfg and cfg.fillColor
		if fc then
			return fc.r, fc.g, fc.b, fc.a
		end
		return 1, 1, 1, 1
	end

	local fr, fg, fb, fa = GetPipFillColor()
	local ec = cfg.emptyColor
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
	p.frame:SetVertexColor(1, 1, 1, 0.95)
	if usingDefaultBackgroundTint then
		p.bg:SetVertexColor(ec.r, ec.g, ec.b, ec.a)
	else
		p.bg:SetVertexColor(br, bg, bb, ec.a * ba)
	end
	p.fill:SetVertexColor(fr, fg, fb, fa)

	p.styleReady = true
end

function ClassResource:ApplyPipVisualOptions()
	if not activeResource then
		return
	end
	for i = 1, #pips do
		local p = pips[i]
		if p then
			ConfigurePipTextures(p, activeResource)
		end
	end
end

local function LayoutPips(cfg, count)
	if not container or count < 1 then
		return
	end

	local total = count * PIP_SIZE + (count - 1) * PIP_SPACING
	local x0 = -(total / 2) + (PIP_SIZE / 2)

	for i = 1, count do
		local p = GetPip(i)
		if p then
			local x = x0 + (i - 1) * (PIP_SIZE + PIP_SPACING)

			p.frame:SetSize(PIP_SIZE, PIP_SIZE)
			p.frame:ClearAllPoints()
			p.frame:SetPoint("CENTER", container, "CENTER", x, 0)

			p.bg:SetSize(PIP_SIZE, PIP_SIZE)
			p.bg:ClearAllPoints()
			p.bg:SetPoint("CENTER", container, "CENTER", x, 0)

			p.fill:SetSize(PIP_SIZE, PIP_SIZE)
			p.fill:ClearAllPoints()
			p.fill:SetPoint("CENTER", container, "CENTER", x, 0)

			if not p.styleReady then
				ConfigurePipTextures(p, cfg)
			end
		end
	end

	for i = count + 1, #pips do
		local p = pips[i]
		if p then
			p.frame:Hide()
			p.bg:Hide()
			p.fill:Hide()
		end
	end

	container:SetSize(total, PIP_SIZE)
	pipMax = count
end

local function HidePips()
	for i = 1, #pips do
		local p = pips[i]
		if p then
			p.frame:Hide()
			p.bg:Hide()
			p.fill:Hide()
		end
	end
end

local function ApplyPipState(current, max)
	if not container or not activeResource then
		HidePips()
		return
	end

	if max ~= pipMax then
		if max > 0 then
			LayoutPips(activeResource, max)
		else
			HidePips()
			return
		end
	end

	if max <= 0 then
		HidePips()
		return
	end

	for i = 1, max do
		local p = pips[i]
		if p then
			p.frame:Show()
			p.bg:Show()
			if i <= current then
				p.fill:Show()
			else
				p.fill:Hide()
			end
		end
	end

	for i = max + 1, #pips do
		local p = pips[i]
		if p then
			p.frame:Hide()
			p.bg:Hide()
			p.fill:Hide()
		end
	end
end

--------------------------------------------------------------------------------
-- Layout and Visibility
--------------------------------------------------------------------------------
function ClassResource:ApplyLayout()
	local anchor = AnchorFrame:GetFrame()
	if not anchor then
		return
	end

	local offsetX = GetDBValue("classresource_offsetX") or 0
	local offsetY = GetDBValue("classresource_offsetY") or 0
	local scale = GetDBValue("classresource_scale") or 1
	local opacity = GetDBValue("classresource_opacity")
	if opacity == nil then
		opacity = 1
	end

	if container then
		container:ClearAllPoints()
		container:SetPoint("CENTER", anchor, "CENTER", offsetX, offsetY)
		container:SetScale(scale)
		container:SetAlpha(opacity)
		if container:GetParent() then
			container:SetFrameLevel(container:GetParent():GetFrameLevel() or 0)
		end
	end
end

function ClassResource:UpdateVisibility()
	if not isEnabled or not activeResource then
		HideContainer()
		return
	end

	if not Visibility:ShouldShow("classresource") then
		HideContainer()
		return
	end

	ShowContainer()
end

function ClassResource:SyncPower()
	if not isEnabled or not activeResource then
		return
	end
	local current, max = ReadPower()
	ApplyPipState(current, max)
end

--------------------------------------------------------------------------------
-- Class Detection
--------------------------------------------------------------------------------
local function DetectActiveResource()
	local resource = ResourceModel:GetCurrentClassResource("player")
	return resource
end

function ClassResource:Refresh()
	EnsureContainer()

	activeResource = DetectActiveResource()
	pipMax = 0
	for i = 1, #pips do
		pips[i].styleReady = false
	end

	if activeResource then
		LayoutPips(activeResource, activeResource.maxCount or 0)
	else
		HidePips()
	end

	self:ApplyLayout()
	self:UpdateVisibility()
	self:SyncPower()
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------
function ClassResource:PLAYER_ENTERING_WORLD()
	self:Refresh()
end

function ClassResource:PLAYER_SPECIALIZATION_CHANGED()
	self:Refresh()
end

function ClassResource:UPDATE_SHAPESHIFT_FORM()
	self:Refresh()
end

function ClassResource:UNIT_POWER_UPDATE(event, unit)
	if unit ~= "player" then
		return
	end
	self:SyncPower()
end

function ClassResource:UNIT_MAXPOWER(event, unit)
	if unit ~= "player" then
		return
	end
	self:SyncPower()
end

function ClassResource:RUNE_POWER_UPDATE()
	if activeResource and activeResource.sourceType == ResourceModel.SourceTypes.RUNES then
		self:SyncPower()
	end
end

function ClassResource:UNIT_DISPLAYPOWER(event, unit)
	if unit ~= "player" then
		return
	end
	self:Refresh()
end

function ClassResource:UNIT_AURA(event, unit)
	if unit ~= "player" then
		return
	end
	if activeResource and activeResource.needsUnitAura then
		self:SyncPower()
	end
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------
local function EnableModule(enabled)
	isEnabled = enabled and true or false

	if enabled then
		EL:RegisterEvent("PLAYER_ENTERING_WORLD")
		EL:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		EL:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
		EL:RegisterEvent("RUNE_POWER_UPDATE")
		EL:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
		EL:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
		EL:RegisterUnitEvent("UNIT_MAXPOWER", "player")
		EL:RegisterUnitEvent("UNIT_AURA", "player")

		ClassResource:Refresh()
	else
		EL:UnregisterAllEvents()
		HideContainer()
		activeResource = nil
		HidePips()
	end
end

EL:SetScript("OnEvent", function(self, event, ...)
	if ClassResource[event] then
		ClassResource[event](ClassResource, event, ...)
	end
end)

--------------------------------------------------------------------------------
-- Setting Callbacks
--------------------------------------------------------------------------------
for _, key in ipairs({
	"classresource_scale",
	"classresource_opacity",
	"classresource_offsetX",
	"classresource_offsetY",
}) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		ClassResource:ApplyLayout()
	end)
end

CallbackRegistry:RegisterSettingCallback("classresource_visibility", function()
	ClassResource:UpdateVisibility()
end)
CallbackRegistry:RegisterSettingCallback("classresource_visibilitySource", function()
	ClassResource:UpdateVisibility()
end)
CallbackRegistry:RegisterSettingCallback("visibility_mode", function()
	ClassResource:UpdateVisibility()
end)
CallbackRegistry:RegisterSettingCallback("visibility_hideOnUIHover", function()
	ClassResource:UpdateVisibility()
end)
CallbackRegistry:RegisterSettingCallback("classresource_hideOnUIHover", function()
	ClassResource:UpdateVisibility()
end)
CallbackRegistry:RegisterSettingCallback("attachToMouse", function()
	ClassResource:UpdateVisibility()
end)

for _, key in ipairs({ "classresource_fillColor", "classresource_fillUseClassColor", "classresource_backgroundColor" }) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		ClassResource:ApplyPipVisualOptions()
		ClassResource:SyncPower()
	end)
end

CallbackRegistry:Register("VisibilityContextChanged", function()
	ClassResource:UpdateVisibility()
end, ClassResource)

--------------------------------------------------------------------------------
-- Module Registration
--------------------------------------------------------------------------------
addon.ControlCenter:AddModule({
	name = L["Class Resource"] or "Class Resource",
	dbKey = "moduleEnabled_ClassResource",
	description = L["Class Resource Description"] or "Displays class resources near the cursor",
	toggleFunc = EnableModule,
	categoryID = 1,
	uiOrder = 3,
})
