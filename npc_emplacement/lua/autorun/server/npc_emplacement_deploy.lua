-- ============================================================
--  NPC Emplacement Deploy  |  npc_emplacement_deploy.lua
--  Server-side only.
--
--  Combine soldiers, metrocops, and elites periodically have a
--  chance to play a turret-deploy animation and place a frozen
--  manned emplacement (npc_manned_emplacement) on the ground
--  directly in front of them.
--
--  Behaviour:
--    1. (Immediate)  NPC stops moving and plays ACT_DEPLOY.
--    2. (1.5s later) npc_manned_emplacement spawns in front of
--       the NPC, frozen in place via MOVETYPE_NONE so it cannot
--       be pushed or fall through the ground.
--    3. NPC movement/AI is released back to the scheduler.
--
--  The emplacement has no velocity or throw logic – it is
--  planted as a static defensive barrier.
-- ============================================================

if CLIENT then return end   -- server only

-- ============================================================
--  ConVars
-- ============================================================
local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

local cv_enabled      = CreateConVar("npc_emplace_deploy_enabled",    "1",    SHARED_FLAGS, "Enable/disable NPC emplacement deployment.")
local cv_chance       = CreateConVar("npc_emplace_deploy_chance",     "0.15", SHARED_FLAGS, "Probability (0–1) that an eligible NPC deploys an emplacement each check.")
local cv_interval     = CreateConVar("npc_emplace_deploy_interval",   "10",   SHARED_FLAGS, "Seconds between deploy-eligibility checks per NPC.")
local cv_cooldown     = CreateConVar("npc_emplace_deploy_cooldown",   "40",   SHARED_FLAGS, "Minimum seconds between deployments for the same NPC.")
local cv_place_dist   = CreateConVar("npc_emplace_deploy_dist",       "80",   SHARED_FLAGS, "Forward distance from the NPC to place the emplacement (units).")
local cv_max_dist     = CreateConVar("npc_emplace_deploy_max_dist",   "1800", SHARED_FLAGS, "Max distance to player for a deployment to be attempted.")
local cv_min_dist     = CreateConVar("npc_emplace_deploy_min_dist",   "200",  SHARED_FLAGS, "Min distance to player (no deploy if closer than this).")
local cv_max_emplace  = CreateConVar("npc_emplace_deploy_max_total",  "6",    SHARED_FLAGS, "Maximum number of deployed emplacements allowed at once (0 = unlimited).")
local cv_announce     = CreateConVar("npc_emplace_deploy_announce",   "0",    SHARED_FLAGS, "Print a debug message to console each time an NPC deploys.")

-- ============================================================
--  NPC whitelist
-- ============================================================

local DEPLOY_NPCS = {
    ["npc_combine_s"]     = true,   -- Combine Soldier
    ["npc_metropolice"]   = true,   -- Metrocop
    ["npc_combine_elite"] = true,   -- Combine Elite
}

local function IsEligibleDeployer(npc)
    if not IsValid(npc) or not npc:IsNPC() then return false end
    return DEPLOY_NPCS[npc:GetClass()] == true
end

-- ============================================================
--  Emplacement count tracking
-- ============================================================

-- We keep a simple table of weak references so we can count
-- how many emplacements this addon has spawned are still alive.
local SpawnedEmplacements = {}

local function CountLiveEmplacements()
    local count = 0
    local alive = {}
    for _, ent in ipairs(SpawnedEmplacements) do
        if IsValid(ent) then
            count = count + 1
            alive[#alive + 1] = ent
        end
    end
    SpawnedEmplacements = alive   -- prune dead refs
    return count
end

-- ============================================================
--  Ground trace helper
-- ============================================================

--- Traces straight down from well above 'pos' to find the floor.
--- Uses MASK_SOLID so displacement surfaces and prop floors are caught,
--- not just world brushes.  Returns the raw surface hit position with
--- no extra vertical offset – callers apply their own model-specific lift.
local function SnapToGround(pos, filter)
    local tr = util.TraceLine({
        start  = Vector(pos.x, pos.y, pos.z + 72),
        endpos = Vector(pos.x, pos.y, pos.z - 256),
        filter = filter,
        mask   = MASK_SOLID,
    })
    if tr.Hit then
        return tr.HitPos
    end
    return pos
end

-- ============================================================
--  Core deploy function
-- ============================================================

--- Triggers the deploy sequence:
---   Step 1 (immediate)  – stop NPC movement, play ACT_DEPLOY.
---   Step 2 (1.5s later) – spawn frozen emplacement, resume AI.
---@param npc Entity  The deploying NPC.
local function DeployEmplacement(npc)

    do
        local seq = npc:SelectWeightedSequence(ACT_COVER_LOW)
        if seq > 0 then
            npc:AddGesture(ACT_COVER_LOW)
        end
    end

    -- Stamp cooldown immediately – prevents a second deploy
    -- being queued during the 1.5-second animation window.
    npc.__emplace_lastDeploy = CurTime()

    -- Snapshot forward direction and position now so the
    -- emplacement lands where the NPC was *looking* when they
    -- started the animation, not where they drifted to.
    local forwardDir = npc:GetForward()
    forwardDir.z     = 0          -- keep horizontal – never plant on a ceiling
    forwardDir:Normalize()

    local npcPos     = npc:GetPos()
    local placeDist  = cv_place_dist:GetFloat()

    if cv_announce:GetBool() then
        print(string.format("[NPC Emplacement Deploy] %s beginning deploy animation.", npc:GetClass()))
    end

    -- --------------------------------------------------------
    --  STEP 2 (1.5 seconds later): spawn the emplacement and
    --  release the NPC back to its AI scheduler.
    --
    --  1.5 s matches roughly the mid-point of the ACT_DEPLOY
    --  animation where the hands reach the ground, giving the
    --  visual impression the NPC physically placed the turret.
    -- --------------------------------------------------------
    timer.Simple(1.5, function()

        -- Abort safely if the NPC was killed during the animation.
        if not IsValid(npc) then return end

        -- ---- Determine spawn position ----
        -- Project forward from where the NPC was standing,
        -- then snap the result down to the ground surface.
        local spawnPos = npcPos + forwardDir * placeDist

        -- Trace forward from waist height to check for walls;
        -- if something is in the way, pull the position back
        -- so the emplacement doesn't clip into geometry.
        local wallTr = util.TraceLine({
            start  = npcPos + Vector(0, 0, 36),
            endpos = spawnPos + Vector(0, 0, 36),
            filter = { npc },
            mask   = MASK_SOLID_BRUSHONLY,
        })
        if wallTr.Hit then
            -- Land just short of the obstruction
            spawnPos = npcPos + forwardDir * (wallTr.Fraction * placeDist * 0.80)
        end

        spawnPos = SnapToGround(spawnPos, { npc })

        -- The barricade model's origin sits at its centre-mass, not its
        -- Spawn the barricade above the snapped position, then call
        -- DropToFloor so the engine settles it using its actual collision
        -- mesh.  This is always correct regardless of model origin offset,
        -- trace surface type, or terrain slope – no hardcoded value needed.
        spawnPos = spawnPos + Vector(0, 0, 72)

        -- Facing angle: NPC's forward direction, pitch and roll zeroed.
        local faceAngle = forwardDir:Angle()
        faceAngle.p = 0
        faceAngle.r = 0

        -- ---- Spawn the barricade base ----
        local barricade = ents.Create("prop_physics")
        if not IsValid(barricade) then
            if cv_announce:GetBool() then
                print("[NPC Emplacement Deploy] ERROR: could not create barricade prop.")
            end
            npc:SetSchedule(SCHED_IDLE_STAND)
            return
        end

        barricade:SetModel("models/props_combine/combine_barricade_short01a.mdl")
        barricade:SetPos(spawnPos)
        barricade:SetAngles(faceAngle)
        barricade:Spawn()
        barricade:Activate()

        -- Let the engine drop the barricade onto the floor surface using
        -- its collision mesh.  Must happen BEFORE freezing physics so the
        -- engine is still allowed to reposition the entity.
        barricade:DropToFloor()

        -- Freeze after DropToFloor has settled the position.
        local bPhys = barricade:GetPhysicsObject()
        if IsValid(bPhys) then
            bPhys:EnableMotion(false)
            bPhys:Sleep()
        end

        -- ---- Spawn the emplacement and attach it to the barricade ----
        local emplacement = ents.Create("npc_manned_emplacement")
        if not IsValid(emplacement) then
            if cv_announce:GetBool() then
                print("[NPC Emplacement Deploy] ERROR: npc_manned_emplacement could not be created.")
            end
            barricade:Remove()
            npc:SetSchedule(SCHED_IDLE_STAND)
            return
        end

        emplacement:Spawn()
        emplacement:Activate()

        -- AttachToBarricade positions the gun relative to the barricade
        -- and calls SetParent so both move together.  This is the same
        -- call the entity's own SpawnFunction uses.
        emplacement:AttachToBarricade(barricade)

        -- Track both so the global cap counts the full installation.
        SpawnedEmplacements[#SpawnedEmplacements + 1] = emplacement
        SpawnedEmplacements[#SpawnedEmplacements + 1] = barricade

        if cv_announce:GetBool() then
            print(string.format("[NPC Emplacement Deploy] %s placed npc_manned_emplacement at %s.",
                npc:GetClass(), tostring(spawnPos)))
        end

    end)  -- end timer.Simple

end

-- ============================================================
--  Per-NPC state initialisation (lazy)
-- ============================================================

local function InitNPCState(npc)
    if not IsValid(npc) then return end
    if npc.__emplace_hooked then return end
    npc.__emplace_hooked      = true
    npc.__emplace_nextCheck   = CurTime() + math.Rand(2, cv_interval:GetFloat())
    npc.__emplace_lastDeploy  = 0
end

-- ============================================================
--  Main Think loop  (timer-based, avoids per-frame iteration)
-- ============================================================

timer.Create("NPCEmplaceDeploy_Think", 0.5, 0, function()
    if not cv_enabled:GetBool() then return end

    local now      = CurTime()
    local interval = cv_interval:GetFloat()
    local cooldown = cv_cooldown:GetFloat()
    local chance   = cv_chance:GetFloat()
    local maxDist  = cv_max_dist:GetFloat()
    local minDist  = cv_min_dist:GetFloat()
    local maxTotal = cv_max_emplace:GetInt()

    -- Global cap check (0 = unlimited)
    if maxTotal > 0 and CountLiveEmplacements() >= maxTotal then return end

    for _, npc in ipairs(ents.GetAll()) do
        if not IsValid(npc) or not npc:IsNPC() then continue end
        if not IsEligibleDeployer(npc) then continue end

        -- Lazy state initialisation
        InitNPCState(npc)

        -- Time gate
        if now < (npc.__emplace_nextCheck or 0) then continue end
        npc.__emplace_nextCheck = now + interval + math.Rand(-1, 1)

        -- Cooldown gate
        if now - (npc.__emplace_lastDeploy or 0) < cooldown then continue end

        -- NPC must be alive and targeting a player
        if npc:Health() <= 0 then continue end
        local enemy = npc:GetEnemy()
        if not IsValid(enemy) or not enemy:IsPlayer() then continue end
        if not enemy:Alive() then continue end

        -- Distance check
        local dist = npc:GetPos():Distance(enemy:GetPos())
        if dist > maxDist or dist < minDist then continue end

        -- Line-of-sight check
        local losTr = util.TraceLine({
            start  = npc:EyePos(),
            endpos = enemy:EyePos(),
            filter = { npc },
            mask   = MASK_SOLID,
        })
        if losTr.Entity ~= enemy and losTr.Fraction < 0.85 then continue end

        -- Probability roll
        if math.random() > chance then continue end

        -- All checks passed – deploy!
        DeployEmplacement(npc)
    end
end)

-- ============================================================
--  Startup message
-- ============================================================

hook.Add("InitPostEntity", "NPCEmplaceDeploy_Init", function()
    print("[NPC Emplacement Deploy] Addon loaded.")
    print("[NPC Emplacement Deploy] Use 'npc_emplace_deploy_*' convars to configure.")
end)
