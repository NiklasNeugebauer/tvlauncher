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

   Done 2026-10-09. `SpringSpec` (response and overshoot) and `SpringState`/`SpringBuilder` in `lib/motion/`, the
   tunable numbers in `Tune`/`Tuning` under `tuning` in the config, and `focus: spring|ease|jump` replacing v4's
   glide switch (a v4 `focusGlide: false` reads as jump). The focus ring is the first spring user. Deviations:
   - The config is polled once a second while the launcher is in front instead of watched: a stat a second costs
     nothing and does not depend on inotify working through Android's shared-storage layer (not tested).
   - The frame-time readout counts missed vsyncs (gaps between frame starts) rather than frames over 16.7 ms:
     Impeller's raster time includes the wait for a swapchain image, so it sits near 16 ms even when no frame is
     late.
   - Measured on the device: the ring peaks about 200 ms after the press, overshoots 5-8 % and settles by
     350 ms. Baseline before any v5 drawing, focus moves 0.4 s apart: build p50 1.6 ms, raster p50 11-16 ms,
     1-7 missed vsyncs per 50 frames (the first batch after a start is shader warm-up, about 20).
2. Tile focus: lift, scale, travelling ring and shadow on springs; dimmed, desaturated unfocused tiles; sheen once
   per focus; edge nudge; press; hold-to-scroll mode; focus memory per region.

   Done 2026-10-09. Each tile runs three springs: raise (lift and scale), light (brightness and saturation) and
   press. Focus out uses a critically damped 120 ms spring. Dimming is a colour matrix on the banner image
   itself (no extra layer per tile); icon-only tiles darken under a black overlay. Every value is in `Tune`.
   Deviations:
   - The ring now springs only the jump between two tiles, as an offset that decays to zero, and is otherwise
     glued to the focused tile. Following the tile on a spring made it lag and overshoot behind scrolling, the
     tile's own lift and the nudge. It is drawn outside the tile with a 4 px gap and an 8 % white halo
     (`ring: brass|cream`).
   - The lift moved the focused tile's centre off its row, and the traversal policy grouped rows by exact centre
     y, so down picked the other hero tile and left/right found nothing. Rows are now centres within half a tile
     height.
   - The edge nudge moves the focused tile, not the whole row, and plays wherever a press finds nothing to focus
     (`EdgeNudge`, also usable in panels). The tap feedback sound now plays only on a real move.
   - Hold-to-scroll is detected from key repeats in `BandController`; while held, focus moves use a 120 ms spring
     with no overshoot and no sheen. `adb input` sends no repeats, so this is covered by tests only.
   - Focus memory covers the hero only: up from the grid returns to the hero tile focused last. Down from the
     hero keeps going to the nearest grid tile, because returning to a tile deep in the grid would scroll away.
   - No title rise: tiles have no titles.
   - Measured on the device: the nudge goes 9 px out and back in about 300 ms; the sheen is visible on dark
     banners and not on white ones (YouTube, Netflix). Focus moves 0.4 s apart: build p50 5-6 ms (was 1.6, the
     springing tiles rebuild every frame), 0-3 missed vsyncs per 60 frames.
   - After the first check: a nudge on a tile focused for a while moved the tile but not the ring, because the
     ring's ticker had stopped. The nudge now restarts it, and the ring measures the tile at paint time (after
     layout) instead of in the ticker, so it never trails the tile by a frame. The halo is 3 px instead of 6
     (`ringHaloPx`), so it overlaps the neighbours less.
3. Diamond background: the light function as a fragment shader with uniforms, spotlight spring, pulse, hue ease,
   Warm or App colour, and strength.

   Done 2026-10-09. `shaders/diamonds.frag` is the plan's light function and diamond, per pixel in device pixels
   (grid 15 px); `DiamondBackground` feeds it the spotlight. Tiles report focus to `BandController.spotlight`, and
   the background measures the focused tile itself while it animates, so the light follows scrolling and the lift.
   Spring, pulse and hue ease are the plan's numbers; strength, grid, spotlight stiffness and shimmer rate are in
   `Tune`, and `background: diamonds|glow` and `light: warm|app` in the config. Warm is the default, so the
   plan's open question stays open for the wall. Deviations:
   - The ground is flat `Palette.bgBottom`, with unlit diamonds 18 % lighter and the warm light in brass; v3's
     gradient and glow remain as `background: glow`.
   - The colour step is eased in RGB rather than by hue; switching between warm and an app colour, or to a grey
     app (which stays warm), needs no special case.
   - An app's hue is the circular mean of its banner's hues weighted by saturation and value, computed once per
     banner from a 32 px wide decode (`BannerHue`).
   - The shimmer is redrawn by a timer at 30 fps instead of every vsync, and the timer stops while the launcher is
     hidden. A ticker runs only while the spotlight moves, pulses or changes colour.
   - Measured on the device: focus moves 0.4 s apart keep 0-2 missed vsyncs per 60 frames (build p50 5 ms). At
     rest the band redraws at 30 fps with about 7 ms raster per frame for the whole scene; the shader's own GPU
     time is not separable this way. The frame-time readout now shows fps, since the shimmer's intentional
     30 fps gaps count as missed vsyncs.
4. Panel style: quick settings and the app panel slide in with staggered rows over a dimmed launcher, and the
   spotlight dims to 40 % while a panel is open.

   Done 2026-10-09. `showPanel` pushes its own route: the panel slides in by 105 % of its width on the plan's
   ease-out in 380 ms and out in 240 ms, 38 % of the screen wide on the surface at 92 %. The route reports how far it
   is open to `BandController.panel`, and behind it the home screen scales to 0.97 and the spotlight dims to 40 %
   without pulsing. Rows and the header rise 10 px and fade in, 40 ms apart (`PanelStagger`); the focused row gets
   a brass bar and its fill on the focus spring (later replaced by a sliding highlight, step 5). The settings panel
   reopened each page on the row used last (removed later, see below). Left, toward the launcher, acts as Back.
   All lengths and amounts are in `Tune`. Deviations:
   - No backdrop blur by default (`panelBlurPx` 0): the device is the low tier the plan names; the launcher behind
     is dimmed by the existing scrim instead of a brightness filter.
   - The tile that had focus keeps its focused look and ring while a panel is open, so closing the panel returns
     focus without replaying the lift, sheen or pulse.
   - Found on the TV: the home screen was wrapped in its scale transform only while a panel was open. The change in
     tree shape remounted the home screen, and the first hero tile's autofocus took focus from behind the panel, so
     the D-pad moved tiles instead of rows. It is now always wrapped.
   - Changed on request: only grid apps have a panel, without "Remove from main apps" and "Move". On a main app a
     held select starts move mode and a very long hold (1.5 s) moves it down to the grid, with focus on its hero
     neighbour; a pointer long press, which has no move mode, moves it down at once.
5. Sound, reduced motion and performance: the prototype tones with their repeat rules, reduced-motion variants,
   frame timings on the device, and the order in which things degrade when over budget.

   Done 2026-10-09. `tool/sounds.py` renders the plan's tones to `res/raw` (focus blip, thud, select click, panel
   open and close, hold tick, and a soft Home tone added on request); `MainActivity` plays them with `SoundPool`
   (`USAGE_ASSISTANCE_SONIFICATION`), and `UiSounds` applies the rules: select on key down, the thud once per
   press, during a held key one tick per four moves instead of a blip each, panels at 60 % level. `sound` and
   `soundVolume` (0.5) are in the config. Reduced motion (`reducedMotion`, or Android's "Remove animations") turns
   off the travelling ring, overshoot, sheen, nudge, pulse and shimmer, makes focus moves 120 ms without
   overshoot, jumps the light to the tile, and fades panels in place without the row rise. Deviations:
   - On the wall: the focus blip keeps the ±12 Hz random spread but not the plan's pitch rising per tile.
   - On request: panels got a sliding row highlight (the glide's second mode: a fill with the brass bar, drawn
     behind the rows) instead of each row fading its own fill, which flashed from dark to light.
   - Found on the TV: entering move mode or pressing a tile left the ring at its old size until the next move,
     and a reordered tile left the light behind. The tile's springs now restart the ring on every step, and a
     moved tile tells the spotlight to follow.
   - Performance, focus moves 0.4 s apart: 60 fps, 0-2 missed vsyncs per batch, build p50 about 5 ms (the tiles
     now rebuild only their transform and colour filter per spring step, and the ring and content sit in separate
     layers; neither lowered the UI time measurably), raster within a frame. The shimmer forced to 60 fps holds
     60 fps at about 11 ms raster per frame for the whole scene, so the background fits and the plan's automatic
     degrade order is not built; the shimmer rate and blur stay tunable.
   - Once during the round the device ran focus moves at a steady 45 fps on every build, including step 3's
     background off; a fresh launcher start cleared it. It began after Netflix and Apple TV had run; the cause is
     not known.

## Fixes and changes after TV checks

- 2026-10-09: moving an app into or out of the main apps from its panel left focus on the first tile, and a select
  still held when the panel closed reached that tile as key repeats, which started move mode there. Repeats of a
  key pressed before a tile had focus are now ignored, and the panel tells the home screen where focus goes:
  an app added to the main apps gets focus on its new hero tile in move mode; a removed one hands focus to its
  hero neighbour, without move mode (following the app into the grid would scroll away from the row being
  arranged).
- 2026-10-09, on request: launch and return dip toward black. The lit frame darkens as the band grows for an app
  (80 % darker by 70 % of the growth, `launchDim`), so the app cuts in from near black instead of a lit olive
  frame; coming back, the full frame starts dark and brightens as it settles into the band.
- 2026-10-09, on the wall: going up from the grid into the hero now blips like every other focus move (it moves
  focus itself, past the focus action). Left or down from the gear returns to the hero tile the light is still on,
  instead of the geometrically nearest. The settings panel always opens on its top row; the plan's per-page focus
  memory for panels was removed.

## v5.1

- Sound test on the device: levels against the projector's fan and the room, the spread, and whether designed
  samples replace the tones (`tool/sounds.py` renders them; `soundVolume` sets the level).
