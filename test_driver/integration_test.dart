import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Writes the screenshot and frame stats reported by the on-device test.
Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) return;
    final dir = Directory('build/integration')..createSync(recursive: true);
    final shots = (data.remove('screenshots') as Map?) ?? {};
    for (final e in shots.entries) {
      File('${dir.path}/${e.key}.png').writeAsBytesSync(base64Decode(e.value as String));
    }
    File('${dir.path}/report.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  },
);
