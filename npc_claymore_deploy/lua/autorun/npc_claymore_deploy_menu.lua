-- ============================================================
--  NPC Claymore Deploy  |  npc_claymore_deploy_menu.lua
--  Client-side Options menu panel.
--
--  Registered under the shared "Bombin Addons" category inside
--  the Options tab of the spawnmenu — sits alongside the
--  NPC Emplacement Deploy panel in the same category.
-- ============================================================

if SERVER then return end

local ADDON_CATEGORY = "Bombin Addons"

-- ============================================================
--  Register the category (safe no-op if already registered
--  by the emplacement deploy addon or any other sibling)
-- ============================================================
hook.Add( "AddToolMenuCategories", "NPCClayDeploy_AddCategory", function()
    spawnmenu.AddToolMenuCategory( ADDON_CATEGORY )
end )

-- ============================================================
--  Build the panel
-- ============================================================
hook.Add( "PopulateToolMenu", "NPCClayDeploy_PopulateMenu", function()
    spawnmenu.AddToolMenuOption(
        "Options",                      -- tab
        ADDON_CATEGORY,                 -- category (shared with emplacement addon)
        "npc_claymore_deploy_settings", -- unique class key
        "NPC Claymore Deploy",          -- display name
        "",
        "",
        function( panel )

            panel:ClearControls()

            -- ------------------------------------------------
            --  Header
            -- ------------------------------------------------
            panel:AddControl( "Header", {
                Description = "NPC Claymore Deploy Settings",
                Height      = "40",
            })

            panel:CheckBox( "Enable NPC Claymore Deployment", "npc_clay_deploy_enabled" )
            panel:ControlHelp( "  Master on/off switch for this addon." )

            panel:CheckBox( "Debug Announce in Console", "npc_clay_deploy_announce" )
            panel:ControlHelp( "  Print a console line each time an NPC plants a claymore." )

            panel:AddControl( "Label", { Text = "" } )   -- spacer

            -- ------------------------------------------------
            --  Probability & timing
            -- ------------------------------------------------
            panel:AddControl( "Header", {
                Description = "Probability & Timing",
                Height      = "30",
            })

            panel:NumSlider( "Deploy Chance",
                "npc_clay_deploy_chance", 0, 1, 2 )
            panel:ControlHelp( "  Probability (0.00 – 1.00) that an eligible NPC plants\n  a claymore each time it is checked.  Default: 0.15" )

            panel:NumSlider( "Check Interval (seconds)",
                "npc_clay_deploy_interval", 1, 60, 0 )
            panel:ControlHelp( "  How many seconds between deploy-eligibility checks\n  per NPC.  Default: 10" )

            panel:NumSlider( "Deploy Cooldown (seconds)",
                "npc_clay_deploy_cooldown", 5, 120, 0 )
            panel:ControlHelp( "  Minimum seconds between claymore plants for the\n  same NPC.  Default: 40" )

            panel:AddControl( "Label", { Text = "" } )   -- spacer

            -- ------------------------------------------------
            --  Placement
            -- ------------------------------------------------
            panel:AddControl( "Header", {
                Description = "Claymore Placement",
                Height      = "30",
            })

            panel:NumSlider( "Forward Placement Distance (units)",
                "npc_clay_deploy_dist", 20, 200, 0 )
            panel:ControlHelp( "  How far in front of the NPC the claymore is planted.\n  Default: 60" )

            panel:NumSlider( "Max Claymores at Once",
                "npc_clay_deploy_max_total", 0, 30, 0 )
            panel:ControlHelp( "  Global cap on NPC-deployed claymores in the world\n  at once.  0 = unlimited.  Default: 8" )

            panel:AddControl( "Label", { Text = "" } )   -- spacer

            -- ------------------------------------------------
            --  Engagement range
            -- ------------------------------------------------
            panel:AddControl( "Header", {
                Description = "Engagement Range",
                Height      = "30",
            })

            panel:NumSlider( "Max Distance",
                "npc_clay_deploy_max_dist", 200, 6000, 0 )
            panel:ControlHelp( "  NPCs will not plant if the enemy player is farther\n  than this many units away.  Default: 1800" )

            panel:NumSlider( "Min Distance",
                "npc_clay_deploy_min_dist", 0, 600, 0 )
            panel:ControlHelp( "  NPCs will not plant if the enemy player is closer\n  than this many units.  Default: 200" )

            panel:AddControl( "Label", { Text = "" } )   -- spacer

            -- ------------------------------------------------
            --  Detection range
            -- ------------------------------------------------
            panel:AddControl( "Header", {
                Description = "Detection Range",
                Height      = "30",
            })

            panel:NumSlider( "Sensor Hull Size (units)",
                "Claymore_DetectRange", 5, 120, 0 )
            panel:ControlHelp( "  Half-size of the invisible detection box around\n  the claymore sensor.  Larger = easier to trigger.\n  Default: 30" )

            panel:AddControl( "Label", { Text = "" } )   -- spacer

            -- ------------------------------------------------
            --  Damage
            -- ------------------------------------------------
            panel:AddControl( "Header", {
                Description = "Damage",
                Height      = "30",
            })

            panel:NumSlider( "Max Damage (point-blank)",
                "Claymore_DamageStart", 1, 500, 0 )
            panel:ControlHelp( "  Damage dealt to targets at close range.\n  Default: 100" )

            panel:NumSlider( "Min Damage (blast edge)",
                "Claymore_DamageEnd", 1, 500, 0 )
            panel:ControlHelp( "  Damage dealt to targets at the edge of the blast.\n  Default: 25" )

            panel:NumSlider( "Falloff Start Distance (units)",
                "Claymore_DamageStartDistance", 10, 500, 0 )
            panel:ControlHelp( "  Distance from the claymore at which damage\n  begins to fall off toward Min Damage.  Default: 170" )

            panel:NumSlider( "Blast Radius (units)",
                "Claymore_Radius", 50, 1000, 0 )
            panel:ControlHelp( "  How far from the claymore the blast reaches.\n  Default: 255" )

            panel:AddControl( "Label", { Text = "" } )   -- spacer

            -- ------------------------------------------------
            --  Info footer
            -- ------------------------------------------------
            panel:ControlHelp(
                "  The claymore is planted frozen (MOVETYPE_NONE) and faces\n" ..
                "  the direction the NPC was looking when it started the\n"    ..
                "  planting animation.  Any player can pick it up — on pickup\n" ..
                "  the player receives the Rebel Claymore SWEP.\n\n"           ..
                "  Combine NPCs walking through their own claymores are safe.\n" ..
                "  Only rebels and human players trigger the mines."
            )

        end
    )
end )
