import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pr_reader/main.dart';
import 'package:pr_reader/src/app/services.dart';
import 'package:pr_reader/src/app/settings.dart';
import 'package:pr_reader/src/github/github_client.dart';
import 'package:pr_reader/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_github.dart';

final _boundary = GlobalKey();
bool _fontsLoaded = false;

/// Loads real fonts so screenshots are readable (tests default to Ahem boxes).
Future<void> loadFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  final sdk = Platform.environment['FLUTTER_ROOT'] ?? '/opt/homebrew/share/flutter';
  final material = '$sdk/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      final file = File(p);
      if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();
  }

  await load('Roboto', [
    '$material/Roboto-Regular.ttf',
    '$material/Roboto-Medium.ttf',
    '$material/Roboto-Bold.ttf',
    '$material/Roboto-Italic.ttf',
  ]);
  await load('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  await load('JetBrainsMono', [
    'assets/fonts/JetBrainsMono-Regular.ttf',
    'assets/fonts/JetBrainsMono-Bold.ttf',
  ]);
}

class TestApp {
  TestApp(this.services, this.fake);

  final AppServices services;
  final FakeGitHub fake;
}

Future<TestApp> pumpApp(
  WidgetTester tester, {
  required Size size,
  String route = '/',
  double dpr = 2,
  bool token = false,
  ThemeMode theme = ThemeMode.light,
  List<ui.DisplayFeature> displayFeatures = const [],
  EdgeInsets padding = EdgeInsets.zero,
  FakeGitHub? fake,
  Map<String, Object> prefs = const {},
}) async {
  await loadFonts();
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  tester.view.displayFeatures = displayFeatures;
  tester.view.padding = FakeViewPadding(
    left: padding.left * dpr,
    top: padding.top * dpr,
    right: padding.right * dpr,
    bottom: padding.bottom * dpr,
  );
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'theme': theme.name,
    'github_token_insecure': ?(token ? 'ghp_test' : null),
    ...prefs,
  });
  final gh = fake ?? FakeGitHub();
  final settings = (await tester.runAsync(SettingsController.load))!;
  final services = AppServices(
    settings: settings,
    client: GitHubClient(httpClient: gh.client, token: settings.token),
  );
  if (token) await tester.runAsync(services.refreshViewer);

  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      // A fresh subtree per call, so each pumpApp starts a new app.
      child: AppScope(
        key: UniqueKey(),
        services: services,
        child: Builder(
          builder: (context) => ListenableBuilder(
            listenable: settings,
            builder: (context, _) => MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: _withFonts(Brightness.light),
              darkTheme: _withFonts(Brightness.dark),
              themeMode: settings.themeMode,
              onGenerateRoute: generateRoute,
              onGenerateInitialRoutes: (name) => [
                generateRoute(const RouteSettings(name: '/')),
                if (name != '/') generateRoute(RouteSettings(name: name)),
              ],
              initialRoute: route,
            ),
          ),
        ),
      ),
    ),
  );
  return TestApp(services, gh);
}

ThemeData _withFonts(Brightness b) {
  final t = buildTheme(b);
  return t.copyWith(textTheme: t.textTheme.apply(fontFamily: 'Roboto'));
}

/// Pumps frames, letting real async work (isolates) run, until [done].
Future<void> settle(WidgetTester tester, bool Function() done, {int maxRounds = 200}) async {
  for (var i = 0; i < maxRounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 16));
    if (done()) break;
  }
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

/// Saves a PNG of the current frame to `build/screenshots/<name>.png`.
Future<void> capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio.clamp(1, 2));
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/screenshots')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
