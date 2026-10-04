class_name HUD
extends Control
## On-screen overlay: crosshair, simulator stats, frame-age bar, help panel.
## Everything lives on the post-warp canvas, like composited VR UI.

const HELP_TEXT := """THE LATENCY MAZE — Asynchronous TimeWarp simulator

WASD move · Mouse look · LMB shoot
T    ATW on / off            P    + positional warp (depth)
, .  render period -/+ 10 ms      V    warp-shift heatmap
[ ]  pipeline latency -/+ 10 ms   L    CSV log on/off
O    overscan on / off   G   auto head-sway
R    new maze · H / F1 help · Esc release mouse

Shoot every glowing target to unlock the EXIT door.
ROT = rotation-only reprojection; +POS adds depth-based
parallax correction. Heatmap colors = per-pixel warp
displacement; magenta holes = disocclusion, just like
real positional TimeWarp."""

var _stats: Label
var _msg: Label
var _help: PanelContainer
var _stale: ProgressBar


func _ready() -> void:
	_stats = Label.new()
	_stats.position = Vector2(16, 10)
	_style(_stats, Color(0.65, 0.95, 1.0), 15)
	add_child(_stats)

	_stale = ProgressBar.new()
	_stale.min_value = 0.0
	_stale.max_value = 1.0
	_stale.show_percentage = false
	_stale.custom_minimum_size = Vector2(230, 9)
	_stale.position = Vector2(16, 172)
	_stale.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_stale)

	_msg = Label.new()
	_msg.anchor_left = 0.5
	_msg.anchor_right = 0.5
	_msg.offset_left = -520
	_msg.offset_right = 520
	_msg.offset_top = 34
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.mouse_filter = MOUSE_FILTER_IGNORE
	_style(_msg, Color(1.0, 0.95, 0.55), 24)
	add_child(_msg)

	_help = PanelContainer.new()
	_help.anchor_left = 1.0
	_help.anchor_right = 1.0
	_help.anchor_bottom = 0.0
	_help.offset_left = -460
	_help.offset_right = -14
	_help.offset_top = 12
	_help.offset_bottom = 412
	var help_lbl := Label.new()
	help_lbl.text = HELP_TEXT
	help_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	_style(help_lbl, Color(0.85, 0.95, 1.0), 14)
	_help.add_child(help_lbl)
	_help.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_help)


func _process(_delta: float) -> void:
	queue_redraw()  # crosshair visibility follows mouse mode


func _draw() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var c := size * 0.5
	var col := Color(1, 1, 1, 0.9)
	var gap := 3.0
	var len := 9.0
	draw_line(c + Vector2(gap, 0), c + Vector2(gap + len, 0), col, 2.0)
	draw_line(c - Vector2(gap, 0), c - Vector2(gap + len, 0), col, 2.0)
	draw_line(c + Vector2(0, gap), c + Vector2(0, gap + len), col, 2.0)
	draw_line(c - Vector2(0, gap), c - Vector2(0, gap + len), col, 2.0)


func _style(lbl: Label, color: Color, size: int) -> void:
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.add_theme_font_size_override("font_size", size)


func set_stats(text: String) -> void:
	_stats.text = text


func set_staleness(frac: float) -> void:
	_stale.value = clampf(frac, 0.0, 1.0)


func show_message(text: String, timeout := 0.0) -> void:
	_msg.text = text
	if timeout > 0.0:
		get_tree().create_timer(timeout).timeout.connect(
			_clear_message_if_same.bind(text))


func _clear_message_if_same(token: String) -> void:
	if _msg.text == token:
		_msg.text = ""


func toggle_help() -> void:
	_help.visible = not _help.visible
