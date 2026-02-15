-- SparkPoint Anchor Frame
-- Central 64x64 frame that all modules parent to, follows cursor or fixed position

local addonName, addon = ...
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
	if settingsOpenFrame then return end
	settingsOpenFrame = CreateFrame("Frame")
	settingsOpenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	settingsOpenFrame:SetScript("OnEvent", function()
		if not settingsOpenDeferred then return end
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

--------------------------------------------------------------------------------
-- Show/Hide Request System
-- Multiple modules can request visibility; anchor hides only when all release
--------------------------------------------------------------------------------
function AnchorFrame:Show(requester)
    showRequests[requester or "default"] = true
    if anchor then
        anchor:Show()
    end
end

function AnchorFrame:Hide(requester)
    showRequests[requester or "default"] = nil

    local anyVisible = false
    for _ in pairs(showRequests) do
        anyVisible = true
        break
    end

    if not anyVisible and anchor then
        anchor:Hide()
    end
end

function AnchorFrame:IsShown()
    return anchor and anchor:IsShown()
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

    AnchorFrame.frame = anchor
end

-- Initialize when addon loads
CallbackRegistry:Register("ADDON_LOADED", Initialize)

--------------------------------------------------------------------------------
-- Position Lock/Unlock for manual positioning
--------------------------------------------------------------------------------
local unlockFrame

function AnchorFrame:Unlock()
    if not unlockFrame then
        unlockFrame = CreateFrame("Frame", nil, UIParent)
        unlockFrame:SetSize(20, 20)
        unlockFrame:SetFrameStrata("DIALOG")
        unlockFrame:EnableMouse(true)
        unlockFrame:SetMovable(true)
        unlockFrame:RegisterForDrag("LeftButton")

        local tex = unlockFrame:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        tex:SetColorTexture(1, 0, 0, 0.5)

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

    -- Position at current anchor location
    local x = GetDBValue("position_x") or 400
    local y = GetDBValue("position_y") or 400
    unlockFrame:ClearAllPoints()
    unlockFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    unlockFrame:Show()

    -- Temporarily show anchor at fixed position
    addon.SetDBValue("attachToMouse", false, false)
    self:Show("unlock")

    print("SparkPoint: Drag to reposition. Right-click to lock.")
end

function AnchorFrame:Lock()
    if unlockFrame then
        unlockFrame:Hide()
    end
    self:Hide("unlock")

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
