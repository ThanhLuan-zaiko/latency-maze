shader_type spatial;
render_mode unshaded, cull_disabled;

// World-space checkerboard with glowing grid lines.
// High-contrast periodic patterns are exactly where motion judder and
// TimeWarp artefacts are the most visible — that is the point.

uniform vec4 color_a : source_color = vec4(0.012, 0.02, 0.035, 1.0);
uniform vec4 color_b : source_color = vec4(0.55, 0.9, 1.0, 1.0);
uniform float cells_per_meter = 1.0;
uniform float line_width = 0.035;      // fraction of a cell
uniform vec3 line_color : source_color = vec3(0.15, 0.85, 1.0);
uniform float line_emission = 1.5;

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	// Project onto the plane the surface is facing (axis-aligned geometry).
	vec3 an = abs(world_nrm);
	vec2 p = an.y > 0.6 ? world_pos.xz : (an.x > an.z ? world_pos.zy : world_pos.xy);

	vec2 cell = p * cells_per_meter;
	float checker = mod(floor(cell.x) + floor(cell.y), 2.0);
	vec3 col = mix(color_a.rgb, color_b.rgb, checker);

	// Emissive line on cell borders.
	vec2 f = fract(cell);
	float d = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float aa = fwidth(d) + 1e-4;
	float line = 1.0 - smoothstep(line_width - aa, line_width + aa, d);
	col = mix(col, line_color, line * 0.85);

	ALBEDO = col;
	EMISSION = line_color * line * line_emission;
}
