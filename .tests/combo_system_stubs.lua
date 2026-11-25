-- Shared stubs for class resource system tests (GenericPips and the combo point systems).
-- Returns a loader (T, opts) -> system, ctl. Before loading the system file it installs
-- CreateFrame (auto-stub frames) and delegating UnitPower / UnitPowerMax /
-- GetUnitChargedPowerPoints closures, because system files capture them as upvalues.
-- opts.file / opts.systemID pick the system (default GenericPips); opts.extendAddon(addon, ctl)
-- may add more addon fields before the file loads.
-- `ctl` controls the stubs: ctl.has[capability], ctl.db[key], ctl.power / ctl.maxPower /
-- ctl.charged (ctl.chargedErrors makes GetUnitChargedPowerPoints raise), ctl.reader.current /
-- ctl.reader.max; it records ctl.calls (per global), ctl.readerCalls, ctl.readerFallbacks and
-- ctl.frames, and exposes ctl.defs and ctl.addon.

-- Auto-stub: any unknown method is a no-op returning another auto-stub. Show/Hide/IsShown/
-- IsPlaying keep per-object state so tests can see what was hidden.
local function NewStub()
	local stub = { shown = false, showCalls = 0, hideCalls = 0, playing = false }
	function stub:Show()
		self.shown = true
		self.showCalls = self.showCalls + 1
	end
	function stub:Hide()
		self.shown = false
		self.hideCalls = self.hideCalls + 1
	end
	function stub:IsShown()
		return self.shown
	end
	function stub:IsPlaying()
		return self.playing
	end
	return setmetatable(stub, {
		__index = function()
			return function()
				return NewStub()
			end
		end,
	})
end

local SYSTEM_IDS = {
	GENERIC_PIPS = "GENERIC_PIPS",
	DEATH_KNIGHT_RUNES = "DEATH_KNIGHT_RUNES",
	EVOKER_ESSENCE = "EVOKER_ESSENCE",
	ROGUE_COMBO_POINTS = "ROGUE_COMBO_POINTS",
	DRUID_COMBO_POINTS = "DRUID_COMBO_POINTS",
	PALADIN_HOLY_POWER = "PALADIN_HOLY_POWER",
	MONK_CHI = "MONK_CHI",
	MAGE_ARCANE_CHARGES = "MAGE_ARCANE_CHARGES",
	WARLOCK_SOUL_SHARDS = "WARLOCK_SOUL_SHARDS",
	SHAMAN_MAELSTROM_WEAPON = "SHAMAN_MAELSTROM_WEAPON",
}

return function(T, opts)
	opts = opts or {}
	local ctl = {
		has = {},
		db = { classresource_simpleAnimations = true },
		power = 0,
		maxPower = 5,
		charged = nil,
		reader = { current = 0, max = 5 },
		readerCalls = 0,
		readerFallbacks = {},
		calls = { UnitPower = 0, UnitPowerMax = 0, GetUnitChargedPowerPoints = 0 },
		frames = {},
		factories = {},
		defs = {
			combo = {
				key = "ROGUE_COMBO_POINTS",
				sourceType = "POWER",
				powerEnum = 4,
				powerToken = "COMBO_POINTS",
				maxCount = 5,
				comboPoints = true,
			},
			holy = { key = "HOLY_POWER", sourceType = "POWER", powerEnum = 9, powerToken = "HOLY_POWER", maxCount = 5 },
		},
	}
	ctl.NewStub = NewStub

	_G.CreateFrame = function()
		local frame = NewStub()
		ctl.frames[#ctl.frames + 1] = frame
		return frame
	end
	_G.UnitPower = function()
		ctl.calls.UnitPower = ctl.calls.UnitPower + 1
		return ctl.power
	end
	_G.UnitPowerMax = function()
		ctl.calls.UnitPowerMax = ctl.calls.UnitPowerMax + 1
		return ctl.maxPower
	end
	_G.GetUnitChargedPowerPoints = function()
		ctl.calls.GetUnitChargedPowerPoints = ctl.calls.GetUnitChargedPowerPoints + 1
		if ctl.chargedErrors then
			error("GetUnitChargedPowerPoints must not be called")
		end
		return ctl.charged
	end

	local addon = {
		addonFolder = "Interface\\AddOns\\SparkPoint",
		ResourceModel = {
			SystemIDs = SYSTEM_IDS,
			SourceTypes = { POWER = "POWER", RUNES = "RUNES", AURA_STACKS = "AURA_STACKS" },
		},
		ClassResourceSystems = {
			Register = function(_, id, factory)
				ctl.factories[id] = factory
			end,
		},
		GetDBValue = function(key)
			return ctl.db[key]
		end,
		GetDBColor = function()
			return 1, 1, 1, 1
		end,
		TintFrameColor = function() end,
		API = {
			GetComboPoints = function(maxFallback)
				ctl.readerCalls = ctl.readerCalls + 1
				ctl.readerFallbacks[#ctl.readerFallbacks + 1] = maxFallback
				return ctl.reader.current, ctl.reader.max
			end,
			GetPlayerClassColor = function()
				return 1, 1, 1, 1
			end,
		},
		Has = function(capability)
			return ctl.has[capability] == true
		end,
	}
	ctl.addon = addon

	T.loadAddonFile("Core/Util.lua", addon)
	addon.Util.SetTextureSmooth = function() end
	if opts.extendAddon then
		opts.extendAddon(addon, ctl)
	end

	T.loadAddonFile(opts.file or "Modules/ClassResourceSystems/GenericPips.lua", addon)
	local factory = assert(ctl.factories[opts.systemID or SYSTEM_IDS.GENERIC_PIPS], "system factory not registered")
	return factory(), ctl
end
