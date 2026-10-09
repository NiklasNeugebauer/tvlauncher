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

import 'package:flauncher/band/band_controller.dart';
import 'package:flauncher/motion/spring.dart';
import 'package:flauncher/motion/tuning.dart';
import 'package:flauncher/theme.dart';
import 'package:flutter/material.dart';

/// Hands the rows and headers that mount together (a panel or page opening) their order, so they rise in one after
/// another, and remembers per page which row had focus last when [rememberFocus] is set.
class PanelStagger extends StatefulWidget {
  final Duration stagger;
  final Duration rise;
  final bool rememberFocus;
  final Widget child;

  const PanelStagger({
    super.key,
    required this.stagger,
    required this.rise,
    this.rememberFocus = false,
    required this.child,
  });

  static PanelStaggerState? maybeOf(BuildContext context) => context.findAncestorStateOfType<PanelStaggerState>();

  @override
  State<PanelStagger> createState() => PanelStaggerState();
}

class PanelStaggerState extends State<PanelStagger> {
  // Last focused row per page, for the whole session; a panel opens on it again.
  static final Map<String, int> _lastFocused = {};

  int _count = 0;
  bool _resetScheduled = false;

  Duration get stagger => widget.stagger;

  Duration get rise => widget.rise;

  /// The next position among the widgets mounting in this frame.
  int next() {
    if (!_resetScheduled) {
      _resetScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _count = 0;
        _resetScheduled = false;
      });
    }
    return _count++;
  }

  int? lastFocused(String page) => widget.rememberFocus ? _lastFocused[page] : null;

  void focused(String page, int index) {
    if (widget.rememberFocus) {
      _lastFocused[page] = index;
    }
  }

  @visibleForTesting
  static void forgetFocus() => _lastFocused.clear();

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Rises 10 px and fades in after [index] stagger steps, once, when it first mounts inside a [PanelStagger].
class _Rise extends StatefulWidget {
  static const double distance = 10;

  final int? index;
  final Widget child;

  const _Rise({required this.index, required this.child});

  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _progress;

  @override
  void initState() {
    super.initState();
    final stagger = PanelStagger.maybeOf(context);
    final index = widget.index;
    if (stagger == null || index == null || stagger.rise == Duration.zero) {
      return;
    }
    final delay = stagger.stagger * index;
    final total = delay + stagger.rise;
    final controller = AnimationController(vsync: this, duration: total);
    _controller = controller;
    _progress = CurvedAnimation(
      parent: controller,
      curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: Motion.sheenCurve),
    );
    controller.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    if (progress == null) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) => Opacity(
        opacity: progress.value.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, _Rise.distance * (1 - progress.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

/// One action in a side panel: a leading icon (or any small widget) and a label. Focus raises the row, draws a
/// brass bar at its leading edge and turns the icon brass, on the same spring as the tiles; a pointer hovering over
/// it focuses it like a D-pad would.
class PanelRow extends StatefulWidget {
  static const double height = 48;
  static const double iconSize = 20;
  static const double gap = 12;
  static const double barWidth = 3;

  final IconData? icon;
  final Widget? leading;
  final IconData? trailingIcon;
  final String label;
  final VoidCallback onPressed;
  final bool autofocus;
  final bool destructive;

  const PanelRow({
    super.key,
    this.icon,
    this.leading,
    this.trailingIcon,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
    this.destructive = false,
  });

  @override
  State<PanelRow> createState() => _PanelRowState();
}

class _PanelRowState extends State<PanelRow> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;
  int? _index;
  String? _page;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    _index = PanelStagger.maybeOf(context)?.next();
  }

  // Back on the page it was used last, the row used last takes focus again (after the first row's autofocus).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_page != null) {
      return;
    }
    _page = ModalRoute.of(context)?.settings.name ?? "";
    final stagger = PanelStagger.maybeOf(context);
    if (_index != null && stagger?.lastFocused(_page!) == _index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _focused = _focusNode.hasFocus);
    final index = _index;
    if (_focused && index != null) {
      PanelStagger.maybeOf(context)?.focused(_page ?? "", index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final band = BandScope.maybeOf(context);
    final tuning = band?.tuning ?? Tuning.defaults;
    final foreground = widget.destructive ? Palette.danger : Palette.cream;
    final iconColor = _focused && !widget.destructive ? Palette.brass : foreground;
    return _Rise(
      index: _index,
      child: SizedBox(
        height: PanelRow.height,
        child: SpringBuilder(
          value: _focused ? 1 : 0,
          spec: _focused ? (band?.focusSpring ?? tuning.focusSpring) : tuning.focusOutSpring,
          builder: (context, lit, child) {
            // Snapped at the ends, where the spring settles within its tolerance.
            final amount = lit > 0.999 ? 1.0 : (lit < 0.001 ? 0.0 : lit);
            return Material(
              color: Color.lerp(Colors.transparent, Palette.surfaceRaised, amount),
              borderRadius: BorderRadius.circular(Shapes.rowRadius),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  child!,
                  if (amount > 0 && !widget.destructive)
                    Positioned(
                      left: 0,
                      top: PanelRow.height * (1 - lit.clamp(0.0, 1.2) * 0.6) / 2,
                      bottom: PanelRow.height * (1 - lit.clamp(0.0, 1.2) * 0.6) / 2,
                      width: PanelRow.barWidth,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          key: Key("row-bar"),
                          decoration: BoxDecoration(
                            color: Palette.brass,
                            borderRadius: BorderRadius.horizontal(right: Radius.circular(PanelRow.barWidth)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
          child: InkWell(
            autofocus: widget.autofocus,
            focusNode: _focusNode,
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            splashFactory: NoSplash.splashFactory,
            onTap: widget.onPressed,
            onHover: (hovering) {
              if (hovering && !_focusNode.hasFocus) {
                _focusNode.requestFocus();
              }
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: PanelRow.gap),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 24,
                    child: Center(
                      child: widget.leading ?? Icon(widget.icon, size: PanelRow.iconSize, color: iconColor),
                    ),
                  ),
                  SizedBox(width: PanelRow.gap),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: foreground),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.trailingIcon != null) ...[
                    SizedBox(width: PanelRow.gap),
                    Icon(widget.trailingIcon, size: PanelRow.iconSize, color: iconColor),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Panel title in the same place on every page; it rises in with the rows.
class PanelHeader extends StatefulWidget {
  final String title;

  const PanelHeader(this.title, {super.key});

  @override
  State<PanelHeader> createState() => _PanelHeaderState();
}

class _PanelHeaderState extends State<PanelHeader> {
  int? _index;

  @override
  void initState() {
    super.initState();
    _index = PanelStagger.maybeOf(context)?.next();
  }

  @override
  Widget build(BuildContext context) => _Rise(
    index: _index,
    child: Padding(
      padding: EdgeInsets.only(left: PanelRow.gap, bottom: 4),
      child: Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
    ),
  );
}
