-- SparkPoint Resource Models: WoW Forever (Camelot)
-- Forever has no specializations, so models are keyed by class (with druid form
-- overrides). Loaded only on Forever via the TOC ([AllowLoadGameType camelot]).
-- Empty until Part 2 adds the Forever class models.

local _, addon = ...

-- Retail clients that do not know the camelot game type ignore the TOC tag and load this
-- file anyway; Core/Flavor.lua (loaded first) is the real gate.
if addon.Flavor.game ~= "Forever" then
	return
end

addon.ResourceModel:SetModelData({ keyedBy = "class", models = {} })
