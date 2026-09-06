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
			notice:SetText(L["Filter Blizzard Mode Notice"])
			notice:Show()
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
