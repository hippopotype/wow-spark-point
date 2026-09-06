-- SparkPoint shared utilities.
-- Helpers used by more than one module. Nothing here may touch the
-- database, the anchor frame, or any module state.

local _, addon = ...

local Util = {}
addon.Util = Util

-- Calls obj:method(...) only when the method exists, for WoW APIs that
-- vary by client build.
function Util.SafeCall(obj, method, ...)
	if obj and obj[method] then
		obj[method](obj, ...)
	end
end

-- Binds a texture with trilinear sampling and disables pixel-grid
-- snapping, keeping vector-derived ring art soft at any UI scale.
function Util.SetTextureSmooth(texture, texturePath)
	if not texture then
		return
	end

	local ok = pcall(texture.SetTexture, texture, texturePath, nil, nil, "TRILINEAR")
	if not ok then
		texture:SetTexture(texturePath)
	end

	Util.SafeCall(texture, "SetSnapToPixelGrid", false)
	Util.SafeCall(texture, "SetTexelSnappingBias", 0)
end

-- Non-numbers clamp to 0 rather than erroring.
function Util.Clamp01(value)
	if type(value) ~= "number" then
		return 0
	end
	if value < 0 then
		return 0
	end
	if value > 1 then
		return 1
	end
	return value
end

function Util.ClampOpacity(value, fallback)
	local opacity = tonumber(value)
	if opacity == nil then
		opacity = fallback
	end
	if opacity < 0 then
		return 0
	end
	if opacity > 1 then
		return 1
	end
	return opacity
end

function Util.DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = Util.DeepCopy(v)
	end
	return out
end

-- Returns r, g, b from a color table, defaulting to white.
function Util.NormalizeColor(color)
	if type(color) ~= "table" then
		return 1, 1, 1
	end

	return color.r or 1, color.g or 1, color.b or 1
end

-- Matches a frame's strata and level to its parent.
function Util.InheritLayering(frame)
	if not frame then
		return
	end

	local parent = frame:GetParent()
	if not parent then
		return
	end

	if parent.GetFrameStrata then
		frame:SetFrameStrata(parent:GetFrameStrata())
	end
	frame:SetFrameLevel(parent:GetFrameLevel() or 0)
end

-- Reads a foreign (Blizzard-owned) frame's accessibility in the current execution
-- context. Required by .skills/secret-values.md rule 5: never inspect a foreign UI
-- object in 12.1 without checking access first. Moved here from Core/Visibility.lua
-- so Core/CooldownViewerBridge.lua can use it without depending on Visibility.
function Util.CanAccessFrameSafe(frame)
	if not frame then
		return false
	end
	if not frame.CanBeAccessedInContext then
		return true
	end

	local ok, canAccess = pcall(frame.CanBeAccessedInContext, frame)
	if not ok then
		return false
	end
	if _G.issecretvalue and _G.issecretvalue(canAccess) then
		return false
	end
	return canAccess == true
end

-- True only for a plain, readable number. Guards every value used as a table key
-- or numeric operand. Spec E2 measured cooldown IDs as plain today, but the gate
-- costs nothing and Invariant 1 makes a secret table key a hard defect.
-- Pattern adapted from .clones/Cooldown-Companion/Config/Pickers.lua:38-43
function Util.IsAccessibleNumber(value)
	if _G.issecretvalue and _G.issecretvalue(value) then
		return false
	end
	if type(value) ~= "number" then
		return false
	end
	if _G.canaccessvalue and not _G.canaccessvalue(value) then
		return false
	end
	return true
end

-- Same gate for booleans. cooldownInfo.isKnown / hasAura / charges were never
-- measured as non-secret, and the prior art treats them as a live hazard:
-- .clones/Cooldown-Companion/Config/Pickers.lua:31-36 has a purpose-built
-- GetAccessibleBoolean, and EnhanceQoL pcall-wraps even an equality test on
-- cooldownInfo fields (CooldownPanels_CDMAuras.lua:373). Returns `fallback`
-- when the value cannot be safely inspected.
function Util.GetAccessibleBoolean(value, fallback)
	if _G.issecretvalue and _G.issecretvalue(value) then
		return fallback
	end
	if type(value) ~= "boolean" then
		return fallback
	end
	return value
end
