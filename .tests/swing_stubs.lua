-- Shared stubs for the swing timer tests: clock, event frame, C_SwingTimer, C_Spell,
-- then loads Core/Util.lua and Core/SwingTimer.lua (and the providers when asked).
-- `ctl` controls the stubs: ctl.now, ctl.inRange[type], ctl.current[identifier],
-- ctl.spellError; it records ctl.rangeCalls and exposes ctl.frame.

return function(T, opts)
	opts = opts or {}
	local ctl = { now = 100, rangeCalls = {}, inRange = {}, current = {} }

	_G.GetTime = function()
		return ctl.now
	end
	_G.CreateFrame = function()
		local frame = { events = {} }
		function frame:RegisterEvent(event)
			self.events[event] = true
		end
		function frame:UnregisterAllEvents()
			self.events = {}
		end
		function frame:SetScript() end
		ctl.frame = frame
		return frame
	end
	_G.C_SwingTimer = {
		EnableRangeCheck = function(swingType, enable)
			ctl.rangeCalls[#ctl.rangeCalls + 1] = { swingType = swingType, enable = enable }
		end,
		IsTargetWithinSwingRange = function(swingType)
			return ctl.inRange[swingType]
		end,
	}
	_G.C_Spell = {
		IsCurrentSpell = function(identifier)
			if ctl.spellError then
				error("spell API failure")
			end
			return ctl.current[identifier] == true
		end,
		GetSpellInfo = function(spellID)
			local name = opts.spellNames and opts.spellNames[spellID]
			return name and { name = name } or nil
		end,
	}

	local addon = {
		L = {},
		API = {
			GetPlayerClass = function()
				return opts.class or "WARRIOR"
			end,
		},
		SwingQueueSpells = opts.queueSpells,
		Has = function(name)
			return opts.capabilities ~= nil and opts.capabilities[name] == true
		end,
	}
	T.loadAddonFile("Core/Util.lua", addon)
	if opts.withProviders then
		T.loadAddonFile("Core/SlotProviders.lua", addon)
	end
	T.loadAddonFile("Core/SwingTimer.lua", addon)
	if opts.withProviders then
		T.loadAddonFile("Providers/SwingTimer.lua", addon)
	end
	return addon, ctl
end
