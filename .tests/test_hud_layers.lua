-- Core/HUDLayers.lua: global HUD scale applied to every layer root.

return function(T)
	local LAYERS = {
		"CAST_SHADOW",
		"DECORATIVE_RING",
		"CAST_FEEDBACK",
		"BAR_SLOTS",
		"CAST_BASE",
		"CLASS_RESOURCE",
		"COOLDOWN_MANAGER",
		"ASSISTED_HIGHLIGHT",
	}

	local function newFrame()
		local frame = {}
		function frame:SetPoint() end
		function frame:SetFrameLevel() end
		function frame:SetFrameStrata() end
		function frame:SetScale(scale)
			self.scale = scale
		end
		return frame
	end

	-- Loads HUDLayers with stubs; `anchorReady` false simulates the startup moment before
	-- the anchor (and therefore any layer root) exists.
	-- Returns `created`: every root frame in creation order. Assertions read these captured
	-- frames directly, because GetLayerFrame itself re-applies the scale and would mask a
	-- broken hud_scale callback.
	local function loadLayers(db, anchorReady)
		local events, settings, created = {}, {}, {}
		local state = { anchor = anchorReady ~= false and newFrame() or nil }
		local addon = {
			GetDBValue = function(key)
				return db[key]
			end,
			AnchorFrame = {
				GetFrame = function()
					return state.anchor
				end,
			},
			CallbackRegistry = {
				Register = function(_, event, fn)
					events[event] = fn
				end,
				RegisterSettingCallback = function(_, key, fn)
					settings[key] = fn
				end,
				Trigger = function() end,
			},
		}
		_G.UIParent = {}
		_G.CreateFrame = function()
			local frame = newFrame()
			created[#created + 1] = frame
			return frame
		end
		T.loadAddonFile("Core/HUDLayers.lua", addon)
		return addon.HUDLayers, events, settings, state, created
	end

	local function assertAllRoots(created, expected)
		T.eq(#created, #LAYERS, "root count")
		for index, frame in ipairs(created) do
			T.eq(frame.scale, expected, "scale of " .. LAYERS[index])
		end
	end

	return {
		{
			name = "roots receive the stored scale when created",
			fn = function()
				local HUDLayers, _, _, _, created = loadLayers({ hud_scale = 1.5 })
				HUDLayers:GetLayerFrame("CAST_BASE")
				assertAllRoots(created, 1.5)
				T.eq(HUDLayers:GetScale(), 1.5, "GetScale")
			end,
		},
		{
			name = "hud_scale callback re-applies the new value live",
			fn = function()
				local db = { hud_scale = 1 }
				local HUDLayers, _, settings, _, created = loadLayers(db)
				HUDLayers:GetLayerFrame("CAST_BASE")
				assertAllRoots(created, 1)
				db.hud_scale = 0.75
				settings.hud_scale()
				assertAllRoots(created, 0.75)
				T.eq(HUDLayers:GetScale(), 0.75, "GetScale")
			end,
		},
		{
			name = "scale is clamped to 50%-200% and garbage falls back to 100%",
			fn = function()
				local cases = {
					{ 0.3, 0.5 },
					{ 5, 2 },
					{ nil, 1 },
					{ "abc", 1 },
				}
				for _, case in ipairs(cases) do
					local HUDLayers, _, _, _, created = loadLayers({ hud_scale = case[1] })
					HUDLayers:GetLayerFrame("CAST_BASE")
					T.eq(HUDLayers:GetScale(), case[2], "GetScale for " .. tostring(case[1]))
					assertAllRoots(created, case[2])
				end
			end,
		},
		{
			name = "callback before roots exist is a no-op; roots created later get the stored scale",
			fn = function()
				local _, events, settings, state, created = loadLayers({ hud_scale = 1.25 }, false)
				settings.hud_scale()
				T.eq(#created, 0, "no roots before the anchor exists")
				state.anchor = newFrame()
				events.ADDON_LOADED()
				assertAllRoots(created, 1.25)
			end,
		},
	}
end
