-- Core/CooldownViewerSkin.lua: when the skin first touches a Blizzard item frame.
--
-- Blizzard's RefreshLayout calls the viewer's RefreshData before RefreshLayout's own
-- post-hooks run. Other skinners (MasqueBlizzBars) take the icon's first mask as the
-- button's IconMask on their first RefreshLayout pass; if we have already swapped in our
-- mask they adopt it and reshape it. So the RefreshData hook must not skin synchronously.

return function(T)
	local function setup()
		local ctl = { timers = {}, masksCreated = 0 }

		_G.hooksecurefunc = function(target, method, hook)
			local original = target[method]
			target[method] = function(...)
				local a, b, c = original(...)
				hook(...)
				return a, b, c
			end
		end
		_G.C_Timer = {
			After = function(_, fn)
				ctl.timers[#ctl.timers + 1] = fn
			end,
		}
		function ctl.runTimers()
			local pending = ctl.timers
			ctl.timers = {}
			for _, fn in ipairs(pending) do
				fn()
			end
		end

		ctl.item = { Icon = {}, Cooldown = {} }
		ctl.children = {}
		ctl.viewer = {
			GetChildren = function()
				return ctl.children[1], ctl.children[2]
			end,
			RefreshData = function() end,
		}
		_G.BuffIconCooldownViewer = ctl.viewer
		_G.ActionButtonSpellAlertManager = { ShowAlert = function() end, HideAlert = function() end }

		local addon = {
			addonFolder = "Interface\\AddOns\\SparkPoint",
			IconMask = {
				-- First thing a skin pass does to a new frame; counting it detects a pass.
				CreateMask = function()
					ctl.masksCreated = ctl.masksCreated + 1
					error("stop: the test only needs to know a skin pass started")
				end,
			},
			IconGlow = {},
			Keybinds = {},
			CallbackRegistry = { Register = function() end },
			GetDBValue = function() end,
			GetDBBool = function() end,
			GetDBColor = function() end,
		}
		T.loadAddonFile("Core/Util.lua", addon)
		T.loadAddonFile("Core/CooldownViewerSkin.lua", addon)
		ctl.skin = addon.CooldownViewerSkin
		ctl.skin:SetModuleEnabled(true)
		ctl.skin:SetCategoryEnabled(2, true)
		return ctl
	end

	return {
		{
			name = "a viewer RefreshData does not skin new frames in the same call",
			fn = function()
				local ctl = setup()
				ctl.children = { ctl.item } -- acquired by RefreshLayout just before RefreshData
				ctl.viewer:RefreshData()
				T.eq(ctl.masksCreated, 0, "skin passes during RefreshData")
			end,
		},
		{
			name = "a viewer RefreshData skins its frames on the next frame",
			fn = function()
				local ctl = setup()
				ctl.children = { ctl.item }
				ctl.viewer:RefreshData()
				ctl.runTimers()
				T.truthy(ctl.masksCreated > 0, "expected a deferred skin pass")
			end,
		},
	}
end
