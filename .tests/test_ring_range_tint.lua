-- Modules/DecorativeRing.lua: out-of-range tint and range service ownership.

return function(T)
	local function newTexture()
		local tex = { last = nil, colorCalls = 0 }
		for _, name in ipairs({ "SetPoint", "SetBlendMode", "SetSize", "SetRotation", "Show" }) do
			tex[name] = function() end
		end
		tex.SetVertexColor = function(self, r, g, b, a)
			self.last = { r, g, b, a }
			self.colorCalls = self.colorCalls + 1
		end
		return tex
	end

	local function newFrame()
		local frame = { shown = false }
		for _, name in ipairs({ "SetAllPoints", "SetScript" }) do
			frame[name] = function() end
		end
		frame.Show = function(self)
			self.shown = true
		end
		frame.Hide = function(self)
			self.shown = false
		end
		frame.IsShown = function(self)
			return self.shown
		end
		frame.CreateTexture = function(self)
			self.texture = newTexture()
			return self.texture
		end
		return frame
	end

	local NORMAL = { 1, 1, 1, 0.18 }

	local function load(opts)
		opts = opts or {}
		local frames = {}
		_G.CreateFrame = function()
			local frame = newFrame()
			frames[#frames + 1] = frame
			return frame
		end

		local db = {
			ring_texture = "decorative_ring_1",
			ring_width = 126,
			ring_rotate = false,
			ring_useClassColor = false,
			ring_classColorAlpha = 0.6,
			ring_color = { r = NORMAL[1], g = NORMAL[2], b = NORMAL[3], a = NORMAL[4] },
			ring_rangeTintEnabled = false,
			ring_rangeTintColor = { r = 1, g = 0.2, b = 0.2, a = 0.6 },
		}
		local function color(key)
			local c = db[key]
			return c.r, c.g, c.b, c.a
		end

		local eventCallbacks = {}
		local settingLists = {}
		local settingCallbacks = setmetatable({}, {
			__index = function(_, key)
				return function(...)
					for _, fn in ipairs(settingLists[key] or {}) do
						fn(...)
					end
				end
			end,
		})
		local registry = {}
		function registry:Register(event, fn)
			eventCallbacks[event] = eventCallbacks[event] or {}
			table.insert(eventCallbacks[event], fn)
		end
		function registry:RegisterSettingCallback(key, fn)
			settingLists[key] = settingLists[key] or {}
			table.insert(settingLists[key], fn)
		end
		local function fire(event, ...)
			for _, fn in ipairs(eventCallbacks[event] or {}) do
				fn(...)
			end
		end

		local range = { state = "UNKNOWN", calls = {} }
		function range:Acquire(owner)
			table.insert(self.calls, "Acquire:" .. owner)
		end
		function range:Release(owner)
			table.insert(self.calls, "Release:" .. owner)
			if self.state ~= "UNKNOWN" then
				self.state = "UNKNOWN"
				fire("TargetRangeChanged", "UNKNOWN")
			end
		end
		function range:GetState()
			return self.state
		end

		local toggle
		local anchorFrame = newFrame()
		local addon = {
			Modules = {},
			addonFolder = "Interface\\AddOns\\SparkPoint",
			L = {},
			API = {
				GetPlayerClassColor = function()
					return 0.1, 0.2, 0.3, 1
				end,
			},
			AnchorFrame = {
				GetFrame = function()
					return anchorFrame
				end,
				Show = function() end,
				Hide = function() end,
			},
			HUDLayers = {
				Names = { DECORATIVE_RING = "x" },
				GetLayerFrame = function()
					return anchorFrame
				end,
			},
			Visibility = {
				ShouldShow = function()
					return true
				end,
			},
			Util = {
				SetTextureSmooth = function() end,
				InheritLayering = function() end,
			},
			GetDBValue = function(key)
				return db[key]
			end,
			GetDBBool = function(key)
				return db[key] and true or false
			end,
			GetDBColor = color,
			CallbackRegistry = registry,
			ControlCenter = {
				AddModule = function(_, def)
					toggle = def.toggleFunc
				end,
			},
		}
		if not opts.noRange then
			addon.TargetRange = range
		end

		T.loadAddonFile("Modules/DecorativeRing.lua", addon)
		local ring = addon.Modules.RingObj
		return {
			ring = ring,
			db = db,
			range = range,
			toggle = toggle,
			fire = fire,
			settingCallbacks = settingCallbacks,
			frames = frames,
			texture = function()
				return frames[#frames].texture
			end,
		}
	end

	local function eqColor(actual, expected, msg)
		for i = 1, 4 do
			T.eq(actual[i], expected[i], (msg or "color") .. " [" .. i .. "]")
		end
	end

	local function resolve(ctx)
		return { ctx.ring:ResolveColor() }
	end

	return {
		{
			name = "tint off: normal color even when out of range",
			fn = function()
				local ctx = load()
				ctx.range.state = "OUT_OF_RANGE"
				eqColor(resolve(ctx), NORMAL)
			end,
		},
		{
			name = "tint on + OUT_OF_RANGE: tint color with its alpha",
			fn = function()
				local ctx = load()
				ctx.db.ring_rangeTintEnabled = true
				ctx.range.state = "OUT_OF_RANGE"
				eqColor(resolve(ctx), { 1, 0.2, 0.2, 0.6 })
			end,
		},
		{
			name = "tint on + IN_RANGE/UNKNOWN: normal; class color path applies",
			fn = function()
				local ctx = load()
				ctx.db.ring_rangeTintEnabled = true
				for _, state in ipairs({ "IN_RANGE", "UNKNOWN" }) do
					ctx.range.state = state
					eqColor(resolve(ctx), NORMAL, state)
				end
				ctx.db.ring_useClassColor = true
				eqColor(resolve(ctx), { 0.1, 0.2, 0.3, 0.6 }, "class")
			end,
		},
		{
			name = "TargetRangeChanged recolors the texture",
			fn = function()
				local ctx = load()
				ctx.db.ring_rangeTintEnabled = true
				ctx.toggle(true)
				eqColor(ctx.texture().last, NORMAL, "initial")
				ctx.range.state = "OUT_OF_RANGE"
				ctx.fire("TargetRangeChanged", "OUT_OF_RANGE")
				eqColor(ctx.texture().last, { 1, 0.2, 0.2, 0.6 }, "tinted")
			end,
		},
		{
			name = "release while OUT_OF_RANGE recolors to normal",
			fn = function()
				local ctx = load()
				ctx.db.ring_rangeTintEnabled = true
				ctx.toggle(true)
				ctx.range.state = "OUT_OF_RANGE"
				ctx.fire("TargetRangeChanged", "OUT_OF_RANGE")
				ctx.db.ring_rangeTintEnabled = false
				ctx.settingCallbacks.ring_rangeTintEnabled()
				eqColor(ctx.texture().last, NORMAL, "after release")
			end,
		},
		{
			name = "callbacks recolor",
			fn = function()
				local ctx = load()
				ctx.toggle(true)
				ctx.db.ring_rangeTintEnabled = true
				ctx.range.state = "OUT_OF_RANGE"
				ctx.settingCallbacks.ring_rangeTintEnabled()
				eqColor(ctx.texture().last, { 1, 0.2, 0.2, 0.6 }, "enabled cb")
				ctx.db.ring_rangeTintColor = { r = 0, g = 1, b = 0, a = 0.5 }
				ctx.settingCallbacks.ring_rangeTintColor()
				eqColor(ctx.texture().last, { 0, 1, 0, 0.5 }, "color cb")
			end,
		},
		{
			name = "tint toggle recolors once",
			fn = function()
				local ctx = load()
				ctx.toggle(true)
				local before = ctx.texture().colorCalls
				ctx.db.ring_rangeTintEnabled = true
				ctx.settingCallbacks.ring_rangeTintEnabled()
				T.eq(ctx.texture().colorCalls - before, 1, "SetVertexColor calls")
			end,
		},
		{
			name = "toggling the setting acquires and releases",
			fn = function()
				local ctx = load()
				ctx.toggle(true)
				T.eq(#ctx.range.calls, 1, "enable while tint off")
				T.eq(ctx.range.calls[1], "Release:ring", "tint off releases")
				ctx.range.calls = {}
				ctx.db.ring_rangeTintEnabled = true
				ctx.settingCallbacks.ring_rangeTintEnabled()
				T.eq(ctx.range.calls[1], "Acquire:ring", "acquire")
				ctx.db.ring_rangeTintEnabled = false
				ctx.settingCallbacks.ring_rangeTintEnabled()
				T.eq(ctx.range.calls[2], "Release:ring", "release")
			end,
		},
		{
			name = "disabling the module releases the service",
			fn = function()
				local ctx = load()
				ctx.db.ring_rangeTintEnabled = true
				ctx.toggle(true)
				T.eq(ctx.range.calls[#ctx.range.calls], "Acquire:ring", "acquired")
				ctx.toggle(false)
				T.eq(ctx.range.calls[#ctx.range.calls], "Release:ring", "released")
			end,
		},
		{
			name = "tint enabled before the frame exists does not error and acquires on enable",
			fn = function()
				local ctx = load()
				ctx.db.ring_rangeTintEnabled = true
				ctx.settingCallbacks.ring_rangeTintEnabled()
				ctx.settingCallbacks.ring_rangeTintColor()
				T.eq(#ctx.range.calls, 1, "one call before enable")
				T.eq(ctx.range.calls[1], "Release:ring", "not enabled: release")
				ctx.range.state = "OUT_OF_RANGE"
				ctx.toggle(true)
				T.eq(ctx.range.calls[#ctx.range.calls], "Acquire:ring", "acquires on enable")
				eqColor(ctx.texture().last, { 1, 0.2, 0.2, 0.6 }, "tinted on init")
			end,
		},
	}
end
