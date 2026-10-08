# Procedural 3D Asset Generation Pipeline

Headless Blender 5.1 Python automation scripts used to generate the 39 bespoke 3D `.fbx` models for *Spider-Man: Web of Destiny*.

## Standards & Constraints

- **Scale:** 1 Blender Unit = 1 Roblox Stud ($1\text{ stud} = 0.28\text{m}$).
- **Geometry:** Manifold, zero degenerate faces (`dissolve_degenerate`), beauty-triangulated.
- **Triangle Budget:** Strict 500–1,400 triangles per asset (700–1,400 for vehicles).
- **Pivot:** Ground props at $Z=0$; wall props at $Y=0$.
- **Exterior-Only:** Solid tinted glass on vehicles and kiosks (zero polygons wasted on unseen interiors).

## CLI Usage

Run any script headlessly via Blender from the repository root:

```bash
# 1. Civilian Vehicles (Taxi, Truck, Sedan, Pickup, Hatchback)
blender --background --python tools/blender/generate_civilian_vehicles.py -- --output-dir assets/models/civilian_vehicles

# 2. Rooftop Skyline Props (Water tower, HVAC, Fire escape, Hydrant, Dumpster)
blender --background --python tools/blender/generate_rooftop_props.py -- --output-dir assets/models/rooftop_props

# 3. Spidey Gadgets & Items (Web shooters, Backpack, Pizza box, Tracer, Web bomb)
blender --background --python tools/blender/generate_spidey_gadgets.py -- --output-dir assets/models/spidey_gadgets

# 4. Street Level Props (NYC Street lamp, NYPD barricade, Payphone, Cones, Fuse box)
blender --background --python tools/blender/generate_street_props.py -- --output-dir assets/models/street_props

# 5. Environmental Throwables (Crates, Barrels, Manholes, 5 Mailbox variants)
blender --background --python tools/blender/generate_throwable_props.py -- --output-dir assets/models/throwable_props

# 6. Thug Combat Weapons (Baseball bat, Knife, Crowbar, Handgun, Riot shield)
blender --background --python tools/blender/generate_thug_weapons.py -- --out assets/models/thug_weapons

# 7. Thug Wearables & Masks (Ski mask, Hockey mask, Beanie, Plate carrier, Bracers)
blender --background --python tools/blender/generate_thug_wearables.py -- --output-dir assets/models/thug_wearables
```
