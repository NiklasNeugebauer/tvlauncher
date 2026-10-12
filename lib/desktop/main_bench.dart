import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:ui';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tvlauncher/database.dart';
import 'package:tvlauncher/desktop/fake_launcher_channel.dart';
import 'package:tvlauncher/desktop/fake_remote.dart';
import 'package:tvlauncher/launcher_app.dart';
import 'package:tvlauncher/desktop/main_desktop.dart';

/// Frame cost of the home screen on a desktop, with the fake apps and the TV's band config (`tool/bench/`): the D-pad
/// path the on-device benchmark used, an app launch and return, the quick settings panel, and idle. Run it with
/// `tool/bench/run.sh`. It runs on the normal binding, so frames are only drawn when the app asks for them; the
/// numbers compare builds on this machine, they are not the TV's frame times.
// For screenshots the clock is fixed, so the time in the corner is the same in every set. The binding is set up
// inside it, so the frame callbacks run in its zone too.
Future<void> main() =>
    Platform.environment["BENCH_SHOTS"] == null ? _main() : withClock(Clock.fixed(DateTime(2026, 1, 1, 12)), _main);

Future<void> _main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final data = Directory.systemTemp.createTempSync("tvlauncher-bench");
  final config = jsonDecode(File("tool/bench/band_config.json").readAsStringSync()) as Map<String, dynamic>;
  // Screenshots compare settled frames, so the shimmer, which never settles, is off for them.
  if (Platform.environment["BENCH_SHOTS"] != null) (config["tuning"] as Map<String, dynamic>)["ambientFps"] = 0;
  File("${data.path}/band_config.json").writeAsStringSync(jsonEncode(config));
  final channel = startDesktop(dataDir: data.path);
  final database = LauncherDatabase(connect());
  await seedHero(channel, database);

  FakeRemote.exclusive();
  final shots = Platform.environment["BENCH_SHOTS"];
  if (shots != null) {
    await _shots(channel, LauncherApp(ImagePicker(), channel, database), Directory(shots));
    exit(0);
  }

  final timings = <FrameTiming>[];
  SchedulerBinding.instance.addTimingsCallback(timings.addAll);
  runApp(LauncherApp(ImagePicker(), channel, database));
  await _wait(3000);

  final passes = int.tryParse(Platform.environment["BENCH_PASSES"] ?? "") ?? 3;
  // BENCH_PROFILE=phases: the framework's own timeline blocks (build, layout, paint, compositing, semantics), summed
  // by self time, cheap enough to keep the frame numbers. BENCH_PROFILE=widgets adds a block for every widget build,
  // layout and paint, which slows the UI thread down several times over, so only its ranking means anything.
  final profile = Platform.environment["BENCH_PROFILE"];
  if (profile != null) {
    final widgets = profile == "widgets";
    debugProfileBuildsEnabled = widgets;
    debugProfileLayoutsEnabled = widgets;
    debugProfilePaintsEnabled = widgets;
    FlutterTimeline.debugCollectionEnabled = true;
  }
  debugPrint("semantics enabled: ${SemanticsBinding.instance.semanticsEnabled}");
  final spans = <String, List<(int, int)>>{};
  Future<void> phase(String name, Future<void> Function() body) async {
    final start = Timeline.now;
    await body();
    (spans[name] ??= []).add((start, Timeline.now));
  }

  for (var pass = 0; pass <= passes; pass++) {
    if (profile != null && pass == 1) FlutterTimeline.debugReset();
    // Pass 0 warms up image decoding, shaders and the first layout of every row; it is not reported. Home first,
    // so every pass starts on the first hero app.
    channel.pressHome();
    await _wait(1500);
    await phase("walk", () async {
      for (final key in _walk) {
        await FakeRemote.press(key);
        await _wait(230);
      }
      await _wait(1500);
    });
    await phase("launch", () async {
      await FakeRemote.press(FakeRemote.select);
      await _wait(channel.returnAfter.inMilliseconds + 2500);
    });
    await phase("panel", () async {
      channel.pressQuickSettings();
      await _wait(1200);
      await FakeRemote.press(FakeRemote.down);
      await _wait(400);
      await FakeRemote.press(FakeRemote.down);
      await _wait(400);
      FakeRemote.back();
      await _wait(1200);
    });
    await phase("idle", () => _wait(4000));
  }
  await _wait(1500); // the engine reports timings in batches

  final report = <String, Object>{};
  spans.forEach((name, list) {
    report[name] = _median([
      for (final (start, end) in list.skip(1))
        _summarize(timings.where((t) => _inSpan(t, start, end)).toList(), (end - start) / 1000),
    ]);
  });
  report["total"] = _median([
    for (var i = 1; i <= passes; i++)
      _summarize(
        timings.where((t) => spans.values.any((list) => _inSpan(t, list[i].$1, list[i].$2))).toList(),
        spans.values.fold(0.0, (sum, list) => sum + (list[i].$2 - list[i].$1) / 1000),
      ),
  ]);
  if (profile != null) report["profile"] = _selfTimes(FlutterTimeline.debugCollect());
  final json = jsonEncode(report);
  stdout.writeln("BENCH $json");
  final out = Platform.environment["BENCH_OUT"];
  if (out != null) File(out).writeAsStringSync(const JsonEncoder.withIndent("  ").convert(report));
  data.deleteSync(recursive: true);
  exit(0);
}

/// `BENCH_SHOTS=dir`: PNGs of settled states instead of timings, to check that a change leaves the picture alone
/// (`tool/bench/diff.py`).
Future<void> _shots(FakeLauncherChannel channel, Widget app, Directory dir) async {
  dir.createSync(recursive: true);
  final key = GlobalKey();
  runApp(RepaintBoundary(key: key, child: app));
  Future<void> shot(String name) async {
    await _wait(2500);
    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(
      pixelRatio: WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio,
    );
    final png = await image.toByteData(format: ImageByteFormat.png);
    File("${dir.path}/$name.png").writeAsBytesSync(png!.buffer.asUint8List());
    image.dispose();
  }

  await _wait(1500);
  channel.pressHome();
  await shot("1-hero");
  for (final k in [FakeRemote.right, FakeRemote.right, FakeRemote.down, FakeRemote.right]) {
    await FakeRemote.press(k);
    await _wait(300);
  }
  await shot("2-grid");
  channel.pressQuickSettings();
  await shot("3-panel");
  FakeRemote.back();
  await _wait(1000);
  await FakeRemote.press(FakeRemote.select);
  await _wait(channel.returnAfter.inMilliseconds);
  await shot("4-returned");
}

/// Starts and ends on the first hero app: along the hero, down into the grid and along two rows, back up.
const _walk = [
  FakeRemote.right, FakeRemote.right, FakeRemote.right, FakeRemote.right, FakeRemote.right, FakeRemote.right, //
  FakeRemote.left, FakeRemote.left, FakeRemote.left, FakeRemote.left, FakeRemote.left, FakeRemote.left, //
  FakeRemote.down, FakeRemote.right, FakeRemote.right, FakeRemote.right, FakeRemote.right, FakeRemote.right, //
  FakeRemote.down, FakeRemote.left, FakeRemote.left, FakeRemote.left, FakeRemote.left, FakeRemote.left, //
  FakeRemote.up, FakeRemote.up, FakeRemote.right, FakeRemote.right, FakeRemote.right, FakeRemote.right, //
  FakeRemote.right, FakeRemote.right, FakeRemote.left, FakeRemote.left, FakeRemote.left, FakeRemote.left, //
  FakeRemote.left, FakeRemote.left,
];

Future<void> _wait(int ms) => Future.delayed(Duration(milliseconds: ms));

bool _inSpan(FrameTiming t, int start, int end) {
  final vsync = t.timestampInMicroseconds(FramePhase.vsyncStart);
  return vsync >= start && vsync < end;
}

const _budgetMs = 1000 / 60;

/// Per phase: how many frames, the UI thread's (build, layout, paint) and the raster thread's total and tail, and
/// frames over a 60 Hz budget on either thread. The `*_ms` totals are the compute the phase cost.
Map<String, num> _summarize(List<FrameTiming> frames, double phaseMs) {
  double ms(Duration d) => d.inMicroseconds / 1000;
  final build = frames.map((t) => ms(t.buildDuration)).toList()..sort();
  final raster = frames.map((t) => ms(t.rasterDuration)).toList()..sort();
  double pct(List<double> v, double p) => v.isEmpty ? 0 : v[((v.length - 1) * p).round()];
  double sum(List<double> v) => v.fold(0.0, (a, b) => a + b);
  return {
    "frames": frames.length,
    "fps": frames.length / phaseMs * 1000,
    "ui_ms": sum(build),
    "raster_ms": sum(raster),
    "ui_p90": pct(build, 0.9),
    "ui_max": pct(build, 1),
    "raster_p90": pct(raster, 0.9),
    "raster_max": pct(raster, 1),
    "over_budget": frames.where((t) => ms(t.buildDuration) > _budgetMs || ms(t.rasterDuration) > _budgetMs).length,
  };
}

Map<String, num> _median(List<Map<String, num>> passes) => {
  for (final key in passes.first.keys)
    key: (passes.map((p) => p[key]!.toDouble()).toList()..sort())[passes.length ~/ 2],
};

/// Milliseconds spent in each timeline block's own code, without the blocks nested in it, and how many blocks,
/// largest first.
Map<String, List<num>> _selfTimes(AggregatedTimings timings) {
  final blocks = timings.timedBlocks.toList()
    ..sort((a, b) => a.start != b.start ? a.start.compareTo(b.start) : b.end.compareTo(a.end));
  final self = <String, double>{};
  final count = <String, int>{};
  final stack = <TimedBlock>[];
  for (final block in blocks) {
    while (stack.isNotEmpty && stack.last.end <= block.start) {
      stack.removeLast();
    }
    if (stack.isNotEmpty) self[stack.last.name] = (self[stack.last.name] ?? 0) - block.duration;
    self[block.name] = (self[block.name] ?? 0) + block.duration;
    count[block.name] = (count[block.name] ?? 0) + 1;
    stack.add(block);
  }
  final sorted = self.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return {
    for (final e in sorted.take(60)) e.key: [(e.value / 10).round() / 100, count[e.key]!],
  };
}
