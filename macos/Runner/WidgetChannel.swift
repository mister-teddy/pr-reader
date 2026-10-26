import FlutterMacOS
import Foundation
import WidgetKit

/// Shares PR snapshots with the widget extension and reloads widgets when
/// they change. See lib/src/app/home_widgets.dart.
///
/// The data goes to the App Group and, as a copy, to a JSON file in
/// ~/Library/Application Support/de.reonic.prReader.widgets/. Without a
/// development team the app and the extension are signed ad hoc, and macOS
/// blocks the extension from the group container as another app's data; the
/// file (granted by a sandbox exception) works either way.
enum WidgetChannel {
  static let exportURL: URL = {
    // NSHomeDirectory() is the sandbox container; the exception is relative
    // to the real home folder.
    let home = getpwuid(getuid()).flatMap { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
    return URL(fileURLWithPath: home)
      .appendingPathComponent("Library/Application Support/de.reonic.prReader.widgets/widgets.json")
  }()

  private static func export(_ defaults: UserDefaults) {
    var data: [String: Any] = [
      "pinned": defaults.stringArray(forKey: "pinned") ?? [],
      "recents": defaults.stringArray(forKey: "recents") ?? [],
      "recentInfo": defaults.dictionary(forKey: "recentInfo") ?? [:],
    ]
    for (k, v) in defaults.dictionaryRepresentation() where k.hasPrefix("snap:") {
      data[k] = v
    }
    do {
      try FileManager.default.createDirectory(
        at: exportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONSerialization.data(withJSONObject: data).write(to: exportURL, options: .atomic)
    } catch {
      NSLog("PR Reader: could not write widget data: \(error)")
    }
  }

  static func register(with messenger: FlutterBinaryMessenger) {
    let defaults = (Bundle.main.object(forInfoDictionaryKey: "PRReaderAppGroup") as? String)
      .flatMap { UserDefaults(suiteName: $0) }
    let channel = FlutterMethodChannel(name: "pr_reader/widgets", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard let defaults else { return result(FlutterError(code: "no_group", message: "No App Group", details: nil)) }
      let args = call.arguments as? [String: Any] ?? [:]
      var pinned = defaults.stringArray(forKey: "pinned") ?? []
      switch call.method {
      case "save":
        defaults.set(args["json"] as? String, forKey: "snap:\(args["key"] as? String ?? "")")
        result(nil)
      case "setRecents":
        // Also reloads, so widgets for recent PRs pick up their titles.
        defaults.set(args["keys"] as? [String] ?? [], forKey: "recents")
        defaults.set(args["info"] as? [String: [String: String]] ?? [:], forKey: "recentInfo")
        reload()
        result(nil)
      case "pin":
        let key = args["key"] as? String ?? ""
        pinned.removeAll { $0 == key }
        defaults.set([key] + pinned, forKey: "pinned")
        reload()
        result(true)
      case "unpin":
        pinned.removeAll { $0 == args["key"] as? String }
        defaults.set(pinned, forKey: "pinned")
        reload()
        result(nil)
      case "pinned":
        result(pinned)
      case "refresh":
        reload()
        result(nil)
      default:
        return result(FlutterMethodNotImplemented)
      }
      if call.method != "pinned" { export(defaults) }
    }
  }

  private static func reload() {
    if #available(macOS 11.0, *) { WidgetCenter.shared.reloadAllTimelines() }
  }
}
