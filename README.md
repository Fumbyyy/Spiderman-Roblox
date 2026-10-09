<div align="center">
  <br/>
  <h1>🕷️ web of destiny</h1>
  <p><strong>A physics-driven Spider-Man traversal and freeflow combat sandbox for Roblox.</strong><br/>Native VectorForce physics. 6 canonical suits. 39 custom 3D models. Zero legacy BodyMovers.</p>
  <p>
    <a href="https://x.com/fumby123">𝕏 @fumby123</a> ·
    <a href="#quick-start">Quick Start</a> ·
    <a href="#controls">Controls</a> ·
    <a href="#suits--combat-identities">Suits</a> ·
    <a href="PROJECT_STATUS.md">Architecture</a> ·
    <a href="LICENSE">License</a>
  </p>
  <p>
    <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-1c1c20?style=flat-square&labelColor=0a0a0b" /></a>
    <a href="https://luau.org/"><img alt="Luau Strict" src="https://img.shields.io/badge/built%20with-luau%20strict-1c1c20?style=flat-square&labelColor=0a0a0b&logo=lua&logoColor=00A2FF" /></a>
    <a href="https://rojo.space/"><img alt="Rojo 7" src="https://img.shields.io/badge/toolchain-rojo%20v7-1c1c20?style=flat-square&labelColor=0a0a0b&logo=rust&logoColor=E84C3D" /></a>
    <a href="https://www.roblox.com/create"><img alt="Platform: Roblox Studio" src="https://img.shields.io/badge/platform-roblox%20studio-1c1c20?style=flat-square&labelColor=0a0a0b&logo=roblox&logoColor=white" /></a>
    <a href="https://x.com/fumby123"><img alt="Follow @fumby123 on X" src="https://img.shields.io/badge/follow-%40fumby123-1c1c20?style=flat-square&labelColor=0a0a0b&logo=x&logoColor=white" /></a>
  </p>
</div>

<br/>

*Spider-Man: Web of Destiny* is an Roblox game that is made by a 16 year old developer built in modern strict Luau. Built from the ground up on native engine constraints, it features dynamic pendulum swinging physics, Arkham/Insomniac-inspired kinetic melee combat, a living Manhattan crime dispatch system, 6 iconic canonical suits with live in-game hot-swapping, and a bespoke 39-model low-poly 3D asset library authored at 1:1 Roblox stud scale.

---

## Why Web of Destiny

| | |
|---|---|
| **True Constraint Physics** | Powered natively by `VectorForce` + `AlignOrientation` + `SphereTrace` raycasting. Zero deprecated BodyMovers (`BodyVelocity`, `BodyGyro`). Real pendulum arc tension, centrifugal release boosts up to **225 studs/s**, and dynamic camera FOV scaling (**70° to 95°**). |
| **Freeflow Intimate Combat** | 3-hit fluid melee combo sequence with directional hit-tracking, aerial launcher uppercuts (hold attack), ground-pound shockwaves, and target-locked Web-Strike Zip-Kicks (`[R]`) with 60 studs/s exit momentum. |
| **6 Canonical Movie Suits + Custom Avatar** | Classic Peter Parker, Stark Tech, Miles Morales, Symbiote Alien, Scarlet Spider, 2099 Cyber, and Custom Avatar mode (`0`/`7`) with live mid-combat hot-swapping, distinct stat multipliers, and dynamic HUD theming. |
| **Procedural Manhattan Crimes** | Real-time NYPD radio transmissions with voice chatter, high-speed getaway van pursuits with destructible engine blocks, hostile bailouts, marksman snipers, and street brawlers. |
| **AAA-Grade Client Telemetry** | Top-right glassmorphic health HUD with animated damage-ghost trails, suit accent bars, Devil May Cry style rank meter (`D` to `SS`), and 3D Spider-Phone wardrobe datapad (`[M]`). |
| **Bespoke 39-Model 3D Library** | 39 low-poly stylized assets across 7 categories (traffic vehicles, rooftop water towers, street lamps, weapons, throwable mailboxes) authored at 1:1 stud scale with headless Python generation scripts. |
| **Clean Recording Mode (`[H]`)** | One hotkey suppresses all on-screen HUDs, Roblox CoreGui, and in-world holographic beacons on the fly for crisp devlog video capture. |

---
## Controls

| Action | Keyboard & Mouse | Gamepad / Controller | Description |
| :--- | :---: | :---: | :--- |
| **Web Swing** | `Left-Click` (Hold) | `Right Trigger (R2)` | Shoots web line to building surface and initiates physical pendulum arc |
| **Slingshot Boost** | Release `Left-Click` / `Space` | `ButtonA (Cross)` | Detach with forward momentum boost at swing apex |
| **Light Melee Combo** | `Left-Click` (on ground) | `ButtonX (Square)` | 3-hit forward-tracking martial arts strike sequence |
| **Aerial Uppercut** | Hold `Left-Click` | Hold `ButtonX` | Launches targeted thug into the air for aerial juggling |
| **Ground Pound Slam** | `Left-Click` (in air) | `ButtonX` (in air) | High-speed vertical slam producing radial shockwave |
| **Web-Strike Zip-Kick** | `R` | `ButtonY (Triangle)` | 65-stud target-locked gap closer breaking enemy guard |
| **Contextual Web-Pellets** | `E` | `Right Bumper (R1)` | Rapid-fire web projectiles; traps thugs after 3 hits |
| **Web Cyclone Ultimate** | `T` | `L1 + R1` | 360° AOE web vortex crowd-control spin |
| **Spider-Sense Dodge** | `F` | `ButtonB (Circle)` | Directional roll with 0.45s i-frames (or Camouflage for Miles) |
| **Suit Hot-Swap** | `1` – `6` (or `V` to cycle) | `D-Pad Left / Right` | Instantly switch between the 6 canonical movie suits |
| **Custom Avatar Mode** | `0` or `7` | `D-Pad Down` | Equip your personal Roblox avatar without losing Spidey physics |
| **Spider-Phone / Visor** | `M` / `Tab` | `Select / View` | Opens Stark datapad, suit vault, and crime codex |
| **Cinematic Mode** | `H` | — | Toggles all UI off/on for clean recording |

---

## Suits & Combat Identities

| Suit | Hotkey | Playstyle / Focus | Mechanics & Multipliers | Theme Accent |
| :--- | :---: | :--- | :--- | :---: |
| **Classic Red & Blue** | `1` | Authentic Peter Parker | **Double Web-Slam** (`[Q]`) & rapid silk reload (**0.16s** cooldown). | Crimson `#E12D37` |
| **Stark Tech Advanced** | `2` | Nanotechnology Armor | **Apex Repulsor Thrusters** (+15% velocity), **Nanotech Shield** (+25 HP absorb), & Sonic Zip-Kick. | Cyan `#4BEBFF` |
| **Miles Morales** | `3` | Spider-Verse Stealth | **Bio-Electric Camo Meter** (`[F]`), true AI invisibility, & **1.5x Ambush Venom Strike**. | Amber `#FFE63C` |
| **Symbiote Alien Suit** | `4` | Raw Physical Dominance | **+20% Brute Damage** on all melee hits, pitch-black alien silk, & **Parasitic Health Siphon**. | Violet `#B496FF` |
| **Scarlet Spider** | `5` | Acrobatic Ballistics | **Slingshot Overdrive** (+25% catapult speed) & **Impact Web Blast** (`[E]`). | Scarlet `#F0323C` |
| **2099 Cyber Suit** | `6` | Futuristic Miguel O'Hara | **Supersonic Claw Slashes** & **Singularity Vortex** (+30% Web Cyclone AOE radius). | Neon Blue `#1E4BE1` |
| **Custom Player Avatar** | `0` / `7` | Your Own Identity | Applies all traversal and combat physics to **your personal Roblox avatar** with zero naked dummy bugs. | Steel `#E1EBF5` |

---

## Project Structure

```
Grapple/
├── Grapple Obby.rbxl           # Complete, standalone playable Roblox Studio place file
├── default.project.json        # Rojo 7 project configuration mapping src/ to Studio DataModel
├── aftman.toml                 # Toolchain package manifest (Rojo 7.7.0, Selene)
│
├── src/
│   ├── client/                 # Client controllers & UI modules (StarterPlayerScripts)
│   │   ├── CombatController.client.luau   # Input handling, combo states, suit swapping hotkeys
│   │   ├── GrappleController.client.luau  # Physics-based swinging engine (VectorForce + raycasts)
│   │   └── Modules/
│   │       ├── CameraController.luau      # Dynamic FOV scaling & cursor lock
│   │       ├── CombatMelee.luau           # 3-hit combo strings, punch hitboxes, uppercuts
│   │       ├── CombatWebs.luau            # Web-strike zip-kicks & web-pellet ballistics
│   │       ├── CombatUltimate.luau        # 360° Web Cyclone vortex logic
│   │       ├── CombatDodge.luau           # Spider-Sense dodge rolls & i-frames
│   │       ├── CombatReticle.luau         # Target acquisition & crosshair tracking
│   │       ├── CombatStyleHUD.luau        # Devil May Cry-style combo meter & rank badges
│   │       ├── PlayerHealthHUD.luau       # Top-right HP HUD, ghost trails, suit accent bars
│   │       ├── PoliceRadioHUD.luau        # NYPD dispatch audio & mission waypoint markers
│   │       └── SpiderPhoneHUD.luau        # 3D viewport wardrobe & Stark OS datapad
│   │
│   ├── server/                 # Authoritative backend services (ServerScriptService)
│   │   ├── CombatService.server.luau      # Authoritative hit-registration, damage, stuns
│   │   ├── CrimeService.server.luau       # Procedural crime encounters, van chases, XP economy
│   │   ├── EnemySpawner.server.luau       # Thug AI spawning, state machines & archetypes
│   │   ├── GrappleService.server.luau     # Server web replication & swing validation
│   │   └── SuitService.server.luau        # Authoritative suit equipping, custom avatar fallback
│   │
│   └── shared/                 # Shared configurations & network definitions (ReplicatedStorage)
│       ├── CombatConfig.luau              # Frame data, damage values, cooldowns, combo timings
│       ├── CrimeConfig.luau               # Crime payout rates, level curves, enemy stats
│       ├── EnemyOverheadUI.luau           # Shared pixel-offset enemy overhead health bars
│       ├── GrappleConfig.luau             # Physical constants (mass, forces, max line distance)
│       └── SuitConfig.luau                # Suit stat multipliers, perk descriptions, colors
│
├── assets/                     # Modular 3D game models & gameplay showcase media
│   ├── media/                  # Gameplay showcase footage (showcase_video.mp4)
│   └── models/                 # 39 production FBX models across 7 categories
│       ├── civilian_vehicles/  # 5 traffic vehicles (Taxi, Truck, Sedan, Pickup, Hatchback)
│       ├── rooftop_props/      # 5 rooftop skyline props (Water tower, HVAC, Fire escape)
│       ├── spidey_gadgets/     # 5 Spider-Man accessories (Web shooters, backpack, pizza box)
│       ├── street_props/       # 5 NYC street props (Street lamps, NYPD barricades, payphones)
│       ├── throwable_props/    # 9 environmental props (Crates, manholes, 5 mailbox styles)
│       ├── thug_weapons/       # 5 thug combat weapons (Baseball bat, crowbar, knife, handgun, riot shield)
│       └── thug_wearables/     # 5 enemy cosmetic meshes (Ski mask, hockey mask, beanie, plate carrier)
│
├── docs/                       # Production roadmaps, creator logs, and devlog scripts
│   ├── Daily_Checkpoints.md    # Creator's daily engineering log & milestone wins
│   ├── Devlog_1_Script.md      # YouTube Devlog #1 voiceover production script
│   └── Game_Workflow.md        # Master game architecture & workflow documentation
│
├── tools/                      # Build automation & procedural generation pipelines
│   └── blender/                # Headless Blender 5.1 procedural generation scripts
│       ├── generate_civilian_vehicles.py
│       ├── generate_rooftop_props.py
│       ├── generate_spidey_gadgets.py
│       ├── generate_street_props.py
│       ├── generate_throwable_props.py
│       ├── generate_thug_weapons.py
│       └── generate_thug_wearables.py
│
├── default.project.json        # Rojo project mapping configuration
├── aftman.toml                 # Toolchain version lock (Rojo, Selene, StyLua)
├── selene.toml                 # Strict Luau linter rules & globals
├── Grapple Obby.rbxl           # Complete 1-click playable Roblox Studio place file
├── PROJECT_STATUS.md           # Deep architectural documentation & changelog history
├── AGENTS.md                   # AI co-founder directives & RTCC prompt engineering standards
└── LICENSE                     # Open-source MIT License
```

---

## 3D Asset Library (39 Models)

Authored at **1:1 Roblox stud scale** ($1\text{ Blender Unit} = 1\text{ Stud}$), triangulated with zero sliver polygons, and optimized for high-performance rendering on mobile and PC:

1. **Civilian Traffic (`assets/models/civilian_vehicles/`):** NYC Yellow Taxi, City Delivery Box Truck, Family Sedan, Pickup Truck, Compact Urban Hatchback.
2. **Rooftop Ambience (`assets/models/rooftop_props/`):** Wooden Water Tower, HVAC Air Conditioner, Industrial Dumpster, Fire Escape Balcony, NYC Fire Hydrant.
3. **Street Props (`assets/models/street_props/`):** NYC Cast-Iron Street Lamp, NYPD Sawhorse Barricade, Vintage Payphone Kiosk, Traffic Hazard Cones, Electrical Hazard Box.
4. **Throwable Props (`assets/models/throwable_props/`):** Wooden Crate, Construction Barrel, Metal Trash Can, Cast-Iron Manhole Cover, and 5 distinct USPS Mailbox variants.
5. **Spidey Gadgets & Items (`assets/models/spidey_gadgets/`):** Web-Shooter Bracer, Webbed Backpack, Classic Pizza Delivery Box, Web Bomb Canister, Spider-Tracer Dart.
6. **Thug Weapons (`assets/models/thug_weapons/`):** Street Baseball Bat, Tactical Combat Knife, Steel Crowbar, 9mm Handgun, Riot Shield.
7. **Thug Wearables (`assets/models/thug_wearables/`):** Knit Ski Mask, Ballistic Hockey Mask, Gang Beanie, Tactical Plate Carrier, Spiked Arm Bracers.

*All models can be regenerated headlessly from source using the Blender automation scripts in [`tools/blender/`](./tools/blender).*

---

## Configuration & Modding

All gameplay parameters are decoupled into typed configurations under `src/shared/`:

- **Swinging Physics:** Edit [`src/shared/GrappleConfig.luau`](./src/shared/GrappleConfig.luau) to tune swing forces, line tension, spring damping, and max reach distance.
- **Combat & Combos:** Edit [`src/shared/CombatConfig.luau`](./src/shared/CombatConfig.luau) to adjust damage values, combo timings, i-frame windows, and style meter rank thresholds.
- **Suits & Perks:** Edit [`src/shared/SuitConfig.luau`](./src/shared/SuitConfig.luau) to tweak suit perks, add new suits, or change cosmetic palette colors.
- **Crime & Progression:** Edit [`src/shared/CrimeConfig.luau`](./src/shared/CrimeConfig.luau) to adjust XP leveling curves, Hero Cash payouts, and spawn rates.

---

## Creator & Community

- **Creator & Solo Founder:** **Rich** · Follow updates on [𝕏 @fumby123](https://x.com/fumby123) · GitHub: [@Fumbyyy](https://github.com/Fumbyyy)
- **Technical Co-Founder Directives:** Built with **Ponytail** (Senior Luau Architect & Mentor).
- **License:** Open-sourced under the **[MIT License](./LICENSE)**. You are free to study, play, fork, adapt, and build upon this code for your own Roblox experiences. If you use this engine in your project, a credit shoutout to [@fumby123](https://x.com/fumby123) is appreciated!

<br/>

<div align="center">

**⭐ Enjoying the engine? Drop a star on the repository! ⭐**

*With great power comes great responsibility.*

</div>
