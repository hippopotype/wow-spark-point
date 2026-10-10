-- Core/API.lua wrappers over modern C_ namespaces.

return function(T)
	local function loadAPI(stubs)
		local addon = {
			Has = function()
				return true
			end,
		}
		T.withGlobals(stubs or {}, function()
			T.loadAddonFile("Core/API.lua", addon)
		end)
		return addon.API
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
	}
end
