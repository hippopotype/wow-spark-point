-- SparkPoint Swing Timer slot providers (WoW Forever)
-- Four Ring Slot sources backed by Core/SwingTimer.lua. requires = { "swingTimer" }
-- hides them on clients without the swing API. displayName is a literal; the slot
-- dropdown localizes it through addon.L at build time.

local _, addon = ...
local SwingTimer = addon.SwingTimer

-- Classic Heroic Strike gold while a next-melee attack is queued.
local QUEUE_COLOR = { r = 1, g = 0.82, b = 0, a = 1 }

local function RegisterSwingProvider(id, displayName, resolveHand)
	local provider = {
		id = id,
		displayName = displayName,
		requires = { "swingTimer" },
	}
	local enabled = false

	function provider:Enable()
		if enabled then
			return
		end
		enabled = true
		SwingTimer:Acquire()
	end

	function provider:Disable()
		if not enabled then
			return
		end
		enabled = false
		SwingTimer:Release()
	end

	function provider:GetProgress()
		local state = SwingTimer:GetState(resolveHand())
		return {
			progress = state.progress,
			active = state.active,
			show = state.active,
			barColor = state.queued and QUEUE_COLOR or nil,
			dimmed = state.outOfRange or nil,
		}
	end

	addon.SlotProviders:Register(id, provider)
end

RegisterSwingProvider("SWING", "Swing (Auto)", function()
	return SwingTimer:GetAutoHand()
end)
RegisterSwingProvider("SWING_MH", "Main Hand Swing", function()
	return "MH"
end)
RegisterSwingProvider("SWING_OH", "Off Hand Swing", function()
	return "OH"
end)
RegisterSwingProvider("SWING_RANGED", "Ranged Swing", function()
	return "RANGED"
end)
