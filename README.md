<div align="center">

# 🕷️ Spider-Man: Web of Destiny
### Next-Generation Physics Traversal & Freeflow Combat Engine for Roblox

[![Roblox Studio](https://img.shields.io/badge/Roblox-Studio-00A2FF?logo=roblox&logoColor=white&style=for-the-badge)](https://www.roblox.com/create)
[![Luau](https://img.shields.io/badge/Luau-Strict%20Typing-00A2FF?logo=lua&logoColor=white&style=for-the-badge)](https://luau.org/)
[![Rojo 7](https://img.shields.io/badge/Rojo-v7.x-E84C3D?logo=rust&logoColor=white&style=for-the-badge)](https://rojo.space/)
[![3D Assets](https://img.shields.io/badge/3D%20Assets-39%20Production%20Models-8A2BE2?style=for-the-badge)](./PROJECT_STATUS.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-2ea44f?style=for-the-badge)](./LICENSE)

<br/>

**A complete, production-grade superhero sandbox built in modern strict Luau.**  
Featuring native constraint-based physics (zero legacy BodyMovers), Arkham/Insomniac-inspired freeflow melee combat, a dynamic Manhattan crime dispatch system, 6 canonical movie suits with distinct gameplay mechanics, and a 39-model low-poly 3D asset library authored at 1:1 Roblox stud scale.

<br/>

[🚀 Quick Start](#-quick-start-2-ways-to-play) • [🕸️ Traversal Engine](#️-physics-driven-traversal-engine) • [🥊 Combat System](#-freeflow-kinetic-combat) • [🧬 Suits & Perks](#-canonical-suits--combat-identities) • [🚓 Manhattan Crime](#-procedural-manhattan-crime-system) • [🕹️ Controls](#️-controls--input-matrix) • [📁 Architecture](#-project-architecture)

</div>

---

## ⚡ Quick Start (2 Ways to Play)

### Option 1: 1-Click Roblox Studio Playtest (Fastest — 10 Seconds) 🎮
The repository includes the complete, standalone Roblox place file pre-configured with all scripts, lighting, and collision geometry:
1. Clone or download this repository.
2. Double-click [`Grapple Obby.rbxl`](./Grapple%20Obby.rbxl) to open it in **Roblox Studio**.
3. Press **`F5`** (or click **Play**) to immediately swing through Manhattan and fight crime!

### Option 2: Professional Rojo 7 Toolchain (Live Sync) 🛠️
For developers building with VS Code, Antigravity, or external editors:
```bash
# 1. Clone the repository
git clone https://github.com/richclintonmozartkurnia-byte/Grapple.git
cd Grapple

# 2. Install Rojo toolchain via Aftman (if installed)
aftman install

# 3. Start the Rojo sync server
rojo serve
```
Open your preferred place in Roblox Studio, open the **Rojo** plugin, and click **Connect** (`localhost:34872`). Source code under `src/` will sync bidirectionally in real time.

---

## 🕸️ Physics-Driven Traversal Engine

Unlike traditional Roblox web-swinging games that rely on deprecated `BodyVelocity` or fake teleportation tweens, *Web of Destiny* runs on **true physical dynamics**:

- **Native Constraint Physics:** Powered entirely by native `VectorForce` + `AlignOrientation` + `SphereTrace` raycasting.
- **Pendulum Arc Tension:** Web lines calculate real-time distance from the anchor attachment, converting gravitational potential energy into forward kinetic momentum.
- **Dynamic Arc Boost & Slingshot:** Releasing `Left-Click` or pressing `Space` at the bottom or apex of a swing applies velocity-preserving catapult impulses (up to **225 studs/s**).
- **Cinematic Dynamic Camera:** Responsive camera module dynamically scales field of view from **70° FOV** at rest up to **95° FOV** at terminal velocity, with subtle speed lines and impact shakes.
- **Surface & Parkour Integration:** Contextual ledge-perching, wall-running, and ground slide-recovery prevent clipping and ground snagging.

---

## 🥊 Freeflow Kinetic Combat

An aggressive, intimate brawler combat system designed after modern AAA superhero games:

- **3-Hit Directional Combo String:** Ground punches feature forward strike-tracking, comic book punch sparks, and hit-stop impact pauses (Hits 1 & 2 deal zero knockback to keep enemies pinned; Hit 3 delivers a satisfying launch).
- **Aerial Combat Juggle (Hold Attack):** Hold attack to launch a thug into the air with an uppercut, leaping up alongside them for mid-air combo strings.
- **Ground-Pound Shockwave (Air Attack):** Attacking while falling unleashes a high-velocity vertical slam producing an expanding radial ground shockwave.
- **Web-Strike Zip-Kick (`[R]`):** Target-locked gap closer verifying enemies up to **65 studs** away. Blasts Spidey forward, breaking enemy shields and granting **60 studs/s** exit momentum.
- **Contextual Web-Pellets (`[E]`):** High-velocity web projectiles (**220 studs/s**). Hit enemies 3 times to trap them in a cocoon or pin them to nearby building walls.
- **Web Cyclone Ultimate (`[T]`):** 360-degree radial web vortex spinning nearby hostiles into a crowd-control blender.
- **Spider-Sense Dodge Roll (`[F]`):** Directional evasive roll equipped with **0.45s invulnerability frames (i-frames)** and sound cue hooks.

---

## 🧬 Canonical Suits & Combat Identities

Swap between 6 iconic Spider-Man suits mid-game using keys `1`–`6` (or cycle with `V`), plus seamlessly toggle your own personal Roblox avatar using `0` or `7`:

| Suit Name | Hotkey | Playstyle / Role | Unique Perk & Combat Modifiers | Theme Color |
| :--- | :---: | :--- | :--- | :---: |
| **Classic Red & Blue** | `1` | Authentic Peter Parker | **Double Web-Slam** (`[Q]`) & rapid silk reload (**0.16s** cooldown). | Crimson `#E12D37` |
| **Stark Tech Advanced** | `2` | Nanotechnology Armor | **Apex Repulsor Thrusters** (+15% velocity), **Nanotech Shield** (+25 HP absorb), & Sonic Zip-Kick. | Cyan `#4BEBFF` |
| **Miles Morales** | `3` | Spider-Verse Stealth | **Bio-Electric Camouflage Meter** (`[F]`), true AI invisibility, & **1.5x Ambush Venom Strike**. | Amber `#FFE63C` |
| **Symbiote Alien Suit** | `4` | Raw Physical Dominance | **+20% Brute Damage** on all melee hits, pitch-black alien silk, & **Parasitic Health Siphon**. | Violet `#B496FF` |
| **Scarlet Spider** | `5` | Acrobatic Ballistics | **Slingshot Overdrive** (+25% catapult speed) & **Impact Web Blast** (`[E]`). | Scarlet `#F0323C` |
| **2099 Cyber Suit** | `6` | Futuristic Miguel O'Hara | **Supersonic Claw Slashes** & **Singularity Vortex** (+30% Web Cyclone AOE radius). | Neon Blue `#1E4BE1` |
| **Custom Player Avatar** | `0` / `7` | Your Own Roblox Identity | Applies all traversal and combat physics to **your personal Roblox avatar and clothing** with zero naked dummy bugs. | Steel `#E1EBF5` |

---

## 🚓 Procedural Manhattan Crime System

A living city system that keeps the world dynamic:

- **NYPD Police Radio Dispatch:** Procedural radio transmissions announce crimes across Manhattan with real-time audio chatter and objective coordinates.
- **High-Speed Getaway Van Chases:** Intercept fleeing getaway vans, disable vehicle engine blocks with web gadgets, and survive multi-wave hostile bailouts.
- **Intelligent Enemy Archetypes:**
  - **Marksman / Gunner:** Keeps distance and snipes with telegraph tracer lasers.
  - **Enforcer / Brute:** Heavily armored, absorbs frontal damage, requires guard-breaking.
  - **Brawler / Mob:** Swarms Spidey in close-quarters melee groups.
- **Shared Overhead UI:** Pixel-perfect overhead nameplates (`src/shared/EnemyOverheadUI.luau`) featuring role tags, damage-ghost health bars, and distance-fading culling.

---

## ⚡ Client Telemetry & Spider-Phone HUD

- **Player Health HUD:** Top-right glassmorphic telemetry displaying base health, Nanotech Shield absorption, suit identity accent strips, and animated damage-lag ghost trails.
- **Combat Style Meter:** Devil May Cry-inspired combo ranker (`D` ➔ `C` ➔ `B` ➔ `A` ➔ `S` ➔ `SS`) with animated bounce scales, auto-flowing hit counters, and dynamic decay bars.
- **Holographic Spider-Phone (`[M]` or `[Tab]`):** In-game OS featuring:
  - **3D Hero Wardrobe:** Live rotating character viewport with instant suit swapping.
  - **FNSM Crime Scanner:** Real-time Manhattan incident tracker.
  - **Hero Combat Codex:** Detailed move directory with damage stats and frame data.
- **Cinematic Recording Mode (`[H]`):** Instantly suppresses all on-screen HUDs, Roblox CoreGui, and in-world holographic beacons on the fly for pristine YouTube devlog recordings.

---

## 🕹️ Controls & Input Matrix

| Action | PC Keyboard & Mouse | Gamepad / Controller | Description |
| :--- | :---: | :---: | :--- |
| **Web Swing** | `Left-Click` (Hold) | `Right Trigger (R2)` | Casts web line to building surface and initiates physical swing |
| **Slingshot Boost** | Release `Left-Click` / `Space` | `ButtonA (Cross)` | Detach with forward momentum boost at swing apex |
| **Light Melee Combo** | `Left-Click` (on ground) | `ButtonX (Square)` | 3-hit forward-tracking martial arts strike sequence |
| **Aerial Uppercut** | Hold `Left-Click` | Hold `ButtonX` | Launches targeted thug into the air for aerial juggling |
| **Ground Pound** | `Left-Click` (in air) | `ButtonX` (in air) | High-speed vertical slam creating radial shockwave |
| **Web-Strike Zip-Kick** | `R` | `ButtonY (Triangle)` | Target-locked gap closer breaking enemy guard |
| **Contextual Web-Pellets**| `E` | `Right Bumper (R1)` | Rapid-fire web projectiles; traps thugs after 3 hits |
| **Web Cyclone Ultimate** | `T` | `L1 + R1` | 360° AOE web vortex crowd-control spin |
| **Spider-Sense Dodge** | `F` | `ButtonB (Circle)` | Directional roll with 0.45s i-frames (or Camouflage for Miles) |
| **Suit Hot-Swap** | `1` – `6` (or `V` to cycle) | `D-Pad Left / Right` | Instantly switch between the 6 canonical movie suits |
| **Custom Avatar Mode** | `0` or `7` | `D-Pad Down` | Equip your personal Roblox avatar without losing Spidey physics |
| **Spider-Phone / Visor** | `M` / `Tab` | `Select / View` | Opens Stark datapad, suit vault, and crime codex |
| **Cinematic Mode** | `H` | — | Toggles all UI off/on for clean recording |

---

## 📁 Project Architecture

```
Grapple/
├── Grapple Obby.rbxl           # Complete, standalone playable Roblox Studio place file
├── default.project.json        # Rojo 7 project configuration mapping src/ to Studio DataModel
├── aftman.toml                 # Toolchain package manifest (Rojo 7.7.0, Selene)
│
├── src/
│   ├── client/                 # Client-side controllers & UI modules (StarterPlayerScripts)
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
├── civilian_vehicles/          # 5 traffic vehicle FBX models (Sedan, Pickup, NYC Taxi, etc.)
├── rooftop_props/              # 5 rooftop skyline props (Water tower, HVAC, Fire escape)
├── street_props/               # 5 NYC street props (Street lamps, NYPD barricades, payphones)
├── throwable_props/            # 9 environmental props (Crates, manholes, 5 mailbox styles)
├── spidey_gadgets/             # 5 Spider-Man accessories (Web shooters, backpack, pizza box)
├── thug_weapons/               # 5 thug combat weapons (Baseball bat, crowbar, knife, handgun, riot shield)
├── thug_wearables/             # 5 enemy cosmetic meshes (Ski mask, hockey mask, beanie, plate carrier)
│
├── generate_*.py               # Headless Python Blender 5.1 procedural generation scripts
├── PROJECT_STATUS.md           # Deep architectural documentation & changelog history
├── Devlog_1_Script.md          # Creator's 4-act devlog script for YouTube
└── LICENSE                     # Open-source MIT License
```

---

## 📦 Included 3D Asset Library (39 Models)

The repository includes a complete library of **39 production-ready low-poly 3D models** authored at **1:1 Roblox stud scale** ($1\text{ Blender Unit} = 1\text{ Stud}$), triangulated with zero sliver polygons and fully optimized for mobile and PC performance:

1. **Civilian Traffic (`civilian_vehicles/`):** NYC Yellow Taxi, City Delivery Box Truck, Family Sedan, Pickup Truck, Compact Urban Hatchback.
2. **Rooftop Ambience (`rooftop_props/`):** Rooftop Wooden Water Tower, HVAC Air Conditioner, Industrial Dumpster, Fire Escape Balcony, NYC Fire Hydrant.
3. **Street Props (`street_props/`):** NYC Cast-Iron Street Lamp, NYPD Sawhorse Barricade, Vintage Payphone Kiosk, Traffic Hazard Cones, Electrical Hazard Box.
4. **Throwable Props (`throwable_props/`):** Wooden Crate, Construction Barrel, Metal Trash Can, Cast-Iron Manhole Cover, and 5 distinct USPS Mailbox variants.
5. **Spidey Gadgets & Items (`spidey_gadgets/`):** Web-Shooter Bracer, Webbed Backpack, Classic Pizza Delivery Box, Web Bomb Canister, Spider-Tracer Dart.
6. **Thug Weapons (`thug_weapons/`):** Street Baseball Bat, Tactical Combat Knife, Steel Crowbar, 9mm Handgun, Riot Shield.
7. **Thug Wearables (`thug_wearables/`):** Knit Ski Mask, Ballistic Hockey Mask, Gang Beanie, Tactical Plate Carrier, Spiked Arm Bracers.

*All models can be regenerated headlessly from source using the included `generate_<category>.py` Blender automation scripts.*

---

## ⚙️ Configuration & Modding

Want to adjust swinging velocity or tweak combat damage? All game balance is decoupled into clean, typed configuration files under `src/shared/`:

- **Swinging Physics:** Edit [`src/shared/GrappleConfig.luau`](./src/shared/GrappleConfig.luau) to modify swing impulse forces, max grapple distance, spring damping, and release speed multipliers.
- **Combat & Combos:** Edit [`src/shared/CombatConfig.luau`](./src/shared/CombatConfig.luau) to adjust damage per combo hit, i-frame duration, web-pellet velocity, and style meter rank thresholds.
- **Suits & Perks:** Edit [`src/shared/SuitConfig.luau`](./src/shared/SuitConfig.luau) to create new custom suits, adjust stat multipliers, or configure theme colors.
- **Economy & Crimes:** Edit [`src/shared/CrimeConfig.luau`](./src/shared/CrimeConfig.luau) to modify Hero Cash payouts, XP leveling curves, and crime frequency.

---

## 👨‍💻 Creator & Community

- **Creator / Solo Founder:** **Rich** ([@richclintonmozartkurnia-byte](https://github.com/richclintonmozartkurnia-byte)) — 16-year-old solo indie game developer and artist from Indonesia.
- **Luau Architecture & Co-Founder Directives:** Built with **Ponytail** (Senior Luau Architect & Mentor).
- **Giveaway Terms:** This repository is open-sourced under the **MIT License**. You are free to study, play, adapt, fork, and build upon this code for your own Roblox experiences. If you use this engine in your project, a credit shoutout to **Rich** is deeply appreciated!

---

<div align="center">

**⭐ Enjoying the engine? Drop a star on the repository! ⭐**

*With great power comes great responsibility.*

</div>