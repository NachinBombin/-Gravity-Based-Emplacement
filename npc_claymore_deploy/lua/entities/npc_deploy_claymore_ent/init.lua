--[[
    npc_deploy_claymore_ent / init.lua
    Server-side logic — identical to rebel_claymore_ent with two changes:

    CHANGE 1 → ENT:Use()
      Any player can pick this up (no SteamID ownership check).
      On pickup the player receives the "rebel_claymore" SWEP + 1 slam ammo,
      matching what the original player-placed version returns.

    CHANGE 2 → ENT.WeaponClass (set in shared.lua)
      "rebel_claymore" — the SWEP the player gets back on pickup.

    Everything else (IsTarget faction filter, TraceHull sensor, directional
    blast, Kids chain, convars, sounds) is taken directly from rebel_claymore_ent.
--]]

AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- -----------------------------------------------------------------------
-- Model (BO2 claymore — same model used by rebel_claymore_ent)
-- -----------------------------------------------------------------------
local CLAYMORE_MODEL = "models/hoff/weapons/claymore/w_claymore_bo2.mdl"

-- -----------------------------------------------------------------------
-- Sounds
-- -----------------------------------------------------------------------
ENT.StickSound = {
    "hoff/mpl/seal_claymore/plant.wav",
}

-- -----------------------------------------------------------------------
-- Initialize
-- -----------------------------------------------------------------------
function ENT:Initialize()
    self:SetModel( CLAYMORE_MODEL )
    self:PhysicsInit( SOLID_VPHYSICS )
    self:SetMoveType( MOVETYPE_NONE )
    self:SetSolid( SOLID_VPHYSICS )
    self:SetCollisionGroup( COLLISION_GROUP_DEBRIS_TRIGGER )
    self:SetFriction( 0 )

    -- NPC-placed claymores never trigger on their placer (an NPC, not a player).
    -- OwnerTrigger convar is irrelevant here; filter is just self.
    self.TriggeredByOwner = false

    local phys = self:GetPhysicsObject()
    if IsValid( phys ) then phys:Wake() end

    self.Spawned = CurTime()
end

-- -----------------------------------------------------------------------
-- IsTarget — FACTION FILTER (identical to rebel_claymore_ent)
--   TRUE   → human player OR whitelisted rebel/citizen NPC
--   FALSE  → any Combine NPC, props, world geometry, etc.
-- -----------------------------------------------------------------------
function ENT:IsTarget( ent )
    if not IsValid( ent ) then return false end

    if ent:IsPlayer() then return true end

    if ent:IsNPC() then
        return ENT.TargetClasses[ ent:GetClass() ] == true
    end

    return false
end

-- -----------------------------------------------------------------------
-- Think — directional hull-trace sensor
--
-- The claymore's sensor faces self:GetRight() * -1 (the lethal forward arc).
-- We sweep a narrow hull FROM the sensor origin TO a point 'range' units
-- ahead along that direction.  Because start != endpos the trace is a
-- directed sweep and physically cannot reach anything behind the claymore,
-- giving a clean forward-only detection zone.
-- -----------------------------------------------------------------------
function ENT:Think()
    local range         = GetConVar( "Claymore_DetectRange" ):GetInt()
    local sensorOrigin  = self:GetPos() + self:GetRight() * -30
    local sensorForward = self:GetRight() * -1   -- same direction as the lethal arc

    local tracedata = {
        ignoreworld    = true,
        collisiongroup = COLLISION_GROUP_PLAYER,
        start          = sensorOrigin,
        endpos         = sensorOrigin + sensorForward * range,  -- sweep forward only
        mins           = Vector( -16, -16, -20 ),   -- narrow cross-section
        maxs           = Vector(  16,  16,  40 ),   -- tall enough to catch crouched NPCs
        filter         = { self },
    }

    local trace = util.TraceHull( tracedata )

    if trace.HitNonWorld and IsValid( trace.Entity ) then
        if self.Exploded then return end

        -- Combine and non-rebel NPCs pass through safely
        if not self:IsTarget( trace.Entity ) then return end

        self:Explode()
    end
end

-- -----------------------------------------------------------------------
-- PhysicsCollide — freeze on surface contact
-- -----------------------------------------------------------------------
function ENT:PhysicsCollide( data, phys )
    if self.Setup or not data.HitEntity:IsWorld() then return end
    self:SetMoveType( MOVETYPE_NONE )
    phys:EnableMotion( false )
    phys:Sleep()
    self:SetUpTripMine( data.HitNormal:GetNormal() * -1 )
end

function ENT:SetUpTripMine( forward )
    self.Setup = true
    self:SetAngles( forward:Angle() + Angle( 90, 0, 0 ) )
    self:EmitSound( self.StickSound[ math.random( 1, #self.StickSound ) ] )
end

function ENT:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end

-- -----------------------------------------------------------------------
-- Kids / parent chain (daisy-chained detonation)
-- -----------------------------------------------------------------------
ENT.Kids      = {}
ENT.Exploding = false

function ENT:OnTakeDamage( dmgInfo )
    if IsValid( self.ClayParent ) then
        self.ClayParent:TakeDamage( 1, dmgInfo:GetAttacker(), dmgInfo:GetInflictor() )
    else
        if table.HasValue( self.Kids, dmgInfo:GetInflictor() ) or self.Exploding then return end
        self.Exploding = true
        for _, kid in pairs( self.Kids ) do
            if IsValid( kid ) then kid:Explode() end
        end
        self:Explode()
    end
end

-- -----------------------------------------------------------------------
-- Explode — directional dot-product blast (unchanged from rebel_claymore_ent)
-- -----------------------------------------------------------------------
function ENT:Explode()
    if self:GetNWBool( "exploded" ) == true then return end
    self:SetNWBool( "exploded", true )
    self.Exploded = true
    if not IsValid( self ) then return end

    self:EmitSound( "ambient/explosions/explode_4.wav" )

    -- env_explosion visual
    local detonate = ents.Create( "env_explosion" )
    detonate:SetPos( self:GetPos() )
    detonate:SetKeyValue( "iMagnitude",      "0" )
    detonate:SetKeyValue( "iRadiusOverride", "300" )
    detonate:Spawn()
    detonate:Activate()
    detonate:Fire( "Explode", "", 0 )

    local radius        = GetConVar( "Claymore_Radius" ):GetInt()
    local startDistance = GetConVar( "Claymore_DamageStartDistance" ):GetInt()
    local startDamage   = GetConVar( "Claymore_DamageStart" ):GetInt()
    local endDamage     = GetConVar( "Claymore_DamageEnd" ):GetInt()
    local forward       = self:GetRight() * -1   -- lethal arc direction

    for _, ent in pairs( ents.FindInSphere( self:GetPos(), radius ) ) do

        -- Faction gate — Combine and non-rebel NPCs take zero damage
        if not self:IsTarget( ent ) then continue end

        local direction  = ( ent:GetPos() - self:GetPos() ):GetNormalized()
        local dotProduct = forward:Dot( direction )

        if dotProduct > 0 then   -- only damage entities in forward arc
            local distance = ent:GetPos():Distance( self:GetPos() )
            local alpha    = math.Clamp( ( distance - startDistance ) / ( radius - startDistance ), 0, 1 )
            local damage   = Lerp( alpha, startDamage, endDamage )
            if distance < startDistance then damage = startDamage end

            ent:TakeDamage( damage )

            if ent:GetClass() == "prop_physics" and IsValid( ent:GetPhysicsObject() ) then
                ent:GetPhysicsObject():ApplyForceCenter( direction * 500 )
            end
        end
    end

    -- Screen shake
    local shake = ents.Create( "env_shake" )
    shake:SetPos( self:GetPos() )
    shake:SetKeyValue( "amplitude",  "2000" )
    shake:SetKeyValue( "radius",     "400" )
    shake:SetKeyValue( "duration",   "2.5" )
    shake:SetKeyValue( "frequency",  "255" )
    shake:SetKeyValue( "spawnflags", "4" )
    shake:Spawn()
    shake:Activate()
    shake:Fire( "StartShake", "", 0 )

    self:Remove()
end

-- -----------------------------------------------------------------------
-- Use — pickup (OPEN TO ANY PLAYER — no SteamID ownership gate)
--
-- Returns the "rebel_claymore" SWEP (ENT.WeaponClass) to the player,
-- matching the behaviour of the player-placed rebel_claymore_ent.
-- -----------------------------------------------------------------------
ENT.CanUse = true

function ENT:Use( activator, caller )
    if not activator:IsPlayer() then return end
    if not self.CanUse then return end

    self.CanUse = false

    if SERVER then
        -- Give the rebel_claymore SWEP back to whoever picks it up.
        if activator:HasWeapon( self.WeaponClass ) then
            -- Already carrying one — just refund the ammo
            activator:GiveAmmo( 1, "Slam", true )
        else
            activator:Give( self.WeaponClass )
            activator:SelectWeapon( self.WeaponClass )
            -- Give 1 slam round (the weapon's DefaultClip is 3; Give() starts at 0)
            activator:GiveAmmo( 1, "Slam", true )
        end
        self:Remove()
    end
end

-- -----------------------------------------------------------------------
-- Prevent physgun pickup
-- -----------------------------------------------------------------------
function ENT:PhysgunPickup( ply, ent )
    if ent:GetClass() == self:GetClass() then return false end
end

hook.Add( "PhysgunPickup", "StopNPCClayPhysgun", function( ply, ent )
    if IsValid( ent ) and ent.PhysgunPickup then
        return ent:PhysgunPickup( ply, ent )
    end
end )
