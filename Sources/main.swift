import Cocoa
import AVFoundation

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var cameraMonitor: CameraMonitor?
    var elgatoController: ElgatoController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "light.beacon.max", accessibilityDescription: "Elgato Control")
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }

        // Setup menu
        setupMenu()

        // Get Key Light IP from UserDefaults or prompt user
        let keyLightIP = UserDefaults.standard.string(forKey: "keyLightIP") ?? ""

        if keyLightIP.isEmpty {
            promptForKeyLightIP()
        } else {
            startMonitoring(keyLightIP: keyLightIP)
        }
    }

    func setupMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Status: Initializing...", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Configure Key Light IP...", action: #selector(promptForKeyLightIP), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Test Light On", action: #selector(testLightOn), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Test Light Off", action: #selector(testLightOff), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc func statusBarButtonClicked() {
        // Menu will show automatically
    }

    @objc func promptForKeyLightIP() {
        let alert = NSAlert()
        alert.messageText = "Enter Elgato Key Light IP Address"
        alert.informativeText = "Enter the local IP address of your Elgato Key Light (e.g., 192.168.1.100)"

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = UserDefaults.standard.string(forKey: "keyLightIP") ?? ""
        alert.accessoryView = input

        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let ip = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ip.isEmpty {
                UserDefaults.standard.set(ip, forKey: "keyLightIP")
                startMonitoring(keyLightIP: ip)
            }
        }
    }

    func startMonitoring(keyLightIP: String) {
        elgatoController = ElgatoController(ipAddress: keyLightIP)
        cameraMonitor = CameraMonitor { [weak self] isActive in
            DispatchQueue.main.async {
                self?.handleCameraStatusChange(isActive: isActive)
            }
        }

        cameraMonitor?.startMonitoring()
        updateStatusMenu(cameraActive: false, monitoring: true)
    }

    func handleCameraStatusChange(isActive: Bool) {
        print("Camera status changed: \(isActive ? "Active" : "Inactive")")
        updateStatusMenu(cameraActive: isActive, monitoring: true)

        if isActive {
            elgatoController?.turnOn()
        } else {
            elgatoController?.turnOff()
        }
    }

    func updateStatusMenu(cameraActive: Bool, monitoring: Bool) {
        guard let menu = statusItem?.menu else { return }

        let statusText = monitoring ?
            (cameraActive ? "Status: Camera Active (Light ON)" : "Status: Camera Inactive (Light OFF)") :
            "Status: Not Monitoring"

        menu.items[0].title = statusText
    }

    @objc func testLightOn() {
        elgatoController?.turnOn()
    }

    @objc func testLightOff() {
        elgatoController?.turnOff()
    }
}

// Keep app running
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
