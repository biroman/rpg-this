class_name PuffMesh
extends RefCounted
## The lumpy sphere that both the motor trail and the blast cloud are built from.
##
## Solid, unit-radius geometry - not a billboard. Instanced a few hundred times
## along a path it builds a real 3D volume of smoke: it parallaxes correctly,
## occludes itself from any angle, and you can fly the replay camera through it.
##
## Normals are worked out from the neighbouring grid points rather than with
## `generate_normals()`. SurfaceTool only welds vertices it can match and this
## surface is built unindexed, so `generate_normals()` would hand back flat
## per-face normals and the blob would shade as a shattered mess of facets.

## Meshes are identical for every caller, so they are built once and shared.
static var _cache: Dictionary = {}


## Radius of a unit blob in direction `d`. Products of sines give the cauliflower
## lumps that stop it reading as a ball bearing. Deterministic, so the mesh comes
## out identical every run.
static func _radius(d: Vector3) -> float:
	var r: float = 1.0
	r += 0.180 * sin(d.x * 5.3 + 0.7) * sin(d.y * 4.7 + 1.9)
	r += 0.130 * sin(d.y * 6.1 + 2.4) * sin(d.z * 5.9 + 0.3)
	r += 0.100 * sin(d.z * 7.7 + 1.1) * sin(d.x * 7.1 + 2.8)
	r += 0.060 * sin((d.x + d.y + d.z) * 9.3 + 0.5)
	return r


## Keep the tessellation low. These are small on screen and overlap heavily, so
## the silhouette is the union of many blobs and individual facets never read.
static func blob(rings: int = 6, segments: int = 11) -> ArrayMesh:
	var key: String = "%d_%d" % [rings, segments]
	if _cache.has(key):
		return _cache[key]

	var grid: Array = []
	for i in rings + 1:
		var phi: float = PI * float(i) / float(rings)
		var row: Array = []
		for j in segments + 1:
			var th: float = TAU * float(j) / float(segments)
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			row.append(d * _radius(d))
		grid.append(row)

	# Smooth normals: cross the two surface tangents, wrapping in theta.
	var norms: Array = []
	for i in rings + 1:
		var row: Array = []
		for j in segments + 1:
			var jm: int = (j - 1 + segments) % segments
			var jp: int = (j + 1) % segments
			var im: int = maxi(i - 1, 0)
			var ip: int = mini(i + 1, rings)
			var t_th: Vector3 = grid[i][jp] - grid[i][jm]
			var t_ph: Vector3 = grid[ip][j] - grid[im][j]
			var n: Vector3 = t_th.cross(t_ph)
			if n.length_squared() < 1e-12:
				n = (grid[i][j] as Vector3).normalized()      # the poles degenerate
			row.append(n.normalized())
		norms.append(row)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Winding follows d/dtheta x d/dphi, which points outward.
	for i in rings:
		for j in segments:
			for e in [[i, j], [i, j + 1], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i + 1, j]]:
				st.set_normal(norms[e[0]][e[1]])
				st.add_vertex(grid[e[0]][e[1]])

	var built: ArrayMesh = st.commit()
	_cache[key] = built
	return built
