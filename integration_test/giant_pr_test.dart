import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pr_reader/main.dart';
import 'package:pr_reader/src/app/services.dart';
import 'package:pr_reader/src/app/settings.dart';
import 'package:pr_reader/src/github/pr_ref.dart';
import 'package:pr_reader/src/ui/diff/files_tab.dart';
import 'package:pr_reader/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opens a real 80k-line pull request in the real app and measures frame
/// times while scrolling and jumping through it. Run in profile mode:
///
///   flutter drive --profile -d macos --driver test_driver/integration_test.dart \
///     --target integration_test/giant_pr_test.dart
const _pr = String.fromEnvironment('PR', defaultValue: 'flutter/flutter#171703');

Map<String, num> _stats(List<double> ms) {
  if (ms.isEmpty) return {};
  final s = [...ms]..sort();
  double p(double q) => s[math.min(s.length - 1, (s.length * q).floor())];
  return {
    'frames': s.length,
    'p50_ms': double.parse(p(0.5).toStringAsFixed(2)),
    'p90_ms': double.parse(p(0.9).toStringAsFixed(2)),
    'p99_ms': double.parse(p(0.99).toStringAsFixed(2)),
    'max_ms': double.parse(s.last.toStringAsFixed(2)),
    'over_16ms': s.where((v) => v > 16.7).length,
  };
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('giant PR scrolls smoothly', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    final services = AppServices(settings: settings);
    final ref = PrRef.tryParse(_pr)!;
    final boundary = GlobalKey();

    final sw = Stopwatch()..start();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: AppScope(
          services: services,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            onGenerateRoute: generateRoute,
            initialRoute: '${ref.routePath}/files',
          ),
        ),
      ),
    );
    final session = services.session(ref);
    double? firstFilesMs;
    while (!session.filesDone && session.filesError == null && session.error == null) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      if (firstFilesMs == null && session.files.isNotEmpty) firstFilesMs = sw.elapsedMilliseconds.toDouble();
      if (sw.elapsed > const Duration(minutes: 2)) break;
    }
    final loadMs = sw.elapsedMilliseconds;
    expect(session.error ?? session.filesError, isNull);
    await tester.pump(const Duration(milliseconds: 500));

    final c = tester.widget<FilesTab>(find.byType(FilesTab)).controller;
    final builds = <double>[], rasters = <double>[];
    void onTimings(List<ui.FrameTiming> t) {
      for (final f in t) {
        builds.add(f.buildDuration.inMicroseconds / 1000);
        rasters.add(f.rasterDuration.inMicroseconds / 1000);
      }
    }

    SchedulerBinding.instance.addTimingsCallback(onTimings);
    final max = c.vertical.position.maxScrollExtent;
    // Continuous fast scrolling: 60k px in 6 s (10k px/s) a few times.
    for (final start in [0.0, max * 0.45, max * 0.9]) {
      c.vertical.jumpTo(start);
      await tester.pump();
      await c.vertical.animateTo(
        math.min(max, start + 60000),
        duration: const Duration(seconds: 6),
        curve: Curves.linear,
      );
    }
    // Scrubber-style jumps to random places.
    final rnd = math.Random(1);
    for (var i = 0; i < 40; i++) {
      c.vertical.jumpTo(rnd.nextDouble() * max);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    SchedulerBinding.instance.removeTimingsCallback(onTimings);

    c.jumpToFile(session.files.length ~/ 3);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await tester.pump();
    final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);

    binding.reportData = {
      'pr': _pr,
      'files': session.files.length,
      'lines': session.lineCount,
      'rows': c.layout!.length,
      'scroll_extent_px': c.layout!.totalExtent.round(),
      'first_files_visible_ms': firstFilesMs,
      'all_files_loaded_ms': loadMs,
      'window': '${render.size.width.round()}x${render.size.height.round()}',
      'build': _stats(builds),
      'raster': _stats(rasters),
      'screenshots': {'real_pr': base64Encode(png!.buffer.asUint8List())},
    };
  });
}
