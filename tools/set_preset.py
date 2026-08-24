"""Switch the whole range between two tuned presets.

    python3 tools/set_preset.py arcade      # slow rocket, 100 m target, 480 m field
    python3 tools/set_preset.py realistic   # RPG-7 speeds, 350 m target, 1000 m field

`realistic` uses real RPG-7 numbers (115 m/s out of the tube, sustainer to
295 m/s) and moves the target out by the same ratio as the speed increase, so
the rocket still takes about 1.5 s to arrive and the target still covers the
same amount of screen. Everything that depends on scale - ground size, boundary
walls, shadow distance, fog, audio falloff, miss-report radius - moves with it.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PRESETS = {
    "arcade": {
        # rocket flight
        "muzzle_speed": "32.0", "ignition_delay": "0.09", "burn_time": "1.2",
        "thrust_acceleration": "45.0", "max_speed": "90.0", "life_time": "5.0",
        "rocket_damp": "0.05",
        # world scale
        "field": "480", "field_half": "240.0", "wall_offset": "241",
        "wall_len": "482", "target_z": "100", "target_scale": "1",
        "shadow_distance": "260.0", "fog_density": "0.0035",
        "miss_within": "120.0",
        # audio falloff
        "motor_distance": "220.0",
        "boom_unit": "28.0", "boom_distance": "400.0",
        "ding_unit": "90.0", "ding_distance": "600.0",
    },
    "realistic": {
        "muzzle_speed": "115.0", "ignition_delay": "0.1", "burn_time": "0.7",
        "thrust_acceleration": "257.0", "max_speed": "300.0", "life_time": "8.0",
        "rocket_damp": "0.02",
        "field": "1000", "field_half": "500.0", "wall_offset": "501",
        "wall_len": "1002", "target_z": "350", "target_scale": "3.5",
        "shadow_distance": "500.0", "fog_density": "0.0012",
        "miss_within": "400.0",
        "motor_distance": "700.0",
        "boom_unit": "60.0", "boom_distance": "1600.0",
        "ding_unit": "320.0", "ding_distance": "1600.0",
    },
}


def edit(rel_path, rules):
    path = os.path.join(ROOT, rel_path)
    with open(path, encoding="utf-8") as f:
        text = f.read()
    original = text
    for pattern, replacement in rules:
        text, n = re.subn(pattern, replacement, text)
        if n == 0:
            raise SystemExit("no match for %r in %s" % (pattern, rel_path))
    if text != original:
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        print("  updated %s" % rel_path)


def apply(name):
    v = PRESETS[name]

    edit("scenes/weapons/rocket.tscn", [
        (r"linear_damp = [\d.]+", "linear_damp = " + v["rocket_damp"]),
        (r"muzzle_speed = [\d.]+", "muzzle_speed = " + v["muzzle_speed"]),
        (r"ignition_delay = [\d.]+", "ignition_delay = " + v["ignition_delay"]),
        (r"burn_time = [\d.]+", "burn_time = " + v["burn_time"]),
        (r"thrust_acceleration = [\d.]+", "thrust_acceleration = " + v["thrust_acceleration"]),
        (r"max_speed = [\d.]+", "max_speed = " + v["max_speed"]),
        (r"life_time = [\d.]+", "life_time = " + v["life_time"]),
        (r"max_distance = [\d.]+", "max_distance = " + v["motor_distance"]),
    ])

    edit("scenes/weapons/explosion.tscn", [
        (r"unit_size = [\d.]+", "unit_size = " + v["boom_unit"]),
        (r"max_distance = [\d.]+", "max_distance = " + v["boom_distance"]),
    ])

    edit("scenes/props/target.tscn", [
        (r"unit_size = [\d.]+", "unit_size = " + v["ding_unit"]),
        (r"max_distance = [\d.]+", "max_distance = " + v["ding_distance"]),
    ])

    edit("scenes/props/target.gd", [
        (r"@export var report_miss_within: float = [\d.]+",
         "@export var report_miss_within: float = " + v["miss_within"]),
    ])

    edit("scenes/world/world.gd", [
        (r"@export var half_extent: float = [\d.]+",
         "@export var half_extent: float = " + v["field_half"]),
    ])

    s = v["target_scale"]
    edit("scenes/world/world.tscn", [
        # ground plane and its collision box
        (r"size = Vector2\([\d.]+, [\d.]+\)", "size = Vector2(%s, %s)" % (v["field"], v["field"])),
        (r"size = Vector3\([\d.]+, 2, [\d.]+\)", "size = Vector3(%s, 2, %s)" % (v["field"], v["field"])),
        # boundary walls
        (r"size = Vector3\([\d.]+, 220, 4\)", "size = Vector3(%s, 220, 4)" % v["wall_len"]),
        (r"Transform3D\(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 108, (-?)\d+\)",
         r"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 108, \g<1>%s)" % v["wall_offset"]),
        (r"Transform3D\(0, 0, -1, 0, 1, 0, 1, 0, 0, (-?)\d+, 108, 0\)",
         r"Transform3D(0, 0, -1, 0, 1, 0, 1, 0, 0, \g<1>%s, 108, 0)" % v["wall_offset"]),
        # the target: distance and scale
        (r"Transform3D\([\d.]+, 0, 0, 0, [\d.]+, 0, 0, 0, [\d.]+, 0, 0, -\d+\)",
         "Transform3D(%s, 0, 0, 0, %s, 0, 0, 0, %s, 0, 0, -%s)" % (s, s, s, v["target_z"])),
        # lighting and atmosphere have to reach further
        (r"directional_shadow_max_distance = [\d.]+",
         "directional_shadow_max_distance = " + v["shadow_distance"]),
        (r"fog_density = [\d.]+", "fog_density = " + v["fog_density"]),
    ])


if __name__ == "__main__":
    choice = sys.argv[1] if len(sys.argv) > 1 else ""
    if choice not in PRESETS:
        raise SystemExit("usage: python3 tools/set_preset.py [%s]" % " | ".join(PRESETS))
    print("applying preset: %s" % choice)
    apply(choice)
    print("done")
