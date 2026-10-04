# 03 — Thí nghiệm, logging và kịch bản thuyết trình 20 phút

## 3.1 Bảng điều khiển đầy đủ

| Nhóm | Phím | Mặc định | Phạm vi | Để làm gì khi demo |
|------|------|----------|---------|-------------------|
| Chơi | WASD / chuột / LMB | — | — | Đi / nhìn (giả IMU) / bắn orb |
| ATW | `T` | on | off/on | A/B test: tắt là nát, bật là dính |
| POS | `P` | off | off/on | Sửa parallax khi strafe, trả giá bằng lỗ magenta |
| Render | `,` `.` | 100ms (10Hz) | 20-250ms | Giả máy yếu/khỏe |
| Pipeline | `[` `]` | 40ms | 0-250ms | Giả pose cũ/mới |
| Overscan | `O` | 1.18 | 1.0/1.18 | Tắt rồi xoay nhanh thấy hở viền |
| Heatmap | `V` | off | off/on | Xem độ dịch warp từng pixel |
| Log | `L` | off | off/REC | Ghi CSV để plot |
| Sway | `G` | off | off/on | Tự lắc đầu demo rảnh tay |
| Khác | `R`, `H/F1`, `Esc` | — | — | Maze mới, help, thả chuột |

Dòng dưới help cần thuộc: `ROT = rotation-only, +POS adds depth-based parallax. Heatmap = per-pixel displacement, magenta = disocclusion`.

## 3.2 6 thí nghiệm mang lên sân khấu (5-7 phút)

Chuẩn bị: mở game, `H` hiện help để khán giả thấy phím, `G` on cho tự lắc.

### TN1: ATW off vs on (1 phút)

1. Giữ `100ms/40ms`, `G on`.
2. `T off` 10s: tường checker xé hình, crosshair không đứng yên, bắn trượt.
3. `T on` 10s: thế giới dính, HUD `Warp correction 2-8 deg` nhảy nhưng ảnh ổn.

Nói: render vẫn 10Hz như nhau, chỉ khác có re-project phút cuối hay không.

### TN2: Pipeline latency (1 phút)

1. `T on`, `V on`.
2. `[` về 0ms: heatmap lạnh, rìa hơi xanh.
3. `]` lên 150-200ms: cả màn vàng/đỏ, correction deg tăng vọt, rìa bắt đầu bad.

Nói: pose càng cũ càng phải warp xa, tốn overscan.

### TN3: Render period (1 phút)

1. Về 40ms, `,` xuống 20ms (~50Hz): `T off` cũng tạm chơi được.
2. `.` lên 200ms (5Hz): `T off` không đọc được, `T on` vẫn định hướng được dù ảnh nhòe khi di chuyển nhanh.

Nhìn thanh frame-age: đầy càng lâu nghĩa là frame càng cũ.

### TN4: Overscan (45 giây)

1. `O` về 1.0, `T on`, xoay nhanh 90 độ: viền đen/xanh lộ.
2. `O` về 1.18: viền hết.

Nói: 0.18 margin = ~39% pixel trả cho warp.

### TN5: ROT vs POS khi strafe (1.5 phút)

1. `P off`, đè `A/D` đi ngang nhìn thẳng tường gần: tường giật theo bước render.
2. `P on`: tường mượt, nhưng mép tường/cửa xuất hiện viền magenta mỏng.
3. Dí sát mép + strafe: magenta dày lên.

Nói: ROT sửa xoay, POS sửa tịnh tiến nhờ depth, lỗ là giá phải trả vì frame cũ không chứa pixel đó.

### TN6: Heatmap đọc như nào (45 giây)

- Tâm lạnh rìa nóng = xoay.
- Vân theo tường gần/xa khi strafe + `P` = parallax.
- `bad` luôn max đỏ (150px).

Tắt `V` trước khi chơi tiếp vì khó aim.

## 3.3 CSV logging: ghi gì, plot gì?

### Bật/tắt

`L` lần 1 tạo `user://atw_log_<unixtime>.csv`, `L` lần 2 flush + báo đường dẫn absolute. Flush tự động mỗi 240 dòng, đóng file khi thoát `main.gd:376-379`.

Tìm file: Godot `user://` trên Windows thường là `%APPDATA%/Godot/app_userdata/LatencyMaze/`.

### Schema (`main.gd:351-364`)

```
elapsed_ms, frame_tick, frame_age_ms, rot_delta_deg, pos_delta_m,
warp_mode, render_interval_ms, pipeline_latency_ms,
yaw_deg, pitch_deg, pos_x, pos_y, pos_z
```

- `elapsed_ms`: từ lúc `_ready`/regen.
- `frame_tick`: 1 nếu display frame này có render mới, else 0.
- `frame_age_ms`: `_accum_ms`, 0 vừa render xong, tiến tới `render_interval`.
- `rot/pos_delta`: pose hiện tại trừ pose render, cũng là việc warp phải bù.
- `warp_mode`: 0 off, 1 ROT, 2 ROT+POS.
- Còn lại là núm + pose head.

Ghi **mỗi display frame**, không phải mỗi render. Nên 10s 60fps ≈ 600 dòng.

### 3 plot nên làm cho báo cáo

1. `rot_delta_deg` theo `elapsed_ms`, tô màu theo `warp_mode`. Kỳ vọng: delta chỉ phụ thuộc latency + tốc độ quay, không phụ thuộc warp, nhưng trải nghiệm khác hẳn — chứng minh warp không giảm delta mà giảm lỗi cảm nhận.
2. Histogram `frame_age_ms` với 2 `render_interval` (50ms vs 200ms). Thấy phân bố đều [0, interval].
3. Bar `pos_delta_m` trung bình khi strafe ROT vs POS + ảnh chụp magenta. POS không giảm `pos_delta` (vì delta là hình học) mà giảm sai số reprojection — cần nói rõ để không bị hỏi vặn.

Python gợi ý:

```python
import pandas as pd, matplotlib.pyplot as plt
df = pd.read_csv("atw_log_xxx.csv")
for m,lbl in [(0,"OFF"),(1,"ROT"),(2,"ROT+POS")]:
  d = df[df.warp_mode==m]
  plt.plot(d.elapsed_ms, d.rot_delta_deg, label=lbl)
plt.legend(); plt.xlabel("ms"); plt.ylabel("deg"); plt.show()
```

## 3.4 Kịch bản thuyết trình 20 phút — 20 slide

| # | Slide | Thời gian | Lời nói tóm tắt |
|---|-------|-----------|-----------------|
| 1 | Tiêu đề + 3 số 10Hz/40ms/60fps | 1' | Không cần kính vẫn học VR compositor |
| 2 | Mục tiêu 4 gạch | 0.5' | Tái hiện, so OFF/ROT/POS, chỉnh + đo, game hóa |
| 3 | Demo sốc `G,T` | 1' | Cùng render cũ, khác warp |
| 4 | Motion-to-photon | 1.5' | Chuỗi latency, 50ms quay 5-15 độ |
| 5 | Vì sao warp rẻ hơn render nhanh | 1' | 1 fullscreen pass vs cả scene |
| 6 | Pose history | 1' | Buffer 2s, sample `now-latency`, nội suy |
| 7 | Toán ROT | 1.5' | `reproj=Rr^-1*Rc`, xoay ray từng pixel |
| 8 | Overscan + demo `O` | 1' | FOV 1.18, tắt là hở viền |
| 9 | Giới hạn ROT khi strafe | 0.5' | Parallax cần depth |
| 10 | Heatmap `V` | 1' | Tâm lạnh rìa nóng, latency càng cao càng đỏ |
| 11 | PTW lặp 3 lần | 1.5' | Dựng P từ depth, trượt ray, chiếu lại |
| 12 | Depth pack RG | 1' | Slab 0.25m + dư, sRGB decode, tắt MSAA |
| 13 | Disocclusion magenta | 1' | Lỗi trung thực, PTW nào cũng bị |
| 14 | Khi nào POS thua | 0.5' | Mặt vát, vật mỏng |
| 15 | Maze + checker | 1' | Pattern cao tần để lộ judder, MultiMesh 1 draw |
| 16 | Player HEAD + HUD | 0.5' | Head 1.55m là IMU, HUD post-warp |
| 17 | Ma trận 5 thí nghiệm | 1' | Làm live TN1-TN5 |
| 18 | CSV + plot | 1' | Schema 13 cột, 3 plot mẫu |
| 19 | Đọc kết quả | 0.5' | Latency tăng -> warp xa, POS mượt + lỗ |
| 20 | Hạn chế + kết | 1' | Không vật động/prediction, 1 câu kết |

Câu kết: **render chậm bao nhiêu cũng được, miễn phút cuối warp đúng pose — nhưng warp càng xa càng hở, và chỗ bị che thì không ai bịa được.**

Backup slide: ATW vs ASW vs Late-latch, luồng 1 frame, bảng phím.

## 3.5 Hạn chế phải tự nói trước khi bị hỏi

1. Scene tĩnh: không xử vật động, animation, particle — cái này cần ASW/optical flow, ngoài scope.
2. Không xử view-dependent: specular/highlight dán theo ảnh cũ, warp xong hơi sai sáng.
3. Depth twin tốn 1 pass + memory: cảnh thật dùng depth buffer sẵn, ở đây duplicate geometry.
4. Pack RGBA8 + sRGB + nearest: có quantization, biên depth răng cưa nhẹ.
5. Không prediction: chỉ dùng pose quá khứ/hiện tại, compositor thật có Kalman đoán 10-20ms tới.
6. Không async thật: vẫn chạy sync trong Godot, không có thread compositor + vsync/scanout riêng.

## 3.6 Hướng phát triển

- Thêm prediction tuyến tính/Kalman cho `pipeline_latency` + display latency, so có/không prediction.
- Depth R32F thay vì pack tay, đo sai số pack.
- Thêm vật động + so ATW thuần vs ATW+flow.
- Đo latency thật bằng LED + photodiode, đối chiếu `frame_age` trong CSV.
- Benchmark overscan 1.0/1.18/1.3: pixel cost vs edge-reveal rate.

## 3.7 FAQ phản biện

**Sao không render luôn 120Hz?** Tốn GPU theo scene, vẫn còn pipeline/display latency. Warp tốn hằng số theo resolution, độc lập scene.

**ATW vs ASW?** ATW sửa đầu cử động bằng hình học, ASW sửa vật cử động bằng flow. Đề tài chỉ làm ATW/PTW vì scene tĩnh.

**Sao depth không lấy từ viewport chính?** Viewport màu không cho metric Euclid + bị MSAA/lighting làm bẩn. Render riêng layer 2 sạch.

**Magenta có phải bug?** Không. Là disocclusion trung thực. Muốn hết phải inpaint/hole-fill, compositor thật cũng chỉ fill tạm.

**Checker để làm gì?** Pattern tuần hoàn tương phản cao làm judder lộ rõ nhất. Tường trơn sẽ che lỗi.

**CSV `warp_mode` để làm gì?** Để cắt đoạn OFF/ROT/POS trong cùng 1 lần log khi demo live, không cần nhiều file.

## 3.8 Checklist trước khi lên bục

- [ ] Godot 4.7, F5 chạy 60fps display.
- [ ] Capture chuột được, `G,T,P,O,V,L` thuộc.
- [ ] `R` 1 maze dễ đi, nhớ vị trí 1-2 target.
- [ ] Xóa log cũ, test `L` 2 lần thấy file.
- [ ] Để sẵn `,` `.` `[` `]` ở 100ms/40ms.
- [ ] Tắt `V` trước khi chơi, bật khi giải thích.
- [ ] Backup ảnh heatmap + magenta phòng máy chiếu lag.
