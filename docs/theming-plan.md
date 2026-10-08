# v3: theming for the projector room

The launcher runs on a projector on an olive-green wall, mostly in dim evenings with the curtains closed,
sometimes in daylight. A projector cannot show black, so every bright pixel lights the room: the theme is dark,
warm, and low in luminance, and only tiles, text and the focus ring carry light. One fixed theme, no picker.

## Palette

| Token | Value | Use |
|---|---|---|
| `bgTop` | `#1C2419` | background gradient, top |
| `bgBottom` | `#0F140E` | background gradient, bottom (never pure black: the projector floor is grey anyway) |
| `glow` | `#5A4A2A` at 18 % | radial vignette centred at (50 %, 85 %), radius ≈ 0.9 screen width: lamp light from below |
| `surface` | `#1A2118` | panels, dialogs, cards |
| `surfaceRaised` | `#242D21` | focused panel rows, hover |
| `line` | `cream` at 8 % | dividers, panel edge |
| `cream` | `#EDE6D6` | primary text, clock, heading |
| `creamDim` | `cream` at 60 % | secondary text (package name, version, hints) |
| `brass` | `#C9A45C` | focus ring, selected row tint, icons on focused rows |
| `danger` | `#B5563F` | Uninstall row text and icon |

Daylight is the exception; it only needs to stay legible, which cream on olive does.

## Home screen

- Background drawn in code (`ThemedBackground`): linear `bgTop → bgBottom`, radial `glow` on top. No asset, crisp
  at any resolution. A custom wallpaper image still replaces it; the upstream gradient catalogue
  (`gradients.dart`, gradient page, `gradientUuid` setting) is removed.
- Hero row sits at ~65 % of its zone instead of centred (`HomeLayout.heroAlignment`), tuned on the wall.
- Tiles: corner radius 12, focus ring `brass` 3 px, unfocused dim 10 % as today, warm shadow (`#000` 40 %).
  Banner-less tiles use `surface` with `cream` text.
- Clock and "Apps" heading in `cream`; heading at 70 % weight so it does not compete with the tiles.
- Gear icon `creamDim`, `brass` when focused.

## Side panels (quick settings, launcher settings, app panel, wallpaper, hidden apps)

Today: a flat blue slab with uniform text buttons. Target:

- `RightPanelDialog`: 380 logical px wide, `surface`, 1 px `line` on the left edge, 24 px padding, scrim over
  the home screen darker (`bgBottom` at 55 %).
- Header: title in `cream` titleLarge; the app panel shows the banner (or icon) at 96 px wide above the name,
  package and version in `creamDim`.
- Rows: 48 px, icon 20 px + label, 12 px gap, rounded 8. Unfocused: `cream` on `surface`. Focused: `surfaceRaised`
  background, `brass` icon, `cream` label. Pressed: no ripple colour change beyond the focus state. Dividers are
  `line`, with 8 px breathing space around them.
- Destructive rows (`Uninstall`) in `danger`, last in the list, behind a divider.
- Hidden apps list rows reuse the same row style with the app icon as leading.

## Steps (each builds, runs on device, and is judged on the wall)

1. Theme tokens (`lib/theme.dart`) and `ThemeData` from them; `ThemedBackground`; hero alignment. Remove the gradient
   catalogue, page, service getter and setting; wallpaper page becomes "Custom image" / "Back to theme".

   Done 2026-10-08. Deviations: `SettingsService` and the `shared_preferences` dependency went with the gradient
   uuid, which was their only content (one plugin fewer in the manifest). "Back to theme" only appears while a
   custom image is set. The glow radius is computed per layout because `RadialGradient` measures against the
   shorter side. Tokens live in `Palette`, shapes in `Shapes`, both in `lib/theme.dart`.
2. Tiles and home chrome (focus ring, radius, heading, clock, gear).

   Done 2026-10-08. "70 % weight" for the heading is cream at 70 % opacity. The gear lost its blurred shadow
   copy and became a small focus-aware widget (`_SettingsButton`, key `settings`) so it can turn brass.
   Move-mode arrows are brass discs with a dark glyph. Text shadows on clock and heading stay for custom
   wallpapers.
3. `RightPanelDialog`, a shared `PanelRow` widget, and the five panels on it.

   Done 2026-10-08. The scrim is the dialog barrier, so panels open through `showPanel()` instead of a bare
   `showDialog`. `PanelRow` (own file, with `PanelHeader`) takes an icon or any small leading widget plus an
   optional trailing icon; the hidden-apps list is one row per app that unhides on select, with the eye icon
   trailing. The app panel's first row autofocuses like the other pages. Titles are left-aligned above a
   divider rather than centred.
4. Tests: delete gradient tests, update wallpaper tests, add a widget test that the home background is the themed
   one without a custom wallpaper and the image with one; panel row focus test.

   Done 2026-10-08, spread over steps 1 and 3: the gradient and settings-service tests went with step 1, the
   wallpaper tests cover "Custom image" and "Back to theme", the home test asserts `ThemedBackground` without
   a custom image, and `test/widgets/panel_row_test.dart` covers focus colours, the destructive row and hover.

Order relative to v2: after the Flutter upgrade lands, because the upgrade touches `ThemeData` (deprecated
`accentColor`/`backgroundColor`) and this would conflict in the same lines.

## Decisions (2026-10-08)

- T1. All four steps are implemented in one go, each verified by adb screenshot; Niklas judges on the wall afterwards
  and corrections land as follow-up commits. Values the plan calls "tuned on the wall" (hero alignment, glow
  strength) are single constants in `lib/theme.dart` / `HomeLayout`.
- T2. Display name **"Launcher"**. Banner: the themed background with its glow as backing and "Launcher" as the
  wordmark, generated by `tool/banner.py` so it can be regenerated from the palette. Closes D6.
- T3. Hero row at 65 % of its zone supersedes D9 (centred): the tiles move toward the glow at 85 % height so the
  bright tiles and the lamp-light vignette read as one composition.
- T4. Typeface stays Roboto in v3. Afterwards: a round of bundled font candidates, judged from screenshots.
  Round done 2026-10-08 on the device (Source Sans 3, Nunito Sans, IBM Plex Sans, Space Grotesk, Outfit, Fraunces,
  and Fraunces titles over Source Sans 3 rows). Recommendation: Fraunces for clock and titles with Source Sans 3
  for everything else; it is the only candidate that moves the mood toward the lamp-lit room, while the rows stay
  a crisp sans for the projector. Runner-up: IBM Plex Sans alone. Nunito Sans and Space Grotesk rejected. Not
  committed; awaiting Niklas's pick.
- T5. Native splash: an XML gradient drawable (`bgTop → bgBottom`) replaces `splash.jpg`; `NormalTheme` paints
  `bgBottom` behind Flutter so nothing flashes before the first frame.
- T6. No separate dialog design. `dialogTheme` is `surface` with radius 12 and `brass` text buttons, and the About
  box inherits it. SnackBars: `surfaceRaised` with `cream` text. Text input: `brass` cursor and underline.
- T7. Branch `v3-theming` in a worktree; one commit per step plus one for name, banner and splash, each with its
  Done note here. The font round is not committed; only the font picked afterwards lands.
- Name, banner and splash done 2026-10-08: `android:label` and the app title are "Launcher"; `tool/banner.py`
  renders `drawable-xhdpi/banner.png` (themed background, cream wordmark inside a brass tile ring, as asked);
  `launch_background.xml` is a gradient shape over `@color/bg_top`/`bg_bottom`, the window background is
  `bg_bottom`, and both JPEGs are gone. The splash itself could not be captured over adb: as the home app the
  launcher restarts before `screencap` runs.
- Experiments after v3, screenshots only: the font round (T4) and a "widescreen" layout with the whole home
  screen squashed into the bottom portion of the frame. Band shots taken 2026-10-08 at 60 % and 50 % of the
  frame height: 60 % keeps full-size hero tiles and shows two grid rows at once; 50 % shrinks the hero. The
  clock and gear drop to the band's top edge, which v4 has to place deliberately. The hidden height above the
  band should be pure black (the projector's minimum light), with the olive gradient and glow confined to the
  band. Goes into v4.
