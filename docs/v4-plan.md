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

Built in one autonomous round on 2026-10-08, before any wall session: everything that does not need your eyes is
done, and every open choice is a switch in the tuning build. Verified on the device by `screenrecord` at 20 fps and
contact sheets, plus widget tests (107 pass).

1. Spike: nudge mode (P2) with edge treatments (P6) and the launch/return switcher (P5). One wall session picks
   height, position, edge, launch and return. Losing launch variants are deleted in a follow-up commit, with the
   reasons recorded here.

   Done 2026-10-08, except the wall session. Deviations:
   - The whole navigator lives in the band (`BandFrame` in `MaterialApp.builder`), so P3 and P9 came for free:
     clock, gear, dialogs and scrims all sit inside it and see the band as their screen.
   - Nudge mode is entered from a "Tune band" row in quick settings (tuning builds only), not by a long press on
     the clock: the clock is not focusable, and making it so would change the D-pad traversal for a tuning tool.
     Quick settings also carry the switchers for launch, return, focus glide and idle.
   - Tuning is saved to `band_tuning.json` in the app's files directory, not `shared_preferences` (removed in
     v3). On a cold start it arrives about 2 s after the first frame, so a tuning build animates from the release
     constants into the saved band once; release builds read nothing.
   - Back is turned into a route pop by `MainActivity`, never a key, so idle and nudge mode take it in
     `BandController.didPopRoute`; the controller is created before the navigator so it is asked first.
   - Launch variants measured on the device (Google TV 14):
     - Clip reveal (`makeClipRevealAnimation`), from the tile and from the band: ignored, plays the same
       cross-fade as the system default. Deleted.
     - Scale up (`makeScaleUpAnimation`): works; the app grows out of the tile, or out of the band ("Scale up
       from band", added as the native version of "the band grows into the app"), in about 150 ms.
     - Band grows (Flutter), then the app with no animation or a fade: works, but apps need 300-400 ms to draw
       their first frame, which left the full frame olive and empty for that long. The app now starts together
       with the growth. `FLAG_ACTIVITY_NO_ANIMATION` still shows a short fade on this build.
   - Return variants: "Band collapses" works: the app cross-fades into a full-frame olive area that then shrinks
     into the band. "Content fades in" overlaps the system cross-fade and is hard to tell from the default.
2. Band layout with the picked constants: black frame, background confined to the band, clock and gear at its top
   edge (P3), row snapping (P4).

   Done 2026-10-08. Picked on the wall: 60 % height, position 60 %, hard edge (`BandGeometry.release`). Row snapping: the grid moves between windows of whole rows (`HomeLayout.windowFor`); window 0 keeps
   the "Apps" heading, later windows start one gap above a row. The first grid row still peeks in under the hero
   as in v1. The soft edge fades only the background, so the clock sits in the fade zone at the band's top.
3. Launch and return animation as picked.

   Picked on the wall 2026-10-08: "Band grows, cut" and "Band collapses", now the release defaults. The first
   round felt like a fast return after a slower launch, so they got their own durations (`Motion.launch` 480 ms,
   `Motion.returnHome` 1000 ms); the app starts 350 ms before the growth ends, and the content comes back over
   the last 60 % of the collapse instead of on its own timer.
4. Motion vocabulary and focus glide, home entrance, panel motion (P7).

   Done 2026-10-08. `Motion` in `theme.dart`: 180 ms for focus and scrolling, 360 ms for layout, one
   ease-in-out-cubic curve. Focus glide: one brass ring at home level (`FocusGlide`) eases toward the focused
   tile's visual box and stops its ticker once settled, so an idle home screen schedules no frames; tiles draw
   their own ring only when there is no glide (tests, or the switch set to "jump"). Panels slide in from the right
   while fading. The home entrance is the return animation (step 3).
5. Side panels inside the band (P9).

   Done 2026-10-08 via step 1. At 60 % height quick settings shows four rows and scrolls; whether that is
   enough is a wall-session call (fallback: floating panels).
6. Idle, last: after some minutes without input the band dims or shrinks to a small picture frame. Waits on the
   open screensaver question (`dreamx`/`backdrop` are still enabled on the device).

   Built 2026-10-08 as a switch (off, dim, picture frame), off in release. After 2 minutes without a key the
   band dims to 25 % or shrinks to a 240×135 rounded frame with a large clock, centred in the band. The next key
   only wakes it; Home and the quick-settings long press wake it too. The device's screensaver (`dreamx`
   Backdrop) starts at 10 minutes and sleep at 20, so the idle state comes well before both.

## Open for the wall session

- Focus glide versus jump; idle off, dim or picture frame.
- Whether quick settings has enough room inside the band, or panels should float.
- Whether the tuning build's switchers stay in the final build.
