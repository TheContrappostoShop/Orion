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
  }
}