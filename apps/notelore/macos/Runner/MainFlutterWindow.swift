import Cocoa
import FlutterMacOS
import Network

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

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
