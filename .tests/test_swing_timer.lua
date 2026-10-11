-- Core/SwingTimer.lua: swing state from PLAYER_SWING, range and queue detection.

return function(T)
	local loadStubs = dofile(".tests/swing_stubs.lua")

	local function loadService(opts)
		local addon, ctl = loadStubs(T, opts)
		return addon.SwingTimer, ctl
	end

	local function countEnables(ctl)
		local count = 0
		for _, call in ipairs(ctl.rangeCalls) do
			T.eq(call.enable, true, "EnableRangeCheck must never be called with false")
			count = count + 1
		end
		return count
	end

	return {
		{
			name = "a main-hand swing fills over its duration",
			fn = function()
				local S, ctl = loadService()
				S:Acquire()
				S:PLAYER_SWING("PLAYER_SWING", 2, 0)
				ctl.now = 101
				local state = S:GetState("MH")
				T.eq(state.progress, 0.5, "progress")
				T.eq(state.active, true, "active")
			end,
		},
		{
			name = "progress clamps at 1 and the swing goes inactive",
			fn = function()
				local S, ctl = loadService()
				S:Acquire()
				S:PLAYER_SWING("PLAYER_SWING", 2, 0)
				ctl.now = 103
				local state = S:GetState("MH")
				T.eq(state.progress, 1, "progress")
				T.eq(state.active, false, "active")
			end,
		},
		{
			name = "a swing marks its hand active without PLAYER_ENTER_COMBAT (reload mid-fight)",
			fn = function()
				local S = loadService()
				S:Acquire()
				T.eq(S:GetState("OH").active, false, "before any swing")
				S:PLAYER_SWING("PLAYER_SWING", 2.6, 1)
				T.eq(S:GetState("OH").active, true, "after an off-hand swing")
			end,
		},
		{
			name = "leaving combat stops melee rings; stopping auto-repeat stops the ranged ring",
			fn = function()
				local S = loadService()
				S:Acquire()
				S:PLAYER_SWING("PLAYER_SWING", 3, 0)
				S:PLAYER_SWING("PLAYER_SWING", 3, 2)
				S:PLAYER_LEAVE_COMBAT("PLAYER_LEAVE_COMBAT")
				T.eq(S:GetState("MH").active, false, "MH after leave combat")
				T.eq(S:GetState("RANGED").active, true, "RANGED after leave combat")
				S:STOP_AUTOREPEAT_SPELL("STOP_AUTOREPEAT_SPELL")
				T.eq(S:GetState("RANGED").active, false, "RANGED after stop auto-repeat")
			end,
		},
		{
			name = "secret, zero and unknown swings are ignored",
			fn = function()
				local S = loadService()
				S:Acquire()
				_G.issecretvalue = function(value)
					return value == 2.5
				end
				S:PLAYER_SWING("PLAYER_SWING", 2.5, 0)
				S:PLAYER_SWING("PLAYER_SWING", 0, 0)
				S:PLAYER_SWING("PLAYER_SWING", 2, 7)
				S:PLAYER_SWING("PLAYER_SWING", "2", 0)
				local state = S:GetState("MH")
				T.eq(state.progress, 0, "progress")
				T.eq(state.active, false, "active")
			end,
		},
		{
			name = "range: dimmed only when checking and not in range",
			fn = function()
				local S = loadService()
				S:Acquire()
				S:PLAYER_SWING_RANGE_UPDATE("PLAYER_SWING_RANGE_UPDATE", 0, false, true)
				T.eq(S:GetState("MH").outOfRange, true, "checking, out of range")
				S:PLAYER_SWING_RANGE_UPDATE("PLAYER_SWING_RANGE_UPDATE", 0, true, true)
				T.eq(S:GetState("MH").outOfRange, false, "checking, in range")
				S:PLAYER_SWING_RANGE_UPDATE("PLAYER_SWING_RANGE_UPDATE", 0, true, false)
				T.eq(S:GetState("MH").outOfRange, false, "not checking")
			end,
		},
		{
			name = "target change re-asserts range checks and polls range (nil counts as in range)",
			fn = function()
				local S, ctl = loadService()
				S:Acquire()
				ctl.rangeCalls = {}
				ctl.inRange[0] = false
				S:PLAYER_TARGET_CHANGED("PLAYER_TARGET_CHANGED")
				T.eq(S:GetState("MH").outOfRange, true, "polled out of range")
				T.eq(countEnables(ctl), 3, "range checks re-asserted for 3 swing types")
				ctl.inRange[0] = nil
				S:PLAYER_TARGET_CHANGED("PLAYER_TARGET_CHANGED")
				T.eq(S:GetState("MH").outOfRange, false, "nil counts as in range")
			end,
		},
		{
			name = "every range re-assert also polls the current range",
			fn = function()
				local S, ctl = loadService()
				ctl.inRange[0] = false
				S:Acquire()
				T.eq(S:GetState("MH").outOfRange, true, "polled on first acquire")
				ctl.inRange[0] = true
				S:CVAR_UPDATE("CVAR_UPDATE", "showSwingTimer")
				T.eq(S:GetState("MH").outOfRange, false, "re-polled on CVAR_UPDATE")
				ctl.inRange[0] = false
				S:PLAYER_ENTERING_WORLD("PLAYER_ENTERING_WORLD")
				T.eq(S:GetState("MH").outOfRange, true, "re-polled on PLAYER_ENTERING_WORLD")
				ctl.inRange[0] = nil
				S:WEAPON_SLOT_CHANGED("WEAPON_SLOT_CHANGED")
				T.eq(S:GetState("MH").outOfRange, false, "re-polled on WEAPON_SLOT_CHANGED")
			end,
		},
		{
			name = "range checks are only ever enabled, including on re-assert events",
			fn = function()
				local S, ctl = loadService()
				S:Acquire()
				S:PLAYER_ENTERING_WORLD("PLAYER_ENTERING_WORLD")
				S:WEAPON_SLOT_CHANGED("WEAPON_SLOT_CHANGED")
				S:CVAR_UPDATE("CVAR_UPDATE", "showSwingTimer")
				S:Release()
				T.eq(countEnables(ctl), 12, "3 types x (acquire + 3 re-assert events)")
			end,
		},
		{
			name = "acquire/release reference-counts events and never underflows",
			fn = function()
				local S, ctl = loadService()
				S:Acquire()
				S:Acquire()
				T.eq(ctl.frame.events.PLAYER_SWING, true, "registered on first acquire")
				S:PLAYER_SWING("PLAYER_SWING", 2, 0)
				S:Release()
				T.eq(ctl.frame.events.PLAYER_SWING, true, "still registered with one holder")
				S:Release()
				T.eq(ctl.frame.events.PLAYER_SWING, nil, "unregistered on last release")
				S:Release()
				S:Acquire()
				T.eq(ctl.frame.events.PLAYER_SWING, true, "registered again after an extra release")
				T.eq(S:GetState("MH").progress, 0, "state cleared on last release")
			end,
		},
		{
			name = "queue: the known rank is detected by name and re-checked on swing and action bar state",
			fn = function()
				local S, ctl = loadService({ queueSpells = { WARRIOR = { 78 } }, spellNames = { [78] = "Heroic Strike" } })
				S:Acquire()
				ctl.current["Heroic Strike"] = true
				S:CURRENT_SPELL_CAST_CHANGED("CURRENT_SPELL_CAST_CHANGED", false)
				T.eq(S:GetState("MH").queued, true, "queued via name")
				T.eq(S:GetState("OH").queued, false, "only the main hand shows queue")
				ctl.current["Heroic Strike"] = nil
				S:PLAYER_SWING("PLAYER_SWING", 2, 0)
				T.eq(S:GetState("MH").queued, false, "cleared when the queued swing lands")
				ctl.current[78] = true
				S:ACTIONBAR_UPDATE_STATE("ACTIONBAR_UPDATE_STATE")
				T.eq(S:GetState("MH").queued, true, "queued via rank-1 id")
			end,
		},
		{
			name = "queue: missing data or a failing spell API never queues",
			fn = function()
				local S = loadService()
				S:Acquire()
				S:CURRENT_SPELL_CAST_CHANGED("CURRENT_SPELL_CAST_CHANGED", false)
				T.eq(S:GetState("MH").queued, false, "no queue data")
				local S2, ctl2 = loadService({ queueSpells = { WARRIOR = { 78 } } })
				S2:Acquire()
				ctl2.spellError = true
				S2:CURRENT_SPELL_CAST_CHANGED("CURRENT_SPELL_CAST_CHANGED", false)
				T.eq(S2:GetState("MH").queued, false, "spell API error")
			end,
		},
		{
			name = "auto hand follows auto-repeat",
			fn = function()
				local S = loadService()
				S:Acquire()
				T.eq(S:GetAutoHand(), "MH", "melee by default")
				S:START_AUTOREPEAT_SPELL("START_AUTOREPEAT_SPELL")
				T.eq(S:GetAutoHand(), "RANGED", "while auto-repeating")
				S:STOP_AUTOREPEAT_SPELL("STOP_AUTOREPEAT_SPELL")
				T.eq(S:GetAutoHand(), "MH", "after auto-repeat stops")
			end,
		},
	}
end
