-- Class resource systems: combo points read through API.GetComboPoints and follow the target
-- on Forever; retail and non-combo resources keep their existing paths.

return function(T)
	local LoadSystem = dofile(".tests/combo_system_stubs.lua")
	local CAPABILITY = "comboPointsOnTarget"

	local function Setup(opts)
		opts = opts or {}
		local system, ctl = LoadSystem(T, opts)
		ctl.has[CAPABILITY] = opts.capability == true
		system:Initialize(ctl.NewStub())
		system:SetResource(ctl.defs[opts.defKey or "combo"])
		return system, ctl
	end

	local function PipsShown(system, count)
		for i = 1, count do
			T.eq(system.pips[i].frame.shown, true, "pip " .. i .. " frame shown")
			T.eq(system.pips[i].bg.shown, true, "pip " .. i .. " background shown")
		end
	end

	local function FilledCount(system)
		local filled = 0
		for i = 1, #system.pips do
			if system.pips[i].fill.shown then
				filled = filled + 1
			end
		end
		return filled
	end

	local function SpyTransitions(system)
		local spy = { calls = 0 }
		local original = system.PlayTransition
		system.PlayTransition = function(...)
			spy.calls = spy.calls + 1
			return original(...)
		end
		return spy
	end

	local cases = {
		{
			name = "GenericPips reads combo points through the reader",
			fn = function()
				local system, ctl = Setup({ capability = true })
				ctl.reader.current, ctl.reader.max = 3, 5
				local current, maxValue = system:ReadPower()
				T.eq(current, 3, "current")
				T.eq(maxValue, 5, "max")
				T.eq(ctl.readerCalls, 1, "reader called once")
				T.eq(ctl.readerFallbacks[1], 5, "reader gets maxCount as fallback")
			end,
		},
		{
			name = "GenericPips hides points on nil current and recovers",
			fn = function()
				local system, ctl = Setup({ capability = true })
				local root = ctl.frames[1]
				ctl.reader.current, ctl.reader.max = 3, 5
				system:Sync()
				PipsShown(system, 5)
				T.eq(FilledCount(system), 3, "three points filled")

				local rootHides = root.hideCalls
				local before = {
					UnitPower = ctl.calls.UnitPower,
					UnitPowerMax = ctl.calls.UnitPowerMax,
					GetUnitChargedPowerPoints = ctl.calls.GetUnitChargedPowerPoints,
				}
				ctl.reader.current = nil
				system:Sync()
				for i = 1, 5 do
					local pip = system.pips[i]
					T.eq(pip.frame.shown, false, "pip " .. i .. " frame hidden")
					T.eq(pip.bg.shown, false, "pip " .. i .. " background hidden")
					T.eq(pip.fill.shown, false, "pip " .. i .. " fill hidden")
					T.truthy(pip.frame.hideCalls > 0, "pip " .. i .. " frame received Hide")
				end
				T.eq(root.hideCalls, rootHides, "root never hidden by Sync")
				for name, count in pairs(before) do
					T.eq(ctl.calls[name], count, name .. " not called")
				end

				ctl.reader.current = 2
				system:Sync()
				PipsShown(system, 5)
				T.eq(FilledCount(system), 2, "two points filled after recovery")
			end,
		},
		{
			name = "GenericPips does not animate on PLAYER_TARGET_CHANGED",
			fn = function()
				local system, ctl = Setup({ capability = true })
				ctl.reader.current, ctl.reader.max = 3, 5
				system:Sync()
				local spy = SpyTransitions(system)

				ctl.reader.current = 0
				system:HandleTargetEvent("PLAYER_TARGET_CHANGED")
				T.eq(spy.calls, 0, "no transition on target change")
				T.eq(FilledCount(system), 0, "points cleared")

				ctl.reader.current = 2
				system:HandleTargetEvent("COMBO_TARGET_CHANGED")
				T.truthy(spy.calls > 0, "transition on combo target change")
			end,
		},
		{
			name = "GenericPips WantsEvent gates target events behind the capability",
			fn = function()
				local system, ctl = Setup({ capability = true })
				T.eq(system:WantsEvent("UNIT_POWER_FREQUENT"), true, "FREQUENT with capability")
				T.eq(system:WantsEvent("PLAYER_TARGET_CHANGED"), true, "PLAYER_TARGET_CHANGED with capability")
				T.eq(system:WantsEvent("COMBO_TARGET_CHANGED"), true, "COMBO_TARGET_CHANGED with capability")
				T.eq(system:WantsEvent("UNIT_POWER_UPDATE"), true, "UNIT_POWER_UPDATE with capability")
				T.eq(system:WantsEvent("UNIT_MAXPOWER"), true, "UNIT_MAXPOWER with capability")

				ctl.has[CAPABILITY] = false
				T.eq(system:WantsEvent("UNIT_POWER_FREQUENT"), false, "FREQUENT without capability")
				T.eq(system:WantsEvent("PLAYER_TARGET_CHANGED"), false, "PLAYER_TARGET_CHANGED without capability")
				T.eq(system:WantsEvent("COMBO_TARGET_CHANGED"), false, "COMBO_TARGET_CHANGED without capability")
				T.eq(system:WantsEvent("UNIT_POWER_UPDATE"), true, "UNIT_POWER_UPDATE without capability")
				T.eq(system:WantsEvent("UNIT_MAXPOWER"), true, "UNIT_MAXPOWER without capability")
			end,
		},
		{
			name = "GenericPips HandleTargetEvent re-reads through the reader",
			fn = function()
				local system, ctl = Setup({ capability = true })
				ctl.reader.current, ctl.reader.max = 3, 5
				system:Sync()
				T.eq(FilledCount(system), 3, "three points filled")
				local calls = ctl.readerCalls

				ctl.reader.current = 0
				system:HandleTargetEvent("PLAYER_TARGET_CHANGED")
				T.eq(ctl.readerCalls, calls + 1, "reader called again")
				T.eq(FilledCount(system), 0, "Sync applied the new count")
			end,
		},
		{
			name = "GenericPips HandleEvent filters unchanged",
			fn = function()
				local system, ctl = Setup({ capability = true })
				ctl.reader.current, ctl.reader.max = 3, 5
				system:HandleEvent("UNIT_POWER_UPDATE", "target", "COMBO_POINTS")
				T.eq(ctl.readerCalls, 0, "target unit ignored")
				system:HandleEvent("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
				T.eq(ctl.readerCalls, 1, "player combo update syncs")
			end,
		},
		{
			name = "GenericPips non-combo resource is unaffected",
			fn = function()
				local system, ctl = Setup({ capability = true, defKey = "holy" })
				ctl.power, ctl.maxPower = 2, 5
				local current, maxValue = system:ReadPower()
				T.eq(current, 2, "holy power current")
				T.eq(maxValue, 5, "holy power max")
				T.eq(ctl.calls.UnitPower, 1, "UnitPower read directly")
				T.eq(ctl.readerCalls, 0, "reader not used")
				T.eq(system:WantsEvent("PLAYER_TARGET_CHANGED"), false, "no target events")
				T.eq(system:WantsEvent("COMBO_TARGET_CHANGED"), false, "no combo target events")
				T.eq(system:WantsEvent("UNIT_POWER_FREQUENT"), false, "no FREQUENT")
			end,
		},
		{
			name = "GenericPips retail combo path is unchanged",
			fn = function()
				local system, ctl = Setup({ capability = false })
				ctl.reader.current, ctl.reader.max = "4", 5
				local current, maxValue = system:ReadPower()
				T.eq(current, 4, "normalized current")
				T.eq(maxValue, 5, "max")

				ctl.reader.current, ctl.reader.max = nil, nil
				current, maxValue = system:ReadPower()
				T.eq(current, 0, "nil current normalizes to 0")
				T.eq(maxValue, 0, "nil max normalizes to 0")

				system:Sync()
				T.eq(FilledCount(system), 0, "nothing filled")
			end,
		},
	}

	-- Dedicated combo point systems (Rogue, Druid). Point visibility is driven only by
	-- point:Show()/Hide() (recorded by the stub); fullness is the explicit point field.
	local SYSTEMS = {
		{
			label = "Rogue",
			file = "Modules/ClassResourceSystems/RogueComboPoints.lua",
			systemID = "ROGUE_COMBO_POINTS",
			isFull = function(point)
				return point.state == 2 or point.state == 4
			end,
		},
		{
			label = "Druid",
			file = "Modules/ClassResourceSystems/DruidComboPoints.lua",
			systemID = "DRUID_COMBO_POINTS",
			isFull = function(point)
				return point.isActive == true
			end,
		},
	}

	local function WowCalls(ctl)
		return {
			UnitPower = ctl.calls.UnitPower,
			UnitPowerMax = ctl.calls.UnitPowerMax,
			GetUnitChargedPowerPoints = ctl.calls.GetUnitChargedPowerPoints,
		}
	end

	for _, sys in ipairs(SYSTEMS) do
		local function SetupSystem(capability)
			return Setup({ capability = capability, file = sys.file, systemID = sys.systemID })
		end

		local function FullCount(system)
			local full = 0
			for i = 1, #system.points do
				if sys.isFull(system.points[i]) then
					full = full + 1
				end
			end
			return full
		end

		local function PointsShown(system, count)
			for i = 1, count do
				T.eq(system.points[i].shown, true, "point " .. i .. " shown")
			end
		end

		local list = {
			{
				name = "reads through the reader",
				fn = function()
					local system, ctl = SetupSystem(true)
					ctl.chargedErrors = true
					ctl.reader.current, ctl.reader.max = 3, 5
					local current, maxPoints, charged = system:ReadState()
					T.eq(current, 3, "current")
					T.eq(maxPoints, 5, "max")
					T.eq(charged, nil, "no charged data on Forever")
					T.eq(ctl.readerCalls, 1, "reader called once")
					T.eq(ctl.readerFallbacks[1], 5, "reader gets maxCount as fallback")
					T.eq(ctl.calls.UnitPower, 0, "UnitPower not called directly")
					T.eq(ctl.calls.UnitPowerMax, 0, "UnitPowerMax not called directly")
				end,
			},
			{
				name = "nil current hides points and recovers",
				fn = function()
					local system, ctl = SetupSystem(true)
					ctl.chargedErrors = true
					local root = ctl.frames[1]
					ctl.reader.current, ctl.reader.max = 3, 5
					system:Sync()
					PointsShown(system, 5)
					T.eq(FullCount(system), 3, "three points full")

					local rootHides, rootShows = root.hideCalls, root.showCalls
					local before = WowCalls(ctl)
					ctl.reader.current = nil
					system:Sync()
					for i = 1, 5 do
						T.eq(system.points[i].shown, false, "point " .. i .. " hidden")
						T.truthy(system.points[i].hideCalls > 0, "point " .. i .. " received Hide")
					end
					T.eq(root.hideCalls, rootHides, "root never hidden by Sync")
					T.eq(root.showCalls, rootShows, "root untouched by Sync")
					for name, count in pairs(before) do
						T.eq(ctl.calls[name], count, name .. " not called")
					end

					ctl.reader.current = 2
					system:Sync()
					PointsShown(system, 5)
					T.eq(FullCount(system), 2, "two points full after recovery")
				end,
			},
			{
				name = "nil max hides points",
				fn = function()
					local system, ctl = SetupSystem(true)
					ctl.reader.current, ctl.reader.max = 3, 5
					system:Sync()
					ctl.reader.current, ctl.reader.max = 2, nil
					system:Sync()
					for i = 1, 5 do
						T.eq(system.points[i].shown, false, "point " .. i .. " hidden")
					end
				end,
			},
			{
				name = "WantsEvent gating",
				fn = function()
					local system, ctl = SetupSystem(true)
					T.eq(system:WantsEvent("UNIT_POWER_FREQUENT"), true, "FREQUENT with capability")
					T.eq(system:WantsEvent("PLAYER_TARGET_CHANGED"), true, "PLAYER_TARGET_CHANGED with capability")
					T.eq(system:WantsEvent("COMBO_TARGET_CHANGED"), true, "COMBO_TARGET_CHANGED with capability")
					T.eq(system:WantsEvent("UNIT_POWER_UPDATE"), true, "UNIT_POWER_UPDATE with capability")
					T.eq(system:WantsEvent("UNIT_MAXPOWER"), true, "UNIT_MAXPOWER with capability")
					T.eq(system:WantsEvent("UNIT_AURA"), false, "unrelated event with capability")

					ctl.has[CAPABILITY] = false
					T.eq(system:WantsEvent("UNIT_POWER_FREQUENT"), false, "FREQUENT without capability")
					T.eq(system:WantsEvent("PLAYER_TARGET_CHANGED"), false, "PLAYER_TARGET_CHANGED without capability")
					T.eq(system:WantsEvent("COMBO_TARGET_CHANGED"), false, "COMBO_TARGET_CHANGED without capability")
					T.eq(system:WantsEvent("UNIT_POWER_UPDATE"), true, "UNIT_POWER_UPDATE without capability")
					T.eq(system:WantsEvent("UNIT_MAXPOWER"), true, "UNIT_MAXPOWER without capability")
				end,
			},
			{
				name = "HandleTargetEvent re-reads through the reader",
				fn = function()
					local system, ctl = SetupSystem(true)
					ctl.reader.current, ctl.reader.max = 3, 5
					system:Sync()
					T.eq(FullCount(system), 3, "three points full")
					local calls = ctl.readerCalls

					ctl.reader.current = 0
					system:HandleTargetEvent("PLAYER_TARGET_CHANGED")
					T.eq(ctl.readerCalls, calls + 1, "reader called again on PLAYER_TARGET_CHANGED")
					T.eq(FullCount(system), 0, "Sync applied the new count")

					ctl.reader.current = 4
					system:HandleTargetEvent("COMBO_TARGET_CHANGED")
					T.eq(ctl.readerCalls, calls + 2, "reader called again on COMBO_TARGET_CHANGED")
					T.eq(FullCount(system), 4, "Sync applied the combo target count")
				end,
			},
			{
				name = "HandleEvent filters unchanged",
				fn = function()
					local system, ctl = SetupSystem(true)
					ctl.reader.current, ctl.reader.max = 3, 5
					system:HandleEvent("UNIT_POWER_UPDATE", "target", "COMBO_POINTS")
					T.eq(ctl.readerCalls, 0, "target unit ignored")
					system:HandleEvent("UNIT_POWER_UPDATE", "player", "ENERGY")
					T.eq(ctl.readerCalls, 0, "other power token ignored")
					system:HandleEvent("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
					T.eq(ctl.readerCalls, 1, "player combo update syncs")
					system:HandleEvent("UNIT_MAXPOWER", "player")
					T.eq(ctl.readerCalls, 2, "player max power update syncs")
				end,
			},
			{
				name = "retail path unchanged",
				fn = function()
					local system, ctl = SetupSystem(false)
					ctl.reader.current, ctl.reader.max = 3, 5
					local current, maxPoints = system:ReadState()
					T.eq(current, 3, "current passes through")
					T.eq(maxPoints, 5, "max passes through")

					ctl.reader.current, ctl.reader.max = nil, nil
					current, maxPoints = system:ReadState()
					T.eq(current, 0, "nil current wraps to 0")
					T.eq(maxPoints, 0, "nil max wraps to 0")

					ctl.reader.current, ctl.reader.max = 3, 5
					system:Sync()
					T.eq(FullCount(system), 3, "three points full")
					ctl.reader.current, ctl.reader.max = nil, nil
					system:Sync()
					for i = 1, 5 do
						T.eq(system.points[i].shown, false, "point " .. i .. " hidden at max 0")
					end
				end,
			},
		}

		if sys.label == "Rogue" then
			list[#list + 1] = {
				name = "skips charged points on Forever",
				fn = function()
					local system, ctl = SetupSystem(true)
					ctl.chargedErrors = true
					ctl.reader.current, ctl.reader.max = 3, 5
					system:ReadState()
					system:Sync()
					ctl.reader.current = nil
					system:ReadState()
					system:Sync()
					T.eq(ctl.calls.GetUnitChargedPowerPoints, 0, "charged points never read with the capability")

					ctl.has[CAPABILITY] = false
					ctl.chargedErrors = false
					ctl.charged = { 2, "4", 0 }
					ctl.reader.current, ctl.reader.max = 3, 5
					local current, maxPoints, charged = system:ReadState()
					T.eq(ctl.calls.GetUnitChargedPowerPoints, 1, "charged points read without the capability")
					T.eq(current, 3, "retail current")
					T.eq(maxPoints, 5, "retail max")
					T.eq(charged[2], true, "point 2 charged")
					T.eq(charged[4], true, "point 4 charged")
					T.eq(charged[0], nil, "index 0 ignored")
					T.eq(charged[1], nil, "point 1 not charged")

					ctl.charged = {}
					local _, _, emptyCharged = system:ReadState()
					T.eq(emptyCharged, nil, "empty charged list gives no map")
					ctl.reader.current, ctl.reader.max = nil, nil
					ctl.charged = { 1 }
					current, maxPoints, charged = system:ReadState()
					T.eq(current, 0, "nil current wraps to 0 with charged data")
					T.eq(maxPoints, 0, "nil max wraps to 0 with charged data")
					T.eq(charged[1], true, "charged still read on retail")
				end,
			}
		end

		for _, case in ipairs(list) do
			cases[#cases + 1] = { name = sys.label .. "ComboPoints " .. case.name, fn = case.fn }
		end
	end

	return cases
end
