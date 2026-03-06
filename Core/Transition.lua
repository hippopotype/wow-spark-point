-- SparkPoint Transition Service
-- Shared frame transitions for subtle HUD transition (alpha).

local _, addon = ...

local GetDBBool = addon.GetDBBool
local GetDBValue = addon.GetDBValue

local Transition = {}
addon.Transition = Transition

local active = setmetatable({}, { __mode = "k" })
local lifecycle = setmetatable({}, { __mode = "k" })
local driver
local EPSILON = 0.0001

local function Clamp01(value)
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

local function EaseLinear(t)
	return t
end

local function EaseOutSine(t)
	return math.sin((t * math.pi) * 0.5)
end

local function EaseOutQuad(t)
	return 1 - ((1 - t) * (1 - t))
end

local function ResolveEasing(name)
	if name == "linear" then
		return EaseLinear
	elseif name == "outQuad" then
		return EaseOutQuad
	end
	return EaseOutSine
end

local function ApplyState(frame, state, factor)
	local eased = state.ease(factor)

	if type(state.fromAlpha) == "number" and type(state.toAlpha) == "number" then
		local a = state.fromAlpha + (state.toAlpha - state.fromAlpha) * eased
		frame:SetAlpha(a)
	end

	if state.onUpdate then
		state.onUpdate(frame, eased, factor)
	end
end

local function OnDriverUpdate(_, elapsed)
	for frame, state in pairs(active) do
		if not frame or not frame.IsObjectType or not frame:IsObjectType("Frame") then
			active[frame] = nil
		else
			state.elapsed = (state.elapsed or 0) + (elapsed or 0)
			local progress = 1
			if state.duration > 0 then
				progress = state.elapsed / state.duration
				if progress < 0 then
					progress = 0
				elseif progress > 1 then
					progress = 1
				end
			end

			ApplyState(frame, state, progress)
			if progress >= 1 then
				active[frame] = nil
				if state.onComplete then
					state.onComplete(frame)
				end
			end
		end
	end

	if not next(active) and driver then
		driver:SetScript("OnUpdate", nil)
	end
end

local function EnsureDriver()
	if not driver then
		driver = CreateFrame("Frame")
	end
	if not driver:GetScript("OnUpdate") then
		driver:SetScript("OnUpdate", OnDriverUpdate)
	end
end

local function GetLifecycle(frame)
	local state = lifecycle[frame]
	if not state then
		state = {
			desiredVisible = false,
			phase = "hidden",
			hideCallbacks = nil,
		}
		lifecycle[frame] = state
	end
	return state
end

local function GetPhase(frame, state)
	local tween = active[frame]
	if tween then
		if type(tween.fromAlpha) == "number" and type(tween.toAlpha) == "number" then
			if tween.toAlpha > tween.fromAlpha + EPSILON then
				state.phase = "showing"
				return "showing"
			elseif tween.toAlpha + EPSILON < tween.fromAlpha then
				state.phase = "hiding"
				return "hiding"
			end
		end
	end

	if frame:IsShown() then
		state.phase = "visible"
		return "visible"
	end

	state.phase = "hidden"
	return "hidden"
end

local function RunHideCallbacks(state, frame)
	if not state.hideCallbacks then
		return
	end
	local callbacks = state.hideCallbacks
	state.hideCallbacks = nil
	for i = 1, #callbacks do
		local cb = callbacks[i]
		if cb then
			cb(frame)
		end
	end
end

function Transition:IsEnabled()
	return not GetDBBool or GetDBBool("transition_enabled")
end

function Transition:GetConfig()
	local inMs = tonumber(GetDBValue and GetDBValue("transition_inDurationMs")) or 180
	local outMs = tonumber(GetDBValue and GetDBValue("transition_outDurationMs")) or 160
	local showMs = tonumber(GetDBValue and GetDBValue("transition_hysteresisShowMs")) or 80
	local hideMs = tonumber(GetDBValue and GetDBValue("transition_hysteresisHideMs")) or 120

	return {
		enabled = self:IsEnabled(),
		inDuration = math.max(0, inMs) / 1000,
		outDuration = math.max(0, outMs) / 1000,
		hysteresisShow = math.max(0, showMs) / 1000,
		hysteresisHide = math.max(0, hideMs) / 1000,
		easing = tostring(GetDBValue and GetDBValue("transition_easing") or "outSine"),
	}
end

function Transition:Stop(frame)
	if not frame then
		return
	end
	active[frame] = nil
	if not next(active) and driver then
		driver:SetScript("OnUpdate", nil)
	end
end

function Transition:Play(frame, spec)
	if not frame or not spec then
		return
	end

	local duration = tonumber(spec.duration) or 0
	local fromAlpha = spec.fromAlpha
	local toAlpha = spec.toAlpha
	local onComplete = spec.onComplete
	local onUpdate = spec.onUpdate

	local currentState = active[frame]
	local isIncomingFadeIn = type(fromAlpha) == "number" and type(toAlpha) == "number" and (toAlpha - fromAlpha) > EPSILON
	if currentState and isIncomingFadeIn then
		local isCurrentFadeIn = type(currentState.fromAlpha) == "number" and type(currentState.toAlpha) == "number" and (currentState.toAlpha - currentState.fromAlpha) > EPSILON
		local sameTarget = type(currentState.toAlpha) == "number" and math.abs(currentState.toAlpha - toAlpha) <= EPSILON
		if isCurrentFadeIn and sameTarget then
			return
		end
	end

	self:Stop(frame)

	if spec.showBefore and frame.Show then
		frame:Show()
	end

	if duration <= 0 then
		local instant = {
			fromAlpha = fromAlpha,
			toAlpha = toAlpha,
			ease = ResolveEasing(spec.easing),
			onUpdate = onUpdate,
		}
		ApplyState(frame, instant, 1)
		if onComplete then
			onComplete(frame)
		end
		return
	end

	active[frame] = {
		elapsed = 0,
		duration = duration,
		fromAlpha = fromAlpha,
		toAlpha = toAlpha,
		ease = ResolveEasing(spec.easing),
		onComplete = onComplete,
		onUpdate = onUpdate,
	}

	EnsureDriver()
end

function Transition:ShowFrame(frame, opts)
	if not frame then
		return
	end
	opts = opts or {}

	local cfg = self:GetConfig()
	local toAlpha = type(opts.toAlpha) == "number" and Clamp01(opts.toAlpha) or 1
	local fromAlpha = type(opts.fromAlpha) == "number" and Clamp01(opts.fromAlpha) or (frame:IsShown() and Clamp01(frame:GetAlpha() or toAlpha) or 0)
	local state = GetLifecycle(frame)
	state.desiredVisible = true

	local phase = GetPhase(frame, state)
	if phase == "showing" or phase == "visible" then
		return
	end

	state.hideCallbacks = nil

	if not cfg.enabled then
		frame:Show()
		frame:SetAlpha(toAlpha)
		state.phase = "visible"
		if opts.onComplete then
			opts.onComplete(frame)
		end
		return
	end

	state.phase = "showing"
	self:Play(frame, {
		showBefore = true,
		duration = type(opts.duration) == "number" and opts.duration or cfg.inDuration,
		easing = opts.easing or cfg.easing,
		fromAlpha = fromAlpha,
		toAlpha = toAlpha,
		onUpdate = opts.onUpdate,
		onComplete = function(localFrame)
			local localState = GetLifecycle(localFrame)
			localState.phase = "visible"
			if opts.onComplete then
				opts.onComplete(localFrame)
			end
		end,
	})
end

function Transition:HideFrame(frame, opts)
	if not frame then
		return
	end
	opts = opts or {}

	local cfg = self:GetConfig()
	local currentAlpha = type(opts.fromAlpha) == "number" and Clamp01(opts.fromAlpha) or Clamp01(frame:GetAlpha() or 1)
	local restoreAlpha = type(opts.restoreAlpha) == "number" and Clamp01(opts.restoreAlpha) or 1
	local state = GetLifecycle(frame)
	state.desiredVisible = false
	if opts.onComplete then
		state.hideCallbacks = state.hideCallbacks or {}
		state.hideCallbacks[#state.hideCallbacks + 1] = opts.onComplete
	end

	local function Finish(localFrame)
		local localState = GetLifecycle(localFrame)
		localState.phase = "hidden"
		frame:Hide()
		frame:SetAlpha(restoreAlpha)
		RunHideCallbacks(localState, localFrame)
	end

	local phase = GetPhase(frame, state)
	if phase == "hidden" then
		Finish(frame)
		return
	end
	if phase == "hiding" then
		return
	end

	if not cfg.enabled then
		Finish(frame)
		return
	end

	state.phase = "hiding"
	self:Play(frame, {
		showBefore = true,
		duration = type(opts.duration) == "number" and opts.duration or cfg.outDuration,
		easing = opts.easing or cfg.easing,
		fromAlpha = currentAlpha,
		toAlpha = 0,
		onUpdate = opts.onUpdate,
		onComplete = Finish,
	})
end
