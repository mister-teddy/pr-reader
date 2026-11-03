import AppKit
import FlutterMacOS

/// Lists the installed monospaced font families for the code font picker.
/// See lib/src/app/fonts.dart.
enum FontChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "pr_reader/fonts", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "monospaceFamilies" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let fm = NSFontManager.shared
      let families = fm.availableFontFamilies.filter { family in
        guard !family.hasPrefix("."), let font = fm.font(withFamily: family, traits: [], weight: 5, size: 12)
        else { return false }
        return font.isFixedPitch
      }
      result(families)
    }
  }
}
