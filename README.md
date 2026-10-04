# The Latency Maze — Asynchronous TimeWarp (ATW) Simulator

A first-person maze game that is secretly a **real-time VR latency simulator**.
Built in Godot 4.7 (Forward+). No VR headset required — your mouse is the IMU.

## The core idea

Real VR compositors (Oculus ATW, SteamVR) fight motion-to-photon latency like
this: the engine renders frames relatively slowly, but right before the image
is sent to the display, the latest IMU head pose is sampled and the rendered
image is **re-projected in 3D** to match it. Your head can move after the frame
was rendered and still see a correctly-oriented world.

This project recreates that pipeline on a flat screen:

- The maze renders into a `SubViewport`, but the **camera pose is only
  refreshed at a simulated render rate** (default 10 Hz) — and uses a head pose
  that is already `pipeline_latency_ms` old, read from a timestamped pose
  history buffer. A deliberately slow, late pipeline.
- The mouse-driven **head updates every display frame**, like a real IMU.
- Every display frame, a fullscreen shader (`shaders/timewarp.gdshader`)
  computes `R_render⁻¹ · R_current` and re-projects each screen pixel's ray
  into the stale rendered image — the exact math of rotational TimeWarp.
- The render camera uses a slightly **larger FOV (overscan)** so the warped
  image has spare pixels at the edges, exactly like real compositors. Toggle it
  off (key `O`) to see the edge-reveal artefact.
- **Positional TimeWarp (key `P`)**: a second `SubViewport` sharing the same
  `World3D` renders layer-2 "depth twin" geometry with a depth-pack material —
  a metric depth buffer for the stale frame. The warp shader then iterates a
  depth-assisted gather: reconstruct each surface point, slide the display ray
  to it, re-project into the render view (3 iterations). This adds true
  parallax correction for translation — and honest disocclusion holes
  (magenta) where the new pose reveals surfaces the frame never saw, just like
  real PTW implementations.

## Playing

Goal: escape the maze. **Shoot all glowing targets** to unlock the green
`EXIT` door in the far wall, then walk through it.

| Input | Action |
|---|---|
| WASD / Mouse / LMB | move / look / shoot |
| `T` | ATW on/off — the A/B test, feel the judder |
| `P` | + positional warp (depth-assisted, needs ATW) |
| `V` | warp-displacement heatmap visualization |
| `L` | CSV logging on/off (saved to `user://atw_log_*.csv`) |
| `,` `.` | simulated render period −/+ 10 ms (20–250 ms) |
| `[` `]` | pipeline latency −/+ 10 ms (0–250 ms) |
| `O` | overscan margin on/off |
| `G` | auto head-sway (hands-free judder demo) |
| `R` | new maze |
| `H` / `F1` | help panel |
| `Esc` | release mouse |

The CSV log records per-display-frame: elapsed time, whether a new rendered
frame arrived, frame age, rotational & positional pose deltas, warp mode,
simulated latency parameters, and head orientation/position — everything
needed to plot motion-to-photon error over time.

The top-left HUD shows display fps vs. simulated render rate, pipeline
latency, live warp-correction angle, and a **frame-age bar** that fills between
rendered frames — watch it while ATW keeps the world stable.

## Things to try

1. `G` to auto-sway, `T` to toggle ATW. At 10 Hz simulated render, ATW-off is
   nearly unreadable; ATW-on stays glued to your view.
2. `O` to disable overscan, rotate with ATW on — the warped edges reveal.
3. Increase pipeline latency with `]`: ATW still corrects the stale pose, but
   the needed correction (and edge reveal) grows.
4. Strafe sideways with ROT only: rotation is smooth, translation stutters.
   Now press `P` — positional warp uses depth to fix parallax too. Watch for
   magenta disocclusion holes at geometry edges: real PTW has the same
   artefact (it can't invent pixels the render never saw).
5. `V` shows the warp-displacement field live: rotational warps displace more
   toward screen edges (projection nonlinearity); positional adds parallax
   structure on top.

## Code map

- `scripts/main.gd` — simulator core: pose ring-buffer, quantized render
  ticks, per-display-frame reprojection uniforms, depth viewport, CSV
  logging, input, HUD, shooting.
- `scripts/player.gd` — FPS body + `head` node (the virtual HMD/IMU).
- `scripts/maze.gd` — recursive-backtracker maze, merged MultiMesh walls,
  layer-2 depth twins, targets, EXIT door, trigger zone.
- `scripts/target.gd` — pulsing target orbs.
- `scripts/hud.gd` — crosshair, stats, frame-age bar, help.
- `shaders/timewarp.gdshader` — rotational reprojection + depth-assisted
  positional iteration + displacement heatmap.
- `shaders/depth_pack.gdshader` — packs Euclidean distance into RGBA8
  (two-channel slab/fine scheme, survives sRGB encode).
- `shaders/checker.gdshader` — world-space high-contrast checker + emissive
  grid lines (judder is most visible on periodic high-frequency patterns).
