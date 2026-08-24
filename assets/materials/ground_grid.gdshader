shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// World-space grid + checker so movement across a huge flat plane stays readable.

uniform vec3 base_color : source_color = vec3(0.145, 0.196, 0.129);
uniform vec3 alt_color : source_color = vec3(0.168, 0.227, 0.149);
uniform vec3 line_color : source_color = vec3(0.42, 0.52, 0.36);
uniform float minor_size = 2.0;
uniform float major_size = 16.0;
uniform float minor_strength : hint_range(0.0, 1.0) = 0.30;
uniform float major_strength : hint_range(0.0, 1.0) = 0.75;
uniform float minor_fade_distance = 90.0;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.92;

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
	SPECULAR = 0.15;
}
