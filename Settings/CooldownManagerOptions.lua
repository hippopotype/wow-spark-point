-- SparkPoint Cooldown Manager Options
--
-- Lives outside Settings/SettingsPanel.lua because that file is already ~1840
-- lines and this is the largest settings surface in the addon. Follows the
-- widget-mixin + XML template pattern of Settings/ColorOverrides.lua, which is a
-- mixin rather than a registration point -- the panel has no extension hook.

local _, addon = ...
local L = addon.L
local Data = addon.CooldownViewerData
local CallbackRegistry = addon.CallbackRegistry
local GetDBValue = addon.GetDBValue

local ROW_HEIGHT = 22

local CATEGORY_ORDER = {
	{ category = 0, groupKey = "essential", label = "Essential Cooldowns" },
	{ category = 1, groupKey = "utility", label = "Utility Cooldowns" },
	{ category = 2, groupKey = "trackedbuff", label = "Tracked Buffs" },
}

SparkPointCooldownFilterMixin = CreateFromMixins(SettingsListElementMixin)

function SparkPointCooldownFilterMixin:OnLoad()
	-- Chaining is mandatory: SettingsListElementMixin.OnLoad creates self.cbrHandles,
	-- which Init later asserts on. Settings/ColorOverrides.lua:20 does the same as its
	-- first statement.
	SettingsListElementMixin.OnLoad(self)
	-- SettingsListElementTemplate declares Text with no anchors at all
	-- (Blizzard_SettingControls.xml:53), leaving subclasses to position it. This panel is
	-- a scroll frame with its own headers and has nowhere to put it, so keep it hidden --
	-- otherwise anything that reaches Text:SetText draws it at an arbitrary position on
	-- top of the list. It must still EXIST: DisplayEnabled calls Text:SetTextColor.
	self.Text:Hide()
	self.rows = {}
	self.headers = {}
	CallbackRegistry:Register("CooldownViewer.EntriesChanged", function()
		if self:IsShown() then
			self:Refresh()
		end
	end, self)
end

-- Without this the list renders empty on first open: Refresh is otherwise only
-- reached from the EntriesChanged callback above, which is guarded on self:IsShown().
function SparkPointCooldownFilterMixin:Init(initializer)
	SettingsListElementMixin.Init(self, initializer)
	-- Data:Refresh's only callers are module-side (Initialize, SetHidden), so with the
	-- module disabled (the default) allEntriesByCategory is permanently empty and the
	-- player sees three headers and zero rows with no explanation. Refresh self-gates
	-- on combat, so it is safe to call unconditionally here.
	local hasAny = false
	for _, section in ipairs(CATEGORY_ORDER) do
		if #Data:GetAllEntries(section.category) > 0 then
			hasAny = true
			break
		end
	end
	if not hasAny then
		Data:Refresh()
	end
	self:Refresh()
end

function SparkPointCooldownFilterMixin:AcquireRow(index)
	local row = self.rows[index]
	if row then
		return row
	end

	row = CreateFrame("CheckButton", nil, self.ScrollFrame.Content, "UICheckButtonTemplate")
	row:SetSize(ROW_HEIGHT, ROW_HEIGHT)
	row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", row, "RIGHT", 4, 0)
	row:SetScript("OnClick", function(button)
		-- Checked means visible, so hidden is the inverse.
		Data:SetHidden(button.cooldownID, not button:GetChecked())
	end)
	self.rows[index] = row
	return row
end

function SparkPointCooldownFilterMixin:AcquireHeader(index)
	local header = self.headers[index]
	if header then
		return header
	end
	header = self.ScrollFrame.Content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	header:SetWordWrap(true)
	self.headers[index] = header
	return header
end

function SparkPointCooldownFilterMixin:Refresh()
	for _, row in ipairs(self.rows) do
		row:Hide()
	end
	for _, header in ipairs(self.headers) do
		header:Hide()
	end

	local content = self.ScrollFrame.Content
	local y = 0
	local rowIndex, headerIndex = 0, 0

	for _, section in ipairs(CATEGORY_ORDER) do
		local mode = tostring(GetDBValue("cooldownmanager_" .. section.groupKey .. "_mode") or "SPARKPOINT")
		local entries = Data:GetAllEntries(section.category)

		headerIndex = headerIndex + 1
		local header = self:AcquireHeader(headerIndex)
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		header:SetText(L[section.label] or section.label)
		header:Show()
		y = y + ROW_HEIGHT

		-- Filtering applies to SPARKPOINT mode only. In BLIZZARD mode Blizzard owns the
		-- display, so rows are disabled and the reason is shown as a separate wrapped
		-- FontString rather than appended to the header, which would clip inside the
		-- 250px content frame.
		if mode == "BLIZZARD" then
			headerIndex = headerIndex + 1
			local notice = self:AcquireHeader(headerIndex)
			notice:ClearAllPoints()
			notice:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -y)
			notice:SetWidth(230)
			notice:SetJustifyH("LEFT")
			notice:SetText(
				L["Filter Blizzard Mode Notice"]
					or "Filtering applies to SparkPoint mode only. In Blizzard mode, configure which spells appear in Blizzard's Cooldown Manager settings."
			)
			notice:Show()
			y = y + (ROW_HEIGHT * 2)

			-- Spec Degradation row 2: BLIZZARD mode is silently dead when cooldownViewerEnabled
			-- is off (the viewer frames exist but never update), and ApplyGroupMode
			-- (Modules/CooldownManager.lua) silently rewrites it to SPARKPOINT. This Refresh
			-- re-runs on both Init and "CooldownViewer.EntriesChanged" so it can never go
			-- stale the way a once-per-session panel notice would -- same reasoning the panel
			-- comment at Settings/SettingsPanel.lua gives for siting the fallback notice there.
			if not Data:IsBlizzardModeUsable() then
				headerIndex = headerIndex + 1
				local unusableNotice = self:AcquireHeader(headerIndex)
				unusableNotice:ClearAllPoints()
				unusableNotice:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -y)
				unusableNotice:SetWidth(230)
				unusableNotice:SetJustifyH("LEFT")
				unusableNotice:SetText(
					L["Filter Blizzard Mode Unusable Notice"] or "Blizzard's Cooldown Manager is disabled, so this category is showing SparkPoint icons instead."
				)
				unusableNotice:Show()
				y = y + (ROW_HEIGHT * 2)
			end
		end

		-- Bridge:IsSupported() failing (Core/CooldownViewerData.lua) means this list is
		-- Blizzard's raw, unfiltered category set rather than the player's ordered,
		-- configured Cooldown Manager selection -- a materially different set of
		-- entries, not merely unordered. Surfaced here (rather than in the settings
		-- panel) because this Refresh re-runs on both Init and
		-- "CooldownViewer.EntriesChanged", so it can never go stale the way a
		-- once-per-session panel notice would.
		if Data:IsUsingFallback(section.category) then
			headerIndex = headerIndex + 1
			local fallbackNotice = self:AcquireHeader(headerIndex)
			fallbackNotice:ClearAllPoints()
			fallbackNotice:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -y)
			fallbackNotice:SetWidth(230)
			fallbackNotice:SetJustifyH("LEFT")
			fallbackNotice:SetText(
				L["Filter Fallback Mode Notice"]
					or "Showing Blizzard's raw category list because the ordered Cooldown Viewer data is unavailable. Order and your configured Cooldown Manager selections are not reflected here."
			)
			fallbackNotice:Show()
			y = y + (ROW_HEIGHT * 2)
		end

		for _, entry in ipairs(entries) do
			rowIndex = rowIndex + 1
			local row = self:AcquireRow(rowIndex)
			row.cooldownID = entry.cooldownID
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -y)
			row:SetChecked(not Data:IsHidden(entry.cooldownID))
			row:SetEnabled(mode ~= "BLIZZARD")

			local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(entry.spellID)
			row.label:SetText((info and info.name) or tostring(entry.spellID))
			row:Show()
			y = y + ROW_HEIGHT
		end
	end

	content:SetHeight(math.max(y, 1))
end
