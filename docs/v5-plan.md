# v5: focus motion, diamonds and sound

The polish layer from the [polish plan](https://claude.ai/code/artifact/ec631e24-aec7-4108-86ee-92d6496e12c6) (the
reference implementation is the hero demo in its Launcher Moodboard), applied to the v4 band. The layout, data and
D-pad model stay as they are. The plan is a starting point: where v4 already solves something, v4 wins and this file
records the difference.

## Decisions (2026-10-09)

- V1. Built on `main` after merging v4, on branch `v5-polish`.
- V2. Focus motion uses interruptible springs with overshoot, which retarget from the current value and velocity.
  This replaces v4's 180 ms ease-in-out for focus, and the ease stays available as a switch so the two can be
  compared on the wall. Layout motion (band, launch, return) keeps `Motion.layout` and the v4 lengths.
- V3. There is no left navigation bar, because the launcher has nothing to navigate to. The plan's side-bar style
  (slide, row stagger, dimmed and slightly smaller launcher behind, dimmed spotlight) goes to the panels that exist:
  quick settings and the app panel.
- V4. The edge nudge plays wherever a D-pad press finds no next tile, which is where focus stops today.
- V5. Tuning extends `band_config.json` and "Band & motion" instead of adding a slider panel. The file is watched,
  so a `adb push` applies to the next focus move without a restart. A frame-time overlay can be switched on there.
- V6. Sound ships the plan's prototype tones as they are, rendered to WAV by a script in `tool/` and played by
  `SoundPool` in `MainActivity`. The per-tile pitch and the ±12 Hz spread come from the playback rate. There is
  no new plugin, so there is no new permission. A sound test on the device and tuning, or designed samples, follow
  in v5.1.
- V7. The focus ring stays brass (the plan's colour table keeps the accent for state). Cream is a switch to compare.
- V8. Idle keeps v4's off, dim and picture frame. The plan's attract pan is not built, because 320×180 banners blur
  at band size.
- V9. The device answers the plan's platform questions: a Google TV stick at 1080p output, 960×540 logical px, no
  Menu key. The diamonds are a fragment shader, and this round measures frame times, which v4 skipped.

## Steps

1. Motion engine and tuning: a spring helper, the motion values from the plan in `Motion`, everything in
   `band_config.json` with a file watch, and a frame-time overlay.
2. Tile focus: lift, scale, travelling ring and shadow on springs; dimmed, desaturated unfocused tiles; sheen once
   per focus; edge nudge; press; hold-to-scroll mode; focus memory per region.
3. Diamond background: the light function as a fragment shader with uniforms, spotlight spring, pulse, hue ease,
   Warm or App colour, and strength.
4. Panel style: quick settings and the app panel slide in with staggered rows over a dimmed launcher, and the
   spotlight dims to 40 % while a panel is open.
5. Sound, reduced motion and performance: the prototype tones with their repeat rules, reduced-motion variants,
   frame timings on the device, and the order in which things degrade when over budget.

## v5.1

- Sound test on the device: levels against the projector's fan and the room, pitch spread, and whether designed
  samples replace the tones.
