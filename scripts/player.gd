class_name Player
extends CharacterBody3D
## First-person body. The `head` node is the simulated HMD: its pose updates
## every display frame (like a high-rate IMU), while the render camera only
## samples it at the simulated render rate.

@export var move_speed := 4.5
@export var mouse_sensitivity := 0.0022
@export var gravity := 18.0

var yaw := 0.0
var pitch := 0.0
var auto_sway := false
var head: Node3D

var _sway_phase := 0.0


func _ready() -> void:
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	col.shape = capsule
	col.position.y = 0.85
	add_child(col)

	head = Node3D.new()
	head.position.y = 1.55
	add_child(head)


## Routed from the main scene — nodes inside a SubViewport do not receive
## the root window's unhandled input events.
func apply_mouse(relative: Vector2) -> void:
	yaw -= relative.x * mouse_sensitivity
	pitch = clampf(pitch - relative.y * mouse_sensitivity, -1.45, 1.45)


func _process(delta: float) -> void:
	_sway_phase += delta * 2.2
	# Two incommensurate sines ≈ natural head drift for hands-off judder demos.
	var sway := 0.0
	if auto_sway:
		sway = sin(_sway_phase) * 0.5 + sin(_sway_phase * 0.37) * 0.35
	head.rotation = Vector3(pitch, yaw + sway, 0.0)


func _physics_process(delta: float) -> void:
	var input_dir := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	).normalized()

	var basis_y := Basis(Vector3.UP, head.rotation.y + rotation.y)
	var wish := (basis_y * Vector3(input_dir.x, 0.0, input_dir.y)) * move_speed
	velocity.x = wish.x
	velocity.z = wish.z
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= gravity * delta
	move_and_slide()


func head_global_transform() -> Transform3D:
	return head.global_transform
