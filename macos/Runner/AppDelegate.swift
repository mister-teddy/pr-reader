import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var engine: FlutterEngine?
  private var window: MainFlutterWindow?

  override func applicationWillFinishLaunching(_ notification: Notification) {
    // Set up before launch finishes, so a pr:// link that launched the app
    // reaches the app_links plugin.
    if UserDefaults.standard.object(forKey: "flutter.multi_window") as? Bool ?? true {
      let project = FlutterDartProject()
      project.dartEntrypointArguments = ["--windows"]
      let engine = FlutterEngine(name: "PR Reader", project: project)
      engine.run(withEntrypoint: nil)
      RegisterGeneratedPlugins(registry: engine)
      WidgetChannel.register(with: engine.binaryMessenger)
      self.engine = engine
    } else {
      let window = MainFlutterWindow()
      window.makeKeyAndOrderFront(nil)
      self.window = window
    }
    super.applicationWillFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
