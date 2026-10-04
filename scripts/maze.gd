class_name Maze
extends Node3D
## Procedural sci-fi maze: recursive-backtracker grid, high-contrast checker
## walls (the best possible texture for spotting judder), glowing targets in
## dead ends, and a locked EXIT door in the far wall.

signal target_hit(target)
signal exit_reached

@export var grid_w := 13
@export var grid_h := 13
@export var cell_size := 3.0
@export var wall_height := 3.0
@export var wall_thickness := 0.2
@export var target_count := 3

var rng := RandomNumberGenerator.new()
var start_cell := Vector2i.ZERO
var exit_cell := Vector2i.ZERO
var targets_total := 0

# walls_v[x][y]: wall segment between cells (x-1,y) and (x,y); x in 0..grid_w
# walls_h[x][y]: wall segment between cells (x,y-1) and (x,y); y in 0..grid_h
var _wv: Array
var _wh: Array
var _door: Node3D
var _door_col: CollisionShape3D
var _door_mat: StandardMaterial3D


func generate(seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	start_cell = Vector2i.ZERO
	exit_cell = Vector2i(grid_w - 1, grid_h - 1)
	_carve_maze()
	_build_walls()
	_build_floor_ceiling()
	_place_targets()
	_build_exit_door()


func cell_world_center(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * cell_size, 0.0, (cell.y + 0.5) * cell_size)


func open_exit() -> void:
	if _door == null:
		return
	_door_mat.albedo_color = Color(0.05, 0.45, 0.18)
	_door_mat.emission = Color(0.2, 1.0, 0.45)
	_door_col.set_deferred("disabled", true)
	var tw := _door.create_tween()
	tw.tween_property(_door, "position:y", -wall_height - 0.3, 0.9) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


# --- Generation -------------------------------------------------------------

func _carve_maze() -> void:
	_wv = []
	for x in range(grid_w + 1):
		var col: Array[bool] = []
		col.resize(grid_h)
		col.fill(true)
		_wv.append(col)
	_wh = []
	for x in range(grid_w):
		var col: Array[bool] = []
		col.resize(grid_h + 1)
		col.fill(true)
		_wh.append(col)

	var visited := {start_cell: true}
	var stack: Array[Vector2i] = [start_cell]
	var dirs := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i(0, 1), Vector2i(0, -1)]
	while not stack.is_empty():
		var c: Vector2i = stack.back()
		var options: Array[Vector2i] = []
		for d in dirs:
			var n: Vector2i = c + d
			if n.x >= 0 and n.y >= 0 and n.x < grid_w and n.y < grid_h and not visited.has(n):
				options.append(n)
		if options.is_empty():
			stack.pop_back()
		else:
			var n: Vector2i = options[rng.randi() % options.size()]
			if n.x > c.x:
				_wv[n.x][c.y] = false
			elif n.x < c.x:
				_wv[c.x][c.y] = false
			elif n.y > c.y:
				_wh[c.x][n.y] = false
			else:
				_wh[c.x][c.y] = false
			visited[n] = true
			stack.append(n)

	# Punch the exit doorway in the east border wall of the exit cell.
	_wv[grid_w][exit_cell.y] = false


# --- Geometry ---------------------------------------------------------------

func _checker_mat(a: Color, b: Color, cells: float, emission: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/checker.gdshader")
	mat.set_shader_parameter("color_a", a)
	mat.set_shader_parameter("color_b", b)
	mat.set_shader_parameter("cells_per_meter", cells)
	mat.set_shader_parameter("line_emission", emission)
	return mat


func _add_wall(transforms: Array[Transform3D], body: StaticBody3D,
		shape: BoxShape3D, center: Vector3, dims: Vector3) -> void:
	transforms.append(Transform3D(Basis.from_scale(dims), center))
	var col := CollisionShape3D.new()
	col.shape = shape
	col.scale = dims
	col.position = center
	body.add_child(col)


func _build_walls() -> void:
	var transforms: Array[Transform3D] = []
	var body := StaticBody3D.new()
	body.name = "WallBody"
	add_child(body)
	var unit_box := BoxShape3D.new()
	unit_box.size = Vector3.ONE

	var t := wall_thickness
	var h := wall_height
	var cs := cell_size

	# Vertical segments (facing +-X), merged into runs along Y.
	for x in range(grid_w + 1):
		var y := 0
		while y < grid_h:
			if _wv[x][y]:
				var y0 := y
				while y < grid_h and _wv[x][y]:
					y += 1
				var length := (y - y0) * cs + t
				var center := Vector3(x * cs, h * 0.5, (y0 + (y - y0) * 0.5) * cs)
				_add_wall(transforms, body, unit_box, center, Vector3(t, h, length))
			else:
				y += 1
	# Horizontal segments (facing +-Z), merged into runs along X.
	for y in range(grid_h + 1):
		var x := 0
		while x < grid_w:
			if _wh[x][y]:
				var x0 := x
				while x < grid_w and _wh[x][y]:
					x += 1
				var length := (x - x0) * cs + t
				var center := Vector3((x0 + (x - x0) * 0.5) * cs, h * 0.5, y * cs)
				_add_wall(transforms, body, unit_box, center, Vector3(length, h, t))
			else:
				x += 1

	# All wall boxes in a single draw call.
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _checker_mat(
		Color(0.02, 0.03, 0.07), Color(0.72, 0.95, 1.0), 1.1, 2.2)
	add_child(mmi)


func _slab(center: Vector3, dims: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dims
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = center
	add_child(mi)
	return mi


func _build_floor_ceiling() -> void:
	var w := grid_w * cell_size
	var d := grid_h * cell_size
	_slab(Vector3(w * 0.5, -0.06, d * 0.5), Vector3(w, 0.12, d),
		_checker_mat(Color(0.012, 0.018, 0.04), Color(0.14, 0.3, 0.4), 0.75, 1.0))
	_slab(Vector3(w * 0.5, wall_height + 0.05, d * 0.5), Vector3(w, 0.1, d),
		_checker_mat(Color(0.006, 0.01, 0.03), Color(0.25, 0.5, 0.68), 0.55, 0.6))

	var fbody := StaticBody3D.new()
	fbody.name = "FloorBody"
	var fcol := CollisionShape3D.new()
	var fshape := BoxShape3D.new()
	fshape.size = Vector3(w, 0.12, d)
	fcol.shape = fshape
	fcol.position = Vector3(w * 0.5, -0.06, d * 0.5)
	fbody.add_child(fcol)
	add_child(fbody)


# --- Targets & exit ----------------------------------------------------------

func _dead_end_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in grid_w:
		for y in grid_h:
			var c := Vector2i(x, y)
			if c == start_cell or c == exit_cell:
				continue
			var n_walls := int(_wv[x][y]) + int(_wv[x + 1][y]) \
				+ int(_wh[x][y]) + int(_wh[x][y + 1])
			if n_walls >= 3:
				cells.append(c)
	return cells


func _place_targets() -> void:
	var candidates := _dead_end_cells()
	if candidates.size() < target_count:
		for x in grid_w:
			for y in grid_h:
				var c := Vector2i(x, y)
				if c != start_cell and c != exit_cell and not candidates.has(c):
					candidates.append(c)
	# Fisher-Yates with our own rng so seeds are reproducible.
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp: Vector2i = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	var chosen: Array[Vector2i] = []
	for c in candidates:
		if chosen.size() >= target_count:
			break
		var far_enough := true
		for o in chosen:
			if abs(c.x - o.x) + abs(c.y - o.y) < 5:
				far_enough = false
				break
		if far_enough:
			chosen.append(c)
	for c in candidates:
		if chosen.size() >= target_count:
			break
		if not chosen.has(c):
			chosen.append(c)

	for c in chosen:
		var t := MazeTarget.new()
		t.position = cell_world_center(c) + Vector3(0, 1.55, 0)
		add_child(t)
		t.shot.connect(_on_target_shot)
	targets_total = chosen.size()


func _build_exit_door() -> void:
	var h := wall_height
	var door_pos := Vector3(grid_w * cell_size, h * 0.5, (exit_cell.y + 0.5) * cell_size)

	_door_mat = StandardMaterial3D.new()
	_door_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_door_mat.albedo_color = Color(0.55, 0.05, 0.08)
	_door_mat.emission_enabled = true
	_door_mat.emission = Color(1.0, 0.15, 0.1)
	_door_mat.emission_energy_multiplier = 1.8

	_door = Node3D.new()
	_door.position = door_pos
	add_child(_door)

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(wall_thickness, h, cell_size)
	mesh.mesh = bm
	mesh.material_override = _door_mat
	_door.add_child(mesh)

	var body := StaticBody3D.new()
	_door_col = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(wall_thickness, h, cell_size)
	_door_col.shape = shape
	body.add_child(_door_col)
	_door.add_child(body)

	var exit_sign := Label3D.new()
	exit_sign.text = "EXIT"
	exit_sign.pixel_size = 0.006
	exit_sign.font_size = 128
	exit_sign.outline_size = 24
	exit_sign.modulate = Color(0.35, 1.0, 0.55)
	exit_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	exit_sign.position = door_pos + Vector3(-0.35, h * 0.5 + 0.8, 0)
	add_child(exit_sign)

	# Small landing pad outside the doorway so the player doesn't fall into
	# the void on the way out.
	var pad_pos := door_pos + Vector3(1.6, -h * 0.5 - 0.05, 0)
	var pad_dims := Vector3(3.2, 0.1, cell_size)
	_slab(pad_pos, pad_dims,
		_checker_mat(Color(0.02, 0.05, 0.03), Color(0.25, 0.85, 0.45), 1.0, 1.6))
	var pad_body := StaticBody3D.new()
	var pad_col := CollisionShape3D.new()
	var pad_shape := BoxShape3D.new()
	pad_shape.size = pad_dims
	pad_col.shape = pad_shape
	pad_col.position = pad_pos
	pad_body.add_child(pad_col)
	add_child(pad_body)

	var zone := Area3D.new()
	var zc := CollisionShape3D.new()
	var zs := BoxShape3D.new()
	zs.size = Vector3(1.6, h, cell_size)
	zc.shape = zs
	zone.add_child(zc)
	zone.position = door_pos + Vector3(0.9, 0, 0)
	add_child(zone)
	zone.body_entered.connect(_on_exit_body_entered)


func _on_target_shot(t: MazeTarget) -> void:
	target_hit.emit(t)


func _on_exit_body_entered(body: Node3D) -> void:
	if body is Player:
		exit_reached.emit()
