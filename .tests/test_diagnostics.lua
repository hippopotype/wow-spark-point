-- /sparkpoint status content.

return function(T)
	return {
		{
			name = "status lists game, capabilities, module states and registries",
			fn = function()
				local addon = {
					VERSION = "1.6.0",
					Flavor = {
						GetDiagnostics = function()
							return { game = "Forever", interface = 16001, capabilities = { specs = false, cooldownViewer = true } }
						end,
					},
					ControlCenter = {
						GetAllModules = function()
							return {
								{ name = "Cast Ring", dbKey = "moduleEnabled_Cast", isEnabled = true },
								{ name = "Assisted Highlight", dbKey = "moduleEnabled_AssistedHighlight", isEnabled = false },
							}
						end,
						GetUnavailableReason = function(_, dbKey)
							if dbKey == "moduleEnabled_AssistedHighlight" then
								return "requires assistedCombat"
							end
						end,
					},
					SlotProviders = {
						GetDropdownOptions = function()
							return { { value = "NONE", label = "None" }, { value = "GCD", label = "GCD" } }
						end,
					},
					BarProviders = {
						GetDropdownOptions = function()
							return { { value = "NONE", label = "None" }, { value = "HEALTH", label = "Health" } }
						end,
					},
					ClassResourceSystems = {
						GetRegisteredIDs = function()
							return { "GENERIC_PIPS", "ROGUE_COMBO_POINTS" }
						end,
					},
				}
				T.loadAddonFile("Core/Diagnostics.lua", addon)
				local text = table.concat(addon.Diagnostics.BuildStatusLines(), "\n")
				T.truthy(text:find("SparkPoint 1.6.0", 1, true), "version")
				T.truthy(text:find("Game: Forever (interface 16001)", 1, true), "game")
				T.truthy(text:find("cooldownViewer=true", 1, true), "capabilities sorted")
				T.truthy(text:find("specs=false", 1, true), "capabilities")
				T.truthy(text:find("Cast Ring: enabled", 1, true), "enabled module")
				T.truthy(text:find("Assisted Highlight: skipped (requires assistedCombat)", 1, true), "skipped module")
				T.truthy(text:find("Slot providers: GCD", 1, true), "slot providers without NONE")
				T.truthy(text:find("Bar providers: HEALTH", 1, true), "bar providers")
				T.truthy(text:find("Class resource systems: GENERIC_PIPS, ROGUE_COMBO_POINTS", 1, true), "systems")
			end,
		},
		{
			name = "status shows range tint state only when TargetRange exists",
			fn = function()
				local function build(targetRange, settings)
					local addon = {
						VERSION = "1.6.0",
						GetDBBool = function(key)
							return settings[key] == true
						end,
						TargetRange = targetRange,
						Flavor = {
							GetDiagnostics = function()
								return { game = "Retail", interface = 120000, capabilities = {} }
							end,
						},
						ControlCenter = {
							GetAllModules = function()
								return {}
							end,
							GetUnavailableReason = function() end,
						},
						SlotProviders = {
							GetDropdownOptions = function()
								return {}
							end,
						},
						BarProviders = {
							GetDropdownOptions = function()
								return {}
							end,
						},
						ClassResourceSystems = {
							GetRegisteredIDs = function()
								return {}
							end,
						},
					}
					T.loadAddonFile("Core/Diagnostics.lua", addon)
					return addon.Diagnostics.BuildStatusLines()
				end
				local function stub(hostile, friendly, kind, state, active)
					return {
						GetActiveSpell = function()
							if active then
								return active[1], active[2]
							end
							return nil
						end,
						GetResolvedSpell = function(_, k)
							if k == "FRIENDLY" then
								if friendly then
									return 8936, "Regrowth", "8936"
								end
								return nil
							end
							if hostile then
								return 8921, "Moonfire", "8921"
							end
							return nil
						end,
						GetTargetKind = function()
							return kind
						end,
						GetState = function()
							return state
						end,
					}
				end
				local function last(lines)
					return lines[#lines]
				end
				T.eq(
					last(build(stub(true, true, "HOSTILE", "OUT_OF_RANGE"), { ring_rangeTintEnabled = true, targetRange_friendlyEnabled = true })),
					"Range tint: on, friendly on, spell Moonfire (8921), friendly spell Regrowth (8936), target HOSTILE, state OUT_OF_RANGE",
					"hostile line"
				)
				T.eq(last(build(stub(false, false, nil, "UNKNOWN"), {})), "Range tint: off, friendly off, spell none, friendly spell none, target none, state UNKNOWN", "off line")
				T.eq(
					last(build(stub(false, true, "FRIENDLY", "UNKNOWN"), { ring_rangeTintEnabled = true })),
					"Range tint: on, friendly off, spell none, friendly spell Regrowth (8936), target FRIENDLY, state UNKNOWN",
					"friendly line"
				)
				T.eq(
					last(build(stub(true, false, "HOSTILE", "IN_RANGE", { 7918, "Shoot Gun" }), { ring_rangeTintEnabled = true })),
					"Range tint: on, friendly off, spell Shoot Gun (7918), friendly spell none, target HOSTILE, state IN_RANGE",
					"active hostile line"
				)
				T.eq(
					last(build(stub(false, true, "FRIENDLY", "IN_RANGE", { 8936, "Rejuvenation" }), { ring_rangeTintEnabled = true, targetRange_friendlyEnabled = true })),
					"Range tint: on, friendly on, spell none, friendly spell Rejuvenation (8936), target FRIENDLY, state IN_RANGE",
					"active friendly line"
				)
				local none = table.concat(build(nil, {}), "\n")
				T.eq(none:find("Range tint", 1, true), nil, "no line without TargetRange")
			end,
		},
		{
			name = "status shows resolved class resources and combo points",
			fn = function()
				local function build(entries, druidForm, classTag, opts)
					opts = opts or {}
					local addon = {
						VERSION = "1.6.0",
						Has = function()
							return opts.targetBound == true
						end,
						API = {
							GetComboPoints = function(maxFallback)
								opts.fallbackSeen = maxFallback
								return opts.cur, opts.max
							end,
						},
						ResourceModel = {
							Resolve = function()
								return { context = { classTag = classTag, druidForm = druidForm }, resources = entries }
							end,
						},
						Flavor = {
							GetDiagnostics = function()
								return { game = "Forever", interface = 16001, capabilities = {} }
							end,
						},
						ControlCenter = {
							GetAllModules = function()
								return {}
							end,
							GetUnavailableReason = function() end,
						},
						SlotProviders = {
							GetDropdownOptions = function()
								return {}
							end,
						},
						BarProviders = {
							GetDropdownOptions = function()
								return {}
							end,
						},
						ClassResourceSystems = {
							GetRegisteredIDs = function()
								return {}
							end,
						},
					}
					T.loadAddonFile("Core/Util.lua", addon)
					T.loadAddonFile("Core/Diagnostics.lua", addon)
					for _, line in ipairs(addon.Diagnostics.BuildStatusLines()) do
						if line:find("^Class resources:") then
							return line
						end
					end
				end
				local combo = { key = "ROGUE_COMBO_POINTS", def = { comboPoints = true, maxCount = 5 } }
				local druidCombo = { key = "DRUID_COMBO_POINTS", def = { comboPoints = true, maxCount = 5 } }
				local opts = { targetBound = true, cur = 3, max = 5 }
				T.eq(build({ { key = "ENERGY", def = {} }, combo }, nil, "ROGUE", opts), "Class resources: ENERGY, ROGUE_COMBO_POINTS; form n/a; combo 3/5 (target-bound)", "rogue")
				T.eq(opts.fallbackSeen, 5, "reader gets maxCount")
				T.eq(
					build({ { key = "ENERGY", def = {} }, druidCombo }, "CAT", "DRUID", { targetBound = true, cur = nil, max = 5 }),
					"Class resources: ENERGY, DRUID_COMBO_POINTS; form CAT; combo unreadable",
					"unreadable"
				)
				T.eq(build({ { key = "MANA", def = {} } }, "HUMANOID", "DRUID"), "Class resources: MANA; form HUMANOID", "druid caster")
				T.eq(build({ { key = "MANA", def = {} } }, nil, "MAGE"), "Class resources: MANA; form n/a", "mage")
				T.eq(build({}, nil, "WARLOCK"), "Class resources: none; form n/a", "none")
				T.eq(build({ combo }, nil, "ROGUE", { targetBound = false, cur = 2, max = 5 }), "Class resources: ROGUE_COMBO_POINTS; form n/a; combo 2/5 (player)", "player bound")
				local secret = setmetatable({}, {
					__tostring = function()
						error("secret")
					end,
				})
				T.withGlobals({
					issecretvalue = function(v)
						return v == secret
					end,
				}, function()
					T.eq(
						build({ combo }, nil, "ROGUE", { targetBound = false, cur = secret, max = 5 }),
						"Class resources: ROGUE_COMBO_POINTS; form n/a; combo unreadable",
						"secret"
					)
				end)
			end,
		},
		{
			name = "ClassResourceSystems:GetRegisteredIDs is sorted",
			fn = function()
				local addon = {}
				T.loadAddonFile("Core/ClassResourceSystems.lua", addon)
				addon.ClassResourceSystems:Register("ZED", function() end)
				addon.ClassResourceSystems:Register("ALPHA", function() end)
				local ids = addon.ClassResourceSystems:GetRegisteredIDs()
				T.eq(ids[1], "ALPHA", "first")
				T.eq(ids[2], "ZED", "second")
			end,
		},
	}
end
