-- SparkPoint Ring Module
-- Displays a decorative rotating ring around the cursor

local addonName, addon = ...
local L = addon.L
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local GetDBValue = addon.GetDBValue
local GetDBBool = addon.GetDBBool
local GetDBColor = addon.GetDBColor

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------
local ringFrame
local showRequests = {}

local rad = math.rad

--------------------------------------------------------------------------------
-- Ring Module Object
--------------------------------------------------------------------------------
local Ring = {}
addon.Modules.RingObj = Ring

--------------------------------------------------------------------------------
-- Available Textures (BlizzardUI IDs)
--------------------------------------------------------------------------------
local RING_TEXTURES = {
    ["165624"] = "AuraRune 1",
    ["165630"] = "AuraRune 1 Glow",
    ["165635"] = "AuraRune 8",
    ["165633"] = "AuraRune 5",
    ["165634"] = "AuraRune 7",
    ["165631"] = "AuraRune 9",
    ["165638"] = "AuraRune A",
    ["165639"] = "AuraRune B",
    ["165640"] = "AuraRune C",
    ["165623"] = "Halo",
    ["165632"] = "Circle",
    ["AuraSplit"] = "Aura Split",
    ["AuraHalf"] = "Aura Half",
}

Ring.TEXTURES = RING_TEXTURES

--------------------------------------------------------------------------------
-- OnUpdate Handler (rotation animation)
--------------------------------------------------------------------------------
local function OnUpdate(self, elapsed)
    self.timer = self.timer + elapsed
    if self.timer > 0.02 then
        self.hAngle = self.hAngle + 0.5
        self.texture:SetRotation(rad(self.hAngle))
        self.timer = 0
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
-- Show/Hide with Request System
--------------------------------------------------------------------------------
function Ring:Show(requester)
    if not ringFrame then return end

    showRequests[requester or "default"] = true
    ringFrame:Show()
end

function Ring:Hide(requester)
    if not ringFrame then return end

    showRequests[requester or "default"] = nil

    local anyVisible = false
    for _ in pairs(showRequests) do
        anyVisible = true
        break
    end

    if not anyVisible then
        ringFrame:Hide()
    end
end

--------------------------------------------------------------------------------
-- ApplyOptions: Update visuals from settings
--------------------------------------------------------------------------------
function Ring:ApplyOptions()
    if not ringFrame then return end

    local textureID = GetDBValue("ring_texture")
    local width = GetDBValue("ring_width")
    local r, g, b, a = GetDBColor("ring_color")

    local texture = ringFrame.texture

    -- Handle texture - could be BlizzardUI ID or custom path
    if textureID:match("^%d+$") then
        -- Numeric ID - BlizzardUI texture
        texture:SetTexture(tonumber(textureID))
    elseif textureID == "AuraSplit" or textureID == "AuraHalf" then
        -- Custom texture
        texture:SetTexture(addon.addonFolder .. "\\Textures\\" .. textureID)
    else
        -- Fallback to default
        texture:SetTexture(165624)
    end

    texture:SetVertexColor(r, g, b, a)
    texture:SetBlendMode("ADD")
    texture:SetSize(width, width)

    -- Update rotation setting
    if GetDBBool("ring_rotate") and ringFrame:IsShown() then
        ringFrame:SetScript("OnUpdate", OnUpdate)
    else
        ringFrame:SetScript("OnUpdate", nil)
    end
end

--------------------------------------------------------------------------------
-- Initialize
--------------------------------------------------------------------------------
function Ring:Initialize()
    local anchor = AnchorFrame:GetFrame()
    if not anchor then return end

    ringFrame = CreateFrame("Frame", nil, anchor)
    ringFrame:SetAllPoints()
    ringFrame:Hide()

    -- Initialize rotation state
    ringFrame.timer = 0
    ringFrame.hAngle = 0

    -- Create texture
    ringFrame.texture = ringFrame:CreateTexture(nil, "ARTWORK")
    ringFrame.texture:SetPoint("CENTER")

    -- Set scripts
    ringFrame:SetScript("OnShow", OnShow)

    self:ApplyOptions()
end

--------------------------------------------------------------------------------
-- Enable/Disable
--------------------------------------------------------------------------------
local function EnableModule(enabled)
    if enabled then
        if not ringFrame then
            Ring:Initialize()
        end
        -- Ring shows when other modules request it (Cast, GCD)
    else
        if ringFrame then
            ringFrame:Hide()
        end
        showRequests = {}
    end
end

--------------------------------------------------------------------------------
-- Register Setting Callbacks
--------------------------------------------------------------------------------
local settingKeys = {
    "ring_texture", "ring_color", "ring_width", "ring_rotate"
}

for _, key in ipairs(settingKeys) do
    CallbackRegistry:RegisterSettingCallback(key, function()
        Ring:ApplyOptions()
    end)
end

--------------------------------------------------------------------------------
-- Register Module
--------------------------------------------------------------------------------
addon.ControlCenter:AddModule({
    name = L["Ring"] or "Ring",
    dbKey = "moduleEnabled_Ring",
    description = L["Ring Description"] or "Displays a decorative rotating ring around the cursor during casts",
    toggleFunc = EnableModule,
    categoryID = 1,
    uiOrder = 4,
})
