# FlatWorld

Godot 4.7 rocket range: a large flat world, a shoulder-fired launcher, and a
short run of levels. Clear a level and you can watch the shot back from a camera
bolted to the rocket, scrubbing the timeline in slow motion.

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

In a replay:

| Input | Action |
| --- | --- |
| Drag mouse | Orbit the camera around the rocket |
| Scroll wheel | Zoom in / out |
| Space | Play / pause |
| Left / Right | Step a frame |
| R | Restart the replay |
| Esc / Enter | Skip to the next level |

## Shipping a build

Players run a self-updating `FlatWorld.exe`: on launch it checks GitHub Releases
and installs a newer build if there is one. To put everybody on your latest work:

```powershell
.\tools\release.ps1
```

See [docs/RELEASING.md](docs/RELEASING.md) for setup, options and how the
updater behaves.

## Structure

```
res://
├── autoload/            Global singletons (registered in project.godot)
│   ├── event_bus.gd     Signal hub - no state, no logic
│   ├── game_state.gd    Pause, mouse capture, player/world registry
│   ├── score.gd         Shots, hits, accuracy, best distance
│   └── replay.gd        Holds the recorded shots
├── assets/              Art, audio, fonts, shaders
│   └── materials/       ground_grid.gdshader
├── scenes/
│   ├── main/            Entry point - wires world + player + UI
│   ├── game/            Level flow: what is placed where, in what weather
│   ├── world/           The arena: ground, lighting, environment, wind
│   ├── replay/          Shot recording and the replay viewer
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

## Art direction

Flat pastel on warm paper, after Mini Motorways. Three rules carry the whole
look:

- **The world is light and the ink is dark.** The ground is cream, the sky is
  pale blue, and every piece of text and the crosshair are near-black. That is
  the reverse of the usual first-person convention, and it is why nothing in the
  HUD carries a drop shadow - there is nothing to separate the type from.
- **Nothing is metallic and nothing is glossy.** Every surface is one authored
  colour that the light only shades. Ambient is a fixed warm white rather than
  the sky, because sky ambient tints every cream surface blue; between it and a
  gentle sun, a shaded face lands at about 0.8 of its albedo and a lit one at
  1.0, so an authored colour looks like the colour that was authored. Tonemapping
  is linear for the same reason.
- **Nothing has a hard edge.** Models stay authored as boxes and cylinders,
  because those are what you can place by eye in the editor, and
  `scenes/style/rounded.gd` rebuilds each one with a fillet on load. Watch the
  winding if you touch it: Godot treats a triangle as front-facing when its
  vertices read *clockwise* from outside, and getting that backwards builds every
  mesh inside out.

`scenes/style/palette.gd` is the reference copy of the colours. Scenes have to
inline theirs as literals, so it is not the only copy - but if it and a `.tscn`
disagree, it is right. `scenes/style/mini.tres` is the UI theme (Nunito, dark
pill buttons, paper panels) and is wired up as the project-wide default.

## World

- 480 x 480 m ground plane, collision box under it, invisible walls at the edge.
- Grid + checker shader in world space, so distance and speed stay readable.
- Nothing is placed in the scene. `LevelManager` builds each level by calling
  `World.spawn(scene, position)`, so the arena stays a stage rather than a level.
- `World.wind` is the level's weather. Only projectiles feel it.

## Levels

`scenes/game/level_manager.gd` owns the run. A level is one entry in its `LEVELS`
array - a distance, a target size and the wind to shoot through:

| # | Name | Range | Wind |
| --- | --- | --- | --- |
| 1 | FIRST SHOT | 100 m | still |
| 2 | CROSSWIND | 150 m | 6 m/s left to right |

Starting a level clears the last target and any smoke still hanging about, sets
the wind, spawns a fresh target and hands the player a loaded tube.

Hitting the target clears the level but does **not** stop the game. A result card
fades in beside the crosshair and the range keeps running underneath it: the blast
is still going off, the smoke is still drifting, and the player can walk downrange
or fire again. `[E]` watches the replay, `[ENTER]` moves on, and nothing happens
until one of them is pressed. The only thing that freezes the tree is the replay
itself. After the last level the run wraps back to the first.

Adding a level is one dictionary in `LEVELS`. Nothing else needs touching - the
HUD banner, the wind gauge and the replay title all read from it.

### Wind

`World.wind` is a plain velocity in metres per second. The rocket turns it into a
steady lateral acceleration of `wind * wind_response` (0.34 by default), so a
6 m/s crosswind pushes an otherwise identical 150 m shot about 5.6 m downrange.
That is roughly two degrees of lead - enough to have to think about, not enough
to be a coin flip. The HUD draws a compass rose rotated into the player's own
view, so an arrow pointing right means the rocket will drift right.

## Replay

Clearing a level offers a replay of the shot that did it. It is not a
re-simulation: `scenes/replay/shot_recording.gd` is a plain data record that the
rocket fills in as it flies, one sample per physics tick, and hands to the
`Replay` autoload when it detonates. The recording outlives the rocket, so
playback is a pure function of the scrub time.

That is what makes the rest of it work:

- **Timeline** - drag or click anywhere, forwards or backwards, at any speed.
- **Speed** - 0.1x to 2x, so you can watch the last tenth of a second land.
- **Camera** - hangs off the rocket, always looking at it. It sits behind the
  current heading by default; drag to orbit, scroll to zoom. Because the
  recording knows the impact is coming, the camera starts backing off half a
  second early and is clear of the fireball before it goes off.
- **Trail** - the smoke laid down so far as a camera-facing ribbon, the whole arc
  as a faint line, and that arc flattened onto the ground for a height cue.

The rocket you watch is not a copy of the model: `ReplayView` lifts the `Visual`
subtree straight out of `rocket.tscn`, so the replay can never drift out of sync
with the real projectile.

### Testing it

`scenes/test/replay_smoke_test.tscn` plays the whole run: clears level 1, checks
that doing so left the game running, checks the recording lines up with the
muzzle and the impact, scrubs the replay end to
end, measures the level 2 wind drift, clears it with a lead and checks the run
wraps round. Run it with F6; results land in `tools/last_replay_test.log`. Add
`-- --shots` on the command line to dump a screenshot of each stage to `user://`.

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

### Smoke and fire

The motor trail and the explosion are not sprites. Both are built from the same
thing: a solid, lumpy, unit-radius sphere (`puff_mesh.gd`) instanced a few
hundred times through a `MultiMeshInstance3D`, shaded so it reads as vapour.
Because it is real geometry it parallaxes correctly, occludes itself from any
angle, and holds up when a camera flies through it - which matters here, since
the replay camera sits five metres behind the rocket.

| File | Role |
| --- | --- |
| `puff_mesh.gd` | The lumpy blob, cached and shared by both effects |
| `smoke_trail.gd` | Motor smoke laid along the flight path |
| `blast_cloud.gd` | The fireball and the smoke column it collapses into |
| `assets/materials/smoke_puff.gdshader` | Lit smoke |
| `assets/materials/blast_cloud.gdshader` | The same, plus an incandescence ramp driven by per-puff heat |

Three details do most of the work:

- **Puffs are laid per metre travelled, interpolated along each step.** `feed()`
  is called once per physics tick, and at 90 m/s the rocket has already moved
  1.5 m by then. Sampling gives a string of lonely blobs with holes between
  them; walking the segment in fixed strides gives one continuous rope.
- **The dissolve uses `discard`, never `ALPHA`.** Writing `ALPHA` at all makes
  Godot classify the material as transparent, and a transparent material does
  not write depth - the puffs would stop occluding one another and the whole
  rope would go see-through as you moved around it.
- **Thinning is neighbour-driven, not budget-driven.** A puff is dropped only
  when its two neighbours already overlap without it, so the rope is never left
  with a hole. Since puffs swell as they age this self-limits, settling at
  whatever density the trail actually needs along its length.

Both effects were ported from the SeaHunter project and rescaled - this rocket
is an order of magnitude slower and shorter ranged than a cruise missile - and
two things had to change beyond the numbers. The rocket is fired off a shoulder
rather than out of a silo, so it lays no smoke until it is `trail_standoff`
clear of the tube; without that the first puffs land inside the player's head
and fill the screen. And both effects hide themselves while the replay is open,
because the replay camera flies straight down the middle of the trail and solid
geometry cannot fade out near the lens the way the replay's own ribbon does.

### Sound

The weapon's three loudest sounds are cut from real recordings rather than
synthesised. `tools/extract_audio.py` reads the raw takes in
`tools/source-audio/` and produces:

| File | Cut from | What it is |
| --- | --- | --- |
| `rocket_launch.wav` | `rpg-shot.mp3` | 0.66 s one-shot: the crack, the gap, the motor catching |
| `rocket_motor.wav` | `rpg-shot.mp3` | 3 s of the motor running, crossfaded to loop seamlessly |
| `explosion.wav` | `explosion.mp3` | the detonation, trimmed and levelled |

`rpg-shot.mp3` holds three takes of an RPG shot, each one a launch crack, a
short gap while the sustainer catches, then the motor running until the rocket
is out of earshot. The script finds the takes by their silence and splits the
middle one, so nothing is hardcoded to a timestamp.

The rocket plays those two the way the recording is laid out: the launcher fires
the one-shot, and the motor loop is faded in when the sustainer actually lights
(`ignition_delay`) and faded out at burnout, so the rocket coasts the last
stretch of its flight in silence.

The loop is made seamless by crossfading the material just past its end back
over its start, equal-power so noise-like material keeps a constant level. The
join measures a 0.2 dB level step and a sample-to-sample discontinuity no larger
than the ordinary motion of the waveform.

Everything is written as mono. All of it plays through `AudioStreamPlayer3D`,
which can only pan a source it can treat as a point; a stereo file keeps its own
width and stops locating properly in the world.

#### Sound takes time to arrive

`World.speed_of_sound` is 343 m/s and `World.sound_delay()` turns a position
into a delay. The blast and the target's ding both wait it out, so a hit on the
100 m target flashes silently and thumps you a third of a second later - nearly
half a second at 150 m. Measured against a capture of the master bus, the bang
lands 0.290 s after the flash for a predicted 0.291 s.

That is the whole of it. This is flat open ground with nothing to bounce off, so
there is no reverb and no slapback anywhere in the mix - just the delay, and the
distance rolloff and air-absorption filter that `AudioStreamPlayer3D` already
applies.

Two details make that work in practice. The shot that clears a level freezes the
whole tree the instant the target scores - which is right in the middle of its
own bang's flight time - so both audio players run on `PROCESS_MODE_ALWAYS`, and
the delay uses a `SceneTreeTimer`, which ignores pause by default. Verified:
with the result panel up and the game frozen, the bang still arrives on time.

`extract_audio.py` needs `soundfile` to decode an MP3; it is a one-off, since
the WAVs it produces are committed. The target ding, the reload and dry-fire
clicks and the particle/decal textures are still generated by
`tools/generate_assets.py`, which is stdlib-only. Re-run either from the project
root.

### Testing it

`scenes/test/weapon_smoke_test.tscn` boots the real game scene, fires at fixed
elevations and prints the ballistics table above. Run it with F6 after changing
anything in `scenes/weapons/`; results also land in `tools/last_smoke_test.log`.

## Target and scoring

The level spawns a ringed target straight ahead of the spawn, centre at 2.3 m.
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

### Hitting a thin target

The face is a 2 m disc only 28 cm thick, and the rocket is a 9 cm sphere that
crosses it at up to 90 m/s - well over a metre per physics tick. Godot's
`continuous_cd` does not catch that, so the rocket sweeps its own path: at the
start of each physics step it casts a ray along the motion that step is about to
make and detonates on the first thing in the way. That runs before the solver,
so the rocket never penetrates anything, and both the impact point and the speed
it struck at are the real ones rather than whatever a contact left behind.

How the pieces talk: `rocket.gd` emits `EventBus.rocket_impact` carrying the
exact impact point, the body it struck and the blast radius. `target.gd` turns
that into a report dictionary and emits `target_hit` / `target_missed`. The
`Score` autoload tallies shots, hits, accuracy and your best distance; the HUD
just renders both. Nothing knows about anything else, so extra targets are drag
and drop - instance `target.tscn` anywhere and it scores itself.

Measured with the smoke test, firing from the spawn at the 100 m target:

| Elevation | Result | Rocket distance from centre |
| --- | --- | --- |
| 10.0 deg | miss | 9.93 m short |
| 10.5 deg | blast hit | 3.86 m short |
| 11.0 deg | direct, edge ring | 1.83 m |
| 11.5 deg | direct, mid ring | 0.97 m |
| 12.0 deg | direct, bullseye | 0.15 m |

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
- Build props as their own scenes in `scenes/props/` and spawn them from a level.
- New levels: one dictionary in `LevelManager.LEVELS`.
