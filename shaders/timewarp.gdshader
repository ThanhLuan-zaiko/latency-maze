shader_type canvas_item;

// ---------------------------------------------------------------------------
// Asynchronous TimeWarp (rotational reprojection), same math as real VR
// compositors:
//
//   ray_world   = R_current  * dir_view(pixel)   // where the display ray aims
//   dir_render  = R_render^-1 * ray_world        // same ray in rendered frame
//   sample_uv   = perspective_project(dir_render)
//
// The rendered frame was produced with an older head pose; we resample it so
// it matches where the head is pointing RIGHT NOW, at scanout time.
// ---------------------------------------------------------------------------

// R_render^-1 * R_current (orthonormal camera bases, rotation only)
uniform mat3 reproj = mat3(1.0);
// tan(half fov) of the virtual display ray set: (x = tan(fov_y/2)*aspect, y)
uniform vec2 tan_half_fov_view = vec2(1.0, 0.6);
// same for the rendered frame (larger because of overscan margin)
uniform vec2 tan_half_fov_render = vec2(1.0, 0.6);
uniform bool atw_enabled = true;
uniform vec4 edge_color : source_color = vec4(0.0, 0.008, 0.03, 1.0);

void fragment() {
	// Head-local ray through this display pixel (camera looks down -Z).
	vec2 ndc = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	vec3 dir = vec3(ndc.x * tan_half_fov_view.x,
					ndc.y * tan_half_fov_view.y,
					-1.0);

	if (atw_enabled) {
		dir = reproj * dir;
	}

	// Project the (possibly warped) ray back into the rendered image's UVs.
	float inv_fwd = -1.0 / dir.z;
	vec2 suv = vec2(0.5 + 0.5 * dir.x * inv_fwd / tan_half_fov_render.x,
					0.5 - 0.5 * dir.y * inv_fwd / tan_half_fov_render.y);

	if (dir.z > -0.02 || suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) {
		// No rendered data here: edge reveal, same artefact real ATW shows
		// when the overscan margin runs out.
		COLOR = edge_color;
	} else {
		COLOR = texture(TEXTURE, suv);
	}
}
