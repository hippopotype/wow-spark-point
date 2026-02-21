-- SparkPoint ClassResource Module
-- Copies Blizzard class-resource visuals near the cursor without reparenting originals.

local addonName, addon = ...
local L = addon.L
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local GetDBValue = addon.GetDBValue

local UnitClass = UnitClass
local UnitExists = UnitExists
local InCombatLockdown = InCombatLockdown
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo

--------------------------------------------------------------------------------
-- Event Frame
--------------------------------------------------------------------------------
local EL = CreateFrame("Frame")

--------------------------------------------------------------------------------
-- Module Object
--------------------------------------------------------------------------------
local ClassResource = {}
addon.Modules.ClassResourceObj = ClassResource

local VISIBILITY_OPTIONS = {
	ALWAYS = "ALWAYS",
	IN_COMBAT = "IN_COMBAT",
	OUT_OF_COMBAT = "OUT_OF_COMBAT",
	HAS_TARGET = "HAS_TARGET",
	CASTING = "CASTING",
}

local CLASS_RESOURCE_FRAME = {
	DEATHKNIGHT = "RuneFrame",
	DRUID = "DruidComboPointBarFrame",
	EVOKER = "EssencePlayerFrame",
	MAGE = "MageArcaneChargesFrame",
	MONK = "MonkHarmonyBarFrame",
	PALADIN = "PaladinPowerBarFrame",
	ROGUE = "RogueComboPointBarFrame",
	SHAMAN = "ShamanMaelstromWeaponBarFrame",
	WARLOCK = "WarlockPowerFrame",
}

local copyFrame
local copyTextures = {}
local sourceFrame
local isEnabled = false
local updateTimer = 0
local UPDATE_INTERVAL = 0.05

local function IsPlayerCastingNow()
	if UnitCastingInfo("player") then return true end
	if UnitChannelInfo("player") then return true end

	local castModule = addon.Modules and addon.Modules.CastObj
	if castModule and castModule.GetFrame then
		local castFrame = castModule:GetFrame()
		if castFrame and castFrame:IsShown() then
			return true
		end
	end

	return false
end

local function GetCurrentClassResourceFrame()
	local _, classTag = UnitClass("player")
	if not classTag then return nil end

	local frameName = CLASS_RESOURCE_FRAME[classTag]
	if not frameName then return nil end

	return _G[frameName]
end

local function EnsureCopyFrame()
	if copyFrame then return end

	local anchor = AnchorFrame:GetFrame()
	if not anchor then return end

	copyFrame = CreateFrame("Frame", nil, anchor)
	copyFrame:SetFrameStrata("HIGH")
	copyFrame:SetFrameLevel((anchor:GetFrameLevel() or 1) + 20)
	copyFrame:SetSize(1, 1)
	copyFrame:Hide()
end

local function GetCopyTexture(index)
	local tex = copyTextures[index]
	if tex then return tex end

	tex = copyFrame:CreateTexture(nil, "ARTWORK")
	copyTextures[index] = tex
	return tex
end

local function HideUnusedTextures(startIndex)
	for i = startIndex, #copyTextures do
		copyTextures[i]:Hide()
	end
end

local function IsRenderableTexture(region)
	if not region or not region.GetObjectType then return false end
	if region:GetObjectType() ~= "Texture" then return false end
	if not region:IsShown() then return false end

	local l, r, t, b = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
	if not l or not r or not t or not b then return false end
	if r <= l or t <= b then return false end
	return true
end

local function CollectTextures(frame, out)
	if not frame or not frame:IsShown() then return end

	for _, region in ipairs({ frame:GetRegions() }) do
		if IsRenderableTexture(region) then
			out[#out + 1] = region
		end
	end

	for _, child in ipairs({ frame:GetChildren() }) do
		CollectTextures(child, out)
	end
end

local function ApplyTextureVisuals(dst, src)
	local atlas = src.GetAtlas and src:GetAtlas()
	if atlas and atlas ~= "" and dst.SetAtlas then
		dst:SetAtlas(atlas, false)
	else
		dst:SetTexture(src:GetTexture())
	end

	local a, b, c, d, e, f, g, h = src:GetTexCoord()
	if a then
		dst:SetTexCoord(a, b, c, d, e, f, g, h)
	else
		dst:SetTexCoord(0, 1, 0, 1)
	end

	local drawLayer, subLevel = src:GetDrawLayer()
	dst:SetDrawLayer(drawLayer or "ARTWORK", subLevel or 0)

	local r, gg, bb, aa = src:GetVertexColor()
	dst:SetVertexColor(r or 1, gg or 1, bb or 1, aa or 1)
	dst:SetBlendMode(src:GetBlendMode() or "BLEND")
	dst:SetAlpha(src:GetAlpha() or 1)
end

function ClassResource:ShouldBeVisible()
	local setting = GetDBValue("classresource_visibility") or VISIBILITY_OPTIONS.ALWAYS
	if setting == VISIBILITY_OPTIONS.IN_COMBAT then
		return InCombatLockdown()
	elseif setting == VISIBILITY_OPTIONS.OUT_OF_COMBAT then
		return not InCombatLockdown()
	elseif setting == VISIBILITY_OPTIONS.HAS_TARGET then
		return UnitExists("target")
	elseif setting == VISIBILITY_OPTIONS.CASTING then
		return IsPlayerCastingNow()
	end
	return true
end

function ClassResource:ApplyLayout()
	EnsureCopyFrame()
	if not copyFrame then return end

	local anchor = AnchorFrame:GetFrame()
	if not anchor then return end

	local offsetX = GetDBValue("classresource_offsetX") or 0
	local offsetY = GetDBValue("classresource_offsetY") or 0
	local scale = GetDBValue("classresource_scale") or 1
	local opacity = GetDBValue("classresource_opacity")
	if opacity == nil then opacity = 1 end

	copyFrame:SetParent(anchor)
	copyFrame:ClearAllPoints()
	copyFrame:SetPoint("CENTER", anchor, "CENTER", offsetX, offsetY)
	copyFrame:SetScale(scale)
	copyFrame:SetAlpha(opacity)
	copyFrame:SetFrameStrata("HIGH")
	copyFrame:SetFrameLevel((anchor:GetFrameLevel() or 1) + 20)
end

function ClassResource:RenderCopy()
	if not copyFrame then return false end
	if not sourceFrame or not sourceFrame:IsShown() then
		HideUnusedTextures(1)
		return false
	end

	local srcLeft, srcRight, srcTop, srcBottom = sourceFrame:GetLeft(), sourceFrame:GetRight(), sourceFrame:GetTop(), sourceFrame:GetBottom()
	if not srcLeft or not srcRight or not srcTop or not srcBottom then
		HideUnusedTextures(1)
		return false
	end

	local srcCenterX = (srcLeft + srcRight) * 0.5
	local srcCenterY = (srcTop + srcBottom) * 0.5

	local regions = {}
	CollectTextures(sourceFrame, regions)

	local used = 0
	for i = 1, #regions do
		local src = regions[i]
		local l, r, t, b = src:GetLeft(), src:GetRight(), src:GetTop(), src:GetBottom()
		if l and r and t and b and r > l and t > b then
			used = used + 1
			local dst = GetCopyTexture(used)
			ApplyTextureVisuals(dst, src)
			dst:ClearAllPoints()
			dst:SetSize(r - l, t - b)
			dst:SetPoint("CENTER", copyFrame, "CENTER", ((l + r) * 0.5) - srcCenterX, ((t + b) * 0.5) - srcCenterY)
			dst:Show()
		end
	end

	HideUnusedTextures(used + 1)
	return used > 0
end

function ClassResource:UpdateVisibility()
	if not isEnabled or not copyFrame then
		if copyFrame then copyFrame:Hide() end
		AnchorFrame:Hide("classresource")
		return
	end

	if not self:ShouldBeVisible() then
		copyFrame:Hide()
		AnchorFrame:Hide("classresource")
		return
	end

	sourceFrame = GetCurrentClassResourceFrame()
	if not sourceFrame then
		copyFrame:Hide()
		AnchorFrame:Hide("classresource")
		return
	end

	local hasVisuals = self:RenderCopy()
	if hasVisuals then
		copyFrame:Show()
		AnchorFrame:Show("classresource")
	else
		copyFrame:Hide()
		AnchorFrame:Hide("classresource")
	end
end

function ClassResource:Refresh()
	sourceFrame = GetCurrentClassResourceFrame()
	self:ApplyLayout()
	self:UpdateVisibility()
end

local function OnUpdate(self, elapsed)
	if not isEnabled then return end

	updateTimer = updateTimer + elapsed
	if updateTimer >= UPDATE_INTERVAL then
		updateTimer = 0
		ClassResource:UpdateVisibility()
	end
end

--------------------------------------------------------------------------------
-- Events
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

function ClassResource:UNIT_DISPLAYPOWER(event, unit)
	if unit ~= "player" then return end
	self:Refresh()
end

function ClassResource:UNIT_POWER_UPDATE(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
end

function ClassResource:UNIT_MAXPOWER(event, unit)
	if unit ~= "player" then return end
	self:Refresh()
end

function ClassResource:PLAYER_REGEN_DISABLED()
	self:UpdateVisibility()
end

function ClassResource:PLAYER_REGEN_ENABLED()
	self:UpdateVisibility()
end

function ClassResource:PLAYER_TARGET_CHANGED()
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_START(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_STOP(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_INTERRUPTED(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_FAILED(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_FAILED_QUIET(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_CHANNEL_START(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_CHANNEL_STOP(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_CHANNEL_UPDATE(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_EMPOWER_START(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_EMPOWER_STOP(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_EMPOWER_UPDATE(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
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
		EL:RegisterEvent("PLAYER_REGEN_DISABLED")
		EL:RegisterEvent("PLAYER_REGEN_ENABLED")
		EL:RegisterEvent("PLAYER_TARGET_CHANGED")
		EL:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
		EL:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
		EL:RegisterUnitEvent("UNIT_MAXPOWER", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "player")

		EL:SetScript("OnUpdate", OnUpdate)
		ClassResource:Refresh()
	else
		EL:SetScript("OnUpdate", nil)
		EL:UnregisterAllEvents()
		if copyFrame then copyFrame:Hide() end
		AnchorFrame:Hide("classresource")
	end
end

EL:SetScript("OnEvent", function(self, event, ...)
	if ClassResource[event] then
		ClassResource[event](ClassResource, event, ...)
	end
end)

local settingKeys = {
	"classresource_scale",
	"classresource_opacity",
	"classresource_offsetX",
	"classresource_offsetY",
}

for _, key in ipairs(settingKeys) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		ClassResource:ApplyLayout()
		ClassResource:UpdateVisibility()
	end)
end

CallbackRegistry:RegisterSettingCallback("classresource_visibility", function()
	ClassResource:UpdateVisibility()
end)

addon.ControlCenter:AddModule({
	name = L["Class Resource"] or "Class Resource",
	dbKey = "moduleEnabled_ClassResource",
	description = L["Class Resource Description"] or "Repositions Blizzard class resource pips near the cursor",
	toggleFunc = EnableModule,
	categoryID = 1,
	uiOrder = 3,
})
