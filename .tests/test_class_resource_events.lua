-- Modules/ClassResource.lua: target event registration and forwarding.

return function(T)
	local function load(hasCapability)
		local rec = { events = {}, unitEvents = {}, handler = nil, toggle = nil }
		local function newStub()
			return setmetatable({}, {
				__index = function()
					return function()
						return newStub()
					end
				end,
			})
		end
		_G.CreateFrame = function()
			local frame = newStub()
			frame.RegisterEvent = function(_, event)
				rec.events[event] = true
			end
			frame.RegisterUnitEvent = function(_, event)
				rec.unitEvents[event] = true
			end
			frame.UnregisterAllEvents = function() end
			frame.SetScript = function(_, name, fn)
				if name == "OnEvent" then
					rec.handler = fn
				end
			end
			return frame
		end

		rec.resource = nil
		rec.system = nil
		rec.has = hasCapability
		local addon = {
			L = {},
			Modules = {},
			CallbackRegistry = {
				Register = function() end,
				RegisterSettingCallback = function() end,
			},
			ControlCenter = {
				AddModule = function(_, def)
					rec.toggle = def.toggleFunc
				end,
			},
			AnchorFrame = {
				GetFrame = function()
					return nil
				end,
				Hide = function() end,
				Show = function() end,
			},
			ResourceModel = {
				SimpleSupport = { NONE = "NONE" },
				GetCurrentClassResource = function()
					return rec.resource
				end,
			},
			GetDBValue = function() end,
			Visibility = {
				ShouldShow = function()
					return false
				end,
			},
			ClassResourceSystems = {
				Create = function()
					return rec.system
				end,
			},
			Has = function(name)
				return name == "comboPointsOnTarget" and rec.has or false
			end,
		}
		T.loadAddonFile("Modules/ClassResource.lua", addon)
		return rec
	end

	local function registered(rec, event)
		return rec.events[event] or rec.unitEvents[event] or false
	end

	return {
		{
			name = "target events only with the capability",
			fn = function()
				local on = load(true)
				on.toggle(true)
				T.truthy(registered(on, "PLAYER_TARGET_CHANGED"), "PLAYER_TARGET_CHANGED on")
				T.truthy(registered(on, "COMBO_TARGET_CHANGED"), "COMBO_TARGET_CHANGED on")

				local off = load(false)
				off.toggle(true)
				T.eq(registered(off, "PLAYER_TARGET_CHANGED"), false, "PLAYER_TARGET_CHANGED off")
				T.eq(registered(off, "COMBO_TARGET_CHANGED"), false, "COMBO_TARGET_CHANGED off")
				for _, event in ipairs({
					"PLAYER_ENTERING_WORLD",
					"PLAYER_SPECIALIZATION_CHANGED",
					"UPDATE_SHAPESHIFT_FORM",
					"RUNE_POWER_UPDATE",
					"UNIT_DISPLAYPOWER",
					"UNIT_POWER_UPDATE",
					"UNIT_POWER_FREQUENT",
					"UNIT_MAXPOWER",
					"UNIT_AURA",
					"UNIT_POWER_POINT_CHARGE",
				}) do
					T.truthy(registered(off, event), event .. " still registered")
				end
			end,
		},
		{
			name = "target events forwarded",
			fn = function()
				local rec = load(true)
				local seen = {}
				rec.resource = { systemID = "X" }
				rec.system = {
					WantsEvent = function()
						return true
					end,
					HandleTargetEvent = function(_, event)
						seen[#seen + 1] = event
					end,
				}
				rec.toggle(true)
				rec.handler(nil, "PLAYER_TARGET_CHANGED")
				rec.handler(nil, "COMBO_TARGET_CHANGED")
				T.eq(#seen, 2, "calls")
				T.eq(seen[1], "PLAYER_TARGET_CHANGED", "first")
				T.eq(seen[2], "COMBO_TARGET_CHANGED", "second")
			end,
		},
		{
			name = "missing or unwanted is safe",
			fn = function()
				local rec = load(true)
				local calls = 0
				rec.resource = { systemID = "X" }
				rec.system = {
					WantsEvent = function()
						return false
					end,
					HandleTargetEvent = function()
						calls = calls + 1
					end,
				}
				rec.toggle(true)
				rec.handler(nil, "PLAYER_TARGET_CHANGED")
				T.eq(calls, 0, "unwanted not called")

				local rec2 = load(true)
				rec2.resource = { systemID = "X" }
				rec2.system = {
					WantsEvent = function()
						return true
					end,
				}
				rec2.toggle(true)
				rec2.handler(nil, "COMBO_TARGET_CHANGED")
			end,
		},
	}
end
