"""Recompute the `load_steps` hint in every .tscn / .tres under the project."""
import os, re, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
changed = 0
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in (".godot", ".git")]
    for fn in filenames:
        if not fn.endswith((".tscn", ".tres")):
            continue
        p = os.path.join(dirpath, fn)
        with open(p, encoding="utf-8") as f:
            s = f.read()
        steps = len(re.findall(r"^\[ext_resource ", s, re.M)) + \
                len(re.findall(r"^\[sub_resource ", s, re.M)) + 1
        new, n = re.subn(r"(\[gd_(?:scene|resource)[^\]]*?)load_steps=\d+", r"\g<1>load_steps=%d" % steps, s, count=1)
        if n == 0:
            new = re.sub(r"(\[gd_(?:scene|resource) )", r"\g<1>load_steps=%d " % steps, s, count=1)
        if new != s:
            with open(p, "w", encoding="utf-8") as f:
                f.write(new)
            changed += 1
            print("  %-46s load_steps=%d" % (os.path.relpath(p, root), steps))
print("updated %d file(s)" % changed)
