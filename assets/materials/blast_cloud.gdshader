// ============================================================================
//  Explosion cloud - the same solid blob geometry as the motor trail, but each
//  puff carries a HEAT value that drives it along an incandescence ramp:
//
//      white-hot -> yellow -> orange -> red -> dark ember -> cold soot
//
//  Two things make this read as fire rather than as orange-painted smoke:
//   * heat drives EMISSION, not albedo. A fireball is a light source, so it
//     stays bright in shadow and blooms; the albedo underneath stays near
//     black, which is what soot actually is.
//   * the two shading models crossfade. Hot puffs are pure emission with no
//     diffuse response at all, cold puffs are lit smoke, and in between you get
//     the dull glowing grey of a fireball collapsing into a smoke column.
// ============================================================================
shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_disabled;

group_uniforms fire;
uniform vec3 white_hot : source_color = vec3(1.00, 0.98, 0.91);
uniform vec3 yellow : source_color = vec3(0.98, 0.75, 0.27);
uniform vec3 orange : source_color = vec3(0.94, 0.50, 0.24);
uniform vec3 red : source_color = vec3(0.84, 0.20, 0.36);
uniform vec3 ember : source_color = vec3(0.29, 0.08, 0.14);
// Tuned against this project's ACES tonemapper (white 6.0): any higher and
// everything above half heat clips to flat white and the ramp never shows.
uniform float fire_energy : hint_range(0.0, 20.0) = 9.0;

group_uniforms smoke;
uniform vec3 soot_dark : source_color = vec3(0.55, 0.54, 0.52);
uniform vec3 soot_light : source_color = vec3(0.93, 0.91, 0.88);
uniform float wrap_power : hint_range(0.5, 4.0) = 1.15;
uniform float floor_light : hint_range(0.0, 1.0) = 0.22;
uniform float translucency : hint_range(0.0, 2.0) = 0.35;

uniform float dissolve_scale = 3.4;

varying vec3 v_local;
varying vec3 v_wnormal;
varying vec4 v_custom;

void vertex() {
	v_local = VERTEX;
	v_custom = INSTANCE_CUSTOM;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 fire_ramp(float h) {
	vec3 c = mix(ember, red, smoothstep(0.02, 0.28, h));
	c = mix(c, orange, smoothstep(0.28, 0.55, h));
	c = mix(c, yellow, smoothstep(0.55, 0.80, h));
	c = mix(c, white_hot, smoothstep(0.80, 1.00, h));
	return c;
}

void fragment() {
	float seed = v_custom.x * 37.0;
	float heat = clamp(v_custom.y, 0.0, 1.0);
	float dissolve = v_custom.z;

	// break up into fragments as it dies - discard, never ALPHA, or the
	// material is classed transparent and stops writing depth
	if (dissolve > 0.001) {
		float n = 0.5 + 0.5
			* sin(v_local.x * dissolve_scale + seed)
			* sin(v_local.y * dissolve_scale * 0.86 + seed * 1.7)
			* sin(v_local.z * dissolve_scale * 0.94 + seed * 2.3);
		if (n + 0.06 < dissolve * 1.25) {
			discard;
		}
	}

	// cold soot: dark, with lighter crowns where the sky reaches it
	float upness = clamp(v_wnormal.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 smoke_albedo = mix(soot_dark, soot_light, smoothstep(0.10, 0.90, upness));

	// hot puffs go near-black in albedo so the emission is doing all the work
	ALBEDO = mix(smoke_albedo, vec3(0.20), heat) * COLOR.rgb;
	// A slight falloff toward the silhouette of each puff: you are looking
	// through less glowing gas at its edge than through its middle. Kept gentle
	// - emission is otherwise constant across a blob, which makes every puff a
	// flat disc of one colour, but push it hard and the ball just goes dark.
	float thickness = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);

	// Steep, not linear. A gentle curve leaves half-cooled puffs glowing a flat
	// red that reads as painted cardboard; squaring it hard keeps the light in
	// the material that is genuinely still burning and lets the rest be smoke.
	EMISSION = fire_ramp(heat) * pow(heat, 2.2) * fire_energy * mix(0.72, 1.12, thickness);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	// A glowing puff has no meaningful diffuse response - it IS the light
	// source - so the sun term fades out as heat comes up.
	// (no early return here: `return` is not legal in a light() function)
	float heat = clamp(v_custom.y, 0.0, 1.0);
	float cold = 1.0 - smoothstep(0.05, 0.55, heat);

	if (cold > 0.001) {
		vec3 N = normalize(NORMAL);
		vec3 L = normalize(LIGHT);
		vec3 V = normalize(VIEW);

		float w = pow(clamp(dot(N, L) * 0.5 + 0.5, 0.0, 1.0), wrap_power);
		w = mix(floor_light, 1.0, w);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * w * cold;

		float back = pow(clamp(dot(V, -L), 0.0, 1.0), 4.0);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * back * translucency * cold;
	}
}
