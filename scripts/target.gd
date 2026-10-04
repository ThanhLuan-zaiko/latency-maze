class_name MazeTarget
extends Area3D
## Glowing orb the player shoots to unlock the exit door.
## Lives inside the SubViewport world; hit detection is a physics raycast.

signal shot(target)

var active := true

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _time := 0.0


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(1.0, 0.28, 0.18)
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.3, 0.15)
	_mat.emission_energy_multiplier = 3.0

	var sphere := SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.64
	sphere.radial_segments = 24
	sphere.rings = 12
	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	_mesh.material_override = _mat
	add_child(_mesh)

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.55
	col.shape = shape
	add_child(col)


func _process(delta: float) -> void:
	_time += delta
	if active:
		var pulse := sin(_time * 4.0)
		_mesh.scale = Vector3.ONE * (0.92 + 0.08 * pulse)
		_mat.emission_energy_multiplier = 2.6 + 1.4 * pulse


## Called by the shooter's raycast.
func hit() -> void:
	if not active:
		return
	active = false
	_mat.albedo_color = Color(0.2, 1.0, 0.55)
	_mat.emission = Color(0.2, 1.0, 0.55)
	_mat.emission_energy_multiplier = 0.7
	_mesh.scale = Vector3.ONE * 0.55
	shot.emit(self)
