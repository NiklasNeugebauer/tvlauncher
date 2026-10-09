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

import 'package:flauncher/motion/edge_nudge.dart';
import 'package:flauncher/widgets/focus_glide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("the ring settles on the focused tile, travels between tiles and fades when focus leaves", (
    tester,
  ) async {
    final first = FocusNode();
    final second = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: FocusGlide(
          enabled: true,
          child: Align(
            alignment: Alignment.topLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Tile(key: Key("first"), focusNode: first),
                SizedBox(width: 100),
                _Tile(key: Key("second"), focusNode: second),
              ],
            ),
          ),
        ),
      ),
    );

    first.requestFocus();
    await tester.pumpAndSettle();
    expect(_ring(tester), tester.getRect(find.byKey(Key("first"))));

    second.requestFocus();
    await tester.pump();
    await tester.pump(Duration(milliseconds: 40));
    final midway = _ring(tester);
    expect(midway.left, greaterThan(tester.getRect(find.byKey(Key("first"))).left));
    expect(midway.left, lessThan(tester.getRect(find.byKey(Key("second"))).left));

    // pumpAndSettle only returns once no frames are scheduled, so the ticker has stopped.
    await tester.pumpAndSettle();
    expect(_ring(tester), tester.getRect(find.byKey(Key("second"))));

    second.unfocus();
    await tester.pumpAndSettle();
    final opacity = tester.widget<AnimatedOpacity>(find.byKey(Key("focus-glide")));
    expect(opacity.opacity, 0);
    first.dispose();
    second.dispose();
  });

  testWidgets("after the ring has settled, a nudge still moves it with the tile", (tester) async {
    final node = FocusNode();
    final nudgeKey = GlobalKey<EdgeNudgeState>();
    await tester.pumpWidget(
      MaterialApp(
        home: FocusGlide(
          enabled: true,
          child: Align(
            alignment: Alignment.topLeft,
            child: Builder(
              builder: (context) => EdgeNudge(
                key: nudgeKey,
                distance: 10,
                duration: Duration(milliseconds: 280),
                onNudge: () => FocusGlideScope.maybeOf(context)?.kick(),
                child: _Tile(key: Key("tile"), focusNode: node),
              ),
            ),
          ),
        ),
      ),
    );
    node.requestFocus();
    await tester.pumpAndSettle();
    final rest = _ring(tester);

    nudgeKey.currentState!.nudge(AxisDirection.right);
    await tester.pump();
    await tester.pump(Duration(milliseconds: 60));

    expect(_ring(tester), tester.getRect(find.byKey(Key("tile"))));
    expect(_ring(tester).left, greaterThan(rest.left + 4));
    await tester.pumpAndSettle();
    node.dispose();
  });

  testWidgets("disabled, it draws nothing and tiles find no glide", (tester) async {
    FocusGlideState? found;
    await tester.pumpWidget(
      MaterialApp(
        home: FocusGlide(
          enabled: false,
          child: Builder(
            builder: (context) {
              found = FocusGlideScope.maybeOf(context);
              return SizedBox();
            },
          ),
        ),
      ),
    );

    expect(found, isNull);
    expect(find.byKey(Key("focus-glide")), findsNothing);
  });
}

Rect _ring(WidgetTester tester) => tester.state<FocusGlideState>(find.byType(FocusGlide)).ringRect!;

class _Tile extends StatelessWidget {
  final FocusNode focusNode;

  const _Tile({super.key, required this.focusNode});

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focusNode,
    onFocusChange: (focused) {
      final glide = FocusGlideScope.maybeOf(context);
      focused ? glide?.track(context) : glide?.release(context);
    },
    child: SizedBox(width: 160, height: 90),
  );
}
