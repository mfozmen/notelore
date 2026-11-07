import Carbon
import Cocoa
import FlutterMacOS
import Network

class MainFlutterWindow: NSWindow {
  /// The quick-add shortcut and window (#800).
  private var quick: QuickWindow?

  // Borderless while it is the quick-add window, and it still takes typing.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    quick = QuickWindow(window: self, messenger: flutterViewController.engine.binaryMessenger)

    // Whether the connection costs by the byte (network_native.dart, #767): the
    // monitor's first path is the current one, answered once.
    FlutterMethodChannel(
      name: "io.github.mfozmen.notelore/network",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    ).setMethodCallHandler { call, result in
      guard call.method == "metered" else { return result(FlutterMethodNotImplemented) }
      let monitor = NWPathMonitor()
      var answered = false
      monitor.pathUpdateHandler = { path in
        if answered { return }
        answered = true
        monitor.cancel()
        DispatchQueue.main.async { result(path.isExpensive || path.isConstrained) }
      }
      monitor.start(queue: DispatchQueue(label: "io.github.mfozmen.notelore.network"))
    }

    super.awakeFromNib()
  }
}

/// The quick-add window (quick_window_native.dart, #800): the global shortcut
/// ⌥⌘N and the main window's small floating shape.
final class QuickWindow {
  private let window: NSWindow
  private let channel: FlutterMethodChannel
  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private var saved: (frame: NSRect, style: NSWindow.StyleMask, level: NSWindow.Level,
                      miniaturized: Bool, visible: Bool)?
  private var previous: NSRunningApplication?

  private static let width: CGFloat = 460
  private static let height: CGFloat = 260
  private static let top: CGFloat = 64

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    channel = FlutterMethodChannel(name: "io.github.mfozmen.notelore/quick", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "listen": result(self.listen(call.arguments as? Bool ?? false))
      case "compact": self.compact(); result(nil)
      case "restore": self.restore(); result(nil)
      case "front": self.front(); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func listen(_ on: Bool) -> Bool {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    hotKey = nil
    guard on else { return true }
    if handler == nil {
      var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
      let me = Unmanaged.passUnretained(self).toOpaque()
      InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
        guard let data else { return noErr }
        let quick = Unmanaged<QuickWindow>.fromOpaque(data).takeUnretainedValue()
        DispatchQueue.main.async { quick.channel.invokeMethod("pressed", arguments: nil) }
        return noErr
      }, 1, &type, me, &handler)
    }
    let id = EventHotKeyID(signature: OSType(0x4E544C52), id: 1) // "NTLR"
    let status = RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(cmdKey | optionKey), id,
                                     GetApplicationEventTarget(), 0, &hotKey)
    return status == noErr
  }

  private func compact() {
    if saved != nil { return front() }
    previous = NSWorkspace.shared.frontmostApplication
    saved = (window.frame, window.styleMask, window.level, window.isMiniaturized, window.isVisible)
    let screen = NSScreen.main ?? window.screen ?? NSScreen.screens[0]
    let area = screen.visibleFrame
    let frame = NSRect(x: area.midX - Self.width / 2, y: area.maxY - Self.top - Self.height,
                       width: Self.width, height: Self.height)
    if window.isMiniaturized { window.deminiaturize(nil) }
    window.styleMask = [.borderless, .fullSizeContentView]
    window.level = .floating
    window.setFrame(frame, display: true)
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  private func restore() {
    guard let saved else { return }
    self.saved = nil
    window.styleMask = saved.style
    window.level = saved.level
    window.setFrame(saved.frame, display: true)
    // Back as it was, minimized again if it was; the person returns to their app.
    if saved.miniaturized {
      window.miniaturize(nil)
    } else if !saved.visible {
      window.orderOut(nil)
    }
    if let previous, previous != NSRunningApplication.current { previous.activate() }
  }

  private func front() {
    if window.isMiniaturized { window.deminiaturize(nil) }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }
}
