local _, addon = ...

local Clamp01 = addon.Util.Clamp01

local EmpowerStageLayout = {}
addon.EmpowerStageLayout = EmpowerStageLayout

function EmpowerStageLayout:Build(stageDurationsMS, holdAtMaxMS)
	local layout = {
		totalMS = 0,
		holdAtMaxMS = math.max(0, tonumber(holdAtMaxMS) or 0),
		holdStartMS = 0,
		holdStartProgress = 0,
		stages = {},
	}

	local cumulativeMS = 0
	for index, durationMS in ipairs(stageDurationsMS or {}) do
		local stageMS = math.max(0, tonumber(durationMS) or 0)
		local stage = {
			index = index,
			durationMS = stageMS,
			startMS = cumulativeMS,
			endMS = cumulativeMS + stageMS,
			startProgress = 0,
			endProgress = 0,
		}

		cumulativeMS = stage.endMS
		table.insert(layout.stages, stage)
	end

	layout.holdStartMS = cumulativeMS
	layout.totalMS = cumulativeMS + layout.holdAtMaxMS

	if layout.totalMS > 0 then
		layout.holdStartProgress = Clamp01(layout.holdStartMS / layout.totalMS)
		for _, stage in ipairs(layout.stages) do
			stage.startProgress = Clamp01(stage.startMS / layout.totalMS)
			stage.endProgress = Clamp01(stage.endMS / layout.totalMS)
		end
	end

	return layout
end
