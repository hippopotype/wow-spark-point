-- SparkPoint Icon Glow
--
-- Pulse animations for a SparkPoint-owned glow texture: a brief "ready" pulse
-- and a looping "proc" pulse. Shared by the Cooldown Manager skin
-- (Core/CooldownViewerSkin.lua) and the dormant icon renderer. The texture
-- must be one SparkPoint created -- never pass a Blizzard region.

local _, addon = ...

local IconGlow = {}
addon.IconGlow = IconGlow

local READY_IN = 0.12
local READY_OUT = 0.6
local PROC_MIN_ALPHA = 0.35
local PROC_HALF_CYCLE = 0.6

local GlowMixin = {}

local function HideTexture(texture)
	texture:SetAlpha(0)
	texture:Hide()
end

function IconGlow:Attach(texture)
	local glow = { texture = texture, procActive = false }
	for k, v in pairs(GlowMixin) do
		glow[k] = v
	end

	local ready = texture:CreateAnimationGroup()
	local fadeIn = ready:CreateAnimation("Alpha")
	fadeIn:SetOrder(1)
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(READY_IN)
	local scaleUp = ready:CreateAnimation("Scale")
	scaleUp:SetOrder(1)
	scaleUp:SetScale(1.08, 1.08)
	scaleUp:SetDuration(READY_IN)
	scaleUp:SetOrigin("CENTER", 0, 0)
	local fadeOut = ready:CreateAnimation("Alpha")
	fadeOut:SetOrder(2)
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetDuration(READY_OUT)
	local scaleDown = ready:CreateAnimation("Scale")
	scaleDown:SetOrder(2)
	scaleDown:SetScale(0.96, 0.96)
	scaleDown:SetDuration(READY_OUT)
	scaleDown:SetOrigin("CENTER", 0, 0)
	ready:SetToFinalAlpha(true)
	ready:SetScript("OnFinished", function()
		if not glow.procActive then
			HideTexture(texture)
		end
	end)

	local proc = texture:CreateAnimationGroup()
	proc:SetLooping("BOUNCE")
	local pulse = proc:CreateAnimation("Alpha")
	pulse:SetFromAlpha(PROC_MIN_ALPHA)
	pulse:SetToAlpha(1)
	pulse:SetDuration(PROC_HALF_CYCLE)
	pulse:SetSmoothing("IN_OUT")

	glow.ready = ready
	glow.proc = proc
	HideTexture(texture)
	return glow
end

function GlowMixin:SetColor(r, g, b, a)
	self.texture:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
end

function GlowMixin:PlayReady()
	if self.procActive then
		return
	end
	self.ready:Stop()
	self.texture:Show()
	self.texture:SetAlpha(1)
	self.ready:Play()
end

function GlowMixin:StartProc()
	if self.procActive then
		return
	end
	self.procActive = true
	self.ready:Stop()
	self.texture:Show()
	self.texture:SetAlpha(1)
	self.proc:Play()
end

function GlowMixin:StopProc()
	if not self.procActive then
		return
	end
	self.procActive = false
	self.proc:Stop()
	HideTexture(self.texture)
end

function GlowMixin:StopAll()
	self.procActive = false
	self.ready:Stop()
	self.proc:Stop()
	HideTexture(self.texture)
end
