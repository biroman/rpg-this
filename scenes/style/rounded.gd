class_name Rounded
extends RefCounted
## Primitive meshes with the hard edges taken off them.
##
## Nothing in this game is drawn with a sharp corner - that softness is most of
## what separates the look from "untextured primitives lit by a sun". Godot's
## box and cylinder primitives have no fillet, so this rebuilds them.
##
## The models stay authored as plain boxes and cylinders in their scenes, since
## those are what you can place by eye in the editor, and `soften()` swaps each
## one for its rounded twin on load: same size, same material, same place.

## Quads per face side on a box, and points per fillet on a cylinder. Four is
## enough for a radius this small to read as round without being a mesh worth
## counting.
const STEPS: int = 4

## Faces as [normal, u, v], picked so `u.cross(v)` is the outward normal and one
## winding rule serves all six.
const _FACES: Array = [
	[Vector3.RIGHT, Vector3.UP, Vector3.BACK],
	[Vector3.LEFT, Vector3.BACK, Vector3.UP],
	[Vector3.UP, Vector3.BACK, Vector3.RIGHT],
	[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
	[Vector3.BACK, Vector3.RIGHT, Vector3.UP],
	[Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
]


## Rebuilds every box and cylinder under `root` with rounded edges.
##
## `radius` is a ceiling rather than a promise: a part thinner than a few times
## the radius gets whatever fits, so a 6 mm front sight does not become a bead.
static func soften(root: Node, radius: float) -> void:
	for node in _mesh_instances(root):
		var box: BoxMesh = node.mesh as BoxMesh
		if box != null:
			var fit: float = _fit(radius, [box.size.x, box.size.y, box.size.z])
			if fit > 0.0001:
				node.mesh = box_mesh(box.size, fit, box.material)
			continue

		var tube: CylinderMesh = node.mesh as CylinderMesh
		if tube == null:
			continue
		var taper: float = absf(tube.top_radius - tube.bottom_radius)
		var side: float = sqrt(tube.height * tube.height + taper * taper)
		var fit_tube: float = _fit(radius, [tube.height, side,
			maxf(tube.top_radius, 0.001) * 2.0, maxf(tube.bottom_radius, 0.001) * 2.0])
		if fit_tube > 0.0001:
			node.mesh = cylinder_mesh(tube, fit_tube)


static func _fit(radius: float, extents: Array) -> float:
	var smallest: float = INF
	for e in extents:
		smallest = minf(smallest, float(e))
	return minf(radius, smallest * 0.4)


# --- boxes --------------------------------------------------------------

static func box_mesh(size: Vector3, radius: float, material: Material = null) -> ArrayMesh:
	var half: Vector3 = size * 0.5
	var core := Vector3(
		maxf(half.x - radius, 0.0),
		maxf(half.y - radius, 0.0),
		maxf(half.z - radius, 0.0)
	)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in _FACES:
		_add_box_face(st, face[0], face[1], face[2], half, core, radius)
	return _commit(st, material)


static func _add_box_face(st: SurfaceTool, normal: Vector3, u: Vector3, v: Vector3,
		half: Vector3, core: Vector3, radius: float) -> void:
	var reach_u: float = (u * half).length()
	var reach_v: float = (v * half).length()

	var grid: Array = []
	for i in STEPS + 1:
		var row: Array = []
		for j in STEPS + 1:
			var sharp: Vector3 = (
				normal * half
				+ u * lerpf(-reach_u, reach_u, float(i) / float(STEPS))
				+ v * lerpf(-reach_v, reach_v, float(j) / float(STEPS))
			)
			row.append(_pull_in(sharp, core, radius, normal))
		grid.append(row)

	for i in STEPS:
		for j in STEPS:
			_quad(st, grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1])


## Pulls one point of the sharp box onto the rounded surface: clamp it into the
## inner core, then push it back out by the radius. On the flat of a face that
## leaves it exactly where it started; near an edge or a corner it bends it.
static func _pull_in(point: Vector3, core: Vector3, radius: float, normal: Vector3) -> Array:
	var inner := Vector3(
		clampf(point.x, -core.x, core.x),
		clampf(point.y, -core.y, core.y),
		clampf(point.z, -core.z, core.z)
	)
	var out: Vector3 = point - inner
	var direction: Vector3 = out.normalized() if out.length_squared() > 0.000001 else normal
	return [inner + direction * radius, direction]


# --- cylinders ----------------------------------------------------------

## A cylinder or cone with its rims filleted, revolved from a rounded profile.
##
## The profile is the silhouette in (radius, height): out along the bottom cap,
## up the side, back in along the top. Both outer corners are cut short, which
## is what turns a rim you could cut yourself on into one the light rolls over.
static func cylinder_mesh(source: CylinderMesh, radius: float) -> ArrayMesh:
	var half_h: float = source.height * 0.5
	var foot := Vector2(source.bottom_radius, -half_h)
	var head := Vector2(source.top_radius, half_h)

	var profile: Array[Vector2] = [Vector2(0.0, -half_h)]
	profile.append_array(_cut_corner(Vector2(0.0, -half_h), foot, head, radius))
	profile.append_array(_cut_corner(foot, head, Vector2(0.0, half_h), radius))
	profile.append(Vector2(0.0, half_h))

	var normals: Array[Vector2] = _profile_normals(profile)
	var segments: int = maxi(source.radial_segments, 24)

	var grid: Array = []
	for k in profile.size():
		var ring: Array = []
		for j in segments + 1:
			var a: float = TAU * float(j) / float(segments)
			var c: float = cos(a)
			var s: float = sin(a)
			ring.append([
				Vector3(profile[k].x * c, profile[k].y, profile[k].x * s),
				Vector3(normals[k].x * c, normals[k].y, normals[k].x * s).normalized(),
			])
		grid.append(ring)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in profile.size() - 1:
		for j in segments:
			_quad(st, grid[k][j], grid[k + 1][j], grid[k + 1][j + 1], grid[k][j + 1])
	return _commit(st, source.material)


## Replaces corner `c` between `a` and `b` with a short curve. A quadratic
## through the corner is not a true fillet, but at these radii the difference is
## smaller than a pixel, and it cannot fail on a degenerate corner the way
## solving for a tangent circle can - which matters, because a nose cone has one.
static func _cut_corner(a: Vector2, c: Vector2, b: Vector2, radius: float) -> Array[Vector2]:
	var to_a: Vector2 = a - c
	var to_b: Vector2 = b - c
	if to_a.length() < 0.00001 or to_b.length() < 0.00001:
		return [c] as Array[Vector2]

	var back: float = minf(radius, minf(to_a.length(), to_b.length()) * 0.45)
	var start: Vector2 = c + to_a.normalized() * back
	var end: Vector2 = c + to_b.normalized() * back

	var arc: Array[Vector2] = []
	for i in STEPS + 1:
		var t: float = float(i) / float(STEPS)
		arc.append(start.lerp(c, t).lerp(c.lerp(end, t), t))
	return arc


## Outward normal per profile point, averaged across the segments either side so
## the fillet shades as one continuous surface rather than as facets.
static func _profile_normals(profile: Array[Vector2]) -> Array[Vector2]:
	var faces: Array[Vector2] = []
	for i in profile.size() - 1:
		var d: Vector2 = profile[i + 1] - profile[i]
		faces.append(Vector2(d.y, -d.x).normalized() if d.length() > 0.00001 else Vector2.RIGHT)
	if faces.is_empty():
		return [Vector2.RIGHT] as Array[Vector2]

	var out: Array[Vector2] = []
	for i in profile.size():
		var before: Vector2 = faces[maxi(i - 1, 0)]
		var after: Vector2 = faces[mini(i, faces.size() - 1)]
		var sum: Vector2 = before + after
		out.append(sum.normalized() if sum.length() > 0.00001 else before)
	return out


# --- shared -------------------------------------------------------------

## Corners are handed in anticlockwise around the outward normal, and emitted
## the other way round: Godot treats a triangle as front-facing when its
## vertices read *clockwise* from outside. Get this backwards and every mesh
## here is built inside out - the near surface is culled and you find yourself
## looking at the far one from within.
static func _quad(st: SurfaceTool, a: Array, b: Array, c: Array, d: Array) -> void:
	for corner in [a, c, b, a, d, c]:
		st.set_normal(corner[1])
		st.add_vertex(corner[0])


static func _commit(st: SurfaceTool, material: Material) -> ArrayMesh:
	var built: ArrayMesh = st.commit()
	if material != null and built.get_surface_count() > 0:
		built.surface_set_material(0, material)
	return built


static func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root as MeshInstance3D)
	for child in root.get_children():
		out.append_array(_mesh_instances(child))
	return out
