-- ============================================================
--  NPC Claymore Deploy  |  npc_claymore_deploy.lua
--  Server-side only.
--
--  Combine soldiers, metrocops, and elites periodically have a
--  chance to crouch, play a planting gesture, and place a frozen
--  npc_deploy_claymore_ent on the ground directly in front of them.
--
--  The claymore targets REBELS and PLAYERS only — Combine NPCs
--  walking past their own mines are completely safe.
--
--  Behaviour:
--    1. (Immediate)  NPC plays ACT_COVER_LOW gesture (crouching
--       planting motion) and ACT_RELOAD gesture as a fallback.
--       The NPC briefly idles in a crouch schedule so the animation
--       reads as deliberate.
--    2. (1.5 s later) npc_deploy_claymore_ent spawns in front of
--       the NPC, frozen in place, facing the NPC's forward direction.
--    3. NPC AI scheduler is released back to normal.
--
--  The claymore can be picked up by any player.  On pickup the
--  player receives the "rebel_claymore" SWEP + 1 slam ammo.
-- ============================================================

if CLIENT then return end   -- server only

-- ============================================================
--  ConVars
-- ============================================================
local SHARED_FLAGS = bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY )

local cv_enabled    = CreateConVar( "npc_clay_deploy_enabled",    "1",    SHARED_FLAGS, "Enable/disable NPC claymore deployment." )
local cv_chance     = CreateConVar( "npc_clay_deploy_chance",     "0.15", SHARED_FLAGS, "Probability (0–1) that an eligible NPC plants a claymore each check." )
local cv_interval   = CreateConVar( "npc_clay_deploy_interval",   "10",   SHARED_FLAGS, "Seconds between deploy-eligibility checks per NPC." )
local cv_cooldown   = CreateConVar( "npc_clay_deploy_cooldown",   "40",   SHARED_FLAGS, "Minimum seconds between deployments for the same NPC." )
local cv_place_dist = CreateConVar( "npc_clay_deploy_dist",       "60",   SHARED_FLAGS, "Forward distance from the NPC to place the claymore (units)." )
local cv_max_dist   = CreateConVar( "npc_clay_deploy_max_dist",   "1800", SHARED_FLAGS, "Max distance to enemy player for a deployment to be attempted." )
local cv_min_dist   = CreateConVar( "npc_clay_deploy_min_dist",   "200",  SHARED_FLAGS, "Min distance to enemy player (no deploy if closer than this)." )
local cv_max_total  = CreateConVar( "npc_clay_deploy_max_total",  "8",    SHARED_FLAGS, "Max number of NPC-deployed claymores allowed at once (0 = unlimited)." )
local cv_announce   = CreateConVar( "npc_clay_deploy_announce",   "0",    SHARED_FLAGS, "Print a debug message to console each time an NPC plants a claymore." )

-- ============================================================
--  NPC whitelist — same Combine classes as the emplacement addon
-- ============================================================
local DEPLOY_NPCS = {
    ["npc_combine_s"]     = true,   -- Combine Soldier
    ["npc_metropolice"]   = true,   -- Metrocop
    ["npc_combine_elite"] = true,   -- Combine Elite
}

local function IsEligibleDeployer( npc )
    if not IsValid( npc ) or not npc:IsNPC() then return false end
    return DEPLOY_NPCS[ npc:GetClass() ] == true
end

-- ============================================================
--  Live claymore count tracking (weak refs, pruned each call)
-- ============================================================
local SpawnedClaymores = {}

local function CountLiveClaymores()
    local count = 0
    local alive = {}
    for _, ent in ipairs( SpawnedClaymores ) do
        if IsValid( ent ) then
            count = count + 1
            alive[ #alive + 1 ] = ent
        end
    end
    SpawnedClaymores = alive
    return count
end

-- ============================================================
--  Ground-snap helper (identical to emplacement addon)
-- ============================================================
local function SnapToGround( pos, filter )
    local tr = util.TraceLine({
        start  = Vector( pos.x, pos.y, pos.z + 72 ),
        endpos = Vector( pos.x, pos.y, pos.z - 256 ),
        filter = filter,
        mask   = MASK_SOLID,
    })
    return tr.Hit and tr.HitPos or pos
end

-- ============================================================
--  Animation helper
--  Tries a prioritised list of actions / gestures; uses the
--  first one the model actually supports.  This handles the
--  differences between soldier, metrocop, and elite rigs.
-- ============================================================
local PLANT_GESTURES = {
    ACT_COVER_LOW,      -- crouch/cover — best visual for "planting"
    ACT_RELOAD,         -- reload gesture — good fallback
    ACT_RANGE_ATTACK2,  -- secondary fire gesture
}

local function PlayPlantAnimation( npc )
    -- Try gestures in order; AddGesture returns -1 if unsupported.
    for _, act in ipairs( PLANT_GESTURES ) do
        local seq = npc:SelectWeightedSequence( act )
        if seq and seq > 0 then
            npc:AddGesture( act )
            break
        end
    end

    -- Additionally push the NPC into a crouching idle so it visibly
    -- stoops rather than just standing and waving its hands.
    -- SCHED_IDLE_WALK_CROUCH_AWAY is a safe schedule present on all
    -- three NPC types; fall back to SCHED_IDLE_STAND if missing.
    local crouchSched = SCHED_COWER   -- available on all Combine
    if npc:SelectWeightedSequence( ACT_COWER ) and
       npc:SelectWeightedSequence( ACT_COWER ) > 0 then
        npc:SetSchedule( SCHED_COWER )
    else
        npc:SetSchedule( SCHED_IDLE_STAND )
    end
end

-- ============================================================
--  Core deploy function
-- ============================================================

---@param npc Entity  The Combine NPC doing the planting.
local function DeployClaymore( npc )

    -- Stamp cooldown immediately to block double-queuing
    npc.__clay_lastDeploy = CurTime()

    -- Snapshot position and forward direction NOW (before the NPC moves)
    -- The claymore must face the direction the NPC was looking, not where
    -- it drifts to during the 1.5-second animation window.
    local forwardDir = npc:GetForward()
    forwardDir.z = 0          -- keep horizontal — never plant on a ceiling
    forwardDir:Normalize()

    local npcPos    = npc:GetPos()
    local npcAngles = npc:GetAngles()    -- snapshotted for correct facing

    if cv_announce:GetBool() then
        print( string.format( "[NPC Claymore Deploy] %s beginning plant animation.", npc:GetClass() ) )
    end

    -- Play animation immediately
    PlayPlantAnimation( npc )

    -- --------------------------------------------------------
    --  1.5 seconds later: spawn the claymore and release AI.
    --  Matches the mid-point of ACT_COVER_LOW where the NPC's
    --  hands reach the ground — sells the visual illusion.
    -- --------------------------------------------------------
    timer.Simple( 1.5, function()
        if not IsValid( npc ) then return end

        local placeDist = cv_place_dist:GetFloat()

        -- ---- Find spawn position ----
        local spawnPos = npcPos + forwardDir * placeDist

        -- Pull back if there's a wall in the way
        local wallTr = util.TraceLine({
            start  = npcPos   + Vector( 0, 0, 20 ),
            endpos = spawnPos + Vector( 0, 0, 20 ),
            filter = { npc },
            mask   = MASK_SOLID_BRUSHONLY,
        })
        if wallTr.Hit then
            spawnPos = npcPos + forwardDir * ( wallTr.Fraction * placeDist * 0.80 )
        end

        -- Snap to ground surface
        spawnPos = SnapToGround( spawnPos, { npc } )

        -- ---- Facing angle ----
        -- The claymore model's "sensor forward" direction is GetRight() * -1
        -- (same offset the player SWEP uses: owner:GetAngles() + Angle(0,-90,0)).
        -- Applying the same -90 yaw offset to the NPC's snapshotted angle ensures
        -- the sensor arc faces the same direction the NPC was looking when it
        -- planted — i.e. toward the enemy.
        local faceAngle   = npcAngles + Angle( 0, -90, 0 )
        faceAngle.p       = 0   -- pitch zeroed — claymore sits flat
        faceAngle.r       = 0   -- roll zeroed

        -- ---- Create the entity ----
        local clay = ents.Create( "npc_deploy_claymore_ent" )
        if not IsValid( clay ) then
            if cv_announce:GetBool() then
                print( "[NPC Claymore Deploy] ERROR: could not create npc_deploy_claymore_ent." )
            end
            npc:SetSchedule( SCHED_IDLE_STAND )
            return
        end

        clay:SetPos( spawnPos )
        clay:SetAngles( faceAngle )
        clay:Spawn()
        clay:Activate()

        -- Freeze physics immediately — claymore must not slide or fall through
        clay:SetMoveType( MOVETYPE_NONE )
        local phys = clay:GetPhysicsObject()
        if IsValid( phys ) then
            phys:EnableMotion( false )
            phys:Sleep()
        end

        clay:EmitSound( "hoff/mpl/seal_claymore/plant.wav" )

        -- Track for global cap
        SpawnedClaymores[ #SpawnedClaymores + 1 ] = clay

        if cv_announce:GetBool() then
            print( string.format( "[NPC Claymore Deploy] %s planted claymore at %s (facing yaw %.1f).",
                npc:GetClass(), tostring( spawnPos ), faceAngle.y ) )
        end

        -- Release NPC back to its normal AI
        npc:SetSchedule( SCHED_IDLE_STAND )

    end )   -- end timer.Simple
end

-- ============================================================
--  Per-NPC state (lazy init)
-- ============================================================
local function InitNPCState( npc )
    if not IsValid( npc ) then return end
    if npc.__clay_hooked then return end
    npc.__clay_hooked     = true
    npc.__clay_nextCheck  = CurTime() + math.Rand( 2, cv_interval:GetFloat() )
    npc.__clay_lastDeploy = 0
end

-- ============================================================
--  Main Think loop — polls every 0.5 s, mirrors emplacement addon
-- ============================================================
timer.Create( "NPCClayDeploy_Think", 0.5, 0, function()
    if not cv_enabled:GetBool() then return end

    local now      = CurTime()
    local interval = cv_interval:GetFloat()
    local cooldown = cv_cooldown:GetFloat()
    local chance   = cv_chance:GetFloat()
    local maxDist  = cv_max_dist:GetFloat()
    local minDist  = cv_min_dist:GetFloat()
    local maxTotal = cv_max_total:GetInt()

    -- Global cap (0 = unlimited)
    if maxTotal > 0 and CountLiveClaymores() >= maxTotal then return end

    for _, npc in ipairs( ents.GetAll() ) do
        if not IsValid( npc ) or not npc:IsNPC() then continue end
        if not IsEligibleDeployer( npc ) then continue end

        InitNPCState( npc )

        -- Time gate
        if now < ( npc.__clay_nextCheck or 0 ) then continue end
        npc.__clay_nextCheck = now + interval + math.Rand( -1, 1 )

        -- Cooldown gate
        if now - ( npc.__clay_lastDeploy or 0 ) < cooldown then continue end

        -- NPC must be alive and targeting a player
        if npc:Health() <= 0 then continue end
        local enemy = npc:GetEnemy()
        if not IsValid( enemy ) or not enemy:IsPlayer() then continue end
        if not enemy:Alive() then continue end

        -- Distance check
        local dist = npc:GetPos():Distance( enemy:GetPos() )
        if dist > maxDist or dist < minDist then continue end

        -- Line-of-sight check (relaxed to 0.85 fraction, same as emplacement addon)
        local losTr = util.TraceLine({
            start  = npc:EyePos(),
            endpos = enemy:EyePos(),
            filter = { npc },
            mask   = MASK_SOLID,
        })
        if losTr.Entity ~= enemy and losTr.Fraction < 0.85 then continue end

        -- Probability roll
        if math.random() > chance then continue end

        -- All checks passed — plant!
        DeployClaymore( npc )
    end
end )

-- ============================================================
--  Startup message
-- ============================================================
hook.Add( "InitPostEntity", "NPCClayDeploy_Init", function()
    print( "[NPC Claymore Deploy] Addon loaded." )
    print( "[NPC Claymore Deploy] Use 'npc_clay_deploy_*' convars to configure." )
end )
