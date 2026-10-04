# 01 — Lý thuyết: từ latency tới ATW / PTW

## 1.1 Motion-to-photon latency vì sao gây say?

Pipeline VR thật:

```
IMU sample (1000Hz) -> game render (10-50ms) -> compositor warp (2-3ms)
  -> scanout/vsync -> display photon
```

Tổng 30-80ms là bình thường. Trong 50ms đó đầu quay 5-15 độ là chuyện thường, đi bộ 5-20cm cũng thường. Nếu bê nguyên ảnh cũ lên kính, thế giới trễ theo đầu, tiền đình và thị giác mâu thuẫn nhau -> say, aim không được.

Giải pháp ngây thơ là render nhanh hơn: lên 90-120fps thật. Tốn GPU, vẫn còn pipeline + display latency, không triệt để.

Giải pháp compositor là **đừng cố render đúng ngay từ đầu, mà sửa sai vào phút cuối**: cứ lấy pose mới nhất rồi re-project ảnh cũ. Warp 1 ảnh full-HD chỉ là 1 fullscreen pass vài trăm micro-giây, chạy kịp 90-120Hz trong khi game chỉ chạy 45-72Hz.

Project này làm quá lên để dễ thấy: render 10Hz + pose cũ 40ms = ảnh lúc nào cũng cũ 40-140ms. Tắt warp là không chơi được.

## 1.2 ROT-ATW: chỉ cần biết đầu xoay bao nhiêu

### Đầu vào / đầu ra

- Lúc render: lưu `R_render` (basis world của camera) + `C_render` (vị trí).
- Lúc hiển thị: có `R_current`, `C_current` mới nhất từ IMU/chuột.
- Cần: với mỗi pixel màn hình hiện tại, tìm màu ở đâu trong ảnh cũ.

### Công thức

```
reproj = R_render^-1 * R_current          # main.gd:231
dir_display = ray qua pixel (tính từ FOV display)
dir_render  = reproj * dir_display        # timewarp.gdshader:91
uv_render   = project(dir_render)         # dir_to_render_uv()
color = texture(anh_cu, uv_render)
```

`dir_to_render_uv()` trong `timewarp.gdshader:42-45`:

```
uv.x = 0.5 + 0.5 * d.x / (-d.z) / tan_half_fov_render.x
uv.y = 0.5 - 0.5 * d.y / (-d.z) / tan_half_fov_render.y
```

Đây là project pinhole ngược. Không cần biết scene là gì, không cần depth. Chỉ xoay ray.

### Vì sao đúng?

Camera quay thuần túy thì ảnh mới là ảnh cũ xoay đi. Với cùng tâm chiếu, mọi vật dù gần xa đều dịch theo cùng 1 phép xoay trên mặt cầu directions. Nên ROT đúng 100% cho xoay đầu thuần túy.

### Khi nào sai?

1. Có tịnh tiến: đi ngang thì vật gần phải dịch nhanh hơn vật xa (parallax). ROT cho mọi vật dịch như nhau -> vật gần giật.
2. Ống kính/FOV khác nhau giữa render và display nếu không quy đổi `tan_half_fov`.
3. Quay quá nhanh vượt overscan -> hết pixel để lấy.

Chính 3 cái sai này dẫn tới 3 tính năng tiếp theo: PTW, overscan, heatmap.

## 1.3 Overscan: pixel dự phòng ở rìa

Render FOV rộng hơn display FOV:

```
fov_render = 2*atan(tan(fov_display/2) * overscan)   # main.gd:247
overscan mặc định 1.18, tắt về 1.0 bằng phím O  # main.gd:424
```

Khi warp xoay ảnh, rìa ảnh mới cần pixel nằm ngoài ảnh cũ. Nhờ overscan, shader vẫn có pixel để lấy. Tắt đi (`O`) rồi xoay nhanh sẽ thấy viền `edge_color = (0, 0.008, 0.03)` `timewarp.gdshader:39,126` — gọi là edge-reveal.

Compositor thật cũng vậy: render eye-buffer lớn hơn vùng nhìn thấy 10-20%.

Lưu ý: overscan không miễn phí. Render to hơn = tốn pixel shader hơn. 1.18 mỗi chiều là ~1.39x pixel.

## 1.4 PTW (+POS): thêm depth để sửa tịnh tiến

### Ý tưởng

Nếu biết mỗi pixel ảnh cũ cách camera bao xa (depth metric), ta dựng được điểm 3D thật của mặt tường, từ đó trượt ray hiện tại ra đúng chỗ đó rồi chiếu ngược lại. Vật gần/xa tự khắc dịch đúng parallax.

### Vòng lặp trong shader

`timewarp.gdshader:97-121`, `ptw_iterations = 3`:

```
seed suv bằng nghiệm ROT
lặp 3 lần:
  rdir_w = normalize(R_render * render_uv_to_dir(suv))  # ray world của guess
  d = decode_depth(depth_tex(suv))                       # depth Euclid
  P = C_render + rdir_w * d                              # điểm mặt tường
  dw = normalize(R_current * dir_display)                # ray display
  t = dot(P - C_current, dw)                             # trượt ray tới mặt
  nếu t <= 0.02 -> bad (sau camera)
  ql = R_render^-1 * (C_current + t*dw - C_render)        # về không gian render
  nếu ql.z > -0.02 -> bad (sau camera)
  suv = dir_to_render_uv(ql)
  nếu suv ngoài [0,1] -> bad
```

Hội tụ nhanh với mặt frontal, chậm/sai với mặt vát, vật mỏng, biên depth không liên tục.

### Depth pack vì sao phải pack tay?

RenderTarget Godot là RGBA8, không cho float depth trực tiếp. `depth_pack.gdshader:18-21` pack khoảng cách Euclid `length(view_pos)`:

```
d clamp [0, 63.999]  # maze chéo ~55m
R = floor(d*4)/256   # slab 0.25m nào, mức rời rạc chính xác
G = d - floor(d*4)*0.25  # phần dư trong slab, ~0.4mm
```

Viewport ghi sRGB nên shader warp phải giải ngược `srgb_to_lin()` trước khi tách slab `timewarp.gdshader:58-66`. `depth_vp` tắt MSAA vì AA làm nhòe pack. Sai số quantization là có nhưng đủ nhỏ so với warp vài pixel.

### Disocclusion: lỗi trung thực, không phải bug

Pose mới có thể thấy vùng mà frame cũ chưa từng thấy: sau mép tường, sau orb, sau cửa. Không có pixel nào để lấy. Shader đánh `hole_color = (0.4, 0, 0.3)` magenta `timewarp.gdshader:40,126`.

Phân biệt:

| Màu lỗi | Khi nào | Ý nghĩa |
|---------|---------|---------|
| Xanh đen `edge_color` | `warp_mode 1` hết pixel rìa | Thiếu overscan |
| Magenta `hole_color` | `warp_mode 2` fail iteration | Che khuất thật, PTW nào cũng bị |

Dí sát mép tường + strafe ngang là thấy magenta dày lên. Đây là trade-off lõi của PTW: sửa parallax nhưng trả giá bằng lỗ.

### Khi nào POS thua ROT?

- Mặt vát/grazing: 1 pixel depth sai kéo cả vùng sai.
- Vật mỏng, dây, lan can: depth nhảy bậc, iteration ping-pong.
- Depth twin không khớp visual (scale pulse của target): twin là con của mesh nên tự scale theo `maze.gd:285-289`, nhưng nếu lệch 1 frame vẫn có halo.

Vì vậy `P` mặc định off, bật `P` tự ép `ATW on` `main.gd:415-418`. Compositor thật cũng coi PTW là hỗ trợ, ROT vẫn là xương sống.

## 1.5 Heatmap warp-shift `V`

`V` vẽ độ dịch pixel:

```
dpx = bad ? 150 : length((suv - suv0)*resolution)  # timewarp.gdshader:133
col = heat(dpx/150)                                # xanh->cyan->xanh lá->vàng->đỏ
```

`suv0` là vị trí không warp. Đọc heatmap:

- Xoay thuần: tâm lạnh, rìa nóng, đối xứng xuyên tâm do phi tuyến `x/z`.
- Thêm latency: cả màn nóng lên đều.
- Bật `P`: thêm vân theo hình học — tường gần nóng hơn tường xa khi strafe.

Dùng heatmap để chứng minh `càng cũ càng phải warp xa`, không nói mồm.

## 1.6 So với kỹ thuật lân cận

| Kỹ thuật | Sửa gì | Cần gì | Project này có? |
|----------|--------|--------|-----------------|
| Late latching | Lấy pose muộn nhất | Pose buffer | Có (`_pose_history`) |
| ROT-ATW | Xoay | `Rr^-1*Rc` | Có, phím `T` |
| PTW | Tịnh tiến | Depth + lặp | Có, phím `P` |
| ASW / motion smoothing | Vật động trong scene (nội suy/extrapolate) | Optical flow / motion vector | Không — scene tĩnh nên không cần |
| Prediction | Đoán pose tương lai bù display latency | Lọc Kalman | Không — chỉ dùng pose quá khứ + hiện tại |

Nói 1 câu khi bị hỏi: ATW sửa đầu cử động, ASW sửa vật cử động. Đề tài này chỉ làm ATW/PTW.
