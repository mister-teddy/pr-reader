// Multiple windows on macOS, using Flutter's experimental windowing API.
// It ships in the stable engine but the tool only enables it on the master
// channel, so the app turns it on itself before the binding starts (see
// enableWindowing). If a Flutter update breaks it, the "Separate windows"
// setting falls back to the single native window.
//
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show AppExitType;

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/src/foundation/_features.dart' as features;
import 'package:flutter/src/widgets/_window.dart';

import 'links.dart';

/// Must run before `WidgetsFlutterBinding.ensureInitialized`.
bool enableWindowing({required bool wanted}) {
  if (kIsWeb || !Platform.isMacOS || !wanted) return false;
  features.isWindowingEnabled = true;
  return true;
}

class _AppWindow {
  _AppWindow(this.controller, this.route, this.arguments);

  final RegularWindowController controller;
  final String route;
  final Object? arguments;
  final navigator = GlobalKey<NavigatorState>();
}

/// The open windows. Every window is equal: closing any of them leaves the
/// others open, and closing the last one quits the app.
class AppWindows extends ChangeNotifier {
  AppWindows({required this.buildApp});

  final Widget Function(String route, Object? arguments, GlobalKey<NavigatorState> navigator) buildApp;

  final List<_AppWindow> _windows = [];

  void open(String route, {Object? arguments, Size? size, String title = 'PR Reader'}) {
    late final _AppWindow window;
    final controller = RegularWindowController(
      preferredSize: size ?? _defaultSize(),
      preferredConstraints: const BoxConstraints(minWidth: 360, minHeight: 480),
      title: title,
      delegate: _Delegate(
        onCloseRequested: (c) {
          // Quitting instead of tearing down the last window keeps "the PR
          // that was open" for the next launch.
          if (_windows.length == 1) {
            unawaited(ServicesBinding.instance.exitApplication(AppExitType.required));
          } else {
            c.destroy();
          }
        },
        onDestroyed: () {
          _windows.remove(window);
          notifyListeners();
        },
      ),
    );
    window = _AppWindow(controller, route, arguments);
    _windows.add(window);
    notifyListeners();
  }

  /// Shows [route] in the frontmost window, or a new one if none is open.
  void show(String route) {
    final target = _windows.where((w) => w.controller.isActivated).firstOrNull ?? _windows.lastOrNull;
    if (target == null) return open(route);
    target.navigator.currentState?.pushNamed(route);
    target.controller.activate();
  }

  static Size _defaultSize() {
    final display = WidgetsBinding.instance.platformDispatcher.displays.firstOrNull;
    final screen = display == null ? const Size(1440, 900) : display.size / display.devicePixelRatio;
    return Size(math.min(1440, screen.width * 0.9), math.min(920, screen.height * 0.9));
  }

  static AppWindows? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AppWindowsScope>()?.windows;
}

class _Delegate with RegularWindowControllerDelegate {
  _Delegate({required this.onCloseRequested, required this.onDestroyed});

  final void Function(RegularWindowController) onCloseRequested;
  final VoidCallback onDestroyed;

  @override
  void onWindowCloseRequested(RegularWindowController controller) => onCloseRequested(controller);

  @override
  void onWindowDestroyed() {
    onDestroyed();
    super.onWindowDestroyed();
  }
}

class _AppWindowsScope extends InheritedWidget {
  const _AppWindowsScope({required this.windows, required super.child});

  final AppWindows windows;

  @override
  bool updateShouldNotify(_AppWindowsScope oldWidget) => windows != oldWidget.windows;
}

/// Renders every open window and opens the first one on [initialRoute].
/// Links from the OS open in the frontmost window, or in a new one when they
/// carry `window=new`.
class WindowsRoot extends StatefulWidget {
  const WindowsRoot({super.key, required this.windows, required this.initialRoute});

  final AppWindows windows;
  final String initialRoute;

  @override
  State<WindowsRoot> createState() => _WindowsRootState();
}

class _WindowsRootState extends State<WindowsRoot> {
  StreamSubscription<Uri>? _links;
  String? _lastLink;
  DateTime _lastLinkAt = DateTime(0);

  @override
  void initState() {
    super.initState();
    widget.windows.open(widget.initialRoute);
    _links = AppLinks().uriLinkStream.listen(_openLink, onError: (_) {});
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  void _openLink(Uri uri) {
    final route = routeForLink(uri);
    if (route == null) return;
    // The OS can deliver the same link twice in quick succession.
    final now = DateTime.now();
    if (route == _lastLink && now.difference(_lastLinkAt) < const Duration(seconds: 2)) return;
    _lastLink = route;
    _lastLinkAt = now;
    if (uri.queryParameters['window'] == 'new') {
      widget.windows.open(route);
    } else {
      widget.windows.show(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AppWindowsScope(
      windows: widget.windows,
      child: ListenableBuilder(
        listenable: widget.windows,
        builder: (context, _) => ViewCollection(
          views: [
            for (final w in widget.windows._windows)
              RegularWindow(
                key: ObjectKey(w),
                controller: w.controller,
                child: widget.windows.buildApp(w.route, w.arguments, w.navigator),
              ),
          ],
        ),
      ),
    );
  }
}

void setWindowTitle(BuildContext context, String title) => windowTitleSetter(context)?.call(title);

/// A function that sets the title of the window [context] is in, usable
/// after [context] is gone (e.g. in `dispose`). Null without windowing.
void Function(String title)? windowTitleSetter(BuildContext context) {
  if (!features.isWindowingEnabled) return null;
  final controller = WindowScope.maybeOf(context);
  return controller is RegularWindowController ? controller.setTitle : null;
}
