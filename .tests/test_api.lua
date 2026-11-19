-- Core/API.lua wrappers over modern C_ namespaces.

return function(T)
	local function loadAPI(stubs, has, withUtil)
		if has == nil then
			has = true
		end
		local addon = {
			Has = function()
				return has
			end,
		}
		T.withGlobals(stubs or {}, function()
			if withUtil then
				T.loadAddonFile("Core/Util.lua", addon)
			end
			T.loadAddonFile("Core/API.lua", addon)
		end)
		return addon.API
	end

	-- Runs API.GetComboPoints with the given WoW stubs; records which stubs were called.
	local function readCombo(opts, has, maxFallback)
		local API = loadAPI(nil, has, true)
		local calls = { combo = 0, power = 0, comboArgs = nil }
		local function value(v)
			if type(v) == "function" then
				return v()
			end
			return v
		end
		local cur, max
		T.withGlobals({
			Enum = { PowerType = { ComboPoints = 4 } },
			issecretvalue = opts.issecretvalue or T.NIL,
			GetComboPoints = function(...)
				calls.combo = calls.combo + 1
				calls.comboArgs = { ... }
				return value(opts.current)
			end,
			UnitPower = function()
				calls.power = calls.power + 1
				return value(opts.current)
			end,
			UnitPowerMax = function()
				return value(opts.max)
			end,
		}, function()
			cur, max = API.GetComboPoints(maxFallback)
		end)
		return cur, max, calls
	end

	-- A value that behaves like a secret: tostring() on it errors.
	local SECRET = setmetatable({}, {
		__tostring = function()
			error("secret")
		end,
	})

	return {
		{
			name = "FindSpellOverride uses C_SpellBook",
			fn = function()
				local API = loadAPI()
				_G.C_SpellBook = {
					FindSpellOverrideByID = function(id)
						return id + 1
					end,
				}
				T.eq(API.FindSpellOverride(100), 101)
				_G.C_SpellBook = nil
			end,
		},
		{
			name = "FindBaseSpell uses C_SpellBook",
			fn = function()
				local API = loadAPI()
				_G.C_SpellBook = {
					FindBaseSpellByID = function(id)
						return id - 1
					end,
				}
				T.eq(API.FindBaseSpell(100), 99)
				_G.C_SpellBook = nil
			end,
		},
		{
			name = "spell lookups return nil when the API errors or is missing",
			fn = function()
				local API = loadAPI()
				_G.C_SpellBook = {
					FindSpellOverrideByID = function()
						error("boom")
					end,
				}
				T.eq(API.FindSpellOverride(100), nil, "erroring API")
				_G.C_SpellBook = nil
				T.eq(API.FindBaseSpell(100), nil, "missing API")
			end,
		},
		{
			name = "action cooldown reads the C_ActionBar struct",
			fn = function()
				local API = loadAPI()
				_G.C_ActionBar = {
					GetActionCooldown = function()
						return { startTime = 10, duration = 1.5, modRate = 1, isEnabled = true }
					end,
				}
				local info = API.GetActionCooldownInfo(1)
				T.eq(info.startTime, 10, "startTime")
				T.eq(info.duration, 1.5, "duration")
				T.eq(info.isActive, true, "isActive")
				_G.C_ActionBar = nil
			end,
		},
		{
			name = "action charges read the C_ActionBar struct",
			fn = function()
				local API = loadAPI()
				_G.C_ActionBar = {
					GetActionCharges = function()
						return { currentCharges = 1, maxCharges = 2, cooldownStartTime = 5, cooldownDuration = 8, chargeModRate = 1 }
					end,
				}
				local info = API.GetActionChargeCooldownInfo(1)
				T.eq(info.currentCharges, 1, "currentCharges")
				T.eq(info.maxCharges, 2, "maxCharges")
				T.eq(info.isActive, true, "isActive")
				_G.C_ActionBar = nil
			end,
		},
		{
			name = "secret cooldown fields degrade to zero without error",
			fn = function()
				local API = loadAPI()
				_G.C_ActionBar = {
					GetActionCooldown = function()
						return { startTime = SECRET, duration = SECRET, modRate = SECRET }
					end,
				}
				local info = API.GetActionCooldownInfo(1)
				T.eq(info.startTime, 0, "startTime")
				T.eq(info.isActive, false, "isActive")
				_G.C_ActionBar = nil
			end,
		},
		{
			name = "action cooldown returns nil without slot or API",
			fn = function()
				local API = loadAPI()
				_G.C_ActionBar = nil
				T.eq(API.GetActionCooldownInfo(1), nil, "no API")
				T.eq(API.GetActionCooldownInfo(nil), nil, "no slot")
			end,
		},
		{
			name = "combo: reads target-bound points",
			fn = function()
				local cur, max, calls = readCombo({ current = 3, max = 5 }, true, 5)
				T.eq(cur, 3, "cur")
				T.eq(max, 5, "max")
				T.eq(calls.comboArgs[1], "player", "arg1")
				T.eq(calls.comboArgs[2], "target", "arg2")
				T.eq(calls.power, 0, "UnitPower not called")
			end,
		},
		{
			name = "combo: secret current is nil",
			fn = function()
				local cur, max = readCombo({
					current = 3,
					max = 5,
					issecretvalue = function(v)
						return v == 3
					end,
				}, true, 5)
				T.eq(cur, nil, "cur")
				T.eq(max, 5, "max")
			end,
		},
		{
			name = "combo: pcall failure is nil",
			fn = function()
				local cur, max = readCombo({
					current = function()
						error("boom")
					end,
					max = 5,
				}, true, 5)
				T.eq(cur, nil, "cur")
				T.eq(max, 5, "max")
			end,
		},
		{
			name = "combo: secret max falls back",
			fn = function()
				local cur, max = readCombo({
					current = 3,
					max = 99,
					issecretvalue = function(v)
						return v == 99
					end,
				}, true, 5)
				T.eq(cur, 3, "cur")
				T.eq(max, 5, "max")
			end,
		},
		{
			name = "combo: failing max falls back",
			fn = function()
				local cur, max = readCombo({
					current = 3,
					max = function()
						error("boom")
					end,
				}, true, 5)
				T.eq(cur, 3, "cur")
				T.eq(max, 5, "max")
			end,
		},
		{
			name = "combo: unreadable max without fallback is nil",
			fn = function()
				local cur, max = readCombo({
					current = 3,
					max = function()
						error("boom")
					end,
				}, true, nil)
				T.eq(cur, 3, "cur")
				T.eq(max, nil, "max")
			end,
		},
		{
			name = "combo: clamps to [0, max]",
			fn = function()
				local cur, max = readCombo({ current = 7, max = 5 }, true, 5)
				T.eq(cur, 5, "high cur")
				T.eq(max, 5, "high max")
				cur, max = readCombo({ current = -1, max = 5 }, true, 5)
				T.eq(cur, 0, "low cur")
				T.eq(max, 5, "low max")
			end,
		},
		{
			name = "combo: retail returns raw UnitPower values",
			fn = function()
				local cur, max, calls = readCombo({ current = 2, max = 6 }, false, 5)
				T.eq(cur, 2, "cur")
				T.eq(max, 6, "max")
				T.eq(calls.combo, 0, "GetComboPoints not called")
				cur, max = readCombo({ current = 9, max = 6 }, false, 5)
				T.eq(cur, 9, "unclamped cur")
				T.eq(max, 6, "max")
			end,
		},
	}
end
