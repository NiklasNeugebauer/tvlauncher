# Home screen redesign: implementation plan (v1)

Scope: new home layout (hero row + alphabetical apps grid), reduced long-press panel, quick-settings panel,
trimmed launcher settings, own `applicationId`/keystore. Pinned toolchain stays as in `CLAUDE.md`
(Flutter 3.7.5 / Dart 2.19, JDK 11, AGP 7.1.1, targetSdk 33). No new permissions, never `INTERNET`.

## Versions

- **v1** (this plan): new home layout, long-press panel variants, quick settings, settings trim, own `applicationId`.
- **v2**: Flutter/AGP upgrade and targetSdk bump. No feature changes.
- **v3**: theming for the projector room, see `theming-plan.md`; also display name and banner (`android:label`,
  `@drawable/banner`), which v1 keeps inherited.

---

## 1. Current architecture (relevant parts)

**Data flow DB → UI**

- `lib/database.dart` has three tables: `Apps` (:29, PK `packageName`, `hidden`, `sideloaded`, `banner`/`icon` blobs),
  `Categories` (:49, `name`, `sort` manual/alphabetical, `type` row/grid, `rowHeight`, `columnsCount`, `order`),
  `AppsCategories` (:66, `categoryId`, `appPackageName`, `order`, both FKs `ON DELETE CASCADE`; FKs are enabled in
  `beforeOpen` :130). Schema version 5 (:103).
- `listCategoriesWithVisibleApps()` (:177) left-joins categories → apps_categories → apps with `hidden = false` in
  the join condition, orders by `categories.order` then per category by `apps_categories.order` (manual) or
  `lower(name)` (alphabetical). Categories with no visible app still come back with an empty list.
- `listApplications()` (:136) returns **all** apps (hidden included) ordered by `lower(name)`.
- `AppsService` (`lib/providers/apps_service.dart`) is a `ChangeNotifier` holding `_applications` and
  `_categoriesWithApps`. `_init` (:49) runs `_refreshState` (sync DB with `getApplications` from the channel, :119),
  seeds "TV Applications" (grid) and "Non-TV Applications" (row) only if `_database.wasCreated` (:51, :85), then
  subscribes to the package event channel (:54) and re-reads both lists on every add/change/remove (:67-68).
  Every mutator re-queries `listCategoriesWithVisibleApps()` and notifies.
- Kotlin `MainActivity.kt`: method channel `me.efesser.flauncher/method` (:41, :49-61), event channel driven by
  `LauncherApps.Callback` (:64-101). Apps come from two queries: `LEANBACK_LAUNCHER` (TV apps, `sideloaded=false`)
  and `LAUNCHER` minus those (`sideloaded=true`) (:110-115). `openSettings` fires `Settings.ACTION_SETTINGS` (:162).

**Rendering**

- `FLauncherApp` (`lib/flauncher_app.dart`) wires providers (:64-73) and maps `select` → `ActivateIntent`,
  `gameButtonB` → `DismissIntent`/`BackIntent` (:75-82). Home route is wrapped in `WillPopScope` (:113) whose
  `onWillPop` **starts the screensaver** (`startAmbientMode`) when FLauncher is the default launcher (:114-119).
- `FLauncher` (`lib/flauncher.dart`) = wallpaper `Stack` + transparent `Scaffold`; `AppBar.actions` contains the
  gear `IconButton` (:94-100) and `TimeWidget` (:107). Body is a `SingleChildScrollView` → `Column` of one widget per
  category: `CategoryRow` for `CategoryType.row`, `AppsGrid` for `CategoryType.grid` (:58-79).
- `CategoryRow` (`lib/widgets/category_row.dart`): title + `SizedBox(height: rowHeight)` with a horizontal
  `ListView` (:51-74). `AppsGrid` (`lib/widgets/apps_grid.dart`): title + shrink-wrapped `GridView` with
  `columnsCount` columns, 16:9 cells (:55-75, :121-126). Both wrap each card in `EnsureVisible` and set
  `autofocus: index == 0` (category_row.dart:65, apps_grid.dart:67), i.e. one autofocus per category.
- `AppCard` (`lib/widgets/app_card.dart`): 16:9 `AspectRatio`, scale 1.1 on focus (:199-206), elevation 16,
  dim overlay when unfocused (:156-163), and a 3px border whose colour **cycles white↔grey** via an endless
  `AnimationController` (:58-63, :164-191, `computeBorderColor` in `color_helpers.dart`), toggleable in settings.
  Banner-less apps get icon + name (:128-153). Owns a private `FocusNode` (:65). Hover requests focus (:260-264),
  tap launches (:269-276). Long press (keyboard via `FocusKeyboardListener`, ≥500 ms on select/enter, or pointer)
  opens `ApplicationInfoPanel`; its `reorderApp` result switches the card into `_moving` mode with arrow overlays
  (:286-297), where D-pad keys call `onMove` and select calls `onMoveEnd` (:232-254).
- `ApplicationInfoPanel` (`lib/widgets/application_info_panel.dart`): Open, Reorder (manual sort only), Hide/Unhide,
  "Remove from <category>", App info, Uninstall (:65-150), inside `RightPanelDialog`.
- `SettingsPanel` (`lib/widgets/settings/settings_panel.dart`) is a `RightPanelDialog` with a nested `Navigator`
  (:48-72) for Settings, Wallpaper, Unsplash, Gradient, Applications, Categories, Category pages.

**Focus traversal**

- The whole home screen is one `FocusTraversalGroup(policy: RowByRowTraversalPolicy())` (flauncher.dart:35).
- `RowByRowTraversalPolicy.inDirection` (`lib/custom_traversal_policy.dart:15-29`) takes all
  `nearestScope.traversalDescendants`, filters by direction using **rounded rect centres** (up/down: strictly
  above/below; left/right: same `dy` only, :41-54), then picks the closest row and within it the node closest by
  distance (:58-77). It does not scroll; scrolling comes from `EnsureVisible` (`lib/widgets/ensure_visible.dart`),
  a non-focusable `Focus` that calls `Scrollable.ensureVisible` when a descendant gains focus.
- Key consequence for the redesign: the policy only sees nodes that are built. A shrink-wrapped grid builds every
  tile, so traversal into off-screen rows works.

---

## 2. Target data model

**No schema change.** Keep `schemaVersion = 5`, all tables and columns.

| Concept | Storage |
|---|---|
| Hero ("main apps") | The category with the lowest `order` (normally exactly one row, `order = 0`). `sort` forced to `manual`. `type`, `rowHeight`, `columnsCount`, `name` are ignored. |
| Hero membership + order | `apps_categories` rows for the hero `categoryId`, ordered by `order` (unchanged mechanics: `addToCategory` appends via `nextAppCategoryOrder`, move mode rewrites via `saveOrderInCategory`). |
| Apps grid | Derived, not stored: `_applications` (already `lower(name)` sorted, database.dart:136) filtered to `!hidden` and not in the hero's package set. |
| Hidden apps | `apps.hidden` as today. A hidden hero app keeps its `apps_categories` row but is filtered out by the join (database.dart:180), so it vanishes from the hero and from the grid; unhiding restores it to its old hero position. |

**Schema decision: leave `type`, `rowHeight`, `columnsCount` (and `sort`) in place, remove only UI and service
setters.** Dropping columns in SQLite means a drift `TableMigration` (table rebuild), `schemaVersion` 6, a new
`drift_schemas/moor_schema_v6.json`, regenerated `test/generated_migrations/schema_v6.dart` and a new migration
test, for zero functional gain. With the new `applicationId` every install of this fork starts from an empty DB,
so there is no legacy data to clean up either. The columns have defaults, so `CategoriesCompanion.insert(name:,
order:)` keeps working. Revisit only if the schema is touched for another reason.

**AppsService API after the change** (replaces the category-centric getters for the UI):

- `Category? get heroCategory`, `List<App> get heroApps` (from `_categoriesWithApps.first`),
  `List<App> get gridApps` (derived as above; compute once per refresh, not per `build`).
- `addToHero(App)`, `removeFromHero(App)`, `reorderHero(old, new)` + `saveHeroOrder()` (thin wrappers over
  existing `addToCategory`, `removeFromCategory`, `reorderApplication`, `saveOrderInCategory`).
- Delete: `addCategory` (keep a private insert for seeding), `renameCategory`, `deleteCategory`, `moveCategory`,
  `setCategoryType`, `setCategorySort` (seed writes `sort` directly), `setCategoryColumnsCount`,
  `setCategoryRowHeight`, `_initDefaultCategories`. Keep `startAmbientMode` (Back on hero starts the screensaver).

**First run / upgrade**

- Replace the `wasCreated`-gated seeding (apps_service.dart:51-53, :85-117) with `_ensureHeroCategory()` that runs on
  every start: if no category exists, insert one (`name: "Main"`, `order: 0`, `sort: manual`); if one exists with
  `sort = alphabetical`, set it to manual. Running it unconditionally also covers a DB whose categories were all
  deleted, which the old code could not recover from.
- Fresh install: the hero starts **empty** (D1). Every app is in the grid.
- Existing DB with several categories (only possible on a dev build that ran the old code under the new
  `applicationId`): the lowest-`order` category becomes the hero; the others stay in the DB and are ignored by
  the UI, and their apps show up in the grid. No cleanup needed.

---

## 3. Implementation steps

Each step builds (`flutter build apk --release` or `flutter run --release` against the device) and leaves a usable
launcher. "Device:" lists what to check on the TV. Test changes per step are listed in section 4; run
`flutter test` at the end of every step.

### Step 0: toolchain and baseline

- `mise use flutter@3.7.5`, `mise use java@temurin-11`, install `platforms;android-33`, `build-tools;33.0.2`.
- `flutter pub get && flutter test` to record which tests pass today, then build the APK unchanged.
- Device logical size, measured 2026-10-08: 1920×1080 at density 320 → **960×540 logical px**. All layout
  numbers below assume that; widget tests use the same size (section 4).
- Done 2026-10-08: toolchain installed, 116 tests pass, debug APK builds. Release build fails only on the missing
  keystore (step 1).

### Step 1: packaging (own applicationId + keystore)

Files: `android/app/build.gradle`, `android/app/src/main/AndroidManifest.xml` (label only), `CLAUDE.md`.

- `applicationId "dev.neugebauer.tvlauncher"` (build.gradle:59). **Do not rename the Kotlin package** in v1:
  with AGP 7.1.1 the manifest `package="me.efesser.flauncher"` (AndroidManifest.xml:20) is the namespace for `R`
  and for resolving `.MainActivity`, independent of `applicationId`. Moving the Kotlin package would also mean
  editing `src/debug`/`src/profile` manifests and the GPL header context for no runtime benefit. The method/event
  channel names (`me.efesser.flauncher/method`, MainActivity.kt:41-42, flauncher_channel.dart:24-25) are internal
  strings and stay.
- Consequence: the activity component is `dev.neugebauer.tvlauncher/me.efesser.flauncher.MainActivity`. The
  `CLAUDE.md` shorthand `<applicationId>/.MainActivity` would expand to `dev.neugebauer.tvlauncher.MainActivity`,
  which does not exist. Correct command:
  ```
  adb shell cmd package set-home-activity --user 0 dev.neugebauer.tvlauncher/me.efesser.flauncher.MainActivity
  ```
  Update the deploy section of `CLAUDE.md` accordingly.
- `android:label` (AndroidManifest.xml:45): pick a new display name so the two launchers are distinguishable in
  the "choose home app" list (deferred to v3, D6).
- Keystore (git-ignored path already in `.gitignore`):
  ```
  keytool -genkeypair -v -keystore android/app/upload-keystore.jks -keyalg RSA -keysize 4096 \
    -validity 10000 -alias tvlauncher
  ```
  Export `SIGNING_KEYSTORE_PASSWORD`, `SIGNING_KEY_PASSWORD`, `SIGNING_KEY_ALIAS=tvlauncher`. Back the keystore up
  outside the repo; losing it means uninstall/reinstall (and loss of the hero layout) for every future update.
- The Zomp build (`me.efesser.flauncher`) can stay installed side by side; uninstall it once the fork is HOME.

Device: APK installs next to the old one, `set-home-activity` succeeds, pressing Home opens the fork (still old UI,
with fresh default categories).

Done 2026-10-08: signed `dev.neugebauer.tvlauncher` versionCode 1 installed next to the Zomp build and set as HOME;
Home opens it. Gradle reads `android/key.properties` first, `SIGNING_*` env vars otherwise. Keystore is JKS
(the Android plugin failed to open a JDK-11-generated PKCS12 store). The Zomp build stays installed as a fallback
until the new UI lands.

### Step 2: data layer (hero + derived grid)

Files: `lib/providers/apps_service.dart`, `test/providers/apps_service_test.dart`.

- Add `_ensureHeroCategory()`, `heroCategory`, `heroApps`, `gridApps`, `addToHero`, `removeFromHero`,
  `reorderHero`, `saveHeroOrder` as described in section 2. Recompute `_gridApps` wherever both
  `_categoriesWithApps` and `_applications` are refreshed (:67-68, :138-139, :243, :250) and after
  add/remove-from-hero.
- Remove `_initDefaultCategories` and its call. Keep the other category mutators for now (old UI still uses them);
  they are deleted in step 8.
- Optional, recommended: exclude the launcher's own package in Kotlin `getApplications`/`getApplication`
  (MainActivity.kt:110-124) so the launcher does not list itself (it declares `LEANBACK_LAUNCHER`,
  AndroidManifest.xml:64). See D5.

Device: old UI now shows one empty category; nothing else changes. Uninstall/reinstall to confirm fresh-install path.

Done 2026-10-08: as planned. Verified on device: fresh install shows one empty "Main" category in the old UI.

### Step 3: new home layout

Files: `lib/flauncher.dart` (rewrite body + app bar), new `lib/widgets/hero_row.dart`, `lib/widgets/apps_grid.dart`
(rewrite), `lib/widgets/app_card.dart`, delete `lib/widgets/category_row.dart`.

Structure (one scroll surface, all children built):

```
FocusTraversalGroup(RowByRowTraversalPolicy)
  Stack[wallpaper, Scaffold(
    appBar: AppBar(title: TimeWidget (left), actions: [gear]),
    body: LayoutBuilder → SingleChildScrollView(controller: _scroll) → Column[
      SizedBox(height: heroZoneH, child: Center(HeroRow)),
      Padding(heading "Apps"),
      AppsGrid(6 columns, shrinkWrap, NeverScrollableScrollPhysics),
      SizedBox(height: bottomSpacer),
    ])])
```

`SingleChildScrollView` + shrink-wrapped grid (as today) rather than a lazy `CustomScrollView`/`SliverGrid`: every
tile stays built, so `RowByRowTraversalPolicy` always finds the next row, and the app count on a TV is small.

**Layout math** (`W`, `H` = body constraints from `LayoutBuilder`; constants in one place, e.g.
`lib/widgets/home_layout.dart`):

- `P = 32` side padding, `g = 16` gap (grid and hero), `A = W − 2P`.
- Grid tile: `gridW = (A − 5g) / 6`, `gridH = gridW · 9/16`. At 960 px: `gridW = 136`, `gridH ≈ 76.5`.
- Peek block: `peekH = headingTop (24) + headingText (≈28, measured with a `TextPainter` on the `titleLarge` style
  rather than hard-coded) + headingBottom (12) + 0.35 · gridH`. At 960×540: `≈ 91`.
- `heroZoneH = H − peekH` (body `H` = 540 − 56 app bar = 484 → `heroZoneH ≈ 393`). The first grid row is therefore
  ~35 % visible at the bottom edge, under the "Apps" heading.
- `bottomSpacer = max(0, H − (headingBlock + gridContentHeight + g))` so the page can always scroll far enough to
  put the heading at the top, even with a one-row grid. Without it, "Down scrolls hero out of view" fails when
  few apps are installed.

**Hero shrink-to-fit** (`HeroRow`, no scrolling widget at all):

- `n = heroApps.length`, `maxW = (A − 3g) / 4` (four tiles fill the width; at 960 px `maxW = 212`, height 119).
- `tileW = min(maxW, (A − (n − 1)·g) / n)`, `tileH = tileW · 9/16`; also cap `tileH ≤ 0.7 · heroZoneH`.
- `Row(mainAxisSize: min, children: [SizedBox(tileW × tileH, AppCard), SizedBox(width: g), …])` inside `Center`
  (centred horizontally and vertically in the hero zone).
- Headroom for the 1.1 focus scale: 5 % of `tileW` per side (≤ 10.6 px) fits inside `P` and the hero zone, so no
  clipping. Keep `Clip.none` on the row.
- Tiles always share one row because the width formula never exceeds `A`.

**AppCard changes**: no text labels already for banner apps; keep the icon+name fallback (app_card.dart:128-153).
Add optional `bool showArrowsVertical` (or an `allowedMoves` set) so hero move mode shows only ←/→ (:208-213).
Drop the `Category category` parameter in favour of a `bool inHero` (the panel needs only that).

**Clock/gear**: `AppBar(title: TimeWidget(), centerTitle: false, actions: [gear])`. Time-only is already the format
(time_widget.dart:52). Keep the gear's blur shadow (flauncher.dart:86-93). Drop the `use24HourTimeFormat` selector (time_widget.dart:50-52) and the setting in `SettingsService`; always `DateFormat.Hm()` (D2).

**Focus feedback**: replace the cycling border (app_card.dart:164-191) with a static
`Border.all(color: Colors.white, width: 3)` when focused. Keep the 200 ms scale/elevation/dim transitions that
are part of the existing scale-up. Delete the animation controller (:58-63, :70-83), `TickerModel` usage (:59).

Device: hero centred in the upper area, peek of the first grid row with "Apps" heading visible at the bottom,
banner-less sideloaded apps show icon+name, mouse hover focuses and click launches, D-pad moves row by row.

Done 2026-10-08, with two deviations: the grid is a `Column` of `Row`s of fixed-size tiles (`AppsGrid`) instead
of a sliver grid, because a shrink-wrapped sliver inside the outer scroll view only builds tiles near the viewport
and the row-by-row traversal cannot reach tiles that do not exist; and `AppCard` dropped "Open" from the panel
(select launches) and got the `inHero` flag plus the left/right-only move mode in the same pass (step 6).

### Step 4: focus and scroll behaviour, Back

Files: `lib/flauncher.dart` (make it a `StatefulWidget`), new `lib/home_focus.dart` (small controller),
`lib/flauncher_app.dart`, `lib/widgets/apps_grid.dart`, `lib/widgets/hero_row.dart`.

- `HomeFocusController` (plain class, provided via `Provider` from `FLauncher` state) owns:
  `ScrollController scroll`, `FocusNode heroNode`, `FocusNode gridNode`, `double heroZoneH`.
  `heroNode`/`gridNode` are attached to `Focus(canRequestFocus: false, skipTraversal: true)` wrappers around the
  hero row and the grid. Such nodes are excluded from `traversalDescendants`, so `RowByRowTraversalPolicy` is
  unaffected. Do **not** add nested `FocusTraversalGroup`s; they would swap the policy for their subtree.
- `focusFirstHero()`: `scroll.jumpTo(0)`, then `heroNode.traversalDescendants.first.requestFocus()` (tree order
  equals visual order). If the hero is empty, focus `gridNode.traversalDescendants.first`. This avoids handing an
  external `FocusNode` to "the card at index 0", which would break when move mode reorders cards while focused.
- Scrolling on focus replaces `EnsureVisible` on the home screen:
  - Hero tile gains focus → `scroll.animateTo(0, 150 ms)`.
  - Grid tile gains focus → `target = RenderAbstractViewport.of(ro).getOffsetToReveal(ro, 0.5).offset`,
    then `scroll.animateTo(clamp(max(target, heroZoneH), 0, maxScrollExtent))`. The `max` keeps the hero fully
    scrolled out while in the grid and puts the "Apps" heading at the top for the first row.
- Autofocus: only the first hero card (`autofocus: inHero && index == 0`); no grid card autofocuses. Empty hero:
  first grid card autofocuses.
- Lost focus after the focused tile disappears (hide, uninstall, add/remove hero): after each `AppsService`
  notification, in a post-frame callback, if `FocusManager.instance.primaryFocus` is null or not inside
  `heroNode`/`gridNode`/the gear and no dialog is open, call `focusFirstHero()`. For add/remove from hero prefer
  focusing the moved app's new tile (look up by `ValueKey(packageName)`), falling back to the first hero tile.
- **Back**. On Android TV the remote's Back is `KEYCODE_BACK`; Flutter sends it to the framework as
  `LogicalKeyboardKey.goBack`, nothing handles it, and the embedding then calls `onBackPressed` →
  `navigation/popRoute` → `WillPopScope.onWillPop` of the top route. Dialogs (panels, settings) are separate routes
  and keep popping themselves.
  Change `onWillPop` in `flauncher_app.dart:114-120` to:
  - if not default launcher (dev install): keep today's behaviour (return true, app exits);
  - else if `gridNode.hasFocus` → `focusFirstHero()`, return false;
  - else (hero focused) → `startAmbientMode()` as today, return false. Back on the hero starts the screensaver.
  Route `BackIntent` from `gameButtonB` (flauncher_app.dart:78-81, :121) through the same function so gamepads
  behave identically.

Device: Down from hero → grid first row focused, hero fully out of view; Up from the first grid row → nearest hero
tile, page back at top; Back anywhere in the grid → first hero tile, top; Back on hero → screensaver starts;
hide an app from the grid → focus lands on a sensible tile, never "nowhere".

Done 2026-10-08. Two additions found on the way: Up from the grid's first row is intercepted
(`HomeFocusController.handleGridKey`) and sent to the nearest hero tile, because the hero is scrolled above the
app bar at that point and plain geometry picks the gear; and `RowByRowTraversalPolicy` no longer falls back to the
generic policy for left/right, so Right at the end of a short last row does nothing instead of jumping.

### Step 5: Home button resets focus

Files: `MainActivity.kt`, `lib/flauncher_channel.dart`, `lib/flauncher.dart` (state), `lib/widgets/app_card.dart`.

- Kotlin: keep a field `private var methodChannel: MethodChannel?` set in `configureFlutterEngine` (:49) and
  override:
  ```kotlin
  override fun onNewIntent(intent: Intent) {
      super.onNewIntent(intent)
      if (intent.action == ACTION_MAIN && intent.hasCategory(CATEGORY_HOME)) {
          methodChannel?.invokeMethod("homePressed", null)
      }
  }
  ```
  `launchMode="singleTask"` (AndroidManifest.xml:51) guarantees Home delivers `onNewIntent` to the existing
  activity both when the launcher is already in front and when returning from another app. A cold start goes
  through normal autofocus instead.
- Dart: `FLauncherChannel.setHomePressedHandler(VoidCallback)` using `_methodChannel.setMethodCallHandler`.
  The `FLauncher` state registers a handler that:
  1. `Navigator.of(context).popUntil((r) => r.isFirst)` (closes the long-press panel or settings),
  2. ends hero move mode (see below),
  3. `focusFirstHero()` with `jumpTo(0)` (no animation, the user may not even see the launcher yet).
- Move mode lives in `AppCard._moving` (app_card.dart:56). Make `AppCard` listen to its focus node and, on focus
  loss while `_moving`, call `onMoveEnd` and clear `_moving`. That covers Home, Back-reset and pointer hover,
  and keeps the persisted order consistent.

Device: scroll deep into the grid, launch an app, press Home → launcher shows first hero tile at the top. Press
Home while a long-press panel or the settings panel is open → panel closes, first hero tile focused. Return from an
app with Back → focus stays on the launched tile (D3).

Done 2026-10-08. The handler unfocuses first and focuses the first tile in the next frame, so a tile in move mode
ends its move on focus loss even when it is the first tile itself. Verified on device: Home from a running app
returns to the first hero tile.

### Step 6: long-press panel variants and hero editing

Files: `lib/widgets/application_info_panel.dart`, `lib/widgets/app_card.dart`, `lib/widgets/hero_row.dart`.

- Replace `Category? category` (:26) with `enum AppPanelContext { hero, grid, hidden }`.
  - grid: "Add to main apps", Hide, App info, Uninstall.
  - hero: "Remove from main apps", Move left/right, Hide, App info, Uninstall.
  - hidden (settings → hidden apps): Unhide, App info, Uninstall.
  Drop "Open" (:65-77; select already launches) and the `sort == manual` condition for Reorder (:78).
- "Move left/right" returns `ApplicationInfoPanelResult.reorderApp`; the hero card enters existing move mode with
  only ←/→ active (reuse `CategoryRow._onMove`, category_row.dart:118-138, moved into `HeroRow`), select or focus
  loss saves via `saveHeroOrder()`. ↑/↓ in move mode are swallowed (today they return `handled`, :248).
- First panel button gets `autofocus: true` so the panel is operable without hunting for focus.

Device: add a grid app to the hero → it appears at the hero's end, disappears from the grid, tiles shrink when
the hero exceeds four apps. Remove → it reappears alphabetically in the grid. Move left/right persists across a
launcher restart (`adb shell am force-stop dev.neugebauer.tvlauncher`, then Home). Hide a hero app → gone from both
areas; unhide in settings → back at its old hero position.

Done 2026-10-08 as part of step 3.

Fix 2026-10-08 (`fix/long-press-tiers`): a held select never reached the long-press code on the remote, because
the key down bubbled to Flutter's shortcut layer and activated the tile at once. `FocusKeyboardListener` now
consumes the key down and fires in tiers: release = launch, 0.5 s = move mode (hero) or panel (grid), 1.5 s =
panel. Tile wrappers are keyed per app so a reorder keeps the moving card's state and focus.

### Step 7: quick settings (gear)

Files: `MainActivity.kt`, `lib/flauncher_channel.dart`, `lib/providers/apps_service.dart` (or a new
`SystemSettingsService`), new `lib/widgets/settings/quick_settings_page.dart`, new
`lib/widgets/settings/launcher_settings_page.dart`, `lib/widgets/settings/settings_panel.dart`.

- Channel: `openSystemSettings(String screen)` with `screen ∈ {bluetooth, wifi, displaySound, all}`, returning
  `bool`. Keep the existing `openSettings` method name working as `all` or replace its single caller.
- Kotlin tries a list of intents in order, `startActivity` inside `try`, falling through on
  `ActivityNotFoundException`/`SecurityException`. Plain `startActivity` with implicit intents needs no
  `<queries>` entry and no permission. Do **not** use `resolveActivity` for the check: under targetSdk 33 package
  visibility it returns null unless the action is declared in `<queries>`.

  | Entry | Intent chain | Notes |
  |---|---|---|
  | Wi-Fi | `Settings.ACTION_WIFI_SETTINGS` → `ACTION_SETTINGS` | AOSP TvSettings 14 `NetworkActivity` declares `android.settings.WIFI_SETTINGS`. |
  | Display & Sound | `Settings.ACTION_SOUND_SETTINGS` → `ACTION_SETTINGS` | TvSettings `DisplaySoundActivity` declares `android.settings.SOUND_SETTINGS`. `ACTION_DISPLAY_SETTINGS` is **not** declared there, so don't use it. |
  | Bluetooth | `Settings.ACTION_BLUETOOTH_SETTINGS` → `Intent("android.settings.SLICE_SETTINGS").putExtra("slice_uri", "content://com.android.tv.settings.accessories.sliceprovider/general")` → `ACTION_SETTINGS` | AOSP TvSettings 14 has **no** activity for `BLUETOOTH_SETTINGS`; Google's TV settings build may add one. The slice route is TvSettings-internal (not a public API) and may show a verification prompt; it is a best-effort middle step. `AddAccessoryActivity` (`com.google.android.intent.action.CONNECT_INPUT`) requires `BLUETOOTH_CONNECT`, so it is off-limits. |
  | All settings | `Settings.ACTION_SETTINGS` | Existing behaviour (MainActivity.kt:162). |

  Verify on the device before writing the chains (one command per action):
  ```
  adb shell cmd package query-activities --brief -a android.settings.BLUETOOTH_SETTINGS
  adb shell cmd package query-activities --brief -a android.settings.WIFI_SETTINGS
  adb shell cmd package query-activities --brief -a android.settings.SOUND_SETTINGS
  adb shell am start -a android.settings.SLICE_SETTINGS \
    --es slice_uri content://com.android.tv.settings.accessories.sliceprovider/general
  ```
  If Google TV's settings package exposes an explicit "Remotes & accessories" activity that is exported without a
  permission, an explicit component can replace the slice step; record what was found in the code comment.
- UI: `SettingsPanel` initial route becomes `QuickSettingsPage` (Bluetooth, Wi-Fi, Display & Sound, All settings,
  divider, Launcher settings → pushes `LauncherSettingsPage`). First item autofocused.

Device: each entry opens the expected screen (or the settings root as fallback); Back from the system screen
returns to the home screen; the gear panel closed itself when the entry was chosen (D4).

Done 2026-10-08. Device check: `BLUETOOTH_SETTINGS` does not resolve, the accessories slice opens
"Fernbedienungen & Zubehör" with the paired speakers, `WIFI_SETTINGS` and `SOUND_SETTINGS` resolve.
Added on request: a second way into quick settings besides Up-from-hero. Tried and rejected: the Assistant
button (owned by the voice service, shows only the mic indicator) and the mute button (never reaches the
Chromecast at all, see below). Chosen: **long press on Back** (`MainActivity.dispatchKeyEvent` consumes Back,
opens quick settings on the first key repeat, replays a short press through `onBackPressed()` on release).
Verified on device 2026-10-08.

Mute finding: with the launcher in front, physical mute presses produce no key, audio, or HDMI event in the
system log, and an adb-injected `KEYCODE_VOLUME_MUTE` changes nothing either. The remote sends volume and mute
to the projector directly (infrared, "Set up remote buttons"), where mute is A/V mute and blanks the picture.
Not a launcher issue; fix is in Google TV's remote button setup.
Also: `FocusKeyboardListener` honours Android's `FLAG_LONG_PRESS`, so long press fires at system timing and
`adb shell input keyevent --longpress` works for testing.

### Step 8: launcher settings trim and dead code removal

Files: `lib/widgets/settings/*`, `lib/providers/*`, `lib/main.dart`, `lib/flauncher_app.dart`, `pubspec.yaml`,
`assets/`, `test/mocks.dart` (+ regenerate `mocks.mocks.dart` via `flutter pub run build_runner build
--delete-conflicting-outputs`).

`LauncherSettingsPage`: Wallpaper (→ existing `WallpaperPanelPage` with Gradient and Custom), Hidden apps
(the hidden tab of `ApplicationsPanelPage`, standalone), About. The 24-hour toggle is removed (D2); the clock is always 24-hour.

Delete (dead after steps 3-7):

- `lib/widgets/category_row.dart`, `lib/widgets/add_category_dialog.dart`, `lib/widgets/add_to_category_dialog.dart`,
  `lib/widgets/settings/categories_panel_page.dart`, `lib/widgets/settings/category_panel_page.dart`,
  `lib/widgets/settings/settings_panel_page.dart` (replaced by the two new pages).
- `ApplicationsPanelPage` TV and sideloaded tabs + "add to category" button (applications_panel_page.dart:76-98,
  :126-135).
- Unsplash: `lib/unsplash_service.dart`, `lib/widgets/settings/unsplash_panel_page.dart`, the `UnsplashService`
  wiring in `main.dart:38-48` and `flauncher_app.dart:40,60,70`, `WallpaperService` unsplash methods
  (wallpaper_service.dart:75-94) and its `setUnsplashAuthor` calls (:70, :101), `SettingsService.unsplashEnabled`,
  `unsplashAuthor`, `setUnsplashAuthor` (settings_service.dart:25, :36-41, :60-67), the author/WebView footer and the
  Unsplash button in `wallpaper_panel_page.dart:37-48, :88-110`, route in `settings_panel.dart:57-58`.
  Assets: `assets/unsplash.png`, `abstract`, `animal`, `architecture`, `colorful`, `landscape`, `minimal`, `plant`,
  `space`, `technology`, `texture` (keep `logo.png`). Dependencies: `unsplash_client`, `webview_flutter`.
- Highlight animation: `lib/widgets/color_helpers.dart`, `lib/providers/ticker_model.dart`,
  `SettingsService.appHighlightAnimationEnabled` + setter (:23, :32, :50-53), its toggle.
- Category management in `AppsService` (list in section 2) and the DB methods only they used:
  `deleteCategory`, `updateCategories` (database.dart:150-162). Keep `insertCategory`, `updateCategory`,
  `deleteAppCategory`, `insertAppsCategories`, `replaceAppsCategories`, `nextAppCategoryOrder`.
- `CategoryType`/`CategorySort` enums stay (the generated `database.drift.dart` references them through the
  columns).
- `EnsureVisible` stays (settings pages still use it).

After removing plugins, check the merged manifest: `build/app/intermediates/merged_manifests/release/AndroidManifest.xml`
must contain only `REQUEST_DELETE_PACKAGES` (plus whatever Flutter adds for debug builds only).

Device: settings show only the agreed entries; wallpaper/gradient/custom image still work; hidden apps list unhides.

---

Done 2026-10-08. `ApplicationsPanelPage` became `HiddenAppsPanelPage` (hidden apps only, one "unhide" button each).
`SettingsPanelPage` keeps its name and route and holds Wallpaper, Hidden apps, About. Merged release manifest
checked: only `REQUEST_DELETE_PACKAGES`. Removed `unsplash_client` and `webview_flutter`; `flutter pub get` done.

**Bluetooth deep link, found after step 7:** Google TV's settings slice activity refuses callers without
`WRITE_SECURE_SETTINGS` (`SecurityException: Permission Denial ... requires android.permission.WRITE_SECURE_SETTINGS`).
Decided 2026-10-08: the manifest declares it and it is granted once over adb
(`adb shell pm grant dev.neugebauer.tvlauncher android.permission.WRITE_SECURE_SETTINGS`, survives updates).
Verified on device: the Bluetooth entry opens "Fernbedienungen & Zubehör" directly.

## 4. Tests

Use 960×540 at DPR 1.0 in widget tests for the home screen (matches the device's logical size) and keep the
existing `textScaleFactor 0.8` workaround (flauncher_test.dart:43-48). With the cycling animation gone,
`pumpAndSettle` no longer needs `TickerModel(tester)` (flauncher_test.dart:739).

**Deleted**

- `test/widgets/settings/categories_panel_page_test.dart`, `category_panel_page_test.dart`,
  `unsplash_panel_page_test.dart`, `test/widgets/color_helpers_test.dart`.
- `apps_service_test.dart`: `addCategory`, `renameCategory`, `deleteCategory`, `moveCategory`, `setCategoryType`,
  `setCategorySort`, `setCategoryColumnsCount`, `setCategoryRowHeight` (:314-391, :419-479). `startAmbientMode` (:246) stays.
- `settings_service_test.dart`: unsplash tests (:47-83).
- `wallpaper_service_test.dart`: unsplash tests; `wallpaper_panel_page_test.dart`: "'Unsplash' navigates…" (:41).
- `database_test.dart`: `deleteCategory`, `updateCategories` (:95, :112).

**Rewritten**

- `flauncher_test.dart`: all tests built on `categoriesWithApps`, `CategoryRow`, `AppsGrid(category:)`,
  "AppCard moves in grid", "Moving down does not skip row", "Moving left or right stays on the same row"
  (:51-116, :230-555) → rewritten for hero + grid. "Tapping on app launches it" and "Hovering over app focuses it"
  (:649, :678) kept with the new fixtures. "Pressing select on app opens ApplicationInfoPanel" is misnamed (it is a
  long-press) and folds into the panel tests.
- `apps_service_test.dart` "with empty database" (:30-131) → asserts one manual hero category and no default
  memberships; add a case for an existing DB with two categories (lowest order wins) and for alphabetical → manual.
- `application_info_panel_test.dart`: "'Open'" (:41) deleted; "'Remove from…'" (:82) becomes
  "Remove from main apps"; add per-context visibility tests.
- `settings_panel_page_test.dart` → `quick_settings_page_test.dart` + `launcher_settings_page_test.dart`.
- `applications_panel_page_test.dart` → hidden apps only.
- Unchanged: `database_migration_test.dart` (schema untouched), `gradient_panel_page_test.dart`.

**New**

- AppsService: `gridApps` excludes hero and hidden apps, is alphabetical case-insensitively, updates on
  `PACKAGE_ADDED`; `addToHero`/`removeFromHero` move apps between the lists; hidden hero app returns to its slot
  on unhide.
- Hero layout: for n = 1, 4, 5, 10 all hero cards share one `dy`, have equal width ≤ `maxW`, total width ≤ `A`, and
  there is no horizontal `Scrollable` in the hero subtree.
- Peek: at 960×540 the first grid row's top is above the viewport bottom and its bottom below it; "Apps" heading
  is visible; hero is vertically centred in `heroZoneH` (±1 px).
- Focus/scroll: arrow down from hero → first grid row focused and `scroll.offset ≥ heroZoneH` (or at
  `maxScrollExtent`); arrow up → hero tile focused and offset 0; one-row grid still scrolls hero out (spacer).
- Back: `await tester.binding.handlePopRoute()` with grid focused → first hero tile focused, offset 0;
  with hero focused → focus unchanged, `startAmbientMode` called once on the mocked channel, no
  `SystemNavigator.pop` when default launcher.
- Home: deliver `homePressed` via
  `tester.binding.defaultBinaryMessenger.handlePlatformMessage('me.efesser.flauncher/method', codec.encodeMethodCall(MethodCall('homePressed')), null)`
  with a panel open and the grid scrolled → panel gone, first hero tile focused, offset 0; while in move mode →
  order saved, move mode ended.
- Long-press panel: grid tile shows exactly the four grid entries, hero tile the five hero entries.
- Empty hero: first grid tile autofocused; Back/Home focus first grid tile.
- Channel: `openSystemSettings` sends the screen argument; Kotlin fallback chain verified on device only.

---

## 5. Risks and open questions

**Risks found in the code**

1. **Back on home starts the screensaver** (flauncher_app.dart:114-119). Kept for the hero; step 4 must branch on
   grid focus *before* that call, otherwise Back in the grid starts the screensaver instead of returning to the hero.
2. **Multiple autofocus cards** (category_row.dart:65, apps_grid.dart:67): with two areas, the grid's index 0 would
   compete with the hero's. Only the first hero card may autofocus.
3. **Move mode survives focus loss** (app_card.dart:56, :260-264): Home/Back reset or a disappearing card would
   leave `_moving = true` and the in-memory order unsaved (`reorderApplication` mutates memory only,
   apps_service.dart:194-199). Fixed by ending move mode on focus loss (step 5).
4. **Focus lost when the focused tile disappears** (add/remove hero, hide, uninstall via `PACKAGE_REMOVED`,
   apps_service.dart:63-69). The dialog route returns focus to a disposed node. Needs the post-frame recovery in
   step 4.
5. **Null icon crash**: banner-less fallback does `widget.application.icon!` (app_card.dart:135) and the panel does
   `application.icon!` (application_info_panel.dart:41, applications_panel_page.dart:122), but Kotlin returns null
   for zero-size drawables (MainActivity.kt:211-213). Pre-existing; a sideloaded app with an adaptive/vector icon of
   intrinsic size ≤ 0 crashes the home screen. Add a placeholder icon when touching these lines.
6. **Hover scrolls the page**: hover requests focus (app_card.dart:260-264), and focus triggers scroll. Moving the
   mouse across the peek row will scroll the hero away. Acceptable but noticeable; alternative is skipping the
   focus-driven scroll when focus came from a pointer (track last input via `FocusManager.highlightMode`).
7. **Same-row detection uses rounded centre `dy`** (custom_traversal_policy.dart:127-129). Fine for equal-size hero
   tiles; it breaks if hero tiles ever get different heights (e.g. a cap that applies only to some). Keep them
   uniform.
8. **`set-home-activity` command in `CLAUDE.md` is wrong for the new id** (see step 1); also the stock Google TV
   home must stay disabled, as it ignores `set-home-activity`.
9. **Bluetooth deep link has no public action on AOSP TvSettings 14**; the fallback may land on the settings root.
   Verify with `query-activities` before relying on it.
10. **Wallpaper sizing uses physical pixels as logical size** (flauncher.dart:118-119, `window.physicalSize`): at
    DPR 2 the image is laid out 2× oversized and cropped by `BoxFit.cover` centred. Harmless, but worth replacing
    with `Positioned.fill` while editing the file.
11. **`versionCode`**: `pubspec.yaml` `version: 0.0.1` gives versionCode 1 for local builds; the CI workflow derives
    it from commit count. Mixing local and CI APKs on the device can produce `INSTALL_FAILED_VERSION_DOWNGRADE`.
    Pick one source (bump `version: x.y.z+N` in pubspec for local installs).
12. **Removing `webview_flutter`/`unsplash_client`** changes the plugin set; re-check the merged manifest (step 8).

**Decisions on questions the code raised**

- D1. Fresh install starts with an **empty hero**; focus starts in the grid. Show a non-focusable hint in the
  hero zone while it is empty ("Long-press an app → Add to main apps").
- D2. **Clock is always 24-hour.** Remove the toggle (settings_panel_page.dart:85-91) and the setting behind it.
- D3. Returning from an app with Back keeps focus on the launched tile. Only a HOME intent resets.
- D4. The gear panel **closes itself** after launching a system settings screen.
- D5. The launcher's own entry is **hidden from the grid**.
- D6. Display name and banner are deferred to v3.
- D7. **No hard cap** on hero size. From the sixth app on, "Add to main apps" shows a toast that tiles are now
  grid-sized. Tiles stay uniform (risk 7).
- D8. "Move left/right" reuses the existing move mode restricted to ←/→.
- D9. Hero row is **centred**.
