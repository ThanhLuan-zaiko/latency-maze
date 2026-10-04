extends Node
## THE LATENCY MAZE — real-time Asynchronous TimeWarp (ATW) simulator.
##
## The maze renders into a SubViewport, but the camera pose is only refreshed
## at a simulated render rate (default 10 Hz) using a pose that is already
## `pipeline_latency_ms` old — a deliberately slow, late VR pipeline.
##
## The mouse-driven "head" updates every display frame like a high-rate IMU.
## Each frame a fullscreen shader re-projects the last rendered image by the
## rotation delta between the render pose and the live pose. That is exactly
## what a real VR compositor does right before scanout.
##
## warp_mode 1 corrects ROTATION only (like classic ATW); warp_mode 2 adds
## depth-assisted positional reprojection — a second viewport renders packed
## euclidean depth of layer-2 "twin" geometry so the warp shader can iterate
## the display ray onto the rendered depth surface. Disocclusions show as
## hole_color, exactly like real positional TimeWarp.

# --- Simulated hardware knobs (live-tweakable) ---
var render_interval_ms := 100.0  # simulated engine frame period (10 fps)
var pipeline_latency_ms := 40.0  # render uses a pose this many ms in the past
var atw_enabled := true
var positional_warp := false     # depth-assisted parallax correction (PTW)
var overscan := 1.18             # render-FOV margin so warping has spare pixels
var debug_viz := false           # warp-displacement heatmap
var display_fov_deg := 80.0

const INTERVAL_MIN := 20.0
const INTERVAL_MAX := 250.0
const LATENCY_MAX := 250.0
const HISTORY_SEC := 2.0

var viewport: SubViewport
var depth_vp: SubViewport
var world_root: Node3D
var camera: Camera3D
var depth_cam: Camera3D
var player: Player
var maze: Maze
var warp_mat: ShaderMaterial
var hud: HUD

var _accum_ms := 0.0
var _pose_history: Array[Dictionary] = []
var _render_basis := Basis.IDENTITY
var _render_pos := Vector3.ZERO
var _last_delta_deg := 0.0
var _last_pos_delta := 0.0
var _tick_flag := false
var _targets_left := 0
var _won := false
var _start_usec := 0

var _csv: FileAccess
var _csv_path := ""
var _csv_logging := false
var _csv_pending := 0


func _ready() -> void:
	var win := get_window()
	win.size_changed.connect(_on_window_resized)

	viewport = SubViewport.new()
	viewport.size = win.size
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	world_root = Node3D.new()
	viewport.add_child(world_root)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.004, 0.006, 0.014)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.05, 0.07, 0.11)
	e.fog_enabled = true
	e.fog_light_color = Color(0.02, 0.05, 0.09)
	e.fog_density = 0.045
	env.environment = e
	world_root.add_child(env)

	maze = Maze.new()
	world_root.add_child(maze)
	maze.generate()

	player = Player.new()
	world_root.add_child(player)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.cull_mask = 1  # layer 1 only — layer 2 holds the depth twins
	camera.make_current()
	world_root.add_child(camera)

	# Second viewport + camera render the SAME World3D but only layer-2
	# depth twins -> a metric depth buffer for positional TimeWarp.
	depth_vp = SubViewport.new()
	depth_vp.size = win.size
	depth_vp.msaa_3d = Viewport.MSAA_DISABLED  # AA would corrupt packed depth
	depth_vp.gui_disable_input = true
	depth_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(depth_vp)
	depth_vp.world_3d = viewport.find_world_3d()  # share the same world
	depth_cam = Camera3D.new()
	depth_cam.near = camera.near
	depth_cam.cull_mask = 2  # depth twins only
	depth_vp.add_child(depth_cam)
	depth_cam.make_current()

	_update_render_fov()
	_spawn_player()

	var layer := CanvasLayer.new()
	add_child(layer)

	warp_mat = ShaderMaterial.new()
	warp_mat.shader = load("res://shaders/timewarp.gdshader")
	warp_mat.set_shader_parameter("depth_tex", depth_vp.get_texture())
	warp_mat.set_shader_parameter("resolution", Vector2(win.size))
	var warp_rect := TextureRect.new()
	warp_rect.material = warp_mat
	warp_rect.texture = viewport.get_texture()
	warp_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	warp_rect.stretch_mode = TextureRect.STRETCH_SCALE
	warp_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	warp_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(warp_rect)

	hud = HUD.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)

	_wire_maze()
	_start_usec = Time.get_ticks_usec()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Stamp a real pose on the camera immediately so the first displayed
	# frame isn't a flash of the identity-transform void.
	_record_pose()
	_render_tick()
	hud.show_message("Shoot %d glowing targets to unlock the EXIT" % _targets_left, 5.0)


func _spawn_player() -> void:
	player.position = maze.cell_world_center(maze.start_cell) + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	player.yaw = -PI * 0.5  # face east, toward the exit side of the maze
	player.pitch = 0.0
	# Sync the head transform now — its _process won't run until next frame.
	player.head.rotation = Vector3(player.pitch, player.yaw, 0.0)


func _wire_maze() -> void:
	maze.target_hit.connect(_on_target_hit)
	maze.exit_reached.connect(_on_exit_reached)
	_targets_left = maze.targets_total


# --- Simulation core ---------------------------------------------------------

func _process(delta: float) -> void:
	_record_pose()
	_accum_ms += delta * 1000.0
	if _accum_ms >= render_interval_ms:
		_accum_ms = fmod(_accum_ms, render_interval_ms)
		_render_tick()
	_update_warp()
	_update_hud()
	if _csv_logging:
		_log_csv_row()
	_tick_flag = false


## A new "rendered frame" becomes available: sample the head pose the engine
## would have used (now - pipeline latency) and stamp it on the camera.
func _render_tick() -> void:
	var target_usec := Time.get_ticks_usec() - int(pipeline_latency_ms * 1000.0)
	var pose := _sample_pose(target_usec)
	camera.global_transform = pose
	depth_cam.global_transform = pose
	_render_basis = pose.basis.orthonormalized()
	_render_pos = pose.origin
	_tick_flag = true


func _record_pose() -> void:
	var now := Time.get_ticks_usec()
	_pose_history.append({"t": now, "tr": player.head_global_transform()})
	var cutoff := now - int(HISTORY_SEC * 1_000_000)
	while _pose_history.size() > 1 and _pose_history[0]["t"] < cutoff:
		_pose_history.pop_front()


func _sample_pose(t: int) -> Transform3D:
	if _pose_history.is_empty():
		return player.head_global_transform()
	if t <= _pose_history[0]["t"]:
		return _pose_history[0]["tr"]
	var last: Dictionary = _pose_history.back()
	if t >= last["t"]:
		return last["tr"]
	for i in range(_pose_history.size() - 1, 0, -1):
		var a: Dictionary = _pose_history[i - 1]
		var b: Dictionary = _pose_history[i]
		if a["t"] <= t:
			var span := int(b["t"]) - int(a["t"])
			if span <= 0:
				return a["tr"]
			var w := float(t - int(a["t"])) / float(span)
			return (a["tr"] as Transform3D).interpolate_with(b["tr"], w)
	return last["tr"]


func _warp_mode() -> int:
	if not atw_enabled:
		return 0
	return 2 if positional_warp else 1


## Every display frame: hand the compositor shader the pose delta
## R_render^-1 * R_current, plus the ray-mapping constants.
func _update_warp() -> void:
	var head_tr := player.head_global_transform()
	var cur := head_tr.basis.orthonormalized()
	_last_delta_deg = rad_to_deg(
		(_render_basis.inverse() * cur).get_rotation_quaternion().get_angle())
	_last_pos_delta = (head_tr.origin - _render_pos).length()
	warp_mat.set_shader_parameter("reproj", _render_basis.inverse() * cur)
	warp_mat.set_shader_parameter("render_basis", _render_basis)
	warp_mat.set_shader_parameter("render_basis_inv", _render_basis.inverse())
	warp_mat.set_shader_parameter("current_basis", cur)
	warp_mat.set_shader_parameter("render_pos", _render_pos)
	warp_mat.set_shader_parameter("current_pos", head_tr.origin)
	warp_mat.set_shader_parameter("warp_mode", _warp_mode())
	warp_mat.set_shader_parameter("debug_viz", debug_viz)
	var t := tan(deg_to_rad(display_fov_deg) * 0.5)
	var aspect := float(viewport.size.x) / float(viewport.size.y)
	var view := Vector2(t * aspect, t)
	warp_mat.set_shader_parameter("tan_half_fov_view", view)
	warp_mat.set_shader_parameter("tan_half_fov_render", view * overscan)


func _update_render_fov() -> void:
	var f := rad_to_deg(2.0 * atan(tan(deg_to_rad(display_fov_deg) * 0.5) * overscan))
	camera.fov = f
	depth_cam.fov = f


# --- Gameplay ----------------------------------------------------------------

func _shoot() -> void:
	if _won:
		return
	var head_tr := player.head_global_transform()
	var from := head_tr.origin
	var to := from - head_tr.basis.z * 60.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = true
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	var hit_point: Vector3 = hit.get("position", to)
	_spawn_tracer(from, hit_point)
	if hit and hit["collider"] is MazeTarget:
		hit["collider"].hit()


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var dist := from.distance_to(to)
	if dist < 0.05:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, 0.02, dist)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.45, 0.95, 1.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.45, 0.95, 1.0)
	mat.emission_energy_multiplier = 3.0
	var tracer := MeshInstance3D.new()
	tracer.mesh = mesh
	tracer.material_override = mat
	world_root.add_child(tracer)
	tracer.global_position = (from + to) * 0.5
	var dir := (to - from).normalized()
	var up := Vector3.UP if abs(dir.y) < 0.9 else Vector3.RIGHT
	tracer.look_at(to, up)
	var tw := tracer.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.09)
	tw.tween_callback(tracer.queue_free)


func _on_target_hit(_t: MazeTarget) -> void:
	_targets_left -= 1
	if _targets_left <= 0:
		maze.open_exit()
		hud.show_message("EXIT UNLOCKED — find the glowing door", 4.0)
	else:
		hud.show_message("%d target(s) left" % _targets_left, 2.0)


func _on_exit_reached() -> void:
	if _won:
		return
	_won = true
	var secs := float(Time.get_ticks_usec() - _start_usec) / 1_000_000.0
	hud.show_message("ESCAPED in %.1f s — press R for a new maze" % secs)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _regenerate() -> void:
	maze.queue_free()
	maze = Maze.new()
	world_root.add_child(maze)
	maze.generate()
	_wire_maze()
	_spawn_player()
	_pose_history.clear()
	_accum_ms = 0.0
	_render_basis = Basis.IDENTITY
	_render_pos = Vector3.ZERO
	_won = false
	_start_usec = Time.get_ticks_usec()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_message("Shoot %d glowing targets to unlock the EXIT" % _targets_left, 5.0)


func _on_window_resized() -> void:
	viewport.size = get_window().size
	depth_vp.size = get_window().size
	warp_mat.set_shader_parameter("resolution", Vector2(get_window().size))


# --- CSV logging --------------------------------------------------------------

func _toggle_logging() -> void:
	if _csv_logging:
		_csv_logging = false
		_flush_csv()
		_csv = null
		hud.show_message("Log saved: %s" % ProjectSettings.globalize_path(_csv_path), 8.0)
	else:
		_csv_path = "user://atw_log_%d.csv" % int(Time.get_unix_time_from_system())
		_csv = FileAccess.open(_csv_path, FileAccess.WRITE)
		if _csv == null:
			hud.show_message("Failed to open log file", 3.0)
			return
		_csv.store_line("elapsed_ms,frame_tick,frame_age_ms,rot_delta_deg,pos_delta_m," +
			"warp_mode,render_interval_ms,pipeline_latency_ms,yaw_deg,pitch_deg,pos_x,pos_y,pos_z")
		_csv_logging = true
		hud.show_message("CSV logging ON — press L to stop", 3.0)


func _log_csv_row() -> void:
	var head_tr := player.head_global_transform()
	_csv.store_line("%d,%d,%.2f,%.3f,%.4f,%d,%.0f,%.0f,%.2f,%.2f,%.4f,%.4f,%.4f" % [
		int((Time.get_ticks_usec() - _start_usec) / 1000),
		int(_tick_flag), _accum_ms, _last_delta_deg, _last_pos_delta,
		_warp_mode(), render_interval_ms, pipeline_latency_ms,
		rad_to_deg(player.yaw), rad_to_deg(player.pitch),
		head_tr.origin.x, head_tr.origin.y, head_tr.origin.z])
	_csv_pending += 1
	if _csv_pending >= 240:
		_flush_csv()


func _flush_csv() -> void:
	if _csv != null:
		_csv.flush()
		_csv_pending = 0


func _exit_tree() -> void:
	if _csv != null:
		_csv.flush()
		_csv.close()


func _update_hud() -> void:
	var mode_txt := "OFF"
	if atw_enabled:
		mode_txt = "ROT+POS" if positional_warp else "ROT"
	var lines := PackedStringArray([
		"Display: %d fps" % int(Engine.get_frames_per_second()),
		"Sim render: %.0f Hz (%.0f ms)" % [1000.0 / render_interval_ms, render_interval_ms],
		"Pipeline latency: %.0f ms" % pipeline_latency_ms,
		"Warp: %s   Overscan: %.2f" % [mode_txt, overscan],
		"Warp correction: %.1f deg  %.3f m" % [_last_delta_deg, _last_pos_delta],
		"Viz: %s   CSV: %s" % ["ON" if debug_viz else "off", "REC" if _csv_logging else "off"],
		"Targets left: %d" % _targets_left,
	])
	hud.set_stats("\n".join(lines))
	hud.set_staleness(_accum_ms / render_interval_ms)


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			player.apply_mouse(event.relative)
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_shoot()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_T:
				atw_enabled = not atw_enabled
			KEY_P:
				positional_warp = not positional_warp
				if positional_warp:
					atw_enabled = true
			KEY_V:
				debug_viz = not debug_viz
			KEY_L:
				_toggle_logging()
			KEY_O:
				overscan = 1.0 if overscan > 1.01 else 1.18
				_update_render_fov()
			KEY_G:
				player.auto_sway = not player.auto_sway
			KEY_R:
				_regenerate()
			KEY_H, KEY_F1:
				hud.toggle_help()
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_COMMA:
				render_interval_ms = clampf(render_interval_ms - 10.0, INTERVAL_MIN, INTERVAL_MAX)
			KEY_PERIOD:
				render_interval_ms = clampf(render_interval_ms + 10.0, INTERVAL_MIN, INTERVAL_MAX)
			KEY_BRACKETLEFT:
				pipeline_latency_ms = clampf(pipeline_latency_ms - 10.0, 0.0, LATENCY_MAX)
			KEY_BRACKETRIGHT:
				pipeline_latency_ms = clampf(pipeline_latency_ms + 10.0, 0.0, LATENCY_MAX)
