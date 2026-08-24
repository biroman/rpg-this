shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// Warm paper with a faint survey grid ruled on it.
//
// The grid is not decoration. This is a flat plane a couple of hundred metres
// across with nothing on it, and without a ruler on the ground there is no way
// to read distance or your own speed. So it is kept as light as it can be and
// still do that job - the major lines carry it, the minor ones fade out before
// they can turn the middle distance into a moire.
//
// Lambert and no specular on purpose: the ground is paper, not a surface with a
// sheen, and the only thing the light should do to it is shade it.

uniform vec3 base_color : source_color = vec3(0.965, 0.945, 0.906);
uniform vec3 alt_color : source_color = vec3(0.945, 0.922, 0.871);
uniform vec3 line_color : source_color = vec3(0.890, 0.859, 0.788);
uniform float minor_size = 2.0;
uniform float major_size = 16.0;
uniform float minor_strength : hint_range(0.0, 1.0) = 0.35;
uniform float major_strength : hint_range(0.0, 1.0) = 0.85;
uniform float minor_fade_distance = 70.0;
uniform float surface_roughness : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Screen-space antialiased grid line mask.
float grid_mask(vec2 p, float cell) {
	vec2 uv = p / cell;
	vec2 g = abs(fract(uv - 0.5) - 0.5) / fwidth(uv);
	return 1.0 - min(min(g.x, g.y), 1.0);
}

void fragment() {
	vec2 p = world_position.xz;

	vec2 cell = floor(p / major_size);
	float checker = mod(cell.x + cell.y, 2.0);
	vec3 col = mix(base_color, alt_color, checker);

	float dist = length(world_position - CAMERA_POSITION_WORLD);
	float minor_fade = clamp(1.0 - dist / minor_fade_distance, 0.0, 1.0);

	float minor = grid_mask(p, minor_size) * minor_strength * minor_fade;
	float major = grid_mask(p, major_size) * major_strength;
	float lines = clamp(minor + major, 0.0, 1.0);

	ALBEDO = mix(col, line_color, lines);
	ROUGHNESS = surface_roughness;
	SPECULAR = 0.0;
}
