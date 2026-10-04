# The Latency Maze — Tài liệu chi tiết

Bộ docs này là bản đầy đủ nhất của đề tài **mô phỏng Asynchronous TimeWarp (ATW) trên màn hình phẳng bằng Godot 4.7**, không cần kính VR.

## Mục lục docs

| File | Nội dung |
|------|----------|
| `README.md` (file này) | Tổng quan, cách chạy, luật chơi, bản đồ code, thuật ngữ |
| `01-ly-thuyet.md` | Lý thuyết gốc: motion-to-photon latency, ROT-ATW, PTW, overscan, disocclusion, heatmap |
| `02-kien-truc-va-code.md` | Kiến trúc hệ thống, luồng 1 frame, walkthrough `main.gd`, `player.gd`, `maze.gd`, 3 shader, `hud.gd` |
| `03-thi-nghiem-va-thuyet-trinh.md` | Bảng phím, 6 thí nghiệm demo, định dạng CSV + cách plot, kịch bản thuyết trình 20 phút 20 slide, hạn chế, hướng phát triển, FAQ |

## 1. Tổng quan 1 phút

Game FPS trong maze nhưng **render cố tình chậm và cũ**:

- Maze render vào `SubViewport` nhưng camera chỉ cập nhật theo **nhịp render mô phỏng** (mặc định `100ms = 10Hz`, chỉnh bằng `,` `.`).
- Pose dùng để render đã **cũ thêm `pipeline_latency_ms`** (mặc định `40ms`, chỉnh bằng `[` `]`), lấy từ buffer lịch sử pose có nội suy.
- Chuột/head update **mỗi frame màn hình** như IMU tốc độ cao.
- Mỗi frame màn hình, fullscreen shader `timewarp.gdshader` re-project ảnh cũ theo delta pose `R_render^-1 * R_current` — đúng việc compositor VR làm trước scanout.
- Viewport thứ 2 render riêng depth metric để làm positional warp (phím `P`), có lỗ magenta trung thực khi bị che khuất.

Kết quả: cùng 1 ảnh cũ, tắt ATW thì nát không chơi được, bật ATW thì thế giới dính chặt vào view.

## 2. Cách chạy

### Yêu cầu

- Godot 4.7 Forward+ (Windows đã cấu hình `d3d12` trong `project.godot:31`).
- Physics Jolt (`project.godot:27`).
- Cửa sổ mặc định 1600x900 (`project.godot:20-21`), stretch `canvas_items/expand`.

### Chạy

1. Mở `scenes/main.tscn` (scene chỉ chứa 1 node `Main` gắn `scripts/main.gd`), nhấn F5.
2. Click vào cửa sổ để capture chuột. `Esc` thả chuột.
3. `H` / `F1` xem help. `R` tạo maze mới.
4. Nhiệm vụ: `WASD` di chuyển, chuột nhìn, `LMB` bắn hết orb đỏ phát sáng để cửa EXIT chuyển xanh, đi qua cửa để thắng.

### Nút quan trọng nhất khi demo

```
G auto-sway -> T tắt ATW (nát) -> T bật lại (dính)
P positional warp | O overscan | V heatmap
, . render period | [ ] pipeline latency | L log CSV
```

Chi tiết xem `03-thi-nghiem-va-thuyet-trinh.md`.

## 3. Bản đồ code

```
scenes/main.tscn          6 dòng, chỉ mount scripts/main.gd
scripts/main.gd           ~441 dòng: lõi sim, pose buffer, render tick,
                          warp uniforms, shooting, maze regen, CSV, input, HUD
scripts/player.gd         67 dòng: CharacterBody3D + node head là HMD/IMU
scripts/maze.gd           366 dòng: sinh maze recursive-backtracker 13x13,
                          MultiMesh tường, depth twin layer 2, target, EXIT
scripts/target.gd         57 dòng: orb脉动, hit đổi màu, phát signal shot
scripts/hud.gd            117 dòng: stats, frame-age bar, help, crosshair
shaders/timewarp.gdshader 137 dòng: ROT + PTW lặp + heatmap
shaders/depth_pack.gdshader 21 dòng: pack khoảng cách Euclid vào RG
shaders/checker.gdshader  41 dòng: checker world-space + line phát sáng
project.godot             Forward+, Jolt, D3D12, viewport 1600x900
```

`scenes/main.tscn:1-6` chứng minh mọi thứ dựng bằng code trong `_ready()`, không xếp node bằng editor. Điều này cố ý để dễ đọc luồng pipeline.

## 4. Thuật ngữ viết tắt

| Thuật ngữ | Nghĩa | Trong project |
|-----------|-------|---------------|
| Motion-to-photon | Thời gian từ lúc đầu cử động tới lúc photon đúng ảnh tới mắt | Render 100ms + pipeline 40ms mô phỏng con số này |
| ATW | Asynchronous TimeWarp, warp xoay ảnh cũ theo pose mới | `warp_mode 1`, phím `T` |
| PTW / +POS | Positional TimeWarp, warp thêm tịnh tiến nhờ depth | `warp_mode 2`, phím `P` |
| Overscan | Render FOV rộng hơn để có pixel dự phòng ở rìa | `1.18`, phím `O` |
| Disocclusion | Vùng pose mới thấy nhưng frame cũ chưa thấy | Lỗ magenta |
| Reproj | Ma trận `R_render^-1 * R_current` | Uniform `reproj` |
| Frame age | Thời gian từ frame render cuối tới hiện tại | Thanh bar + cột `frame_age_ms` trong CSV |
| IMU | Cảm biến đầu trong kính thật | Chuột + `player.head` ở đây |

Đọc tiếp `01-ly-thuyet.md` để hiểu toán, `02-kien-truc-va-code.md` để hiểu code.
