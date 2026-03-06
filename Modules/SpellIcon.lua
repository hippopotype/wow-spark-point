-- SparkPoint SpellIcon Module
-- Settings and enable/disable proxy for the Cast-integrated icon

local _, addon = ...
local L = addon.L
local CallbackRegistry = addon.CallbackRegistry

--------------------------------------------------------------------------------
-- Module Object
--------------------------------------------------------------------------------
local SpellIcon = {}
addon.Modules.SpellIconObj = SpellIcon

--------------------------------------------------------------------------------
-- ApplyOptions: delegate to Cast module
--------------------------------------------------------------------------------
function SpellIcon:ApplyOptions()
	if addon.Modules.CastObj and addon.Modules.CastObj.ApplyIconOptions then
		addon.Modules.CastObj:ApplyIconOptions()
	end
	if addon.Modules.CastObj and addon.Modules.CastObj.UpdateSpellIcon then
		addon.Modules.CastObj:UpdateSpellIcon()
	end
end

--------------------------------------------------------------------------------
-- Enable/Disable
--------------------------------------------------------------------------------
local function EnableModule(enabled)
	if addon.Modules.CastObj and addon.Modules.CastObj.SetSpellIconEnabled then
		addon.Modules.CastObj:SetSpellIconEnabled(enabled)
	end
	if not enabled then
		-- Ensure icon is hidden when disabled
		if addon.Modules.CastObj and addon.Modules.CastObj.UpdateSpellIcon then
			addon.Modules.CastObj:UpdateSpellIcon()
		end
	end
end

--------------------------------------------------------------------------------
-- Register Setting Callbacks
--------------------------------------------------------------------------------
local settingKeys = {
	"spellicon_size",
	"spellicon_offsetX",
	"spellicon_offsetY",
	"spellicon_castProgressSwipe",
	"spellicon_castProgressSwipeColor",
	"spellicon_showInstantCasts",
}

for _, key in ipairs(settingKeys) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		SpellIcon:ApplyOptions()
	end)
end

--------------------------------------------------------------------------------
-- Register Module
--------------------------------------------------------------------------------
addon.ControlCenter:AddModule({
	name = L["Spell Icon"] or "Spell Icon",
	dbKey = "moduleEnabled_SpellIcon",
	description = L["Spell Icon Description"] or "Displays the icon of the spell being cast near the cursor",
	toggleFunc = EnableModule,
	categoryID = 1,
	uiOrder = 5,
})
