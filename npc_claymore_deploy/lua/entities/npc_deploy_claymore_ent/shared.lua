--[[
    npc_deploy_claymore_ent / shared.lua

    Entity bundled inside the NPC Claymore Deploy addon.
    Behaviour is identical to rebel_claymore_ent with two differences:
      1. WeaponClass = "seal6-claymore-bo2"  →  pickup returns the BO2 SWEP.
      2. Any player can pick this up (no SteamID ownership check) because
         it was placed by an NPC, not by a specific player.

    TARGETING RULES
    ===============
    TRIGGERS  → human players + rebel/citizen NPCs  (TargetClasses)
    SAFE      → ALL Combine NPCs and anything not listed
--]]

ENT.Type            = "anim"
ENT.Base            = "base_gmodentity"
ENT.PrintName       = "Rebel Claymore (NPC)"
ENT.Author          = ""
ENT.Category        = ""
ENT.Spawnable       = false
ENT.AdminSpawnable  = false

-- SWEP given to the player on pickup — the original BO2 claymore weapon.
ENT.WeaponClass = "seal6-claymore-bo2"

-- -----------------------------------------------------------------------
-- Faction whitelist — only these NPC classes (plus players) trigger it.
-- Combine soldiers, police, manhacks, striders, etc. are NOT listed.
-- -----------------------------------------------------------------------
ENT.TargetClasses = {
    ["npc_rebel"]       = true,
    ["npc_citizen"]     = true,
    ["npc_alyx"]        = true,
    ["npc_barney"]      = true,
    ["npc_fisherman"]   = true,
    ["npc_gman"]        = true,
}

-- -----------------------------------------------------------------------
-- ConVars (re-use the same ones from rebel_claymore_ent if both addons
-- are loaded at the same time — safe because CreateConVar is idempotent
-- when FCVAR_REPLICATED is set and the value already exists).
-- -----------------------------------------------------------------------
hook.Add( "Initialize", "CreateNPCClayConvars", function()

    if not ConVarExists( "Claymore_OwnerTrigger" ) then
        CreateConVar( "Claymore_OwnerTrigger", 0, { FCVAR_REPLICATED, FCVAR_ARCHIVE },
            "Should Claymores get triggered by their owner?" )
    end
    if not ConVarExists( "Claymore_Infinite" ) then
        CreateConVar( "Claymore_Infinite", 0, { FCVAR_REPLICATED, FCVAR_ARCHIVE },
            "Infinite claymores? 1 = yes" )
    end
    if not ConVarExists( "Claymore_Radius" ) then
        CreateConVar( "Claymore_Radius", 255, { FCVAR_REPLICATED, FCVAR_ARCHIVE },
            "Blast radius in units." )
    end
    if not ConVarExists( "Claymore_DamageStart" ) then
        CreateConVar( "Claymore_DamageStart", 100, { FCVAR_REPLICATED, FCVAR_ARCHIVE },
            "Maximum damage (point-blank)." )
    end
    if not ConVarExists( "Claymore_DamageStartDistance" ) then
        CreateConVar( "Claymore_DamageStartDistance", 170, { FCVAR_REPLICATED, FCVAR_ARCHIVE },
            "Distance at which damage starts falling off." )
    end
    if not ConVarExists( "Claymore_DamageEnd" ) then
        CreateConVar( "Claymore_DamageEnd", 25, { FCVAR_REPLICATED, FCVAR_ARCHIVE },
            "Minimum damage at blast edge." )
    end
    -- Detection range: controls the TraceHull box half-extents.
    -- Default 30 matches the original claymore sensor size.
    if not ConVarExists( "Claymore_DetectRange" ) then
        CreateConVar( "Claymore_DetectRange", 30, { FCVAR_REPLICATED, FCVAR_ARCHIVE },
            "Half-size of the claymore sensor hull (units). Default: 30" )
    end
    if not ConVarExists( "Claymore_DrawBeams" ) then
        CreateConVar( "Claymore_DrawBeams", 1, { FCVAR_REPLICATED, FCVAR_ARCHIVE },
            "Show laser beams. 1 = yes" )
    end
    if not ConVarExists( "Claymore_BeamStyle" ) then
        CreateConVar( "Claymore_BeamStyle", 1, { FCVAR_REPLICATED, FCVAR_ARCHIVE },
            "Beam style: 1 = quad sprites, 2 = simple lines." )
    end

end )
