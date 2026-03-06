-- SparkPoint Minimap Button
-- Minimal native minimap button that opens the SparkPoint settings panel.
-- Pattern adapted from .clones/Narcissus/Narcissus/Bridge/DataBroker.lua (minimap integration concept),
-- implemented here without LibDBIcon to keep SparkPoint dependency-free.

local _, addon = ...
local L = addon.L
local CallbackRegistry = addon.CallbackRegistry
local GetDBBool = addon.GetDBBool
local GetDBValue = addon.GetDBValue

local MinimapButton = {}
addon.MinimapButton = MinimapButton

local button
local fadeOutGroup
local fadeOutAnim
local isDragging = false
local suppressClick = false
local dragMoved = false
local isMinimapHovered = false
local isButtonHovered = false
local minimapHoverHooked = false

local FULL_ALPHA = 1

local rad = math.rad
local cos = math.cos
local sin = math.sin
local deg = math.deg
local atan2 = math.atan2
local sqrt = math.sqrt
local max = math.max
local min = math.min

local minimapShapes = {
	ROUND = { true, true, true, true },
	SQUARE = { false, false, false, false },
	["CORNER-TOPLEFT"] = { false, false, false, true },
	["CORNER-TOPRIGHT"] = { false, false, true, false },
	["CORNER-BOTTOMLEFT"] = { false, true, false, false },
	["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
	["SIDE-LEFT"] = { false, true, false, true },
	["SIDE-RIGHT"] = { true, false, true, false },
	["SIDE-TOP"] = { false, false, true, true },
	["SIDE-BOTTOM"] = { true, true, false, false },
	["TRICORNER-TOPLEFT"] = { false, true, true, true },
	["TRICORNER-TOPRIGHT"] = { true, false, true, true },
	["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
	["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function GetStoredAngle()
	local angle = GetDBValue and GetDBValue("minimapButtonAngle")
	if type(angle) ~= "number" then
		return 225
	end
	return angle % 360
end

local function StoreAngle(angle)
	if type(angle) ~= "number" then
		return
	end
	if addon.DB then
		addon.DB.minimapButtonAngle = angle % 360
	end
end

local function ShouldFade()
	return GetDBBool and GetDBBool("fadeMinimapButtonWhenNotHovered")
end

local function GetFadeAlpha()
	local value = GetDBValue and GetDBValue("minimapButtonFadeOpacity")
	if type(value) ~= "number" then
		return 0.25
	end
	if value < 0 then
		return 0
	end
	if value > 1 then
		return 1
	end
	return value
end

local function EnsureFadeAnimation()
	if not button or fadeOutGroup then
		return
	end
	fadeOutGroup = button:CreateAnimationGroup()
	fadeOutAnim = fadeOutGroup:CreateAnimation("Alpha")
	fadeOutAnim:SetOrder(1)
	fadeOutAnim:SetDuration(0.2)
	fadeOutAnim:SetFromAlpha(1)
	fadeOutAnim:SetStartDelay(1)
	fadeOutGroup:SetToFinalAlpha(true)
end

local function StopFadeAnimation()
	if fadeOutGroup then
		fadeOutGroup:Stop()
	end
end

local function PlayFadeAnimation()
	if not button or not button:IsShown() then
		return
	end
	EnsureFadeAnimation()
	if not fadeOutAnim or not fadeOutGroup then
		return
	end
	fadeOutAnim:SetFromAlpha(button:GetAlpha() or 1)
	fadeOutAnim:SetToAlpha(GetFadeAlpha())
	fadeOutGroup:Play()
end

local function UpdatePosition(angle)
	if not button or not Minimap then
		return
	end

	local a = rad(type(angle) == "number" and angle or GetStoredAngle())
	local x, y = cos(a), sin(a)
	local quadrant = 1
	if x < 0 then
		quadrant = quadrant + 1
	end
	if y > 0 then
		quadrant = quadrant + 2
	end

	local shape = (GetMinimapShape and GetMinimapShape()) or "ROUND"
	local quadTable = minimapShapes[shape] or minimapShapes.ROUND
	local w = ((Minimap:GetWidth() or 140) * 0.5) + 5
	local h = ((Minimap:GetHeight() or 140) * 0.5) + 5

	if quadTable[quadrant] then
		x = x * w
		y = y * h
	else
		local diagW = sqrt(2 * (w ^ 2)) - 10
		local diagH = sqrt(2 * (h ^ 2)) - 10
		x = max(-w, min(x * diagW, w))
		y = max(-h, min(y * diagH, h))
	end

	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function OpenSettings()
	if addon.OpenSettings then
		addon.OpenSettings()
		return
	end
	if addon.SettingsCategoryID and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(addon.SettingsCategoryID)
	end
end

local function UpdateAlpha()
	if not button or not button:IsShown() then
		return
	end
	if not ShouldFade() or isDragging or isButtonHovered or isMinimapHovered then
		StopFadeAnimation()
		button:SetAlpha(FULL_ALPHA)
	else
		PlayFadeAnimation()
	end
end

local function UpdateVisibility()
	if not button then
		return
	end
	button:SetShown(GetDBBool and GetDBBool("showMinimapButton"))
	if button:IsShown() then
		UpdatePosition()
		UpdateAlpha()
	end
end

local function OnDragUpdate(self)
	if not Minimap then
		return
	end
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	px = px / scale
	py = py / scale
	local angle = deg(atan2(py - my, px - mx)) % 360
	dragMoved = true
	StoreAngle(angle)
	UpdatePosition(angle)
end

local function OnDragStart(self)
	isDragging = true
	dragMoved = false
	self:LockHighlight()
	self:SetScript("OnUpdate", OnDragUpdate)
	UpdateAlpha()
end

local function OnDragStop(self)
	if dragMoved then
		suppressClick = true
	end
	self:SetScript("OnUpdate", nil)
	self:UnlockHighlight()
	isDragging = false
	UpdatePosition()
	UpdateAlpha()
end

local function EnsureMinimapHoverHooks()
	if minimapHoverHooked or not Minimap or not Minimap.HookScript then
		return
	end
	minimapHoverHooked = true
	Minimap:HookScript("OnEnter", function()
		isMinimapHovered = true
		UpdateAlpha()
	end)
	Minimap:HookScript("OnLeave", function()
		isMinimapHovered = false
		UpdateAlpha()
	end)
end

local function EnsureButton()
	if button or not Minimap then
		return
	end

	button = CreateFrame("Button", "SparkPointMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel((Minimap:GetFrameLevel() or 5) + 8)
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local overlay = button:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(50, 50)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
	button.overlay = overlay

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(24, 24)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetPoint("CENTER", button, "CENTER", 0, 0)
	button.background = background

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\AddOns\\SparkPoint\\Textures\\icon.png")
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER", button, "CENTER", 0, 0)
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	button.icon = icon

	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnClick", function()
		if suppressClick then
			suppressClick = false
			return
		end
		if isDragging then
			return
		end
		OpenSettings()
	end)
	button:SetScript("OnDragStart", OnDragStart)
	button:SetScript("OnDragStop", OnDragStop)
	button:SetScript("OnEnter", function(self)
		isButtonHovered = true
		UpdateAlpha()
		if not GameTooltip then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L["SparkPoint"] or "SparkPoint")
		GameTooltip:AddLine(L["Minimap Button Click Tooltip"] or "Click to open settings", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		isButtonHovered = false
		UpdateAlpha()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)

	EnsureFadeAnimation()
	EnsureMinimapHoverHooks()
	UpdatePosition()
	UpdateVisibility()
end

CallbackRegistry:Register("ADDON_LOADED", function()
	EnsureButton()
	UpdateVisibility()
end, MinimapButton)

CallbackRegistry:Register("PLAYER_ENTERING_WORLD", function()
	EnsureButton()
	UpdateVisibility()
end, MinimapButton)

CallbackRegistry:RegisterSettingCallback("showMinimapButton", function()
	EnsureButton()
	UpdateVisibility()
end, MinimapButton)

CallbackRegistry:RegisterSettingCallback("fadeMinimapButtonWhenNotHovered", function()
	EnsureButton()
	UpdateVisibility()
end, MinimapButton)

CallbackRegistry:RegisterSettingCallback("minimapButtonFadeOpacity", function()
	EnsureButton()
	UpdateVisibility()
end, MinimapButton)
