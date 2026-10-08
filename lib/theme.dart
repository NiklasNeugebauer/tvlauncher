/*
 * FLauncher
 * Copyright (C) 2026  Niklas Neugebauer
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:math';

import 'package:flutter/material.dart';

/// The one fixed theme: dark, warm and low in luminance for a projector on an olive wall, where every bright pixel
/// lights the room. Only tiles, text and the focus ring carry light.
abstract final class Palette {
  static const Color bgTop = Color(0xFF1C2419);
  static const Color bgBottom = Color(0xFF0F140E);
  static const Color glow = Color(0xFF5A4A2A);
  static const double glowOpacity = 0.18;
  static const Color surface = Color(0xFF1A2118);
  static const Color surfaceRaised = Color(0xFF242D21);
  static const Color cream = Color(0xFFEDE6D6);
  static const Color creamDim = Color(0x99EDE6D6);
  static const Color line = Color(0x14EDE6D6);
  static const Color brass = Color(0xFFC9A45C);
  static const Color danger = Color(0xFFB5563F);
  static const Color scrim = Color(0x8C0F140E);
  static const Color shadow = Color(0x66000000);
}

/// Shapes shared by tiles and panels.
abstract final class Shapes {
  static const double tileRadius = 12;
  static const double rowRadius = 8;
  static const double dialogRadius = 12;
  static const double focusRing = 3;
}

/// Bundled under fonts/ (SIL Open Font License): the APK has no network, so a Google font must ship with it.
const String fontFamily = 'SourceSans3';

ThemeData buildTheme() {
  final textTheme = Typography.material2018().white.apply(
    bodyColor: Palette.cream,
    displayColor: Palette.cream,
    fontFamily: fontFamily,
  );
  return ThemeData(
    // Material 2: the launcher's look was designed for it and Material 3 restyles every widget.
    useMaterial3: false,
    brightness: Brightness.dark,
    primaryColor: Palette.brass,
    colorScheme: ColorScheme.dark(
      primary: Palette.brass,
      onPrimary: Palette.bgBottom,
      secondary: Palette.brass,
      onSecondary: Palette.bgBottom,
      surface: Palette.surface,
      onSurface: Palette.cream,
      error: Palette.danger,
      onError: Palette.cream,
    ),
    scaffoldBackgroundColor: Palette.surface,
    canvasColor: Palette.surface,
    cardColor: Palette.surfaceRaised,
    dividerColor: Palette.line,
    shadowColor: Palette.shadow,
    focusColor: Palette.brass.withValues(alpha: 0.25),
    hoverColor: Palette.cream.withValues(alpha: 0.05),
    highlightColor: Palette.cream.withValues(alpha: 0.08),
    splashColor: Palette.cream.withValues(alpha: 0.08),
    textTheme: textTheme,
    iconTheme: IconThemeData(color: Palette.cream),
    typography: Typography.material2018(),
    dividerTheme: DividerThemeData(color: Palette.line, thickness: 1, space: 17),
    dialogTheme: DialogThemeData(
      backgroundColor: Palette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Shapes.dialogRadius)),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: Palette.brass)),
    appBarTheme: AppBarTheme(elevation: 0, backgroundColor: Colors.transparent, foregroundColor: Palette.cream),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Palette.surfaceRaised,
      contentTextStyle: textTheme.bodyMedium,
      actionTextColor: Palette.brass,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: Palette.brass),
    inputDecorationTheme: InputDecorationTheme(
      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Palette.brass)),
      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Palette.line)),
      labelStyle: textTheme.bodyMedium!.copyWith(color: Palette.creamDim),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Palette.brass,
      selectionColor: Palette.brass.withValues(alpha: 0.4),
      selectionHandleColor: Palette.brass,
    ),
  );
}

/// The home screen background: a vertical fade over which a warm radial glow rises from below, like lamp light
/// on the wall. Drawn in code so it is crisp at any resolution.
class ThemedBackground extends StatelessWidget {
  /// Glow centre as a fraction of the screen, and its radius as a fraction of the screen width.
  static const Alignment glowCenter = Alignment(0, 0.7);
  static const double glowRadiusFraction = 0.9;

  const ThemedBackground({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // RadialGradient measures its radius against the shorter side.
      final shortSide = min(constraints.maxWidth, constraints.maxHeight);
      final radius = shortSide == 0 ? 1.0 : glowRadiusFraction * constraints.maxWidth / shortSide;
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Palette.bgTop, Palette.bgBottom],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: glowCenter,
              radius: radius,
              colors: [Palette.glow.withValues(alpha: Palette.glowOpacity), Palette.glow.withValues(alpha: 0)],
            ),
          ),
        ),
      );
    },
  );
}
