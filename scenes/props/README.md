Reusable placeable scenes go here (crates, doors, pickups, spawners).

Each prop is its own `.tscn` + `.gd` pair, e.g. `crate.tscn` / `crate.gd`.
The world currently generates its blocks procedurally in `world.gd`; replace
that with instances of scenes from this folder when they get real behaviour.
