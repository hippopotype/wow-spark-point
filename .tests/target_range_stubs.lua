-- Shared stubs for the target range tests: target unit, C_Spell, C_SpellBook, C_Timer,
-- event frame and database, then loads Core/Util.lua and Core/TargetRange.lua.
-- `ctl` controls the stubs: ctl.target, ctl.inRange[identifier], ctl.known[id],
-- ctl.spells[id], ctl.byName[name], ctl.apiError, ctl.knownError; it records
-- ctl.rangeCalls, ctl.infoCalls[arg], ctl.knownCalls[arg], ctl.tickers, ctl.afterQueue, ctl.triggers, ctl.enableCalls and
-- exposes ctl.frame, ctl.db, ctl.settingCallbacks and ctl.flush().

return function(T, opts)
	opts = opts or {}
	local ctl = {
		target = { exists = false, canAttack = false, canAssist = false, isSelf = false, dead = false },
		inRange = {},
		rangeCalls = {},
		infoCalls = {},
		knownCalls = {},
		known = {},
		spells = {},
		byName = {},
		SECRET = {},
		tickers = {},
		afterQueue = {},
		triggers = {},
		settingCallbacks = {},
		enableCalls = 0,
		db = {
			targetRange_spell = opts.saved or {},
			targetRange_friendlySpell = opts.savedFriendly or {},
			targetRange_friendlyEnabled = opts.friendlyEnabled == true,
		},
	}

	_G.issecretvalue = function(v)
		return v == ctl.SECRET
	end

	_G.UnitExists = function()
		return ctl.target.exists
	end
	_G.UnitCanAttack = function()
		return ctl.target.canAttack
	end
	_G.UnitIsDeadOrGhost = function()
		return ctl.target.dead
	end
	_G.UnitCanAssist = function(a, b)
		assert(a == "player" and b == "target", "UnitCanAssist expects (player, target)")
		return ctl.target.canAssist
	end
	_G.UnitIsUnit = function(a, b)
		assert(a == "target" and b == "player", "UnitIsUnit expects (target, player)")
		return ctl.target.isSelf
	end

	local function SpellInfo(id)
		local spell = ctl.spells[id]
		if not spell then
			return nil
		end
		return { name = spell.name, spellID = id, minRange = spell.minRange or 0, maxRange = spell.maxRange or 0 }
	end

	_G.C_Spell = {
		IsSpellInRange = function(identifier, unit)
			if ctl.apiError then
				error("range API failure")
			end
			ctl.rangeCalls[#ctl.rangeCalls + 1] = { identifier = identifier, unit = unit }
			return ctl.inRange[identifier]
		end,
		GetSpellInfo = function(spell)
			ctl.infoCalls[spell] = (ctl.infoCalls[spell] or 0) + 1
			if type(spell) == "string" then
				local id = ctl.byName[spell]
				return id and SpellInfo(id) or nil
			end
			return SpellInfo(spell)
		end,
		EnableSpellRangeCheck = function()
			ctl.enableCalls = ctl.enableCalls + 1
		end,
	}

	local function IsKnown(id)
		ctl.knownCalls[id] = (ctl.knownCalls[id] or 0) + 1
		if ctl.knownError then
			error("known API failure")
		end
		return ctl.known[id] == true
	end
	_G.C_SpellBook = { IsSpellKnown = IsKnown, IsSpellInSpellBook = IsKnown }

	_G.C_Timer = {
		NewTicker = function(interval, fn)
			local ticker = { interval = interval, fn = fn, cancelled = false }
			function ticker:Cancel()
				self.cancelled = true
			end
			ctl.tickers[#ctl.tickers + 1] = ticker
			return ticker
		end,
		After = function(_, fn)
			ctl.afterQueue[#ctl.afterQueue + 1] = fn
		end,
	}
	function ctl.flush()
		local queue = ctl.afterQueue
		ctl.afterQueue = {}
		for _, fn in ipairs(queue) do
			fn()
		end
	end

	_G.CreateFrame = function()
		local frame = { events = {} }
		function frame:RegisterEvent(event)
			self.events[event] = true
		end
		function frame:UnregisterEvent(event)
			self.events[event] = nil
		end
		function frame:UnregisterAllEvents()
			self.events = {}
		end
		function frame:SetScript(script, fn)
			if script == "OnEvent" then
				self.onEvent = fn
			end
		end
		ctl.frame = frame
		return frame
	end

	local function DeepCopy(value)
		if type(value) ~= "table" then
			return value
		end
		local out = {}
		for k, v in pairs(value) do
			out[k] = DeepCopy(v)
		end
		return out
	end

	local addon = {
		L = {},
		API = {
			GetPlayerClass = function()
				return opts.class or "WARRIOR"
			end,
		},
		RangeSpells = opts.rangeSpells,
		FriendlyRangeSpells = opts.friendlySpells,
		GetDBValue = function(key)
			return ctl.db[key]
		end,
		SetDBValue = function(key, value)
			ctl.db[key] = DeepCopy(value)
			if ctl.settingCallbacks[key] then
				ctl.settingCallbacks[key](ctl.db[key])
			end
		end,
		CallbackRegistry = {
			Trigger = function(_, event, ...)
				ctl.triggers[#ctl.triggers + 1] = { event = event, args = { ... } }
			end,
			RegisterSettingCallback = function(_, key, fn)
				ctl.settingCallbacks[key] = fn
			end,
			Register = function() end,
		},
	}
	T.loadAddonFile("Core/Util.lua", addon)
	T.loadAddonFile("Core/TargetRange.lua", addon)
	return addon, ctl
end
