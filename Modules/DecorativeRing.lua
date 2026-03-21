-- SparkPoint Ring Module
-- Displays a decorative rotating ring around the cursor

local _, addon = ...
local L = addon.L
local API = addon.API
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local HUDLayers = addon.HUDLayers
local Visibility = addon.Visibility
local Transition = addon.Transition
local GetDBValue = addon.GetDBValue
local GetDBBool = addon.GetDBBool
local GetDBColor = addon.GetDBColor

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------
local ringFrame
local isEnabled = false

local rad = math.rad

--------------------------------------------------------------------------------
-- Ring Module Object
--------------------------------------------------------------------------------
local Ring = {}
addon.Modules.RingObj = Ring

--------------------------------------------------------------------------------
-- Texture Definitions
-- Add new decorative ring textures here:
-- { key = "my_key", file = "my_file.tga", label = "My Label" }
--------------------------------------------------------------------------------
local RING_TEXTURE_DEFINITIONS = {
	{ key = "decorative_ring_1", file = "decorative_ring_1.tga", label = "Decorative Ring 1" },
	{ key = "decorative_ring_2", file = "decorative_ring_2.tga", label = "Decorative Ring 2" },
}

local RING_TEXTURE_PATHS = {}
local RING_TEXTURE_OPTIONS = {}
for _, def in ipairs(RING_TEXTURE_DEFINITIONS) do
	RING_TEXTURE_PATHS[def.key] = addon.addonFolder .. "\\Textures\\" .. def.file
	RING_TEXTURE_OPTIONS[#RING_TEXTURE_OPTIONS + 1] = { value = def.key, label = def.label }
end

local DEFAULT_TEXTURE_KEY = (RING_TEXTURE_DEFINITIONS[1] and RING_TEXTURE_DEFINITIONS[1].key) or "decorative_ring_1"

Ring.TEXTURE_OPTIONS = RING_TEXTURE_OPTIONS

local function ApplyLayering()
	if not ringFrame then
		return
	end

	local parent = ringFrame:GetParent()
	if not parent then
		return
	end

	if parent.GetFrameStrata then
		ringFrame:SetFrameStrata(parent:GetFrameStrata())
	end
	ringFrame:SetFrameLevel(parent:GetFrameLevel() or 0)
end

local function SetTextureSmooth(texture, texturePath)
	if not texture then
		return
	end
	local ok = pcall(texture.SetTexture, texture, texturePath, nil, nil, "TRILINEAR")
	if not ok then
		texture:SetTexture(texturePath)
	end
	if texture.SetSnapToPixelGrid then
		texture:SetSnapToPixelGrid(false)
	end
	if texture.SetTexelSnappingBias then
		texture:SetTexelSnappingBias(0)
	end
end

local function NormalizeTextureKey(textureValue)
	local textureKey = tostring(textureValue or "")
	if RING_TEXTURE_PATHS[textureKey] then
		return textureKey
	end
	return DEFAULT_TEXTURE_KEY
end

local function IsVisibilityAllowed()
	return (not Visibility) or Visibility:ShouldShow("ring")
end

local function ShowRingFrame()
	if not ringFrame then
		return
	end
	AnchorFrame:Show("ring")
	if Transition and Transition.ShowFrame then
		Transition:ShowFrame(ringFrame)
	else
		ringFrame:Show()
	end
end

local function HideRingFrame()
	if not ringFrame then
		AnchorFrame:Hide("ring")
		return
	end
	local function ReleaseAnchor()
		if not ringFrame:IsShown() then
			AnchorFrame:Hide("ring")
		end
	end
	if Transition and Transition.HideFrame then
		Transition:HideFrame(ringFrame, { onComplete = ReleaseAnchor })
	else
		ringFrame:Hide()
		ReleaseAnchor()
	end
end

--------------------------------------------------------------------------------
-- OnUpdate Handler (rotation animation)
--------------------------------------------------------------------------------
local function OnUpdate(self, elapsed)
	local texture = self.texture
	texture.timer = texture.timer + elapsed
	if texture.timer > 0.02 then
		texture.hAngle = texture.hAngle + 0.5
		texture:SetRotation(rad(texture.hAngle))
		texture.timer = 0
	end
end

local function OnShow(self)
	if GetDBBool("ring_rotate") then
		self:SetScript("OnUpdate", OnUpdate)
	else
		self:SetScript("OnUpdate", nil)
	end
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------
function Ring:Show()
	if not ringFrame then
		return
	end
	if not isEnabled then
		return
	end
	self:UpdateVisibility()
end

function Ring:Hide()
	if not ringFrame then
		return
	end
	self:UpdateVisibility()
end

function Ring:UpdateVisibility()
	if not ringFrame then
		return
	end
	if not isEnabled then
		HideRingFrame()
		return
	end

	if IsVisibilityAllowed() then
		ShowRingFrame()
	else
		HideRingFrame()
	end
end

--------------------------------------------------------------------------------
-- ApplyOptions: Update visuals from settings
--------------------------------------------------------------------------------
function Ring:ApplyOptions()
	if not ringFrame then
		return
	end

	local textureID = GetDBValue("ring_texture")
	local width = GetDBValue("ring_width")
	local r, g, b, a
	if GetDBBool("ring_useClassColor") then
		r, g, b, a = API.GetPlayerClassColor()
		a = GetDBValue("ring_classColorAlpha") or a
	else
		r, g, b, a = GetDBColor("ring_color")
	end

	local texture = ringFrame.texture
	local textureKey = NormalizeTextureKey(textureID)
	local texturePath = RING_TEXTURE_PATHS[textureKey] or RING_TEXTURE_PATHS[DEFAULT_TEXTURE_KEY]
	SetTextureSmooth(texture, texturePath)

	texture:SetVertexColor(r, g, b, a)
	texture:SetBlendMode("ADD")
	texture:SetSize(width, width)
	texture:SetPoint("CENTER", ringFrame, "CENTER")
	texture:SetRotation(rad(texture.hAngle or 0))
	texture:Show()

	-- Update rotation setting
	if GetDBBool("ring_rotate") and ringFrame:IsShown() then
		ringFrame:SetScript("OnUpdate", OnUpdate)
	else
		ringFrame:SetScript("OnUpdate", nil)
	end

	self:UpdateVisibility()
end

--------------------------------------------------------------------------------
-- Initialize
--------------------------------------------------------------------------------
function Ring:Initialize()
	local anchor = AnchorFrame:GetFrame()
	if not anchor then
		return
	end

	local layerRoot = (HUDLayers and HUDLayers:GetLayerFrame(HUDLayers.Names.DECORATIVE_RING)) or anchor
	ringFrame = CreateFrame("Frame", nil, layerRoot)
	ringFrame:SetAllPoints()
	ApplyLayering()
	ringFrame:Hide()

	-- Initialize rotation state
	-- Create texture
	ringFrame.texture = ringFrame:CreateTexture(nil, "ARTWORK")
	ringFrame.texture:SetPoint("CENTER", ringFrame, "CENTER")
	ringFrame.texture.timer = 0
	ringFrame.texture.hAngle = 0

	-- Set scripts
	ringFrame:SetScript("OnShow", OnShow)

	self:ApplyOptions()
end

--------------------------------------------------------------------------------
-- Enable/Disable
--------------------------------------------------------------------------------
local function EnableModule(enabled)
	if enabled then
		isEnabled = true
		if not ringFrame then
			Ring:Initialize()
		end
		Ring:UpdateVisibility()
	else
		isEnabled = false
		HideRingFrame()
	end
end

--------------------------------------------------------------------------------
-- Register Setting Callbacks
--------------------------------------------------------------------------------
local settingKeys = {
	"ring_texture",
	"ring_color",
	"ring_width",
	"ring_rotate",
	"ring_useClassColor",
	"ring_classColorAlpha",
}

for _, key in ipairs(settingKeys) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		Ring:ApplyOptions()
	end)
end

for _, key in ipairs({
	"visibility_mode",
	"ring_visibilitySource",
	"ring_visibility",
	"visibility_hideOnUIHover",
	"ring_hideOnUIHover",
	"attachToMouse",
}) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		Ring:UpdateVisibility()
	end)
end

CallbackRegistry:Register("VisibilityContextChanged", function()
	Ring:UpdateVisibility()
end, Ring)

CallbackRegistry:Register("HUDLayersChanged", function()
	ApplyLayering()
end, Ring)

--------------------------------------------------------------------------------
-- Register Module
--------------------------------------------------------------------------------
addon.ControlCenter:AddModule({
	name = L["Decorative Ring"] or "Decorative Ring",
	dbKey = "moduleEnabled_Ring",
	description = L["Decorative Ring Description"] or "Displays a decorative rotating ring around the cursor during casts",
	toggleFunc = EnableModule,
	categoryID = 1,
	uiOrder = 4,
})
