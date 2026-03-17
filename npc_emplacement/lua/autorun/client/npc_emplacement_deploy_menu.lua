-- ============================================================
--  NPC Emplacement Deploy  |  npc_emplacement_deploy_menu.lua
--  Client-side Options menu panel.
--
--  Registers under the shared "Bombin Addons" category inside
--  the Options tab of the spawnmenu, alongside the throw addons.
-- ============================================================

if SERVER then return end

local ADDON_CATEGORY = "Bombin Addons"

-- ============================================================
--  Register the category (safe no-op if it already exists)
-- ============================================================
hook.Add("AddToolMenuCategories", "NPCEmplaceDeploy_AddCategory", function()
    spawnmenu.AddToolMenuCategory(ADDON_CATEGORY)
end)

-- ============================================================
--  Build the panel
-- ============================================================
hook.Add("PopulateToolMenu", "NPCEmplaceDeploy_PopulateMenu", function()
    spawnmenu.AddToolMenuOption(
        "Options",                        -- tab
        ADDON_CATEGORY,                   -- category
        "npc_emplacement_deploy_settings",-- unique class key
        "NPC Emplacement Deploy",         -- display name
        "",
        "",
        function(panel)

            panel:ClearControls()

            -- ------------------------------------------------
            --  Header
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "NPC Emplacement Deploy Settings",
                Height      = "40",
            })

            panel:CheckBox("Enable NPC Emplacement Deployment", "npc_emplace_deploy_enabled")
            panel:ControlHelp("  Master on/off switch for the entire addon.")

            panel:CheckBox("Debug Announce in Console", "npc_emplace_deploy_announce")
            panel:ControlHelp("  Print a console message each time an NPC deploys.")

            panel:AddControl("Label", { Text = "" })    -- spacer

            -- ------------------------------------------------
            --  Probability & timing
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Probability & Timing",
                Height      = "30",
            })

            panel:NumSlider("Deploy Chance",
                "npc_emplace_deploy_chance", 0, 1, 2)
            panel:ControlHelp("  Probability (0.00 – 1.00) that an eligible NPC deploys\n  an emplacement each time it is checked.  Default: 0.15")

            panel:NumSlider("Check Interval (seconds)",
                "npc_emplace_deploy_interval", 1, 60, 0)
            panel:ControlHelp("  How many seconds between deploy-eligibility checks\n  for each individual NPC.  Default: 10")

            panel:NumSlider("Deploy Cooldown (seconds)",
                "npc_emplace_deploy_cooldown", 5, 120, 0)
            panel:ControlHelp("  Minimum seconds between deployments for the same NPC.\n  Default: 40")

            panel:AddControl("Label", { Text = "" })    -- spacer

            -- ------------------------------------------------
            --  Placement
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Emplacement Placement",
                Height      = "30",
            })

            panel:NumSlider("Forward Placement Distance (units)",
                "npc_emplace_deploy_dist", 30, 200, 0)
            panel:ControlHelp("  How far in front of the NPC the emplacement is planted.\n  Default: 80")

            panel:NumSlider("Max Emplacements at Once",
                "npc_emplace_deploy_max_total", 0, 20, 0)
            panel:ControlHelp("  Global cap on how many deployed emplacements can exist\n  at once.  0 = unlimited.  Default: 6")

            panel:AddControl("Label", { Text = "" })    -- spacer

            -- ------------------------------------------------
            --  Engagement range
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Engagement Range",
                Height      = "30",
            })

            panel:NumSlider("Max Distance",
                "npc_emplace_deploy_max_dist", 200, 6000, 0)
            panel:ControlHelp("  NPCs will not deploy if the player is farther than\n  this many units away.  Default: 1800")

            panel:NumSlider("Min Distance",
                "npc_emplace_deploy_min_dist", 0, 600, 0)
            panel:ControlHelp("  NPCs will not deploy if the player is closer than\n  this many units.  Default: 200")

            panel:AddControl("Label", { Text = "" })    -- spacer

            -- ------------------------------------------------
            --  Info footer
            -- ------------------------------------------------
            panel:ControlHelp("  The emplacement is spawned frozen (MOVETYPE_NONE)\n  and faces the direction the NPC was looking.\n  NPC movement is paused for the animation duration\n  then automatically released.")

        end
    )
end)
