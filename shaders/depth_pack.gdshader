shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

// Packs the Euclidean camera distance of each fragment into RG channels of
// an RGBA8 target:
//   R = which 0.25 m slab (floor(d*4)/256)   — coarse, exact levels
//   G = remainder inside the slab            — fine, ~0.4 mm precision
// The viewport encodes to sRGB on write; the warp shader decodes with
// pow(c, 2.2). Max range 64 m (maze diagonal is ~55 m).

varying float dist;

void vertex() {
	vec3 v = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	dist = length(v.xyz);
}

void fragment() {
	float d = clamp(dist, 0.0, 63.999);
	ALBEDO = vec3(floor(d * 4.0) / 256.0, d - floor(d * 4.0) * 0.25, 0.0);
}
