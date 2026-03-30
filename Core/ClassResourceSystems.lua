-- SparkPoint Class Resource System Registry
-- Allows ClassResource to stay controller-only while resource families
-- provide their own implementations.

local _, addon = ...

local ClassResourceSystems = {}
addon.ClassResourceSystems = ClassResourceSystems

local factories = {}

function ClassResourceSystems:Register(systemID, factory)
	if type(systemID) ~= "string" or systemID == "" then
		error("ClassResourceSystems:Register requires a non-empty systemID")
	end

	if type(factory) ~= "function" then
		error("ClassResourceSystems:Register requires a factory function")
	end

	factories[systemID] = factory
end

function ClassResourceSystems:Create(systemID, context)
	local factory = factories[systemID]
	if not factory then
		return nil
	end

	return factory(context)
end
