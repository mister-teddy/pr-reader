import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/app/links.dart';
import 'src/app/services.dart';
import 'src/app/settings.dart';
import 'src/github/pr_ref.dart';
import 'src/ui/home/home_screen.dart';
import 'src/ui/home/repo_pulls_screen.dart';
import 'src/ui/pr/pr_screen.dart';
import 'src/ui/settings/settings_screen.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsController.load();
  final services = AppServices(settings: settings)..refreshViewer();
  runApp(AppScope(services: services, child: const PrReaderApp()));
  // After the first frame: on macOS the native side registers the widget
  // channel only once the window exists.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(services.widgets.prune([for (final r in settings.recents) r.ref]));
    unawaited(services.widgets.setRecents(settings.recents).then((_) => services.backfillWidgets()));
    // Keep the widget's PR picker in step when recents are removed or cleared.
    var recents = settings.recents;
    settings.addListener(() {
      if (identical(settings.recents, recents)) return;
      recents = settings.recents;
      unawaited(services.widgets.setRecents(recents));
    });
  });
}

class PrReaderApp extends StatefulWidget {
  const PrReaderApp({super.key});

  @override
  State<PrReaderApp> createState() => _PrReaderAppState();
}

class _PrReaderAppState extends State<PrReaderApp> {
  final _navigator = GlobalKey<NavigatorState>();
  StreamSubscription<Uri>? _links;
  String? _lastLink;
  DateTime _lastLinkAt = DateTime(0);

  @override
  void initState() {
    super.initState();
    // On the web the browser URL already drives the initial route.
    if (!kIsWeb) _links = AppLinks().uriLinkStream.listen(_openLink, onError: (_) {});
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  /// Opens a `pr://` or GitHub link handed to the app by the OS, both
  /// on launch and while running.
  void _openLink(Uri uri) {
    final route = routeForLink(uri);
    if (route == null) return;
    // Some platforms deliver the same link twice in quick succession.
    final now = DateTime.now();
    if (route == _lastLink && now.difference(_lastLinkAt) < const Duration(seconds: 2)) return;
    _lastLink = route;
    _lastLinkAt = now;
    void push() => _navigator.currentState?.pushNamed(route);
    if (_navigator.currentState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => push());
    } else {
      push();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        navigatorKey: _navigator,
        title: 'PR Reader',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: settings.themeMode,
        onGenerateRoute: generateRoute,
        onGenerateInitialRoutes: (name) => initialRoutes(name, settings),
      ),
    );
  }
}

/// Home, with the PR on top when launched from a deep link (e.g. on the web)
/// or when a PR was open as the app closed, so reading picks up where it
/// left off.
List<Route<void>> initialRoutes(String name, SettingsController settings) {
  final resume = name == '/' || name.isEmpty ? settings.lastPr?.routePath : name;
  return [
    generateRoute(const RouteSettings(name: '/')),
    if (resume != null) generateRoute(RouteSettings(name: resume)),
  ];
}

Route<void> generateRoute(RouteSettings s) {
  final uri = Uri.tryParse(s.name ?? '/') ?? Uri();
  final seg = uri.pathSegments.where((e) => e.isNotEmpty).toList();
  Widget page = const HomeScreen();
  if (seg.length == 1 && seg[0] == 'settings') {
    page = const SettingsScreen();
  } else if (seg.length >= 4 && (seg[2] == 'pull' || seg[2] == 'pulls')) {
    final n = int.tryParse(seg[3]);
    if (n != null) {
      final tab = switch (seg.length > 4 ? seg[4] : '') {
        'files' || 'changes' => PrTab.files,
        'commits' => PrTab.commits,
        'conversation' => PrTab.conversation,
        // No tab in the link: resume the one the reader was last on.
        _ => null,
      };
      page = PrScreen(
        key: ValueKey('${seg[0]}/${seg[1]}#$n'),
        prRef: PrRef(seg[0], seg[1], n),
        initialTab: tab,
      );
    }
  } else if (seg.length == 2) {
    page = RepoPullsScreen(repo: RepoRef(seg[0], seg[1]));
  }
  return MaterialPageRoute(settings: s, builder: (_) => page);
}
