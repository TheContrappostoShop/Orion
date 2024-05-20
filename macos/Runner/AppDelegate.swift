import Cocoa
import FlutterMacOS
import CoreWLAN

@NSApplicationMain
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ aNotification: Notification) {
    guard let controller = NSApplication.shared.mainWindow?.contentViewController as? FlutterViewController else {
      print("Failed to get FlutterViewController")
      return
    }
    let wifiChannel = FlutterMethodChannel(name: "orion.macplatform.channel",
                                              binaryMessenger: controller.engine.binaryMessenger)
    wifiChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      // Note: this method is invoked on the UI thread.
      // Handle the method call
      print("Received method call: \(call.method)")
      if call.method == "networks" {
        print("Calling getWifiNetworks()")
        result(self.getWifiNetworks())
      } else {
        print("Method not recognized, calling getWifiNetworks() by default")
        result(self.getWifiNetworks())
      }
    })
  }

  func getWifiNetworks() -> [String] {
    print("In getWifiNetworks()")
    let wifiClient = CWWiFiClient.shared()
    let interfaces = wifiClient.interfaces()
    var networks: [String] = []

    interfaces?.forEach { interface in
        do {
            let networkList = try interface.scanForNetworks(withName: nil)
            networkList.forEach { network in
                print("Found network: \(network.ssid ?? "")")
                networks.append(network.ssid ?? "")
            }
        } catch {
            print("Error: \(error)")
        }
    }
    return networks
  }
}