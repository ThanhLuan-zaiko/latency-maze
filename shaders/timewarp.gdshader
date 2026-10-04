shader_type canvas_item;

// ---------------------------------------------------------------------------
// Asynchronous TimeWarp + Positional TimeWarp (depth-assisted reprojection).
//
// warp_mode 0: raw — the stale frame is shown as rendered (judder!)
// warp_mode 1: rotational ATW — reproject by R_render^-1 * R_current
// warp_mode 2: + positional refinement — iterative depth-assisted gather:
//              seeded by the rotational solution, each step reconstructs the
//              rendered surface point (render ray + packed depth), slides the
//              display ray to that depth, and re-projects into the render
//              view. Converges for frontal surfaces; failures -> hole_color,
//              which is what disocclusion looks like on real PTW.
// ---------------------------------------------------------------------------

uniform int warp_mode = 1;
uniform int ptw_iterations = 3;

// poses
uniform mat3 reproj = mat3(1.0);           // R_r^-1 * R_c
uniform mat3 render_basis = mat3(1.0);     // R_r  (view->world)
uniform mat3 render_basis_inv = mat3(1.0); // R_r^-1
uniform mat3 current_basis = mat3(1.0);    // R_c  (view->world)
uniform vec3 render_pos = vec3(0.0);       // C_r
uniform vec3 current_pos = vec3(0.0);      // C_c

// tan(half-fov) for the display rays and for the overscanned render
uniform vec2 tan_half_fov_view = vec2(1.0, 0.6);
uniform vec2 tan_half_fov_render = vec2(1.0, 0.6);

// packed euclidean depth, rendered by the depth SubViewport
uniform sampler2D depth_tex : filter_nearest, repeat_disable;

// debug
uniform bool debug_viz = false;
uniform vec2 resolution = vec2(1600.0, 900.0);
uniform float viz_scale_px = 150.0;

uniform vec4 edge_color : source_color = vec4(0.0, 0.008, 0.03, 1.0);
uniform vec4 hole_color : source_color = vec4(0.4, 0.0, 0.3, 1.0);

vec2 dir_to_render_uv(vec3 d) {
	return vec2(0.5 + 0.5 * d.x / (-d.z) / tan_half_fov_render.x,
				0.5 - 0.5 * d.y / (-d.z) / tan_half_fov_render.y);
}

vec3 render_uv_to_dir(vec2 uv) {
	vec2 n = vec2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
	return vec3(n.x * tan_half_fov_render.x, n.y * tan_half_fov_render.y, -1.0);
}

bool uv_out(vec2 uv) {
	return uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0;
}

// invert the two-channel pack — the viewport writes sRGB-encoded RGBA8
// (verified empirically), so undo that first or the coarse slab snaps wrong
float srgb_to_lin(float c) {
	return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

float decode_depth(vec3 s) {
	float hi = srgb_to_lin(s.r) * 256.0;
	float lo = srgb_to_lin(s.g);
	return floor(hi + 0.5) * 0.25 + lo;
}

vec3 heat(float t) {
	t = clamp(t, 0.0, 1.0);
	vec3 c = mix(vec3(0.0, 0.0, 0.15), vec3(0.0, 0.25, 1.0), smoothstep(0.0, 0.2, t));
	c = mix(c, vec3(0.0, 1.0, 1.0), smoothstep(0.2, 0.4, t));
	c = mix(c, vec3(0.15, 1.0, 0.0), smoothstep(0.4, 0.6, t));
	c = mix(c, vec3(1.0, 0.9, 0.0), smoothstep(0.6, 0.8, t));
	c = mix(c, vec3(1.0, 0.0, 0.0), smoothstep(0.8, 1.0, t));
	return c;
}

void fragment() {
	// head-local ray through this display pixel (camera looks down -Z)
	vec2 ndc = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	vec3 dir_v = vec3(ndc.x * tan_half_fov_view.x,
					ndc.y * tan_half_fov_view.y,
					-1.0);

	// unwarped sample position — viz measures displacement from here
	vec2 suv0 = dir_to_render_uv(dir_v);

	// --- rotational reprojection ---
	vec3 dir_r = dir_v;
	if (warp_mode > 0) {
		dir_r = reproj * dir_v;
	}
	vec2 suv = dir_to_render_uv(dir_r);
	bool bad = dir_r.z > -0.02 || uv_out(suv);

	// --- positional refinement ---
	if (warp_mode > 1 && !bad) {
		vec3 dw = normalize(current_basis * dir_v); // display ray, world space
		for (int i = 0; i < ptw_iterations; i++) {
			// surface point the stale frame stored at the current guess
			vec3 rdir_w = normalize(render_basis * render_uv_to_dir(suv));
			float d = decode_depth(texture(depth_tex, suv).rgb);
			vec3 P = render_pos + rdir_w * d;
			// slide the display ray out to that surface distance
			float t = dot(P - current_pos, dw);
			if (t <= 0.02) {
				bad = true;
				break;
			}
			// re-project the corrected point into the render view
			vec3 ql = render_basis_inv * (current_pos + t * dw - render_pos);
			if (ql.z > -0.02) {
				bad = true;
				break;
			}
			suv = dir_to_render_uv(ql);
			if (uv_out(suv)) {
				bad = true;
				break;
			}
		}
	}

	vec3 col;
	if (bad) {
		// no valid sample: edge reveal (rot) / disocclusion hole (pos)
		col = warp_mode > 1 ? hole_color.rgb : edge_color.rgb;
	} else {
		col = texture(TEXTURE, suv).rgb;
	}

	if (debug_viz) {
		float dpx = bad ? viz_scale_px : length((suv - suv0) * resolution);
		col = heat(dpx / viz_scale_px);
	}
	COLOR = vec4(col, 1.0);
}
