/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

import 'dart:async';

import 'package:tvlauncher/theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TimeWidget extends StatefulWidget {
  /// The idle picture frame shows the time on its own, much larger than in the band's corner.
  final bool large;

  const TimeWidget({super.key, this.large = false});

  @override
  State<TimeWidget> createState() => _TimeWidgetState();
}

class _TimeWidgetState extends State<TimeWidget> {
  late DateTime _now;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(Duration(seconds: 1), (_) => _refreshTime());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    DateFormat.Hm().format(_now),
    style: (widget.large ? Theme.of(context).textTheme.displaySmall! : Theme.of(context).textTheme.titleLarge!)
        .copyWith(
          color: Palette.cream,
          shadows: [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 8)],
        ),
  );

  void _refreshTime() {
    setState(() {
      _now = DateTime.now();
    });
  }
}
