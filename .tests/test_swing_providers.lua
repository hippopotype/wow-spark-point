-- Providers/SwingTimer.lua: the four swing slot providers.

return function(T)
	local loadStubs = dofile(".tests/swing_stubs.lua")

	local function loadProviders(hasSwing, opts)
		opts = opts or {}
		opts.withProviders = true
		opts.capabilities = { swingTimer = hasSwing }
		return loadStubs(T, opts)
	end

	local function optionValues(options)
		local values = {}
		for _, option in ipairs(options) do
			values[#values + 1] = option.value
		end
		return table.concat(values, ",")
	end

	return {
		{
			name = "swing sources exist only where the swingTimer capability does",
			fn = function()
				local retail = loadProviders(false)
				T.eq(retail.SlotProviders:Get("SWING_MH"), nil, "retail Get")
				T.eq(optionValues(retail.SlotProviders:GetDropdownOptions()), "NONE", "retail dropdown")
				local forever = loadProviders(true)
				T.eq(optionValues(forever.SlotProviders:GetDropdownOptions()), "NONE,SWING,SWING_MH,SWING_OH,SWING_RANGED", "forever dropdown")
			end,
		},
		{
			name = "main-hand provider mirrors the main-hand swing",
			fn = function()
				local addon, ctl = loadProviders(true)
				local provider = addon.SlotProviders:Get("SWING_MH")
				provider:Enable()
				addon.SwingTimer:PLAYER_SWING("PLAYER_SWING", 2, 0)
				ctl.now = 101
				local result = provider:GetProgress()
				T.eq(result.progress, 0.5, "progress")
				T.eq(result.active, true, "active")
				T.eq(result.show, true, "show")
				T.eq(result.barColor, nil, "no colour override")
				T.eq(result.dimmed, nil, "not dimmed")
			end,
		},
		{
			name = "a queued attack turns the ring gold and out of range dims it",
			fn = function()
				local addon, ctl = loadProviders(true, { queueSpells = { WARRIOR = { 78 } } })
				local provider = addon.SlotProviders:Get("SWING_MH")
				provider:Enable()
				ctl.current[78] = true
				addon.SwingTimer:CURRENT_SPELL_CAST_CHANGED("CURRENT_SPELL_CAST_CHANGED", false)
				addon.SwingTimer:PLAYER_SWING_RANGE_UPDATE("PLAYER_SWING_RANGE_UPDATE", 0, false, true)
				local result = provider:GetProgress()
				T.eq(result.barColor and result.barColor.r, 1, "gold r")
				T.eq(result.barColor and result.barColor.g, 0.82, "gold g")
				T.eq(result.barColor and result.barColor.b, 0, "gold b")
				T.eq(result.dimmed, true, "dimmed")
			end,
		},
		{
			name = "the auto source follows auto-shot",
			fn = function()
				local addon, ctl = loadProviders(true)
				local provider = addon.SlotProviders:Get("SWING")
				provider:Enable()
				addon.SwingTimer:PLAYER_SWING("PLAYER_SWING", 4, 0)
				addon.SwingTimer:START_AUTOREPEAT_SPELL("START_AUTOREPEAT_SPELL")
				addon.SwingTimer:PLAYER_SWING("PLAYER_SWING", 2, 2)
				ctl.now = 101
				T.eq(provider:GetProgress().progress, 0.5, "ranged swing while auto-shooting")
				addon.SwingTimer:STOP_AUTOREPEAT_SPELL("STOP_AUTOREPEAT_SPELL")
				T.eq(provider:GetProgress().progress, 0.25, "main-hand swing otherwise")
			end,
		},
		{
			name = "enable and disable are idempotent and balanced",
			fn = function()
				local addon, ctl = loadProviders(true)
				local mainHand = addon.SlotProviders:Get("SWING_MH")
				local offHand = addon.SlotProviders:Get("SWING_OH")
				mainHand:Enable()
				mainHand:Enable()
				T.eq(#ctl.rangeCalls, 3, "service acquired once")
				offHand:Disable()
				mainHand:Disable()
				mainHand:Disable()
				T.eq(ctl.frame.events.PLAYER_SWING, nil, "events released")
				offHand:Enable()
				T.eq(ctl.frame.events.PLAYER_SWING, true, "re-acquired after balanced release")
			end,
		},
	}
end
