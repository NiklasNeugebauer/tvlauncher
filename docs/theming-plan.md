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
2. Tiles and home chrome (focus ring, radius, heading, clock, gear).
3. `RightPanelDialog`, a shared `PanelRow` widget, and the five panels on it.
4. Tests: delete gradient tests, update wallpaper tests, add a widget test that the home background is the themed
   one without a custom wallpaper and the image with one; panel row focus test.

Order relative to v2: after the Flutter upgrade lands, because the upgrade touches `ThemeData` (deprecated
`accentColor`/`backgroundColor`) and this would conflict in the same lines.
