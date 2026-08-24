# FlatWorld

Godot 4.7 boilerplate: a large flat world you can walk around in first person.

## Run

Open the folder in Godot 4.7 and press F5, or run the `Main` scene.

## Controls

| Key | Action |
| --- | --- |
| W A S D / Arrows | Move |
| Mouse | Look |
| Shift | Sprint (forward only) |
| Ctrl | Crouch |
| Space | Jump |
| Left mouse | Fire |
| R | Reload |
| Esc | Pause / release mouse |
| F3 | Debug overlay |
| F11 | Fullscreen |

## Structure

```
res://
├── autoload/            Global singletons (registered in project.godot)
│   ├── event_bus.gd     Signal hub - no state, no logic
│   ├── game_state.gd    Pause, mouse capture, player/world registry
│   └── score.gd         Shots, hits, accuracy, best distance
├── assets/              Art, audio, fonts, shaders
│   └── materials/       ground_grid.gdshader
├── scenes/
│   ├── main/            Entry point - wires world + player + UI
│   ├── world/           The level: ground, lighting, environment
│   ├── player/          First-person CharacterBody3D controller
│   ├── weapons/         Weapon base class, launcher, rocket, explosion
│   ├── props/           Placeable scenes - the scoring target lives here
│   ├── test/            Smoke tests you can run directly (F6)
│   └── ui/              HUD, pause menu, debug overlay
├── resources/           .tres data (tuning curves, configs)
├── addons/              Third-party plugins
└── tools/               Offline scripts (asset generation, maintenance)
```

Rule of thumb: a scene and its script live in the same folder. Anything shared
between features goes in `autoload/` (behaviour) or `assets/` (data).

## World

- 480 x 480 m ground plane, collision box under it, invisible walls at the edge.
- Grid + checker shader in world space, so distance and speed stay readable.
- The level is empty on purpose. Put anything you place under the `Props` node,
  or call `World.spawn(scene, position)` from code.

## Weapon

`scenes/weapons/` is a small four-part system:

| File | Role |
| --- | --- |
| `weapon.gd` | Base class: fire cadence, ammo, reload timing, recoil values |
| `rocket_launcher.gd` | Subclass: spawns the rocket, muzzle flash, backblast, audio |
| `rocket.gd` | The projectile and its flight model |
| `explosion.gd` | Blast impulse, particles, light flash, scorch decal, shake |
| `weapon_rig.gd` | Viewmodel motion: sway, walk bob, recoil spring, reload pose |

### Viewmodel

The held weapon lives in a `SubViewport` with `own_world_3d`, its own camera at
58 deg FOV and its own two-light rig, composited over the main view. That is the
standard first-person setup: the gun can never clip into walls, and it is lit
independently of the scene. The muzzle in that viewport is cosmetic - the actual
rocket is spawned into the real world from the player camera, aimed at whatever
the crosshair is over.

### Flight model

Three phases, matching a real shoulder-fired rocket:

1. The booster kicks it out of the tube at `muzzle_speed` (32 m/s) - slow enough
   to watch it go.
2. After `ignition_delay` the sustainer motor lights and pushes for `burn_time`,
   accelerating toward `max_speed`.
3. Motor burns out and it coasts as a plain ballistic body.

Thrust is applied along the *current velocity vector*, not the launch direction.
That is what a fin-stabilised rocket does - it weathervanes into the airflow -
and it means gravity bends the entire trajectory rather than just dropping the
tail. Measured range at the default settings, fired from eye height:

| Elevation | Flight time | Range |
| --- | --- | --- |
| 0 deg | 0.5 s | 20 m |
| 5 deg | 0.9 s | 42 m |
| 10 deg | 1.6 s | 89 m |
| 20 deg | 3.9 s | 223 m |

So you lead and loft, like the real thing. Every number is an `@export` on the
Rocket node in `rocket.tscn`.

### Assets

The sounds and particle/decal textures are generated, not downloaded -
`tools/generate_assets.py` synthesises them with the Python standard library.
Re-run it from the project root to regenerate or tweak them.

### Testing it

`scenes/test/weapon_smoke_test.tscn` boots the real game scene, fires at fixed
elevations and prints the ballistics table above. Run it with F6 after changing
anything in `scenes/weapons/`; results also land in `tools/last_smoke_test.log`.

## Target and scoring

A ringed target stands 100 m straight ahead of the spawn, centre at 2.3 m.
`scenes/props/target.gd` classifies every rocket impact in the world:

| Result | Meaning | Points |
| --- | --- | --- |
| `DIRECT HIT` | The rocket physically struck the target | 10 / 8 / 6 / 4 / 2 by ring |
| `BLAST HIT` | It landed elsewhere but the explosion reached the centre | 1-4, scaled by closeness |
| `MISS` | Neither, but within `report_miss_within` (120 m) of the centre | 0 |

Every result - hits included - reports **how far the rocket itself landed from
the centre**, so a blast hit still tells you how much you were off by, plus
whether you fell short or sailed long. That readout is the feedback loop for
learning the arc.

How the pieces talk: `rocket.gd` emits `EventBus.rocket_impact` carrying the
exact impact point, the body it struck and the blast radius. `target.gd` turns
that into a report dictionary and emits `target_hit` / `target_missed`. The
`Score` autoload tallies shots, hits, accuracy and your best distance; the HUD
just renders both. Nothing knows about anything else, so extra targets are drag
and drop - instance `target.tscn` anywhere and it scores itself.

Measured with the smoke test, firing from the spawn at the 100 m target:

| Elevation | Result | Rocket distance from centre |
| --- | --- | --- |
| 10.0 deg | miss | 10.05 m short |
| 10.5 deg | blast hit | 4.24 m short |
| 11.0 deg | direct, edge ring | 1.86 m |
| 11.5 deg | direct, mid ring | 1.01 m |
| 12.0 deg | direct, bullseye | 0.25 m |

Half a degree of elevation is the difference between a graze and a bullseye at
that range.

## Physics layers

| Layer | Name |
| --- | --- |
| 1 | world |
| 2 | player |
| 3 | props |
| 4 | interactable |
| 5 | projectile |

## Where to go next

- `player.gd` exports every movement value - tune in the inspector while running.
- `interact_ray` on the camera + `get_looked_at()` is the hook for interaction.
- Emit and listen on `EventBus` instead of wiring nodes to each other directly.
- New weapons: extend `Weapon`, override `_shoot()`, drop the scene under the
  `WeaponRig` in `player.tscn`.
- Build props as their own scenes in `scenes/props/` and place them under `Props`.
