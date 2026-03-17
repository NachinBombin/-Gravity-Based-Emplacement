--[[
    npc_deploy_claymore_ent / cl_init.lua
    Client-side rendering — beam code identical to rebel_claymore_ent.
    HUD prompt is shown to ANY nearby player (no ownership check) because
    an NPC placed this claymore.
--]]

include( "shared.lua" )

function ENT:Initialize()
    self.Color = Color( 255, 255, 255, 255 )
end

-- -----------------------------------------------------------------------
-- Fonts
-- -----------------------------------------------------------------------
surface.CreateFont( "Arialfclay_npc", {
    font      = "Arial",
    antialias = true,
    size      = 35,
    outline   = true,
} )

-- -----------------------------------------------------------------------
-- Beam materials
-- -----------------------------------------------------------------------
local M_WhiteStripe = Material( "models/hoff/weapons/claymore/sprites/M_Claymore_Beam" )
local Laser         = Material( "cable/redlaser" )

ENT.BeamOffsetVertical = 11
ENT.DrawBeams          = true
ENT.BeamStyle          = 1
ENT.BeamThickness      = 3

-- -----------------------------------------------------------------------
-- RenderLaserQuad helper (unchanged from original claymore)
-- -----------------------------------------------------------------------
function ENT:RenderLaserQuad( basePos, baseAngle, forwardOffset, rightOffset,
                               verticalOffset, yawOffset, pitchOffset, rollOffset,
                               width, height, material, color )

    local quadCenter = basePos
        + baseAngle:Forward() * forwardOffset
        + baseAngle:Right()   * rightOffset
        + baseAngle:Up()      * verticalOffset

    local quadAngle = baseAngle + Angle( pitchOffset, yawOffset, rollOffset )
    local right     = quadAngle:Right()
    local up        = quadAngle:Up()

    local corner1 = quadCenter + ( right * ( width  / 2 ) ) - ( up * ( height / 2 ) )
    local corner2 = quadCenter - ( right * ( width  / 2 ) ) - ( up * ( height / 2 ) )
    local corner3 = quadCenter - ( right * ( width  / 2 ) ) + ( up * ( height / 2 ) )
    local corner4 = quadCenter + ( right * ( width  / 2 ) ) + ( up * ( height / 2 ) )

    render.SetMaterial( material )
    render.DrawQuad( corner1, corner2, corner3, corner4, color )
end

-- -----------------------------------------------------------------------
-- Draw
-- -----------------------------------------------------------------------
function ENT:Draw()
    self:DrawModel()

    if not self.DrawBeams then return end

    local basePos   = self:GetPos()
    local baseAngle = self:GetAngles()
    local vOffset   = self.BeamOffsetVertical
    local thickness = self.BeamThickness

    if self.BeamStyle == 1 then
        local beamHeight = 60
        local beamColor  = Color( 255, 255, 255 )

        self:RenderLaserQuad( basePos, baseAngle,  13, -30, vOffset,  70 + 180, 90, 0, thickness, beamHeight, M_WhiteStripe, beamColor )
        self:RenderLaserQuad( basePos, baseAngle, -13, -30, vOffset, 110 + 180, 90, 0, thickness, beamHeight, M_WhiteStripe, beamColor )
        self:RenderLaserQuad( basePos, baseAngle,  13, -30, vOffset, -20,  0, 90, thickness, beamHeight, M_WhiteStripe, beamColor )
        self:RenderLaserQuad( basePos, baseAngle, -13, -30, vOffset,  20,  0, 90, thickness, beamHeight, M_WhiteStripe, beamColor )
    else
        local up = self:GetUp() * 11

        local v1 = self:GetPos() + self:GetForward() *  2.4 + up + self:GetRight() * -1
        local v2 = self:GetPos() + self:GetRight()   * -50  + self:GetForward() *  20 + up
        render.SetMaterial( Laser )
        render.DrawBeam( v1, v2, 3.5, 1, 1, Color( 255, 255, 255, 255 ) )

        local v3 = self:GetPos() + self:GetForward() * -2.4 + up + self:GetRight() * -1
        local v4 = self:GetPos() + self:GetRight()   * -50  + self:GetForward() * -20 + up
        render.SetMaterial( Laser )
        render.DrawBeam( v3, v4, 3.5, 1, 1, Color( 255, 255, 255, 255 ) )
    end
end

-- -----------------------------------------------------------------------
-- Client Think — polls convars every 0.5 s
-- -----------------------------------------------------------------------
if CLIENT then
    function ENT:Think()
        if ConVarExists( "Claymore_BeamStyle" ) then
            self.BeamStyle = GetConVar( "Claymore_BeamStyle" ):GetInt()
        end
        if ConVarExists( "Claymore_DrawBeams" ) then
            self.DrawBeams = GetConVar( "Claymore_DrawBeams" ):GetInt() == 1
        end
        self:NextThink( CurTime() + 0.5 )
        return true
    end
end

-- -----------------------------------------------------------------------
-- HUD pickup prompt — shown to ANY player within range.
-- No SteamID gate: this claymore was placed by an NPC, not a specific player.
-- -----------------------------------------------------------------------
hook.Add( "HUDPaint", "NPCClayHudText", function()
    local trace = util.TraceLine({
        start  = LocalPlayer():EyePos(),
        endpos = LocalPlayer():EyePos() + LocalPlayer():EyeAngles():Forward() * 85,
        filter = { LocalPlayer() },
    })

    local ent = trace.Entity
    if not IsValid( ent ) or not LocalPlayer():Alive() then return end

    local dist = LocalPlayer():EyePos():Distance( ent:GetPos() )

    if ent:GetClass() == "npc_deploy_claymore_ent" and dist < 85 then
        local useKey = input.LookupBinding( "+use" ) or "E"
        draw.DrawText(
            "Press " .. string.upper( useKey ) .. " to Pick Up Claymore",
            "Arialfclay_npc",
            ScrW() / 2, ScrH() / 2 + 200,
            Color( 255, 255, 255, 255 ),
            TEXT_ALIGN_CENTER
        )
    end
end )
