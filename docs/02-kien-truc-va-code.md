# 02 — Kiến trúc và code walkthrough

## 2.1 Sơ đồ tổng

```
┌─────────────┐  mouse/IMU mỗi display frame  ┌──────────────┐
│ Player.head │ ────────────────────────────>│ pose_history │
│ 1.55m       │  _record_pose()               │ 2 giây       │
└──────┬──────┘                               └──────┬───────┘
       │ head_global_transform()                    │ sample(now-latency)
       │                                            v
       │ tick render khi accum>=interval     ┌──────────────┐
       │────────────────────────────────────>│Camera render │ layer 1 màu
       │ _render_tick()                      │DepthCam      │ layer 2 depth
       │                                     └──────┬───────┘
       │                                            │ SubViewport textures
       v                                            v
┌──────────────────────────────────────────────────────────┐
│ Fullscreen TextureRect + timewarp.gdshader                │
│  inputs: color tex, depth tex, reproj, bases, pos, FOVs   │
│  output: warped color / edge / magenta / heatmap         │
└──────────────────────────────┬───────────────────────────┘
                               v
                    ┌─────────────────────┐
                    │ HUD (post-warp)     │
                    │ stats, age bar,help │
                    └─────────────────────┘
```

Mọi node dựng bằng code trong `main.gd:60-144`, `main.tscn` chỉ mount script. Cố ý để đọc 1 file là thấy pipeline.

## 2.2 Một display frame xảy ra gì? (`main.gd:164-175`)

```gdscript
_record_pose()            # 1. lưu head hiện tại + timestamp micros
_accum_ms += delta*1000
if _accum_ms >= render_interval_ms:  # 2. đủ lâu mới có frame render mới
  _accum_ms = fmod(...)
  _render_tick()          # 3. sample pose cũ, stamp lên 2 camera
_update_warp()            # 4. tính reproj + đẩy uniforms cho shader
_update_hud()             # 5. stats + thanh staleness
if _csv_logging: _log_csv_row()
_tick_flag = false
```

Điểm mấu chốt sinh viên hay nhầm: `_render_tick()` không render ngay. Nó chỉ **đổi pose của camera**. Việc render thật do `SubViewport.UPDATE_ALWAYS` tự làm sau đó. Shader warp thì chạy **mỗi display frame** trên ảnh mới nhất của viewport.

## 2.3 Pose history + render tick

### Ghi (`main.gd:189-194`)

```gdscript
_pose_history.append({"t": now_usec, "tr": head_global})
xóa mẫu cũ hơn 2s
```

Micros từ `Time.get_ticks_usec()`, giữ `HISTORY_SEC=2.0` đủ cho latency max 250ms.

### Đọc (`main.gd:180-214`)

```gdscript
target = now - pipeline_latency_ms*1000
pose = _sample_pose(target)  # tìm 2 mẫu kẹp target, interpolate_with(w)
camera.global_transform = pose
depth_cam.global_transform = pose
_render_basis/pos = pose
_tick_flag = true
```

`_sample_pose()` kẹp 2 đầu, nội suy tuyến tính cả vị trí + slerp basis qua `interpolate_with`. Nếu history rỗng trả về head hiện tại.

Mặc định `render_interval_ms=100` `main.gd:20`, `pipeline_latency_ms=40` `main.gd:21`, giới hạn `20-250` và `0-250` `main.gd:28-30`.

### Warp uniforms (`main.gd:225-243`)

```gdscript
delta_deg từ (_render_basis^-1 * cur).quaternion.angle
pos_delta = |head_pos - render_pos|
reproj, render_basis(+inv), current_basis, render_pos, current_pos
warp_mode = 0/1/2 (_warp_mode())
tan_half_fov_view/render = f(display_fov=80°, aspect) và *overscan
```

`display_fov_deg=80` `main.gd:26`, `_update_render_fov()` đổi `camera.fov` theo overscan `main.gd:246-249`.

## 2.4 Player = HMD (`player.gd:1-67`)

- `CharacterBody3D` capsule `r=0.3 h=1.7`, `head` Node3D ở `y=1.55`.
- `apply_mouse()` từ `main.gd:404` khi `MOUSE_MODE_CAPTURED`: `yaw -= dx*0.0022`, pitch clamp ±1.45rad.
- `_process()`: `head.rotation = (pitch, yaw+sway, 0)` với sway 2 sine không giao ước `sin(t)*0.5+sin(0.37t)*0.35` khi `G` bật — giả drift đầu tự nhiên.
- `_physics_process()`: WASD theo basis yaw, `move_speed=4.5`, gravity 18.
- `head_global_transform()` là pose IMU mà sim sample.

Vì node nằm trong SubViewport nên không nhận `unhandled_input` của cửa sổ gốc — phải route chuột từ main qua `apply_mouse()`. Đây là chi tiết Godot hay bị hỏi.

## 2.5 Maze sinh thủ tục (`maze.gd`)

- Grid 13x13, cell 3m, tường cao 3m dày 0.2m, 3 target.
- `_carve_maze()`: recursive-backtracker với stack, đập cửa đông ở `exit_cell` cho EXIT.
- `_build_walls()`: gộp đoạn tường thẳng thành run dài, 1 `StaticBody3D` collision + 1 `MultiMeshInstance3D` visual => 1 draw call tường. Material checker xanh `cells 1.1, emission 2.2`.
- `_build_floor_ceiling()`: 2 slab + depth twin (xem dưới), floor có collision, trần không.
- `_place_targets()`: chọn dead-end (3 tường quanh), Fisher-Yates bằng rng riêng, ưu tiên cách nhau Manhattan >=5. Đếm `targets_total`.
- `_build_exit_door()`: cửa đỏ khóa + collision + chữ EXIT Label3D + pad ngoài + Area3D trigger. `open_exit()` đổi xanh, disable collision deferred, tween tụt xuống.

### Depth twin — trick quan trọng nhất của PTW

Mỗi visual đều có bản sao layer 2 với `_depth_material()`:

```gdscript
_depth_twin(mmi, self)          # tường
_depth_twin(slab, self)         # sàn/trần/pad
dtwin là con của t._mesh        # target, tự pulse theo
_depth_twin(mesh, _door)         # cửa, con của _door nên đi theo animation mở
```

Twin duplicate geometry, set `layers=2`, `material_override=depth_pack`. Camera màu `cull_mask=1`, depth cam `cull_mask=2`, cùng `World3D` `main.gd:106`. Nhờ đó depth view thấy đúng hình học mà không chạm tới scene nhìn thấy.

## 2.6 Shader timewarp (đọc từng khối)

File `shaders/timewarp.gdshader:1-137`, `shader_type canvas_item`.

- Uniforms pose: `reproj, render_basis(+inv), current_basis, render_pos, current_pos`.
- Uniforms FOV: `tan_half_fov_view/render`.
- `depth_tex` filter nearest, `debug_viz`, `resolution`, `viz_scale_px=150`, `edge/hole_color`.
- `dir_to_render_uv()` / `render_uv_to_dir()` / `uv_out()` / `srgb_to_lin()` / `decode_depth()` / `heat()`.

`fragment()`:

1. Dựng `dir_v` từ UV display.
2. `suv0` để đo heatmap.
3. ROT: `dir_r = reproj*dir_v` nếu mode>0, `suv=...`, `bad` nếu sau camera hoặc ngoài ảnh.
4. POS: lặp 3 lần như docs lý thuyết, `bad` khi `t<=0.02`, `ql.z>-0.02`, ngoài ảnh.
5. Lấy màu: `bad ? (mode>1?magenta:xanh đen) : texture(TEXTURE,suv)`.
6. Nếu `debug_viz`: đè bằng `heat(dpx/150)`.

## 2.7 Depth pack + checker

`depth_pack.gdshader`: `vertex` tính `length(MODELVIEW*VERTEX)`, `fragment` pack như đã nói. `unshaded, fog_disabled, cull_disabled` để depth không bị ánh sáng/sương làm lệch.

`checker.gdshader`: chọn mặt chiếu theo normal trội (`xz` cho sàn, `zy/zx` cho tường), `checker=mod(floor(x)+floor(y),2)`, line biên `fwidth()` antialiased + emission. `unshaded` để tương phản tối đa — judder lộ rõ nhất trên pattern này. Đây là lựa chọn có chủ ý cho demo, không phải trang trí.

## 2.8 Shooting + thắng/thua (`main.gd:254-328`)

`_shoot()`: ray từ head dài 60m, `exclude player`, `collide_with_areas=true` vì target là Area3D. Vẽ tracer box 0.02m cyan fade 0.09s. Trúng `MazeTarget` gọi `hit()`.

`target.gd`: sphere r=0.32 unshaded đỏ, pulse `scale 0.92±0.08`, emission `2.6±1.4`. `hit()` đổi xanh, scale 0.55, emit `shot`.

`main.gd:296-311`: đếm `_targets_left`, hết thì `maze.open_exit()` + báo `EXIT UNLOCKED`, đi vào Area thì `ESCAPED in Xs`, thả chuột. `R` regen maze mới, xóa history, reset pose.

## 2.9 HUD (`hud.gd:1-117`)

- `_stats` 15pt cyan: Display fps, Sim Hz/ms, Pipeline ms, Warp mode + Overscan, Correction deg/m, Viz/CSV, Targets left. Set từ `main.gd:382-396`.
- `_stale` ProgressBar 230x9 ở (16,172): `accum/interval`, đầy dần giữa 2 render.
- `_msg` vàng 24pt giữa top: thông báo có timeout.
- `_help` panel phải 446x400: text hằng số `HELP_TEXT` khớp ảnh chụp đề bài.
- `_draw()` crosshair khi captured.

HUD nằm trên cùng CanvasLayer sau warp nên không bị warp theo — giống UI composited trong VR.

## 2.10 Input (`main.gd:401-441`)

| Phím | Code | Ghi chú |
|------|------|---------|
| Chuột/LMB | `apply_mouse`, `_shoot()` | Captured mới aim/bắn, không thì click để capture lại |
| `T` | `atw_enabled=!` | `warp_mode 0<->1/2` |
| `P` | `positional=!; nếu bật thì atw=true` | Ép ATW on |
| `V` | `debug_viz=!` | Đẩy uniform bool |
| `L` | `_toggle_logging()` | Mở/đóng CSV |
| `O` | `overscan=1.0<->1.18; _update_render_fov()` | Đổi FOV 2 camera |
| `G` | `player.auto_sway=!` | Nằm trong player |
| `R` | `_regenerate()` | Free maze cũ, gen mới |
| `H/F1` | `hud.toggle_help()` | Ẩn/hiện panel |
| `Esc` | `MOUSE_MODE_VISIBLE` | Thả chuột |
| `,/ .` | `render_interval ∓/±10 clamp 20-250` | Giảm/tăng |
| `[ / ]` | `pipeline ∓/±10 clamp 0-250` | Giảm/tăng |
