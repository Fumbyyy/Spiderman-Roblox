# Spider-Man: Web of Destiny — Master Project Status & Handover Document

> **Project:** *Spider-Man: Web of Destiny* (Roblox / Luau / Rojo)  
> **Solo Founder & Creative Director:** Rich (16-year-old solo indie developer, Indonesia)  
> **Senior Technical Co-Founder & Mentor:** Ponytail (Luau Architect, Systems Engineer & Quality Auditor)  
> **Date:** October 8, 2026  
> **Active Git Head:** `f404bee` (Fully committed & synced with `origin/main`)  
> **Milestone Status:** Public Giveaway & Open-Source Release Showcase Ready (MIT License, Showstopper README, 1-Click Studio Playtest)  

---

## 1. The Co-Founder Chemistry & Operating Contract
This document encodes the exact working dynamic, philosophical contract, and division of labor between Rich and Ponytail. Any future session or AI agent picking up this project **must operate under this exact contract.**

### The "Ruthless Efficiency" Principle
- **"Lazy" means smart, not sloppy:** We never write 50 lines of convoluted callback spaghetti when a 10-line native engine feature solves it.
- **The Core Development Ladder:** Every proposed feature, mechanic, or refactor must pass this filter before a line of code is written:
  1. *YAGNI:* Do we need this right now to ship the immediate milestone? If no, kill it.
  2. *Reuse:* Does a module, math helper, or config already exist for this in our codebase?
  3. *Engine Native:* Does Roblox already provide a native constraint or service (`VectorForce`, `CollectionService`, `TweenService`)?
  4. *Simplicity:* Can this be written cleanly without deep nesting or over-abstracted OOP?
  5. *Juice (Game Feel):* Does this make web-swinging, combat, or exploration punchy and satisfying?

### Anti-Yes-Man Policy
- **No Sycophantic Agreement:** Ponytail never blindly validates bad ideas. If an idea is over-scoped, hurts mobile performance, or introduces technical debt, Ponytail challenges it immediately, explains why, and provides the leaner alternative.
- **The Burnout Shield:** Rich is a 16-year-old student balancing high school academics, midterm exams, creative drawing, and solo game development. When he grinds late into the night or gets hyper-fixated on non-essential micro-details, Ponytail intervenes and tells him to step away from the keyboard. A fatigued developer writes technical debt.

### Dual-AI Studio Division of Labor
Rich operates with a clear two-tier AI setup:
1. **Tier 1: Senior Technical Co-Founder & Architect (Ponytail):**
   - High-level architectural authority, scope guard, burnout shield, brainstorming filter, prompt engineer for external AI generation (Astra/Blender), and quality assurance auditor.
   - Vets every idea before code is written; protects Rich from fatigue and prevents over-engineering.
2. **Tier 2: The Engineering Team (Code Generators & Implementers):**
   - Headless script executors, subagents, and coding tools that write the raw implementation lines based on Tier 1 specifications.
   - Bound strictly by: zero placeholder comments (`-- TODO`), strict modern Luau typing, explicit `RBXScriptConnection` cleanup, and server-authoritative boundaries.

---

## 2. Technical Architecture & Verified Systems

### A. Core Traversal & Swinging Engine (`src/client/GrappleController.client.luau`)
*Status: FROZEN & FULLY VERIFIED. Do not touch or refactor unless fixing a verified bug.*
- **Physics Stack:** Powered by Roblox native `VectorForce` + `AlignOrientation` combined with `SphereTrace` raycasting. Zero deprecated `BodyVelocity`/`BodyGyro` instances.
- **Release Momentum Boost:** Preserves directional kinetic velocity upon web release, allowing high-speed slingshots out of dives.
- **Camera Dynamics:** Dynamic speed-based FOV scaling smoothly interpolating from 70 (idle) to 95 (terminal swing velocity).
- **Surface Traversal:** Wall-run friction checks, ledge zip-targeting, ceiling drop-hang, and automatic obstacle clearance.
- **Configuration Hub:** All physical constants (tensions, damping, max distances, speeds) are centralized in `src/shared/GrappleConfig.luau`.

### B. Combat & Melee Engine
*Status: IMPLEMENTED & POLISHED.*
- **Light Combo String:** 3-hit rhythmic sequence (0.28s cadence) with 100% magnetic target alignment and step-in velocity impulses.
- **Verticality & Aerial Finisher:** 1-2-3 combo $\rightarrow$ Jump $\rightarrow$ Air Ground Slam (`performAirGroundSlam`) with instant 0ms client-predicted floating comic damage numbers (`"-24 SLAM!"`), screen crunch, and twin web descent lines.
- **Floating Comic Damage Numbers:** Lightweight client-side popup system (`CombatVFXListener.spawnDamageNumber`) with critical yellow/red styling, billboard camera tracking, and automatic `Debris` cleanup.
- **Dynamic Ability Tray Latch:** In `CombatStyleHUD`, `isTrayLockedHidden` prevents skill pills (`[E] PELLET`, `[R] ZIP-KICK`, `[T] CYCLONE`) from reopening after quests clear or when out of combat; only intentional player combat inputs (`registerCombatAction`) re-arm visibility.
- **Procedural Crime Auto-Clear:** Quests complete and pay out immediately when all living enemies are eliminated, auto-disabling getaway vehicles without spurious dialog.
- **Evasion & Dodge:** Spider-Sense dodge roll (F key) with invulnerability frames (i-frames) and camera FOV punch.
- **Hit Registration & Security:** Server-authoritative validation with rate-limiting cooldown tables, 12-stud impact sanity checks, wall-pinning synergy, and platform-stand hitstun.

### C. Character Rig & Suit Architecture
*Status: ARCHITECTURAL STANDARD LOCKED IN.*
- **No Skinned 3D Suits via AI:** Procedural AI mesh generators cannot weight-paint deforming shoulder and knee joints cleanly without horrific polygon pinching or tearing during animations.
- **The Hybrid Standard Adopted:**
  1. *Base:* Standard R15 humanoid rig (guarantees buttery 60 FPS animation blending).
  2. *Suit Skin:* Classic 2D `Shirt` and `Pants` textures (585×559 layout) for flawless joint bending with zero performance cost.
  3. *3D Silhouette Accents:* Rigid accessories socketed to avatar attachment points (`web_shooter_bracer.fbx` on forearms, `webbed_backpack.fbx` on torso, 3D masks on head).

---

## 3. The 39-Model Bespoke 3D Asset Library
Authored via headless Blender 5.1 with procedural Python generators (`generate_*.py`). All models enforce **1 Blender Unit = 1 Roblox Stud** relative to 5-stud avatars, zero degenerate faces, manifold geometry, and strict 500–1,400 triangle budgets.

| Category & Folder | Asset Name | FBX File | Triangles | Dimensions (Studs) | Gameplay Role / Attachment |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Thug Weapons**<br>`thug_weapons/` | Baseball Bat | `baseball_bat.fbx` | ~650 | $0.5 \times 0.5 \times 4.2$ | Melee thug weapon (taped handle) |
| | Crowbar | `crowbar.fbx` | ~720 | $0.4 \times 0.6 \times 3.6$ | Melee thug weapon (angled pry claw) |
| | Combat Knife | `combat_knife.fbx` | ~580 | $0.3 \times 0.6 \times 2.0$ | Fast melee thug weapon (serrated edge) |
| | Handgun | `handgun.fbx` | ~810 | $0.4 \times 1.5 \times 1.1$ | Ranged thug firearm (slide, trigger, grip) |
| | Riot Shield | `riot_shield.fbx` | ~890 | $3.0 \times 1.2 \times 5.4$ | Brute thug shield (ballistic viewport) |
| **2. Throwable Props**<br>`throwable_props/` | Manhole Cover | `manhole_cover.fbx` | ~740 | $3.6 \times 3.6 \times 0.3$ | Heavy throwable disc (crosshatch grip) |
| | Trash Can + Lid | `trash_can.fbx` | ~1,260 | $2.1 \times 2.1 \times 4.2$ | Throwable street prop with separate lid |
| | Wooden Crate | `wooden_crate.fbx` | ~1,008 | $4.8 \times 4.8 \times 4.8$ | Breakable throwable container (cross-braced) |
| | Construction Barrel | `construction_barrel.fbx` | ~944 | $2.4 \times 2.4 \times 4.8$ | Heavy street obstacle / throwable |
| | Classic USPS Mailbox | `mailbox_classic_usps.fbx` | ~912 | $1.9 \times 1.6 \times 3.8$ | Curbside drop-chute mailbox |
| | Double Chute Mailbox | `mailbox_double_chute.fbx` | ~980 | $2.4 \times 1.6 \times 3.8$ | High-volume twin mail drop box |
| | Dented Combat Mailbox| `mailbox_combat_dented.fbx`| ~940 | $1.9 \times 1.6 \times 3.8$ | Battered street combat cover |
| | Green Relay Mailbox | `mailbox_relay_green.fbx` | ~860 | $2.0 \times 1.8 \times 3.9$ | Storage relay box (olive/brass) |
| | Vintage Pillar Mailbox| `mailbox_vintage_pillar.fbx`| ~1,020 | $1.8 \times 1.8 \times 4.2$ | Victorian fluted pillar postbox |
| **3. Rooftop Props**<br>`rooftop_props/` | Rooftop Water Tower | `rooftop_water_tower.fbx` | 1,086 | $7.7 \times 7.7 \times 16.4$ | Multi-story skyline landmark / perch |
| | HVAC AC Unit | `hvac_air_conditioner.fbx` | 888 | $6.3 \times 3.9 \times 4.1$ | Industrial rooftop exhaust fan & vents |
| | Fire Escape Balcony | `fire_escape_balcony.fbx` | 1,308 | $6.1 \times 3.7 \times 5.7$ | Wall-mounted iron balcony with drop ladder |
| | NYC Fire Hydrant | `nyc_fire_hydrant.fbx` | 808 | $1.4 \times 1.4 \times 2.35$ | Curbside red cast-iron hydrant |
| | Industrial Dumpster | `industrial_dumpster.fbx` | 760 | $6.1 \times 4.3 \times 4.6$ | Alleyway steel dumpster (lid ajar) |
| **4. Spidey Gadgets**<br>`spidey_gadgets/` | Web Shooter Bracer | `web_shooter_bracer.fbx` | 888 | $1.4 \times 1.4 \times 1.6$ | Rigid forearm accessory (dual wrists) |
| | Web Bomb Canister | `web_bomb_canister.fbx` | 896 | $1.0 \times 1.0 \times 1.2$ | Impact web grenade projectile |
| | Spider-Tracer Dart | `spider_tracer_dart.fbx` | 648 | $0.8 \times 0.8 \times 0.2$ | Arachnid tracking beacon pickup |
| | Classic Pizza Box | `classic_pizza_box.fbx` | 724 | $2.4 \times 2.4 \times 0.5$ | NYC delivery pizza box (heal / collectible) |
| | Webbed Backpack | `webbed_backpack.fbx` | 1,048 | $1.8 \times 1.4 \times 2.2$ | Peter Parker collectible daypack |
| **5. Thug Wearables**<br>`thug_wearables/` | Ballistic Hockey Mask | `ballistic_hockey_mask.fbx` | 804 | $1.3 \times 1.1 \times 1.4$ | Thug face mask (`FaceFrontAttachment`) |
| | Thug Ski Mask | `thug_ski_mask.fbx` | 888 | $1.3 \times 1.3 \times 1.6$ | Full knit balaclava (`HatAttachment`) |
| | Tactical Plate Carrier| `tactical_plate_carrier.fbx`| 1,088 | $2.2 \times 1.3 \times 2.2$ | Ceramic torso armor (`BodyFrontAttachment`) |
| | Street Gang Beanie | `street_gang_beanie.fbx` | 728 | $1.3 \times 1.3 \times 0.9$ | Slouchy folded cuff beanie (`HatAttachment`) |
| | Spiked Arm Bracers | `spiked_arm_bracers.fbx` | 1,064 | $1.4 \times 1.4 \times 1.6$ | Dual leather/steel studded forearm cuffs |
| **6. Street Props**<br>`street_props/` | NYPD Sawhorse Barricade| `nypd_sawhorse_barricade.fbx`| 888 | $4.6 \times 1.4 \times 2.8$ | Vaultable cover / crowd control barricade |
| | NYC Street Lamp | `nyc_street_lamp.fbx` | 956 | $2.8 \times 1.6 \times 12.5$ | 12.5-stud lamppost with top perch finial |
| | Vintage Payphone Kiosk| `vintage_payphone_kiosk.fbx`| 1,004 | $2.2 \times 2.0 \times 6.4$ | Curbside acoustic hood & coiled handset |
| | Traffic Hazard Cones | `traffic_hazard_cones.fbx` | 616 | $2.4 \times 1.8 \times 2.2$ | Upright cone + knocked cone pair |
| | Electrical Hazard Box | `electrical_hazard_box.fbx` | 948 | $2.2 \times 1.2 \times 3.0$ | Web-pull environmental shock hazard |
| **7. Civilian Vehicles**<br>`civilian_vehicles/` | NYC Yellow Taxi | `nyc_yellow_taxi.fbx` | 1,200 | $6.6 \times 15.0 \times 5.0$ | Crown Vic taxi, roof fare box, tinted glass |
| | Civilian Family Sedan | `civilian_family_sedan.fbx` | 1,124 | $6.5 \times 14.5 \times 4.8$ | Slate blue commuter sedan, taillight bar |
| | Civilian Pickup Truck | `civilian_pickup_truck.fbx` | 1,284 | $7.0 \times 16.0 \times 5.6$ | Crew-cab with open ribbed cargo bed |
| | City Box Delivery Truck| `city_box_delivery_truck.fbx`| 1,344 | $7.2 \times 18.5 \times 7.8$ | Flat-nose truck with large cargo parkour box |
| | Urban Compact Hatchback| `urban_compact_hatchback.fbx`| 1,184 | $6.2 \times 12.8 \times 4.6$ | Crimson red 2-door city compact |

---

## 4. Professional AI Prompt Engineering Protocol: The RTCC Framework
When Rich needs new 3D assets generated through external LLMs (e.g. GPT-6 Astra on arena.ai), the Co-Founder drafts the prompt following the **RTCC Framework** (Role, Task, Context, Constraints):

- **R — Role:** Anchor the external AI as a *"Lead 3D Technical Artist & Blender Python Automation Architect specializing in low-poly game asset pipelines for Roblox."*
- **T — Task:** Explicit standalone headless CLI script (`generate_<category>.py`) outputting 5 named `.fbx` models and a structured `export_report.json`.
- **C — Context:** Real-world Manhattan scaling calibrated against 5-stud Roblox humanoid avatars, detailing player interaction utility (vaulting, parkour, web-pulling).
- **C — Constraints (The 6 Non-Negotiables):**
  1. **Exact 1:1 Stud Scaling:** Mandate `1 Blender unit = 1 Roblox stud` relative to 5-stud avatars. Explicitly mandate `apply_unit_scale=False`, `apply_scale_options='FBX_SCALE_NONE'`, `axis_forward='-Z'`, `axis_up='Y'`. Never apply meter multipliers.
  2. **Object Cleanup Bugfix:** Mandate `mesh_data = obj.data` cached BEFORE `bpy.data.objects.remove(obj)` to eliminate `StructRNA ReferenceError` crashes.
  3. **Topology Cleansing:** Mandate `bmesh.ops.triangulate(bm, quad_method='BEAUTY', ngon_method='EAR_CLIP')` followed by `bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=list(bm.edges))` to eliminate 0-area sliver polygons.
  4. **Strict Budget:** Enforce 500–1,400 triangles per asset (700–1,400 for vehicles).
  5. **Exterior-Only Rule:** All vehicle and prop windows must be solid tinted glass surfaces. Zero polygons wasted on invisible interior dashboards, steering wheels, or seats.
  6. **Explicit Authoring Pivots:** Ground props must place bottom at $Z=0$; wall props must place rear mounting plane at $Y=0$. Zero placeholder comments (`-- TODO`) allowed.

---

## 5. Active To-Do List & Production Roadmap

### ✅ Completed & Verified (Today's Engineering Wins)
- [x] **Van ProximityPrompt Removed:** Completely eliminated `Web-Sabotage Engine [E]` prompt from the getaway van in `CrimeService.server.luau`. Zero camera occlusion, zero `[E]` key conflict with Web-Pellets.
- [x] **Procedural Crime Auto-Clear:** Crime missions complete immediately upon eliminating all living enemies, paying out XP/Cash cleanly without dialog spam.
- [x] **Dynamic Ability Tray Latch:** In `CombatStyleHUD`, `isTrayLockedHidden` prevents ability pills (`[E]`, `[R]`, `[T]`) from popping back up after combat or quest completion; only intentional combat inputs re-arm visibility.
- [x] **Floating Comic Damage Numbers:** Client-predicted visual feedback popups (`"-18 FINISHER"`, `"-10"`) with camera billboard tracking and automatic cleanup.
- [x] **Grounded Combat Purity:** Left-Click kept clean and focused strictly on the 1-2-3 Kinetic Punch Combo (Tap) and Uppercut Launcher (Hold) without clunky mid-air input contention.

---

### 📋 Next Action Items (Tomorrow: Devlog #1 Recording)

```
[Tomorrow's Session]
         │
         ├── STEP 1: Record Gameplay B-Roll in Studio (15-20 mins)
         │   • Script ready: `Devlog_1_Script.md` (~3 mins, Dani/Duckable pacing)
         │   • Clip 1: Web-swinging through Manhattan skyscrapers + release slingshot
         │   • Clip 2: 1-2-3 kinetic punch combo on thugs with comic damage numbers
         │   • Clip 3: Web-pellet wall cocooning ([E]) + Spider-Sense dodge ([F])
         │   • Clip 4: Web-strike zip kick ([R]) + 360° Web Cyclone ultimate ([T])
         │
         ├── STEP 2: Devlog #1 Voiceover & CapCut Assembly
         │   • Mic: Rexus Xora-II (calibrated: pop filter, +6dB gain, 30% noise reduction)
         │   • Tool: CapCut (fast cuts, kinetic sound effects, upbeat pacing)
         │   • Goal: Tell the 16-year-old solo founder story and showcase the physics engine
         │
         └── STEP 3: Studio Scene Dressing (Post-Recording)
             • Bulk-import the 39 Blender FBX assets via Asset Manager
             • Material pass: Rubber on tires, Metal on bumpers, Neon on lamps
             • Scatter environmental throwables (crates, barricades) for [Q] prop-throwing
```

---

## 6. How the Next Session Must Begin
When opening a new session in this workspace after exams:
1. Greet Rich as **Ponytail** (senior technical co-founder & mentor).
2. Confirm he survived midterms and ask how his rest went.
3. Immediately direct attention to **Step 1 (Devlog #1 Voiceover)** without adding new scope or distractions.
