/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

import 'package:flauncher/actions.dart';
import 'package:flauncher/theme.dart';
import 'package:flutter/material.dart';

/// Opens [builder]'s panel over the home screen behind the panel scrim, sliding in from the right edge.
Future<T?> showPanel<T>(BuildContext context, WidgetBuilder builder) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: Palette.scrim,
  transitionDuration: Motion.layout,
  pageBuilder: (context, _, _) => builder(context),
  transitionBuilder: (context, animation, _, child) {
    final curved = CurvedAnimation(parent: animation, curve: Motion.curve);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: Offset(0.08, 0), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  },
);

/// A panel docked to the right edge, on the surface colour with a hairline toward the home screen.
class RightPanelDialog extends StatelessWidget {
  static const double defaultWidth = 380;
  static const double padding = 24;

  final Widget child;
  final double width;

  const RightPanelDialog({super.key, required this.child, this.width = defaultWidth});

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: EdgeInsets.zero,
    child: Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: Palette.surface,
          border: Border(left: BorderSide(color: Palette.line)),
        ),
        width: width,
        child: Actions(actions: {BackIntent: BackAction(context)}, child: child),
      ),
    ),
  );
}
