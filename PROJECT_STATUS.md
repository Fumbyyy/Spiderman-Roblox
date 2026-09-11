# Project Status & Session Handover
**Project:** Spider-Man: Web of Destiny (Roblox / Luau / Rojo)  
**Developer:** Rich (16-year-old solo indie dev, Indonesia)  
**Mentor Persona:** Ponytail (Senior Roblox Luau Developer & Technical Mentor)  
**Last Updated:** September 11, 2026 (Pre-Midterms Freeze)  
**Git Commit:** `af58ea3` (Synced with `origin/main`)

---

## 1. Engine & Gameplay State (Core Engine Frozen & Verified)
- **Swinging Physics:** Native physics via `VectorForce` + `AlignOrientation` + `SphereTrace` raycasting. Zero deprecated BodyMovers.
- **Traversal:** High-velocity release boosts, ceiling cling/drop, wall-run friction checks, and camera speed FOV scaling (70 to 95 FOV).
- **Web-Zip / Perch:** Accurate point targeting on ledge corners, roof crests, and street lamp finials.
- **Combat Mechanics:** 4-hit light combo string, aerial launcher uppercut, ground-pound slam, directional dodge with i-frames, and enemy hit-reaction ragdoll/stun.
- **Config Authority:** Centralized in `src/shared/GrappleConfig.luau`.

---

## 2. Complete 3D Asset Arsenal (39 Bespoke Production Models)
All assets authored in Blender 5.1 at **1 Blender Unit = 1 Roblox Stud** (5-stud avatar scale), identity transforms, convex-clean topology, zero degenerate faces, and strict triangle budgets (500–1,400 tris).

1. **`thug_weapons/` (5 assets):**
   - `baseball_bat.fbx` (4.2 studs)
   - `crowbar.fbx` (3.6 studs)
   - `combat_knife.fbx` (2.0 studs)
   - `handgun.fbx` (1.5 studs)
   - `riot_shield.fbx` (5.4 x 3.0 studs)
2. **`throwable_props/` (9 assets):**
   - `manhole_cover.fbx` (3.6x3.6 studs)
   - `trash_can.fbx` (4.2 studs, separable lid)
   - `wooden_crate.fbx` (4.8 studs)
   - `construction_barrel.fbx` (4.8 studs)
   - 5 Mailbox Variants: Classic USPS, Double Chute, Dented Combat, Green Relay, Vintage Pillar
3. **`rooftop_props/` (5 assets):**
   - `rooftop_water_tower.fbx` (16.4 studs tall, multi-story silhouette)
   - `hvac_air_conditioner.fbx` (6.3x3.9x4.1 studs, exhaust fan & louvers)
   - `fire_escape_balcony.fbx` (6.1x3.7x5.7 studs, drop ladder)
   - `nyc_fire_hydrant.fbx` (2.35 studs, chained dual caps)
   - `industrial_dumpster.fbx` (6.1x4.3x4.6 studs, lid ajar)
4. **`spidey_gadgets/` (5 assets):**
   - `web_shooter_bracer.fbx` (1.4x1.4x1.6 studs, forearm accessory)
   - `web_bomb_canister.fbx` (1.0x1.0x1.2 studs, impact web grenade)
   - `spider_tracer_dart.fbx` (0.8x0.8x0.2 studs, magnetic beacon)
   - `classic_pizza_box.fbx` (2.4x2.4x0.5 studs, collectible / heal)
   - `webbed_backpack.fbx` (1.8x1.4x2.2 studs, Peter Parker daypack)
5. **`thug_wearables/` (5 assets):**
   - `ballistic_hockey_mask.fbx` (804 tris, head face-front fit)
   - `thug_ski_mask.fbx` (888 tris, full balaclava)
   - `tactical_plate_carrier.fbx` (1,088 tris, torso ceramic vest)
   - `street_gang_beanie.fbx` (728 tris, slouchy knit cuff)
   - `spiked_arm_bracers.fbx` (1,064 tris combined, dual forearm cuffs)
6. **`street_props/` (5 assets):**
   - `nypd_sawhorse_barricade.fbx` (888 tris, A-frame hurdle/cover)
   - `nyc_street_lamp.fbx` (956 tris, 12.5 studs tall, perch finial)
   - `vintage_payphone_kiosk.fbx` (1,004 tris, acoustic hood curbside)
   - `traffic_hazard_cones.fbx` (616 tris, upright + knocked pair)
   - `electrical_hazard_box.fbx` (948 tris, web-pull combat hazard)
7. **`civilian_vehicles/` (5 assets):**
   - `nyc_yellow_taxi.fbx` (1,200 tris, 15.0 studs, roof ad-box)
   - `civilian_family_sedan.fbx` (1,124 tris, 14.5 studs, slate blue)
   - `civilian_pickup_truck.fbx` (1,284 tris, 16.0 studs, open ribbed bed)
   - `city_box_delivery_truck.fbx` (1,344 tris, 18.5 studs, parkour box)
   - `urban_compact_hatchback.fbx` (1,184 tris, 12.8 studs, crimson red)

---

## 3. Avatar / Suit Architecture Decision
- **No Skinned Mesh Suits via AI:** Procedural Python code cannot weight-paint deforming shoulder/elbow joints cleanly.
- **Hybrid Standard Adopted:**
  - Base: Standard Roblox R15 rig.
  - Skin: Classic 2D `Shirt` and `Pants` templates (585x559 texture) for perfect 60 FPS joint bending with zero clipping.
  - 3D Accents: Rigid accessories (`web_shooter_bracer.fbx` on arms, `webbed_backpack.fbx` on back, 3D masks on head).

---

## 4. Next Priorities (Post-Midterms Roadmap)
1. **Devlog #1 Voiceover:**
   - Script ready in `Devlog_1_Script.md` (~3 minutes, punchy indie dev story).
   - Mic: Rexus Xora-II (dialed in with pop filter, +6dB gain, 30% noise reduction).
   - Tool: CapCut.
2. **Roblox Studio Scene Dressing:**
   - Bulk-import FBX files into Studio.
   - Set quick material overrides (`Rubber` for tires, `Metal` for chrome, `Neon` for lamp glass).
3. **Gameplay Polish:**
   - Wire street props into the combat arena (web-pull electrical box explosion, vaulting over barricades).
