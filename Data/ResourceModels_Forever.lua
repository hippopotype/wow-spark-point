-- SparkPoint Resource Models: WoW Forever (Camelot)
-- Forever has no specializations, so models are keyed by class (with druid form
-- overrides). Loaded only on Forever via the TOC ([AllowLoadGameType camelot]).
-- Empty until Part 2 adds the Forever class models.

local _, addon = ...

addon.ResourceModel:SetModelData({ keyedBy = "class", models = {} })
