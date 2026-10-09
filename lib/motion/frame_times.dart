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

import 'dart:ui';

import 'package:flauncher/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Build and raster times of the last frames the engine reported, as a small readout. The engine reports frames
/// in batches (about once a second in release); every report also goes to the log as `frame times ...`.
class FrameTimes extends StatefulWidget {
  const FrameTimes({super.key});

  @override
  State<FrameTimes> createState() => _FrameTimesState();
}

class _FrameTimesState extends State<FrameTimes> {
  // A frame that starts this long after the previous one's vsync means at least one missed vsync at 60 Hz.
  static const double _missedMs = 1000 / 60 * 1.5;
  String _text = "frame times: waiting for frames";

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  // Impeller's raster time includes waiting for a swapchain image, so it sits near one vsync even when nothing is
  // late; the gaps between frame starts during an animation are what show dropped frames.
  void _onTimings(List<FrameTiming> timings) {
    // A batch of one is most likely the frame this readout itself caused; skipping it keeps an idle screen idle.
    if (timings.length < 2 || !mounted) {
      return;
    }
    double ms(Duration d) => d.inMicroseconds / 1000;
    final build = timings.map((t) => ms(t.buildDuration)).toList()..sort();
    final raster = timings.map((t) => ms(t.rasterDuration)).toList()..sort();
    var missed = 0;
    for (var i = 1; i < timings.length; i++) {
      final gap =
          (timings[i].timestampInMicroseconds(FramePhase.vsyncStart) -
              timings[i - 1].timestampInMicroseconds(FramePhase.vsyncStart)) /
          1000;
      // Gaps longer than a few frames are pauses between animations, not drops.
      if (gap > _missedMs && gap < 100) {
        missed += (gap / (1000 / 60)).round() - 1;
      }
    }
    String stats(List<double> sorted) =>
        "p50 ${sorted[sorted.length ~/ 2].toStringAsFixed(1)} max ${sorted.last.toStringAsFixed(1)}";
    final span =
        (timings.last.timestampInMicroseconds(FramePhase.vsyncStart) -
            timings.first.timestampInMicroseconds(FramePhase.vsyncStart)) /
        1e6;
    final fps = span <= 0 ? 0 : (timings.length - 1) / span;
    // At rest the background's shimmer draws below 60 fps on purpose; its gaps count as missed vsyncs here.
    final text =
        "${timings.length} frames, ${fps.toStringAsFixed(0)} fps · build ${stats(build)} · raster ${stats(raster)} ms · "
        "missed vsyncs $missed";
    debugPrint("frame times $text");
    setState(() => _text = text);
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Padding(
      padding: EdgeInsets.all(8),
      child: Text(
        _text,
        style: TextStyle(
          color: Palette.creamDim,
          fontSize: 11,
          // Drawn outside any Material, where Text would get the debug underline.
          decoration: TextDecoration.none,
          fontFamily: fontFamily,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ),
  );
}
