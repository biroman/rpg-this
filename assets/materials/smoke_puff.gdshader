// ============================================================================
//  Motor smoke, on real geometry.
//
//  Each puff is a solid lumpy sphere, instanced a few hundred times along the
//  rocket's path. Nothing here is a billboard: the normals come from actual
//  mesh geometry, so the volume parallaxes correctly, you can fly the replay
//  camera through it, and it occludes itself properly from any angle.
//
//  IMPORTANT: the dissolve uses discard, NOT ALPHA. Writing ALPHA at all makes
//  Godot classify the material as transparent, and a transparent material does
//  not write depth - so the puffs stop occluding one another and the rope goes
//  see-through as you move around it. discard keeps this fully opaque.
//
//  Lighting is wrapped rather than lambert. Light scatters right around a
//  droplet cloud instead of terminating at 90 degrees, which is why real smoke
//  never shows a hard shadow line - that single detail is most of what makes
//  something read as vapour instead of plastic.
// ============================================================================
shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_disabled;

uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 crown_color : source_color = vec3(1.0, 0.995, 0.98);
uniform vec3 belly_color : source_color = vec3(0.78, 0.79, 0.80);
uniform float form : hint_range(0.0, 1.0) = 0.60;

uniform float wrap_power : hint_range(0.5, 4.0) = 1.05;
uniform float sun_amount : hint_range(0.0, 3.0) = 0.85;
uniform float floor_light : hint_range(0.0, 1.0) = 0.28;
uniform float translucency : hint_range(0.0, 2.0) = 0.60;
uniform float rim_amount : hint_range(0.0, 2.0) = 0.30;
uniform float variation : hint_range(0.0, 0.4) = 0.10;
uniform float dissolve_scale = 5.2;

varying vec3 v_local;
varying vec3 v_wnormal;
varying vec4 v_custom;

void vertex() {
	v_local = VERTEX;
	v_custom = INSTANCE_CUSTOM;
	// instance scale is uniform, so normalising is enough here
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float seed = v_custom.x * 37.0;
	float dissolve = v_custom.z;

	// break the blob into fragments as it dies rather than ghosting out
	if (dissolve > 0.001) {
		float n = 0.5 + 0.5
			* sin(v_local.x * dissolve_scale + seed)
			* sin(v_local.y * dissolve_scale * 0.86 + seed * 1.7)
			* sin(v_local.z * dissolve_scale * 0.94 + seed * 2.3);
		if (n + 0.06 < dissolve * 1.25) {
			discard;
		}
	}

	// Vertical form baked into albedo rather than into the light term, so the
	// sky ambient obeys it too: sunlit crowns, cool shaded bellies. This is what
	// gives a cloud its mass no matter where the sun happens to be.
	float upness = clamp(v_wnormal.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 body = mix(belly_color, crown_color, smoothstep(0.12, 0.88, upness));
	body = mix(crown_color, body, form);

	// a little value spread between neighbouring puffs, so the rope is not one
	// flat mass
	float vary = 1.0 + variation * (sin(seed * 12.9898) * 0.5);

	ALBEDO = COLOR.rgb * tint * body * vary;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	vec3 N = normalize(NORMAL);
	vec3 L = normalize(LIGHT);
	vec3 V = normalize(VIEW);

	// Wrapped diffuse, with a floor: light scatters right around a droplet
	// cloud, and multiple scattering means the shadow side is never black.
	float w = pow(clamp(dot(N, L) * 0.5 + 0.5, 0.0, 1.0), wrap_power);
	w = mix(floor_light, 1.0, w);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * w * sun_amount;

	// light punching through the thin edges when the sun is behind the puff
	float back = pow(clamp(dot(V, -L), 0.0, 1.0), 4.0);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * back * translucency;

	// bright silhouette so the rope reads against the sky
	float rim = pow(1.0 - clamp(dot(N, V), 0.0, 1.0), 3.0);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * rim * rim_amount * w;
}
