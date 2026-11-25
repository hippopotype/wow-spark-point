-- Core/TargetRange.lua: owner-keyed polling of C_Spell.IsSpellInRange for the target.

return function(T)
	local loadStubs = dofile(".tests/target_range_stubs.lua")

	-- Default fixture: a Warrior with Heroic Throw (30 yd) and Charge (8-25 yd), both known,
	-- listed longest reach first like the data files.
	local function loadService(opts)
		opts = opts or {}
		if opts.rangeSpells == nil then
			opts.rangeSpells = { WARRIOR = { 200, 100 } }
		end
		local addon, ctl = loadStubs(T, opts)
		ctl.spells[100] = { name = "Charge", minRange = 8, maxRange = 25 }
		ctl.spells[200] = { name = "Heroic Throw", minRange = 0, maxRange = 30 }
		ctl.known[100] = true
		ctl.known[200] = true
		return addon.TargetRange, ctl, addon
	end

	local function hostile(ctl)
		ctl.target.exists = true
		ctl.target.canAttack = true
		ctl.target.dead = false
	end

	-- Friendly fixture: a Priest with hostile and friendly lists, all spells known.
	local function loadFriendly(opts)
		opts = opts or {}
		opts.class = "PRIEST"
		if opts.rangeSpells == nil then
			opts.rangeSpells = { PRIEST = { 589, 8092 } }
		end
		if opts.friendlySpells == nil then
			opts.friendlySpells = { PRIEST = { 2061, 17 } }
		end
		if opts.friendlyEnabled == nil then
			opts.friendlyEnabled = true
		end
		local addon, ctl = loadStubs(T, opts)
		ctl.spells[589] = { name = "Shadow Word: Pain", minRange = 0, maxRange = 40 }
		ctl.spells[8092] = { name = "Mind Blast", minRange = 0, maxRange = 40 }
		ctl.spells[2061] = { name = "Flash Heal", minRange = 0, maxRange = 40 }
		ctl.spells[17] = { name = "Power Word: Shield", minRange = 0, maxRange = 40 }
		for _, id in ipairs({ 589, 8092, 2061, 17 }) do
			ctl.known[id] = true
		end
		return addon.TargetRange, ctl, addon
	end

	local function friendly(ctl)
		ctl.target = { exists = true, canAttack = false, canAssist = true, dead = false }
	end

	-- Melee companion fixture: Shoot Gun (8-30 yd) with Taunt (5 yd), both known.
	local function loadCompanion(opts)
		opts = opts or {}
		if opts.rangeSpells == nil then
			opts.rangeSpells = { WARRIOR = { 7918, 355 } }
		end
		local S, ctl, addon = loadService(opts)
		ctl.spells[7918] = { name = "Shoot Gun", minRange = 8, maxRange = 30 }
		ctl.spells[355] = { name = "Taunt", minRange = 0, maxRange = 5 }
		ctl.known[7918] = true
		ctl.known[355] = true
		return S, ctl, addon
	end

	local function rangeCalled(ctl, identifier)
		for _, call in ipairs(ctl.rangeCalls) do
			if call.identifier == identifier then
				return true
			end
		end
		return false
	end

	local function sumCalls(counts)
		local total = 0
		for _, count in pairs(counts) do
			total = total + count
		end
		return total
	end

	local function countKeys(tbl)
		local count = 0
		for _ in pairs(tbl) do
			count = count + 1
		end
		return count
	end

	local function sameIds(a, b, msg)
		T.eq(#a, #b, msg .. " length")
		for i = 1, #a do
			T.eq(a[i].id, b[i].id, msg .. " id " .. i)
		end
	end

	local function clearTarget(ctl)
		ctl.target.exists = false
		ctl.target.canAttack = false
	end

	local function countEvents(ctl)
		local count = 0
		for _ in pairs(ctl.frame.events) do
			count = count + 1
		end
		return count
	end

	local function countChanges(ctl)
		local count = 0
		for _, trigger in ipairs(ctl.triggers) do
			if trigger.event == "TargetRangeChanged" then
				count = count + 1
			end
		end
		return count
	end

	local function activeTickers(ctl)
		local count = 0
		for _, ticker in ipairs(ctl.tickers) do
			if not ticker.cancelled then
				count = count + 1
			end
		end
		return count
	end

	return {
		-- Lifecycle and wiring
		{
			name = "idle until acquired",
			fn = function()
				local S, ctl = loadService()
				T.eq(countEvents(ctl), 0, "registered events")
				T.eq(#ctl.tickers, 0, "tickers")
				T.eq(S:GetState(), "UNKNOWN", "state")
			end,
		},
		{
			name = "acquire with a target already selected evaluates and starts one ticker",
			fn = function()
				local S, ctl = loadService()
				hostile(ctl)
				ctl.inRange[200] = false
				S:Acquire("a")
				T.eq(S:GetState(), "OUT_OF_RANGE", "state")
				T.eq(#ctl.tickers, 1, "tickers")
				T.eq(ctl.tickers[1].interval, 0.1, "interval")
			end,
		},
		{
			name = "ticker and OnEvent are wired",
			fn = function()
				local S, ctl = loadService()
				hostile(ctl)
				ctl.inRange[200] = false
				S:Acquire("a")
				ctl.inRange[200] = true
				ctl.tickers[1].fn()
				T.eq(S:GetState(), "IN_RANGE", "after tick")
				clearTarget(ctl)
				ctl.frame.onEvent(ctl.frame, "PLAYER_TARGET_CHANGED")
				T.eq(S:GetState(), "UNKNOWN", "after target cleared")
				T.eq(ctl.tickers[1].cancelled, true, "ticker cancelled")
			end,
		},
		{
			name = "PLAYER_ENTERING_WORLD flush with an existing target starts the ticker",
			fn = function()
				local S, ctl = loadService()
				S:Acquire("a")
				T.eq(#ctl.tickers, 0, "no ticker without a target")
				hostile(ctl)
				ctl.inRange[200] = false
				S:PLAYER_ENTERING_WORLD()
				ctl.flush()
				T.eq(#ctl.tickers, 1, "tickers")
				T.eq(S:GetState(), "OUT_OF_RANGE", "state")
			end,
		},
		{
			name = "ticker runs only while a target exists",
			fn = function()
				local S, ctl = loadService()
				S:Acquire("a")
				hostile(ctl)
				S:PLAYER_TARGET_CHANGED()
				T.eq(#ctl.tickers, 1, "ticker on target")
				clearTarget(ctl)
				S:PLAYER_TARGET_CHANGED()
				T.eq(ctl.tickers[1].cancelled, true, "cancelled on clear")
				hostile(ctl)
				S:PLAYER_TARGET_CHANGED()
				T.eq(#ctl.tickers, 2, "new ticker")
				T.eq(ctl.tickers[2].cancelled, false, "new ticker running")
			end,
		},
		{
			name = "last release goes idle and announces UNKNOWN",
			fn = function()
				local S, ctl = loadService()
				hostile(ctl)
				ctl.inRange[200] = false
				S:Acquire("a")
				S:Acquire("b")
				T.eq(S:GetState(), "OUT_OF_RANGE", "state")
				S:Release("a")
				T.truthy(countEvents(ctl) > 0, "still active after one release")
				T.eq(activeTickers(ctl), 1, "ticker still running")
				S:Release("b")
				T.eq(countEvents(ctl), 0, "events after last release")
				T.eq(ctl.tickers[1].cancelled, true, "ticker cancelled")
				T.eq(S:GetState(), "UNKNOWN", "state")
				local last = ctl.triggers[#ctl.triggers]
				T.eq(last.event, "TargetRangeChanged", "last event")
				T.eq(last.args[1], "UNKNOWN", "last payload")

				S:Acquire("a")
				S:Acquire("a")
				S:Release("a")
				T.eq(countEvents(ctl), 0, "idempotent owner goes idle on one release")
				T.eq(activeTickers(ctl), 0, "no running ticker")
			end,
		},
		{
			name = "setting callback or flush while idle stays idle",
			fn = function()
				local S, ctl = loadService()
				hostile(ctl)
				ctl.settingCallbacks.targetRange_spell()
				ctl.flush()
				T.eq(#ctl.tickers, 0, "no ticker")
				T.eq(countEvents(ctl), 0, "no events")

				S:Acquire("a")
				clearTarget(ctl)
				S:PLAYER_TARGET_CHANGED()
				S:SPELLS_CHANGED()
				S:Release("a")
				hostile(ctl)
				ctl.flush()
				T.eq(activeTickers(ctl), 0, "no ticker after flush while idle")
				T.eq(S:GetState(), "UNKNOWN", "state")
			end,
		},
		{
			name = "GetCandidates works with no owners and registers nothing",
			fn = function()
				local S, ctl = loadService()
				local candidates = S:GetCandidates()
				T.eq(#candidates, 2, "candidate count")
				T.eq(candidates[1].id, 200, "first id")
				T.eq(candidates[2].id, 100, "second id")
				T.eq(candidates[2].name, "Charge", "second name")
				T.eq(candidates[2].minRange, 8, "second minRange")
				T.eq(candidates[2].maxRange, 25, "second maxRange")
				T.eq(S:GetResolvedSpell(), 200, "resolved")
				T.eq(S:GetDropdownValue(), "AUTO", "dropdown value")
				T.eq(#S:GetDropdownOptions(), 3, "dropdown options")
				T.eq(countEvents(ctl), 0, "events")
				T.eq(#ctl.tickers, 0, "tickers")
				T.eq(#ctl.afterQueue, 0, "queued passes")
			end,
		},
		{
			name = "never touches the shared range toggle",
			fn = function()
				local S, ctl = loadService()
				S:Acquire("a")
				hostile(ctl)
				ctl.inRange[200] = false
				S:PLAYER_TARGET_CHANGED()
				S:SPELLS_CHANGED()
				S:PLAYER_ENTERING_WORLD()
				ctl.flush()
				S:Tick()
				S:SetSavedSpell(100)
				S:Tick()
				T.eq(ctl.enableCalls, 0, "EnableSpellRangeCheck calls")
				T.eq(ctl.frame.events.SPELL_RANGE_CHECK_UPDATE, nil, "SPELL_RANGE_CHECK_UPDATE")
				S:Release("a")
				T.eq(ctl.enableCalls, 0, "EnableSpellRangeCheck calls after release")
			end,
		},

		-- Gate and state
		{
			name = "attackable target: true/false/nil -> IN_RANGE/OUT_OF_RANGE/UNKNOWN",
			fn = function()
				local S, ctl = loadService()
				hostile(ctl)
				S:Acquire("a")
				ctl.inRange[200] = true
				S:Tick()
				T.eq(S:GetState(), "IN_RANGE", "true")
				ctl.inRange[200] = false
				S:Tick()
				T.eq(S:GetState(), "OUT_OF_RANGE", "false")
				ctl.inRange[200] = nil
				ctl.inRange[100] = nil
				S:Tick()
				T.eq(S:GetState(), "UNKNOWN", "nil")
			end,
		},
		{
			name = "non-assistable target -> UNKNOWN",
			fn = function()
				local S, ctl = loadService()
				hostile(ctl)
				ctl.target.canAttack = false
				ctl.inRange[200] = false
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetState(), "UNKNOWN", "state")
			end,
		},
		{
			name = "dead target -> UNKNOWN",
			fn = function()
				local S, ctl = loadService()
				hostile(ctl)
				ctl.target.dead = true
				ctl.inRange[200] = false
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetState(), "UNKNOWN", "state")
			end,
		},
		{
			name = "hostile to friendly re-evaluates without a tick",
			fn = function()
				local S, ctl = loadService()
				hostile(ctl)
				ctl.inRange[200] = false
				S:Acquire("a")
				T.eq(S:GetState(), "OUT_OF_RANGE", "hostile")
				ctl.target.canAttack = false
				ctl.frame.onEvent(ctl.frame, "PLAYER_TARGET_CHANGED")
				T.eq(S:GetState(), "UNKNOWN", "friendly")
				T.eq(activeTickers(ctl), 1, "ticker still running")
			end,
		},
		{
			name = "secret gate value -> UNKNOWN",
			fn = function()
				local S, ctl = loadService()
				hostile(ctl)
				ctl.target.canAttack = ctl.SECRET
				ctl.inRange[200] = false
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetState(), "UNKNOWN", "state")
			end,
		},
		{
			name = "API error -> UNKNOWN",
			fn = function()
				local S, ctl = loadService()
				hostile(ctl)
				ctl.apiError = true
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetState(), "UNKNOWN", "state")
			end,
		},
		{
			name = "event fires only on change",
			fn = function()
				local S, ctl = loadService()
				S:Acquire("a")
				hostile(ctl)
				ctl.inRange[200] = false
				S:Tick()
				S:Tick()
				T.eq(countChanges(ctl), 1, "TargetRangeChanged count")
				T.eq(ctl.triggers[1].args[1], "OUT_OF_RANGE", "payload")
			end,
		},
		{
			name = "target change re-evaluates immediately",
			fn = function()
				local S, ctl = loadService()
				hostile(ctl)
				ctl.inRange[200] = false
				S:Acquire("a")
				T.eq(S:GetState(), "OUT_OF_RANGE", "before")
				clearTarget(ctl)
				S:PLAYER_TARGET_CHANGED()
				T.eq(S:GetState(), "UNKNOWN", "after")
			end,
		},

		-- Resolution
		{
			name = "automatic picks the first known candidate in data order",
			fn = function()
				local S, ctl = loadService({ rangeSpells = { WARRIOR = { 100, 200 } } })
				T.eq(S:GetResolvedSpell(), 100, "both known: first in data order")
				T.eq(S:GetDropdownOptions()[1].label, "Automatic (Charge (8–25 yd))", "automatic label")
				ctl.known[100] = nil
				T.eq(S:GetResolvedSpell(), 200, "only Heroic Throw known")
			end,
		},
		{
			name = "automatic skips a candidate that returns nil on a gated target",
			fn = function()
				local S, ctl = loadService({ rangeSpells = { WARRIOR = { 2480, 7918 } } })
				ctl.spells[2480] = { name = "Shoot Bow", minRange = 0, maxRange = 30 }
				ctl.spells[7918] = { name = "Shoot Gun", minRange = 0, maxRange = 30 }
				ctl.known[2480] = true
				ctl.known[7918] = true
				ctl.inRange[2480] = nil
				ctl.inRange[7918] = false
				hostile(ctl)
				S:Acquire("a")
				T.eq(S:GetState(), "OUT_OF_RANGE", "automatic falls through")
				T.eq(ctl.rangeCalls[#ctl.rangeCalls].identifier, 7918, "last identifier")

				S:SetSavedSpell(2480)
				T.eq(S:GetState(), "UNKNOWN", "saved spell has no fallback")
				T.eq(ctl.rangeCalls[#ctl.rangeCalls].identifier, 2480, "saved identifier")
			end,
		},
		{
			name = "saved unknown spell falls back to automatic without erasing",
			fn = function()
				local S, ctl = loadService({ saved = { WARRIOR = 999 } })
				T.eq(S:GetResolvedSpell(), 200, "resolved")
				T.eq(ctl.db.targetRange_spell.WARRIOR, 999, "saved value kept")
			end,
		},
		{
			name = "saved spells are per class",
			fn = function()
				local S, ctl = loadService({ saved = { MAGE = 300 } })
				T.eq(S:GetSavedSpell(), nil, "no Warrior entry")
				T.eq(S:GetResolvedSpell(), 200, "automatic")
				local before = ctl.db.targetRange_spell
				S:SetSavedSpell(100)
				T.eq(before.WARRIOR, nil, "live table not mutated")
				T.eq(ctl.db.targetRange_spell.MAGE, 300, "Mage kept")
				T.eq(ctl.db.targetRange_spell.WARRIOR, 100, "Warrior saved")
				T.eq(S:GetSavedSpell(), 100, "saved getter")
				T.eq(S:GetResolvedSpell(), 100, "resolved saved")
				S:SetSavedSpell(nil)
				T.eq(ctl.db.targetRange_spell.WARRIOR, nil, "Warrior removed")
				T.eq(ctl.db.targetRange_spell.MAGE, 300, "Mage still kept")
			end,
		},
		{
			name = "setting callback while acquired re-evaluates without a tick",
			fn = function()
				local S, ctl = loadService()
				hostile(ctl)
				ctl.inRange[200] = false
				ctl.inRange[100] = true
				S:Acquire("a")
				T.eq(S:GetState(), "OUT_OF_RANGE", "automatic")
				S:SetSavedSpell(100)
				T.eq(S:GetState(), "IN_RANGE", "saved Charge")
			end,
		},
		{
			name = "Forever rank resolves by name",
			fn = function()
				local S, ctl = loadService({ rangeSpells = { WARRIOR = { 78 } } })
				ctl.spells[78] = { name = "Heroic Strike", minRange = 0, maxRange = 0 }
				ctl.spells[285] = { name = "Heroic Strike", minRange = 0, maxRange = 0 }
				ctl.byName["Heroic Strike"] = 285
				ctl.known[285] = true
				local id, name, identifier = S:GetResolvedSpell()
				T.eq(id, 78, "candidate id")
				T.eq(name, "Heroic Strike", "name")
				T.eq(identifier, "Heroic Strike", "identifier")
				hostile(ctl)
				ctl.inRange["Heroic Strike"] = true
				S:Acquire("a")
				S:Tick()
				local call = ctl.rangeCalls[#ctl.rangeCalls]
				T.eq(call.identifier, "Heroic Strike", "range identifier")
				T.eq(call.unit, "target", "range unit")
				T.eq(S:GetState(), "IN_RANGE", "state")
				local candidates = S:GetCandidates()
				T.eq(#candidates, 1, "candidate count")
				T.eq(candidates[1].id, 78, "candidate id in list")
			end,
		},
		{
			name = "known-check failure means not known, no error",
			fn = function()
				local S, ctl = loadService()
				ctl.knownError = true
				hostile(ctl)
				ctl.inRange[200] = false
				S:Acquire("a")
				S:Tick()
				T.eq(#S:GetCandidates(), 0, "candidates")
				T.eq(S:GetResolvedSpell(), nil, "resolved")
				T.eq(S:GetState(), "UNKNOWN", "state")
			end,
		},
		{
			name = "class without a list -> UNKNOWN and only Automatic in the dropdown",
			fn = function()
				local S, ctl = loadService({ class = "MAGE" })
				hostile(ctl)
				ctl.inRange[200] = false
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetState(), "UNKNOWN", "state")
				local options = S:GetDropdownOptions()
				T.eq(#options, 1, "option count")
				T.eq(options[1].value, "AUTO", "value")
				T.eq(options[1].label, "Automatic (no range spell known)", "label")
			end,
		},
		{
			name = "missing RangeSpells table -> UNKNOWN",
			fn = function()
				local S, ctl = loadService({ rangeSpells = false })
				hostile(ctl)
				S:Acquire("a")
				T.eq(S:GetState(), "UNKNOWN", "state")
				T.eq(#S:GetCandidates(), 0, "candidates")
			end,
		},
		{
			name = "SPELLS_CHANGED re-resolves and re-evaluates",
			fn = function()
				local S, ctl = loadService()
				hostile(ctl)
				ctl.inRange[200] = true
				ctl.inRange[100] = false
				S:Acquire("a")
				T.eq(S:GetState(), "IN_RANGE", "before")
				ctl.known[200] = nil
				S:SPELLS_CHANGED()
				S:SPELLS_CHANGED()
				S:SPELLS_CHANGED()
				T.eq(#ctl.afterQueue, 1, "coalesced")
				ctl.flush()
				T.eq(S:GetResolvedSpell(), 100, "resolved")
				T.eq(S:GetState(), "OUT_OF_RANGE", "after")
				S:SPELLS_CHANGED()
				T.eq(#ctl.afterQueue, 1, "a new pass can queue after the flush")
			end,
		},

		-- Melee companion
		{
			name = "min-range spell with melee companion",
			fn = function()
				local cases = {
					{ spell = false, companion = true, want = "IN_RANGE", label = "too close" },
					{ spell = true, companion = false, want = "IN_RANGE", label = "spell in range" },
					{ spell = false, companion = false, want = "OUT_OF_RANGE", label = "out of range" },
					{ spell = nil, companion = true, want = "IN_RANGE", label = "fallthrough reaches Taunt" },
				}
				for i, case in ipairs(cases) do
					local S, ctl = loadCompanion()
					hostile(ctl)
					ctl.inRange[7918] = case.spell
					ctl.inRange[355] = case.companion
					S:Acquire("a")
					S:Tick()
					T.eq(S:GetState(), case.want, case.label)
					if i == 1 then
						T.truthy(rangeCalled(ctl, 7918), "Shoot Gun checked")
						T.truthy(rangeCalled(ctl, 355), "Taunt checked")
					end
				end
			end,
		},
		{
			name = "no companion keeps a min-range false as OUT_OF_RANGE",
			fn = function()
				local S, ctl = loadService({ rangeSpells = { WARRIOR = { 2480, 7918 } } })
				ctl.spells[2480] = { name = "Shoot Bow", minRange = 8, maxRange = 30 }
				ctl.spells[7918] = { name = "Shoot Gun", minRange = 8, maxRange = 30 }
				ctl.known[2480] = true
				ctl.known[7918] = true
				hostile(ctl)
				ctl.inRange[2480] = false
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetState(), "OUT_OF_RANGE", "state")
			end,
		},
		{
			name = "saved min-range spell also uses the companion",
			fn = function()
				local S, ctl = loadCompanion({ saved = { WARRIOR = 7918 } })
				hostile(ctl)
				ctl.inRange[7918] = false
				ctl.inRange[355] = true
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetState(), "IN_RANGE", "state")
			end,
		},
		{
			name = "saved min-range spell returning nil uses the companion",
			fn = function()
				local S, ctl = loadCompanion({ saved = { WARRIOR = 7918 } })
				hostile(ctl)
				ctl.inRange[7918] = nil
				ctl.inRange[355] = true
				S:Acquire("a")
				T.eq(S:GetState(), "IN_RANGE", "state")
			end,
		},
		{
			name = "min-range spell in range does not query the companion",
			fn = function()
				local S, ctl = loadCompanion()
				hostile(ctl)
				ctl.inRange[7918] = true
				ctl.inRange[355] = false
				S:Acquire("a")
				ctl.rangeCalls = {}
				S:Tick()
				T.eq(S:GetState(), "IN_RANGE", "state")
				T.eq(rangeCalled(ctl, 7918), true, "spell checked")
				T.eq(rangeCalled(ctl, 355), false, "companion not checked")
			end,
		},
		{
			name = "companion must not reach beyond the dead zone",
			fn = function()
				local S, ctl = loadService({ rangeSpells = { WARRIOR = { 355, 100 } }, saved = { WARRIOR = 100 } })
				ctl.spells[355] = { name = "Taunt", minRange = 0, maxRange = 30 }
				ctl.known[355] = true
				hostile(ctl)
				ctl.inRange[100] = false
				ctl.inRange[355] = true
				S:Acquire("a")
				ctl.rangeCalls = {}
				S:Tick()
				T.eq(S:GetState(), "OUT_OF_RANGE", "state")
				T.eq(rangeCalled(ctl, 355), false, "no companion query")
			end,
		},
		{
			name = "no-min-range spell does not query a companion",
			fn = function()
				local S, ctl = loadService()
				hostile(ctl)
				ctl.inRange[200] = false
				ctl.inRange[100] = true
				S:Acquire("a")
				T.eq(S:GetResolvedSpell(), 200, "resolved")
				ctl.rangeCalls = {}
				S:Tick()
				T.eq(#ctl.rangeCalls, 1, "range calls when false")
				ctl.inRange[200] = true
				S:Tick()
				T.eq(#ctl.rangeCalls, 2, "range calls when true")
			end,
		},

		-- Cache
		{
			name = "target change keeps the cache",
			fn = function()
				local S, ctl = loadService()
				hostile(ctl)
				ctl.inRange[200] = false
				S:Acquire("a")
				T.eq(S:GetState(), "OUT_OF_RANGE", "before")
				ctl.infoCalls = {}
				ctl.knownCalls = {}
				ctl.inRange[200] = true
				ctl.frame.onEvent(ctl.frame, "PLAYER_TARGET_CHANGED")
				ctl.frame.onEvent(ctl.frame, "PLAYER_TARGET_CHANGED")
				T.eq(sumCalls(ctl.infoCalls), 0, "info calls")
				T.eq(sumCalls(ctl.knownCalls), 0, "known calls")
				T.eq(S:GetState(), "IN_RANGE", "evaluated")
			end,
		},
		{
			name = "equipment change clears the cache",
			fn = function()
				local S, ctl = loadService()
				hostile(ctl)
				ctl.inRange[200] = false
				S:Acquire("a")
				T.eq(ctl.frame.events.PLAYER_EQUIPMENT_CHANGED, true, "event registered")
				ctl.infoCalls = {}
				ctl.knownCalls = {}
				ctl.frame.onEvent(ctl.frame, "PLAYER_EQUIPMENT_CHANGED")
				ctl.frame.onEvent(ctl.frame, "PLAYER_EQUIPMENT_CHANGED")
				T.eq(#ctl.afterQueue, 1, "coalesced")
				ctl.flush()
				T.truthy(sumCalls(ctl.infoCalls) > 0, "info calls")
				T.truthy(sumCalls(ctl.knownCalls) > 0, "known calls")
				T.eq(S:GetState(), "OUT_OF_RANGE", "state")
			end,
		},

		-- Active spell
		{
			name = "active spell is the candidate that answered",
			fn = function()
				local S, ctl = loadCompanion()
				hostile(ctl)
				T.eq(S:GetActiveSpell(), nil, "nil before acquire")
				ctl.inRange[7918] = true
				S:Acquire("a")
				local id, name = S:GetActiveSpell()
				T.eq(id, 7918, "primary id")
				T.eq(name, "Shoot Gun", "primary name")

				ctl.inRange[7918] = false
				ctl.inRange[355] = true
				S:Tick()
				id, name = S:GetActiveSpell()
				T.eq(id, 355, "companion id")
				T.eq(name, "Taunt", "companion name")

				S:Release("a")
				T.eq(S:GetActiveSpell(), nil, "nil after last release")

				local S2, ctl2 = loadCompanion()
				hostile(ctl2)
				ctl2.inRange[7918] = nil
				ctl2.inRange[355] = true
				S2:Acquire("a")
				T.eq(S2:GetActiveSpell(), 355, "companion id when the spell is nil")
			end,
		},
		{
			name = "active spell clears when no candidate answers",
			fn = function()
				local S, ctl = loadCompanion()
				hostile(ctl)
				ctl.inRange[7918] = true
				S:Acquire("a")
				T.eq(S:GetActiveSpell(), 7918, "answered")
				ctl.inRange[7918] = nil
				ctl.inRange[355] = nil
				ctl.frame.onEvent(ctl.frame, "PLAYER_TARGET_CHANGED")
				T.eq(S:GetState(), "UNKNOWN", "state")
				T.eq(S:GetActiveSpell(), nil, "no stale spell")
			end,
		},
		{
			name = "active spell follows the automatic fallthrough",
			fn = function()
				local S, ctl = loadService({ rangeSpells = { WARRIOR = { 2480, 7918 } } })
				ctl.spells[2480] = { name = "Shoot Bow", minRange = 8, maxRange = 30 }
				ctl.spells[7918] = { name = "Shoot Gun", minRange = 8, maxRange = 30 }
				ctl.known[2480] = true
				ctl.known[7918] = true
				hostile(ctl)
				ctl.inRange[2480] = nil
				ctl.inRange[7918] = false
				S:Acquire("a")
				T.eq(S:GetResolvedSpell(), 2480, "resolved")
				local id, name = S:GetActiveSpell()
				T.eq(id, 7918, "fallthrough id")
				T.eq(name, "Shoot Gun", "fallthrough name")
				T.eq(S:GetState(), "OUT_OF_RANGE", "state")
			end,
		},

		-- Dropdown
		{
			name = "dropdown default is AUTO",
			fn = function()
				local S = loadService()
				T.eq(S:GetDropdownValue(), "AUTO", "value")
			end,
		},
		{
			name = "SetDropdownValue writes nil for AUTO and the number otherwise",
			fn = function()
				local S, ctl = loadService()
				S:SetDropdownValue("200")
				T.eq(ctl.db.targetRange_spell.WARRIOR, 200, "saved number")
				T.eq(S:GetDropdownValue(), "200", "value")
				S:SetDropdownValue("AUTO")
				T.eq(ctl.db.targetRange_spell.WARRIOR, nil, "cleared")
				T.eq(S:GetDropdownValue(), "AUTO", "value after clear")
			end,
		},
		{
			name = "dropdown labels show range bands",
			fn = function()
				local S, ctl = loadService({ rangeSpells = { WARRIOR = { 100, 200, 300 } } })
				ctl.spells[300] = { name = "Slam", minRange = 0, maxRange = 0 }
				ctl.known[300] = true
				local options = S:GetDropdownOptions()
				T.eq(#options, 4, "option count")
				T.eq(options[1].value, "AUTO", "auto value")
				T.eq(options[2].value, "100", "charge value")
				T.eq(options[2].label, "Charge (8–25 yd)", "charge label")
				T.eq(options[3].value, "200", "throw value")
				T.eq(options[3].label, "Heroic Throw (30 yd)", "throw label")
				T.eq(options[4].label, "Slam (melee)", "melee label")
			end,
		},
		{
			name = "Automatic label names the spell Automatic resolves, ignoring the saved spell",
			fn = function()
				local S = loadService()
				T.eq(S:GetDropdownOptions()[1].label, "Automatic (Heroic Throw (30 yd))", "default")
				local S2 = loadService({ saved = { WARRIOR = 100 } })
				T.eq(S2:GetDropdownOptions()[1].label, "Automatic (Heroic Throw (30 yd))", "saved ignored")
				local S3, ctl3 = loadService({ rangeSpells = { WARRIOR = { 100 } } })
				T.eq(S3:GetDropdownOptions()[1].label, "Automatic (Charge (8–25 yd))", "min range fallback")
				ctl3.known[100] = false
				T.eq(S3:GetDropdownOptions()[1].label, "Automatic (no range spell known)", "none known")
			end,
		},
		{
			name = "unavailable saved spell is appended to the options",
			fn = function()
				local S, ctl = loadService({ saved = { WARRIOR = 999 } })
				ctl.spells[999] = { name = "Old Spell", minRange = 0, maxRange = 30 }
				local options = S:GetDropdownOptions()
				local last = options[#options]
				T.eq(#options, 4, "option count")
				T.eq(last.value, "999", "value")
				T.eq(last.label, "Old Spell (unavailable — using Automatic)", "label")
				T.eq(S:GetDropdownValue(), "999", "dropdown value")
			end,
		},
		{
			name = "labels come from localization when present",
			fn = function()
				local S, _, addon = loadService()
				addon.L["Range Spell Automatic Resolved"] = "Auto [%s]"
				addon.L["Range Spell Label"] = "%s [%d]"
				addon.L["Range Spell Label MinMax"] = "%s [%d-%d]"
				local options = S:GetDropdownOptions()
				T.eq(options[1].label, "Auto [Heroic Throw [30]]", "automatic")
				T.eq(options[2].label, "Heroic Throw [30]", "max only")
				T.eq(options[3].label, "Charge [8-25]", "min-max")
			end,
		},
		-- Kind-aware API
		{
			name = "friendly saved choice is per class and independent",
			fn = function()
				local S, ctl = loadFriendly()
				S:SetSavedSpell(17, "FRIENDLY")
				T.eq(ctl.db.targetRange_friendlySpell.PRIEST, 17, "friendly saved")
				T.eq(ctl.db.targetRange_spell.PRIEST, nil, "hostile untouched")
				T.eq(S:GetSavedSpell("FRIENDLY"), 17, "friendly getter")
			end,
		},
		{
			name = "friendly dropdown",
			fn = function()
				local S = loadFriendly()
				local options = S:GetDropdownOptions("FRIENDLY")
				T.eq(options[1].label, "Automatic (Flash Heal (40 yd))", "automatic label")
				T.eq(#options, 3, "option count")
				S:SetDropdownValue("17", "FRIENDLY")
				T.eq(S:GetSavedSpell("FRIENDLY"), 17, "saved")
				T.eq(S:GetDropdownValue("FRIENDLY"), "17", "dropdown value")
				local S2 = loadFriendly({ friendlySpells = {} })
				local none = S2:GetDropdownOptions("FRIENDLY")
				T.eq(#none, 1, "none option count")
				T.eq(none[1].label, "Automatic (no friendly spell known)", "none label")
			end,
		},
		{
			name = "GetResolvedSpell friendly",
			fn = function()
				local S = loadFriendly()
				local id, name, identifier = S:GetResolvedSpell("FRIENDLY")
				T.eq(id, 2061, "id")
				T.eq(name, "Flash Heal", "name")
				T.eq(identifier, 2061, "identifier")
			end,
		},
		{
			name = "default kind matches hostile",
			fn = function()
				local S = loadFriendly()
				sameIds(S:GetCandidates(), S:GetCandidates("HOSTILE"), "candidates")
				local a = { S:GetResolvedSpell() }
				local b = { S:GetResolvedSpell("HOSTILE") }
				T.eq(a[1], b[1], "resolved id")
				T.eq(a[2], b[2], "resolved name")
				T.eq(a[3], b[3], "resolved identifier")
				T.eq(S:GetDropdownValue(), S:GetDropdownValue("HOSTILE"), "dropdown value")
			end,
		},
		{
			name = "unknown kind",
			fn = function()
				local S, ctl = loadFriendly({ saved = { PRIEST = 589 }, savedFriendly = { PRIEST = 17 } })
				T.eq(#S:GetCandidates("BOGUS"), 0, "candidates")
				T.eq(S:GetResolvedSpell("BOGUS"), nil, "resolved")
				T.eq(#S:GetDropdownOptions("BOGUS"), 0, "options")
				T.eq(S:GetDropdownValue("BOGUS"), nil, "dropdown value")
				S:SetSavedSpell(1, "BOGUS")
				S:SetDropdownValue("1", "BOGUS")
				T.eq(countKeys(ctl.db.targetRange_spell), 1, "hostile key count")
				T.eq(ctl.db.targetRange_spell.PRIEST, 589, "hostile value")
				T.eq(countKeys(ctl.db.targetRange_friendlySpell), 1, "friendly key count")
				T.eq(ctl.db.targetRange_friendlySpell.PRIEST, 17, "friendly value")
			end,
		},

		-- Friendly targets
		{
			name = "opt-in off: friendly target is UNKNOWN with zero range calls",
			fn = function()
				local S, ctl = loadFriendly({ friendlyEnabled = false })
				friendly(ctl)
				ctl.inRange[2061] = false
				S:Acquire("a")
				ctl.infoCalls = {}
				ctl.knownCalls = {}
				S:Tick()
				T.eq(S:GetState(), "UNKNOWN", "state")
				T.eq(S:GetTargetKind(), "FRIENDLY", "kind")
				T.eq(#ctl.rangeCalls, 0, "range calls")
				for _, id in ipairs({ 2061, 17 }) do
					T.eq(ctl.infoCalls[id], nil, "no info call " .. id)
					T.eq(ctl.knownCalls[id], nil, "no known call " .. id)
				end
			end,
		},
		{
			name = "non-assistable with opt-in on is UNKNOWN",
			fn = function()
				local S, ctl = loadFriendly()
				friendly(ctl)
				ctl.target.canAssist = false
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetTargetKind(), nil, "kind")
				T.eq(S:GetState(), "UNKNOWN", "state")
				T.eq(#ctl.rangeCalls, 0, "range calls")
			end,
		},
		{
			name = "friendly in/out",
			fn = function()
				local S, ctl = loadFriendly()
				friendly(ctl)
				ctl.inRange[2061] = true
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetState(), "IN_RANGE", "in")
				T.eq(S:GetTargetKind(), "FRIENDLY", "kind")
				ctl.inRange[2061] = false
				S:Tick()
				T.eq(S:GetState(), "OUT_OF_RANGE", "out")
				T.truthy(#ctl.rangeCalls > 0, "range calls made")
				for i, call in ipairs(ctl.rangeCalls) do
					T.eq(call.identifier, 2061, "identifier " .. i)
					T.truthy(call.identifier ~= 589, "no hostile spell " .. i)
				end
			end,
		},
		{
			name = "friendly nil",
			fn = function()
				local S, ctl = loadFriendly()
				friendly(ctl)
				ctl.inRange[2061] = nil
				ctl.inRange[17] = nil
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetState(), "UNKNOWN", "state")
			end,
		},
		{
			name = "friendly automatic fallthrough",
			fn = function()
				local S, ctl = loadFriendly()
				friendly(ctl)
				ctl.inRange[2061] = nil
				ctl.inRange[17] = false
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetState(), "OUT_OF_RANGE", "state")
				T.eq(ctl.rangeCalls[#ctl.rangeCalls].identifier, 17, "last identifier")
			end,
		},
		{
			name = "self-target",
			fn = function()
				local S, ctl = loadFriendly()
				friendly(ctl)
				ctl.target.isSelf = true
				ctl.inRange[2061] = true
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetTargetKind(), nil, "kind")
				T.eq(S:GetState(), "UNKNOWN", "state")
				T.eq(#ctl.rangeCalls, 0, "range calls")
			end,
		},
		{
			name = "secret UnitIsUnit falls back to not-self",
			fn = function()
				local S, ctl = loadFriendly()
				friendly(ctl)
				ctl.target.isSelf = ctl.SECRET
				ctl.inRange[2061] = false
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetTargetKind(), "FRIENDLY", "kind")
				T.eq(S:GetState(), "OUT_OF_RANGE", "state")
			end,
		},
		{
			name = "dead friendly",
			fn = function()
				local S, ctl = loadFriendly()
				friendly(ctl)
				ctl.target.dead = true
				ctl.inRange[2061] = false
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetTargetKind(), nil, "kind")
				T.eq(S:GetState(), "UNKNOWN", "state")
			end,
		},
		{
			name = "secret UnitCanAssist",
			fn = function()
				local S, ctl = loadFriendly()
				friendly(ctl)
				ctl.target.canAssist = ctl.SECRET
				ctl.inRange[2061] = false
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetTargetKind(), nil, "kind")
				T.eq(S:GetState(), "UNKNOWN", "state")
			end,
		},
		{
			name = "secret UnitCanAttack with assistable target",
			fn = function()
				local S, ctl = loadFriendly()
				friendly(ctl)
				ctl.target.canAttack = ctl.SECRET
				ctl.target.canAssist = true
				ctl.inRange[2061] = false
				ctl.inRange[589] = false
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetTargetKind(), nil, "kind")
				T.eq(S:GetState(), "UNKNOWN", "state")
				T.eq(#ctl.rangeCalls, 0, "range calls")
			end,
		},
		{
			name = "attackable and assistable is HOSTILE",
			fn = function()
				local S, ctl = loadFriendly()
				friendly(ctl)
				ctl.target.canAttack = true
				ctl.target.canAssist = true
				ctl.inRange[589] = false
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetTargetKind(), "HOSTILE", "kind")
				T.eq(ctl.rangeCalls[#ctl.rangeCalls].identifier, 589, "last identifier")
			end,
		},
		{
			name = "kind re-evaluated each tick",
			fn = function()
				local S, ctl = loadFriendly()
				friendly(ctl)
				ctl.inRange[2061] = true
				ctl.inRange[589] = false
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetTargetKind(), "FRIENDLY", "friendly kind")
				T.eq(ctl.rangeCalls[#ctl.rangeCalls].identifier, 2061, "friendly identifier")
				ctl.target.canAttack = true
				S:Tick()
				T.eq(S:GetTargetKind(), "HOSTILE", "hostile kind")
				T.eq(ctl.rangeCalls[#ctl.rangeCalls].identifier, 589, "hostile identifier")
			end,
		},
		{
			name = "class without friendly list",
			fn = function()
				local S, ctl = loadFriendly({ friendlySpells = {} })
				friendly(ctl)
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetTargetKind(), "FRIENDLY", "kind")
				T.eq(S:GetState(), "UNKNOWN", "state")
				T.eq(#ctl.rangeCalls, 0, "range calls")
			end,
		},
		{
			name = "opt-in callback",
			fn = function()
				local S, ctl = loadFriendly({ friendlyEnabled = false })
				friendly(ctl)
				ctl.inRange[2061] = false
				S:Acquire("a")
				T.eq(S:GetState(), "UNKNOWN", "before")
				ctl.db.targetRange_friendlyEnabled = true
				ctl.settingCallbacks.targetRange_friendlyEnabled()
				T.eq(S:GetState(), "OUT_OF_RANGE", "after")
			end,
		},
		{
			name = "friendly spell callback",
			fn = function()
				local S, ctl = loadFriendly()
				friendly(ctl)
				ctl.inRange[2061] = true
				ctl.inRange[17] = false
				S:Acquire("a")
				T.eq(S:GetState(), "IN_RANGE", "before")
				S:SetSavedSpell(17, "FRIENDLY")
				T.eq(S:GetState(), "OUT_OF_RANGE", "after")
			end,
		},
		{
			name = "hostile spell callback clears the hostile cache",
			fn = function()
				local S, ctl = loadFriendly()
				hostile(ctl)
				ctl.inRange[589] = true
				ctl.inRange[8092] = true
				S:Acquire("a")
				S:Tick()
				T.eq(ctl.rangeCalls[#ctl.rangeCalls].identifier, 589, "before identifier")
				ctl.db.targetRange_spell.PRIEST = 8092
				ctl.settingCallbacks.targetRange_spell()
				S:Tick()
				T.eq(ctl.rangeCalls[#ctl.rangeCalls].identifier, 8092, "last identifier")
			end,
		},
		{
			name = "SPELLS_CHANGED clears the friendly cache",
			fn = function()
				local S, ctl = loadFriendly()
				friendly(ctl)
				ctl.inRange[2061] = true
				ctl.inRange[17] = true
				S:Acquire("a")
				S:Tick()
				T.eq(ctl.rangeCalls[#ctl.rangeCalls].identifier, 2061, "before")
				ctl.known[2061] = nil
				ctl.frame.onEvent(ctl.frame, "SPELLS_CHANGED")
				ctl.flush()
				S:Tick()
				T.eq(ctl.rangeCalls[#ctl.rangeCalls].identifier, 17, "after")
			end,
		},
		{
			name = "kind nil after last release",
			fn = function()
				local S, ctl = loadFriendly()
				friendly(ctl)
				ctl.inRange[2061] = true
				S:Acquire("a")
				S:Tick()
				T.eq(S:GetTargetKind(), "FRIENDLY", "while acquired")
				S:Release("a")
				T.eq(S:GetTargetKind(), nil, "after release")
			end,
		},
	}
end
