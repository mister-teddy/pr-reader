import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  init() {
    // Open large enough for the tree + split diff layout, centered on screen.
    let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let size = NSSize(width: min(1440, visible.width * 0.9), height: min(920, visible.height * 0.9))
    let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
    super.init(
      contentRect: NSRect(origin: origin, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false)
    isReleasedWhenClosed = false
    minSize = NSSize(width: 360, height: 480)
    title = "PR Reader"

    let flutterViewController = FlutterViewController()
    contentViewController = flutterViewController
    setFrame(NSRect(origin: origin, size: size), display: true)
    RegisterGeneratedPlugins(registry: flutterViewController)
    WidgetChannel.register(with: flutterViewController.engine.binaryMessenger)
    FontChannel.register(with: flutterViewController.engine.binaryMessenger)
  }
}
