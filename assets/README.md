# Assets Directory

Production 3D models and gameplay media assets for *Spider-Man: Web of Destiny*.

## Directory Layout

```
assets/
├── media/                      # High-resolution video and footage captures
│   └── showcase_video.mp4      # 1080p 60fps gameplay showcase clip
│
└── models/                     # 39 production FBX models across 7 categories
    ├── civilian_vehicles/      # 5 traffic vehicles (Taxi, Truck, Sedan, Pickup, Hatchback)
    ├── rooftop_props/          # 5 rooftop skyline props (Water tower, HVAC, Fire escape, Hydrant, Dumpster)
    ├── spidey_gadgets/         # 5 Spider-Man accessories (Web shooters, Backpack, Pizza box, Tracer, Web bomb)
    ├── street_props/           # 5 NYC street props (Street lamps, NYPD barricades, Payphones, Cones, Fuse box)
    ├── throwable_props/        # 9 environmental props (Crates, Barrels, Manholes, 5 Mailbox styles)
    ├── thug_weapons/           # 5 thug combat weapons (Baseball bat, Knife, Crowbar, Handgun, Riot shield)
    └── thug_wearables/         # 5 enemy cosmetic meshes (Ski mask, Hockey mask, Beanie, Plate carrier, Bracers)
```

Each category includes exported `.fbx` models and a structured `export_report.json` detailing triangle counts, bounding dimensions, and coordinate validations.
