import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('pr_reader/fonts');

/// Installed monospaced font families, on macOS; empty elsewhere.
Future<List<String>> monospaceFamilies() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return const [];
  try {
    final list = await _channel.invokeListMethod<String>('monospaceFamilies');
    return [...?list]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  } on MissingPluginException {
    return const [];
  } on PlatformException {
    return const [];
  }
}
