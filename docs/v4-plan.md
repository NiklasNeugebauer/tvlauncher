# v4: polish for projector viewing

Purely aesthetic. The top of the projected frame sits high in the room and is uncomfortable to look at, the
full-frame layout has dead space, and the projector's black is close to off. So the home screen shrinks into a
lit band on a black frame, and motion ties the band to app launches. Builds on v3 (`theming-plan.md`): black
outside the band, olive gradient and glow only inside it.

## Decisions (2026-10-08)

- P1. Band height and vertical position are picked on the wall, not on the laptop. Both become release
  constants in `HomeLayout`; no user-facing setting.
- P2. Nudge mode, compiled in only with a `--dart-define` flag. Long-press on the clock enters it. Up/down change
  the band height in 5 % steps, left/right move it from top to bottom in 5 % steps, select cycles the edge
  treatment (P6), Back exits. The real home screen renders in the band while nudging; focus navigation pauses.
  An overlay shows the values plus a 1 px brass outline of the full 1920×1080 frame and of the band, so overscan
  and keystone show up on the wall in the same look. If the frame outline is clipped, a safe-area inset becomes
  one more constant. Values persist in a small JSON file in the app's data directory (`path_provider` is
  already a dependency; `shared_preferences` went in v3 and does not come back), so they survive a launcher
  restart. The mode stays on the branch for later retuning.
- P3. Clock and gear move inside the band, at its top edge. Nothing lit above the band.
- P4. Scrolling inside the band always lands on whole grid rows; content is hard-clipped below the clock line.
  A short fade during motion only if the clip looks harsh on the wall.
- P5. App launch and return are chosen in a spike (step 1). Launch variants: clip reveal from the focused tile,
  clip reveal from the band (`ActivityOptions.makeClipRevealAnimation`), and a Flutter band-grow followed by a
  start without system animation. Return variants: plain system transition, and a launcher-side "band
  collapses from full black to its height" on resume. Judged with two or three real apps, since their splash
  colours differ. The switcher may stay in the flag build if it proves useful.
- P6. Band edge: hard edge, soft fade into black, or an inset panel with side margins and rounded corners;
  picked in nudge mode. The inset panel would make the idle shrink (step 6) a continuous move.
- P7. One motion vocabulary: a short duration for focus, a longer one for layout changes, one curve; constants
  next to `Palette`. In scope: focus glide (the ring slides between tiles), home entrance, panel motion.
- P8. "Aspect checks" are not a separate phase; P2's frame outline covers the projection chain, and tiles keep
  16:9 at every band height.
- P9. Side panels live inside the band: docked right, band height and position, scrim only over the band. If the
  band turns out too short for them, fall back to floating panels with rounded corners.

## Steps

1. Spike: nudge mode (P2) with edge treatments (P6) and the launch/return switcher (P5). One wall session picks
   height, position, edge, launch and return. Losing launch variants are deleted in a follow-up commit, with the
   reasons recorded here.
2. Band layout with the picked constants: black frame, background confined to the band, clock and gear at its top
   edge (P3), row snapping (P4).
3. Launch and return animation as picked.
4. Motion vocabulary and focus glide, home entrance, panel motion (P7).
5. Side panels inside the band (P9).
6. Idle, last: after some minutes without input the band dims or shrinks to a small picture frame. Waits on the
   open screensaver question (`dreamx`/`backdrop` are still enabled on the device).
