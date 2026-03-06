-- SparkPoint Anchor Frame
-- Central 64x64 frame that all modules parent to, follows cursor or fixed position

local _, addon = ...
local CallbackRegistry = addon.CallbackRegistry
local GetDBValue = addon.GetDBValue
local GetDBBool = addon.GetDBBool

local AnchorFrame = {}
addon.AnchorFrame = AnchorFrame

local anchor
local showRequests = {}
local settingsOpenDeferred = false
local settingsOpenFrame
local OpenSettingsSafely
local unlockFrame
local unlockManualActive = false
local unlockEditModeActive = false
local editModeHooked = false
local editModeEventCallbacksHooked = false
local editModeWatcher
local anchorVisible = false

local GetCursorPosition = GetCursorPosition
local UIParent = UIParent

local function OpenSettingsNow()
	if addon.SettingsCategoryID then
		Settings.OpenToCategory(addon.SettingsCategoryID)
		return
	end

	C_Timer.After(0.1, function()
		-- Re-check combat state before opening to avoid protected call races.
		OpenSettingsSafely()
	end)
end

local function EnsureSettingsOpenFrame()
	if settingsOpenFrame then
		return
	end
	settingsOpenFrame = CreateFrame("Frame")
	settingsOpenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	settingsOpenFrame:SetScript("OnEvent", function()
		if not settingsOpenDeferred then
			return
		end
		settingsOpenDeferred = false
		OpenSettingsNow()
	end)
end

OpenSettingsSafely = function()
	if InCombatLockdown and InCombatLockdown() then
		settingsOpenDeferred = true
		EnsureSettingsOpenFrame()
		print("SparkPoint: Settings will open after combat.")
		return
	end

	OpenSettingsNow()
end

addon.OpenSettings = OpenSettingsSafely

local function IsBlizzardEditModeActive()
	if not EditModeManagerFrame then
		return false
	end
	if EditModeManagerFrame.IsEditModeActive then
		return EditModeManagerFrame:IsEditModeActive() and true or false
	end
	return EditModeManagerFrame:IsShown() and true or false
end

local function HasAnyShowRequests()
	for _ in pairs(showRequests) do
		return true
	end
	return false
end

local function UpdateAnchorVisibilityGate(visible)
	if not anchor then
		return
	end
	anchorVisible = visible == true
	if anchorVisible then
		anchor:SetAlpha(1)
		anchor:Show()
	else
		anchor:Hide()
		anchor:SetAlpha(1)
	end
end

--------------------------------------------------------------------------------
-- Show/Hide Request System
-- Multiple modules can request visibility; anchor hides only when all release
--------------------------------------------------------------------------------
function AnchorFrame:Show(requester)
	showRequests[requester or "default"] = true
	UpdateAnchorVisibilityGate(true)
end

function AnchorFrame:Hide(requester)
	showRequests[requester or "default"] = nil
	if not HasAnyShowRequests() then
		UpdateAnchorVisibilityGate(false)
	end
end

function AnchorFrame:IsShown()
	return anchorVisible == true
end

function AnchorFrame:GetFrame()
	return anchor
end

--------------------------------------------------------------------------------
-- OnUpdate for cursor tracking
--------------------------------------------------------------------------------
local function OnUpdate(self, elapsed)
	local x, y

	if GetDBBool("attachToMouse") then
		x, y = GetCursorPosition()
		local scale = self:GetEffectiveScale()
		x = x / scale + GetDBValue("offset_x")
		y = y / scale + GetDBValue("offset_y")
	else
		x = GetDBValue("position_x")
		y = GetDBValue("position_y")
	end

	self:ClearAllPoints()
	self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------
local function Initialize()
	anchor = CreateFrame("Frame", "SparkPointAnchor", UIParent)
	anchor:SetSize(64, 64)
	anchor:SetFrameStrata("HIGH")
	anchor:SetScript("OnUpdate", OnUpdate)
	anchor:Hide()
	anchor:SetAlpha(1)
	anchorVisible = false

	AnchorFrame.frame = anchor
end

-- Initialize when addon loads
CallbackRegistry:Register("ADDON_LOADED", Initialize)

--------------------------------------------------------------------------------
-- Position Lock/Unlock for manual positioning
--------------------------------------------------------------------------------
local function EnsureUnlockFrame()
	if unlockFrame then
		return
	end

	unlockFrame = CreateFrame("Frame", nil, UIParent)
	unlockFrame:SetSize(72, 72)
	unlockFrame:SetFrameStrata("TOOLTIP")
	unlockFrame:SetToplevel(true)
	unlockFrame:SetFrameLevel(200)
	unlockFrame:SetMovable(true)
	unlockFrame:EnableMouse(true)
	unlockFrame:RegisterForDrag("LeftButton")

	local dragSurface
	do
		local ok, selection = pcall(CreateFrame, "Frame", nil, unlockFrame, "EditModeSystemSelectionTemplate")
		if ok and selection then
			selection:SetAllPoints()
			selection:Show()
			selection:EnableMouse(false)
			if selection.SetFrameStrata then
				selection:SetFrameStrata("TOOLTIP")
			end
			if selection.SetFrameLevel then
				selection:SetFrameLevel(201)
			end
			unlockFrame.selection = selection
			dragSurface = selection
		end
	end

	if not dragSurface then
		local bg = unlockFrame:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.20, 0.45, 1.00, 0.12)
		unlockFrame.bg = bg

		local function AddEdge(point, relPoint, x, y, w, h)
			local edge = unlockFrame:CreateTexture(nil, "BORDER")
			edge:SetColorTexture(0.45, 0.72, 1.00, 0.95)
			edge:SetPoint(point, unlockFrame, relPoint, x, y)
			edge:SetSize(w, h)
			return edge
		end

		unlockFrame.edgeTop = AddEdge("TOPLEFT", "TOPLEFT", 0, 0, 72, 2)
		unlockFrame.edgeBottom = AddEdge("BOTTOMLEFT", "BOTTOMLEFT", 0, 0, 72, 2)
		unlockFrame.edgeLeft = AddEdge("TOPLEFT", "TOPLEFT", 0, 0, 2, 72)
		unlockFrame.edgeRight = AddEdge("TOPRIGHT", "TOPRIGHT", 0, 0, 2, 72)

		local inner = unlockFrame:CreateTexture(nil, "ARTWORK")
		inner:SetColorTexture(0.45, 0.72, 1.00, 0.25)
		inner:SetSize(8, 8)
		inner:SetPoint("CENTER")
		unlockFrame.inner = inner

		local crossH = unlockFrame:CreateTexture(nil, "ARTWORK")
		crossH:SetColorTexture(0.45, 0.72, 1.00, 0.6)
		crossH:SetSize(24, 1)
		crossH:SetPoint("CENTER")
		unlockFrame.crossH = crossH

		local crossV = unlockFrame:CreateTexture(nil, "ARTWORK")
		crossV:SetColorTexture(0.45, 0.72, 1.00, 0.6)
		crossV:SetSize(1, 24)
		crossV:SetPoint("CENTER")
		unlockFrame.crossV = crossV

		local label = unlockFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("TOP", unlockFrame, "BOTTOM", 0, -4)
		label:SetText("SparkPoint")
		label:SetTextColor(0.70, 0.85, 1.00)
		unlockFrame.label = label
	end

	unlockFrame:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)

	unlockFrame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local x, y = self:GetCenter()
		addon.SetDBValue("position_x", x, true)
		addon.SetDBValue("position_y", y, true)
	end)

	unlockFrame:SetScript("OnMouseDown", function(self, button)
		if button == "RightButton" then
			AnchorFrame:Lock()
		end
	end)
end

local function RefreshUnlockHandle()
	EnsureUnlockFrame()

	local shouldShow = unlockManualActive or unlockEditModeActive
	if shouldShow then
		if anchor and unlockFrame.SetFrameLevel then
			unlockFrame:SetFrameLevel((anchor:GetFrameLevel() or 0) + 50)
		end
		local x = GetDBValue("position_x") or 400
		local y = GetDBValue("position_y") or 400
		unlockFrame:ClearAllPoints()
		unlockFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
		unlockFrame:Show()
		if unlockFrame.selection then
			if unlockFrame.selection.ShowHighlighted then
				unlockFrame.selection:ShowHighlighted()
			else
				unlockFrame.selection:Show()
			end
		end
		AnchorFrame:Show("unlock")
	else
		if unlockFrame.selection then
			unlockFrame.selection:Hide()
		end
		unlockFrame:Hide()
		AnchorFrame:Hide("unlock")
	end
end

local function UpdateEditModeUnlockState()
	unlockEditModeActive = IsBlizzardEditModeActive() and (not GetDBBool("attachToMouse"))
	if unlockFrame or unlockEditModeActive or unlockManualActive then
		RefreshUnlockHandle()
	end
end

local function HookEditModeEventRegistry()
	if editModeEventCallbacksHooked or not EventRegistry or not EventRegistry.RegisterCallback then
		return
	end
	editModeEventCallbacksHooked = true

	EventRegistry:RegisterCallback("EditMode.Enter", function()
		UpdateEditModeUnlockState()
	end, AnchorFrame)
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		UpdateEditModeUnlockState()
	end, AnchorFrame)
end

local function HookEditModeManager()
	if editModeHooked or not EditModeManagerFrame or not EditModeManagerFrame.HookScript then
		return
	end
	editModeHooked = true

	EditModeManagerFrame:HookScript("OnShow", function()
		UpdateEditModeUnlockState()
	end)
	EditModeManagerFrame:HookScript("OnHide", function()
		UpdateEditModeUnlockState()
	end)

	UpdateEditModeUnlockState()
end

local function EnsureEditModeWatcher()
	if editModeWatcher then
		return
	end
	editModeWatcher = CreateFrame("Frame")
	editModeWatcher:RegisterEvent("PLAYER_LOGIN")
	editModeWatcher:RegisterEvent("ADDON_LOADED")
	editModeWatcher:SetScript("OnEvent", function(_, event, addonNameOrNil)
		if event == "ADDON_LOADED" and addonNameOrNil ~= "Blizzard_EditMode" then
			return
		end
		HookEditModeEventRegistry()
		HookEditModeManager()
	end)
end

function AnchorFrame:Unlock()
	-- Temporarily show anchor at fixed position
	addon.SetDBValue("attachToMouse", false, false)
	unlockManualActive = true
	RefreshUnlockHandle()

	print("SparkPoint: Drag to reposition. Right-click to lock.")
end

function AnchorFrame:Lock()
	unlockManualActive = false
	UpdateEditModeUnlockState()

	print("SparkPoint: Position locked.")
end

--------------------------------------------------------------------------------
-- Slash Commands
--------------------------------------------------------------------------------
SLASH_SPARKPOINT1 = "/sp"
SLASH_SPARKPOINT2 = "/sparkpoint"

SlashCmdList["SPARKPOINT"] = function(msg)
	msg = msg:lower():trim()

	if msg == "unlock" then
		AnchorFrame:Unlock()
	elseif msg == "lock" then
		AnchorFrame:Lock()
	elseif msg == "reset" then
		addon.SetDBValue("position_x", 400, true)
		addon.SetDBValue("position_y", 400, true)
		addon.SetDBValue("attachToMouse", true, true)
		print("SparkPoint: Position reset to defaults.")
	else
		OpenSettingsSafely()
	end
end

CallbackRegistry:RegisterSettingCallback("attachToMouse", function()
	UpdateEditModeUnlockState()
end)

CallbackRegistry:Register("ADDON_LOADED", function()
	EnsureEditModeWatcher()
	HookEditModeEventRegistry()
	HookEditModeManager()
end, AnchorFrame)
