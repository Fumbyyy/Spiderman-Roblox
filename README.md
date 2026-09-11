# 🕸️ Spider-Man: Web of Destiny

An authentic, physics-driven Spider-Man sandbox and combat experience for Roblox, built with modern Luau, Rojo, and external 3D asset pipelines.

---

## 🎮 Core Gameplay Systems

- **Kinetic Web-Swinging Physics:** Powered natively by `VectorForce` + `AlignOrientation` + `SphereTrace` raycasting. Zero deprecated BodyMovers. Features high-velocity release boosts and dynamic camera FOV scaling (70 to 95 FOV).
- **Tactical Arkham-Style Melee Combat:** 4-hit light combo sequence, aerial launcher uppercut, ground-pound shockwave slam, and directional dodge with invulnerability frames (i-frames).
- **Stark Tech AR Visor & Spider-Phone:** Integrated HUD featuring FNSM Crime Scanner, Hero Combat Codex, Suit Vault, and player progression profile.
- **Suit Perks & Visual Feedback:** Canonical suits with gameplay modifiers (Stark velocity thrusters, Symbiote damage & black silk, Spider-Armor shielding, 2099 singularity vortex).
- **Bespoke 3D Asset Library:** 39 low-poly stylized production models authored in Blender 5.1 at 1:1 Roblox stud scale across 7 categories (weapons, throwables, rooftop ambience, Spidey gadgets, thug wearables, street props, and civilian traffic vehicles).

---

## 🕹️ Controls (PC / Keyboard & Mouse)

| Action | Input | Description |
| :--- | :--- | :--- |
| **Web Swing** | `Left-Click` (Hold) | Shoot web line to building facade and swing |
| **Release / Slingshot** | Release `Left-Click` / `Space` | Detach with preserved forward momentum boost |
| **Web-Zip / Ledge Perch** | `E` | High-speed zip to targeted ledge, lamp finial, or corner |
| **Light Melee Combo** | `Left-Click` (on ground) | 4-hit punch combo with forward strike tracking |
| **Aerial Uppercut** | Hold `Left-Click` | Launch enemy into air for aerial combat juggle |
| **Ground Pound Slam** | `Left-Click` (in air) | High-velocity vertical slam with radial shockwave |
| **Spider-Sense Dodge** | `F` | Directional dodge roll with 0.45s i-frames |
| **Spider-Phone / Visor** | `M` / `Tab` | Open Stark OS datapad, crime scanner, and suit vault |

---

## 🛠️ Architecture & Developer Toolchain

- **Sync Engine:** [Rojo 7.x](https://rojo.space/) syncing local Luau source to Roblox Studio via `default.project.json`.
- **Toolchain Manager:** [Aftman](https://github.com/LPGhatguy/aftman) managing Rojo and Selene.
- **Pattern:** Service-Controller architecture (`src/server` $\rightarrow$ `ServerScriptService`, `src/client` $\rightarrow$ `StarterPlayerScripts`, `src/shared` $\rightarrow$ `ReplicatedStorage`).
- **Server Authority:** Authoritative hitboxes, damage calculation, cooldown validation, and economy security.
- **3D Pipeline:** Headless procedural Blender 5.1 generation (`generate_*.py`) using the RTCC framework at 1:1 Roblox stud scale.

---

## 📁 Repository Structure

```
├── src/
│   ├── client/          # GrappleController, CombatController, Modules
│   ├── server/          # CombatService, CrimeService, EnemySpawner, SuitService
│   └── shared/          # GrappleConfig (Single source of truth)
├── thug_weapons/        # 5 melee & firearm assets
├── throwable_props/     # 9 throwable street items & 5 mailbox variants
├── rooftop_props/       # 5 skyline ambient assets (Water tower, HVAC, Fire escape)
├── spidey_gadgets/      # 5 Spider-Man gadgets & pickups
├── thug_wearables/      # 5 masks, plate carrier, & studded bracers
├── street_props/        # 5 NYC street crime props & lamp posts
├── civilian_vehicles/   # 5 civilian traffic cars & trucks
├── AGENTS.md            # Co-Founder directive & RTCC prompt engineering standards
├── PROJECT_STATUS.md    # Master architecture, asset roster & session handover
└── Devlog_1_Script.md   # YouTube Devlog #1 video script (Dani/Duckable style)
```