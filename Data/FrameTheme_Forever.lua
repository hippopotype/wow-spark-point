-- SparkPoint Frame Theme default: WoW Forever (Camelot)
-- "Automatic" Frame Theme resolves to Copper on Forever to match its copper UI frames.
-- Loaded only on Forever via the TOC ([AllowLoadGameType camelot]).

local _, addon = ...

-- Retail clients that do not know the camelot game type ignore the TOC tag and load this
-- file anyway; Core/Flavor.lua (loaded first) is the real gate.
if addon.Flavor.game ~= "Forever" then
	return
end

addon.DefaultFrameTheme = "COPPER"
