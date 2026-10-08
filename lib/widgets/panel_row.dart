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

import 'package:flauncher/theme.dart';
import 'package:flutter/material.dart';

/// One action in a side panel: a leading icon (or any small widget) and a label. Focus raises the row and turns
/// the icon brass; a pointer hovering over it focuses it like a D-pad would.
class PanelRow extends StatefulWidget {
  static const double height = 48;
  static const double iconSize = 20;
  static const double gap = 12;

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

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() => setState(() => _focused = _focusNode.hasFocus);

  @override
  Widget build(BuildContext context) {
    final foreground = widget.destructive ? Palette.danger : Palette.cream;
    final iconColor = _focused && !widget.destructive ? Palette.brass : foreground;
    return SizedBox(
      height: PanelRow.height,
      child: Material(
        color: _focused ? Palette.surfaceRaised : Colors.transparent,
        borderRadius: BorderRadius.circular(Shapes.rowRadius),
        clipBehavior: Clip.antiAlias,
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
    );
  }
}

/// Panel title in the same place on every page.
class PanelHeader extends StatelessWidget {
  final String title;

  const PanelHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: PanelRow.gap, bottom: 4),
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );
}
