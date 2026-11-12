import AppKit

/// Owns the bundled HomeKit helper. No system Python or shell setup is needed.
final class HomeKitBridge {
    static let pairingCode = "031-45-154"

    private let files = FileManager.default
    private let dataDirectory: URL
    private let helperURL: URL
    private let logURL: URL
    private let homeDirectory: URL
    private let stopLegacyAgent: () throws -> Void
    private var process: Process?
    private var logHandle: FileHandle?
    private var pendingRestart: DispatchWorkItem?
    private var stopping = false
    private var restartRequested = false
    private var desiredLamps: [String: String] = [:]
    private(set) var enabled = false
    private(set) var lastError: String?
    var onStatusChanged: (() -> Void)?

    init(dataDirectory: URL? = nil, helperURL: URL? = nil,
         homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
         stopLegacyAgent: (() throws -> Void)? = nil) {
        self.homeDirectory = homeDirectory
        self.stopLegacyAgent = stopLegacyAgent ?? Self.unloadLegacyAgent
        self.dataDirectory = dataDirectory ?? files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ElgatoCameraControl/HomeKit", isDirectory: true)
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let helpers = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers")
        let nativeHelper = helpers.appendingPathComponent("ElgatoHomeKitBridge-\(architecture)")
        self.helperURL = helperURL ?? (files.isExecutableFile(atPath: nativeHelper.path)
            ? nativeHelper : helpers.appendingPathComponent("ElgatoHomeKitBridge"))
        logURL = homeDirectory
            .appendingPathComponent("Library/Logs/ElgatoCameraControl-homekit.log")
        do {
            try files.createDirectory(at: self.dataDirectory, withIntermediateDirectories: true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    var savedLamps: [String: String] {
        guard let data = existingConfigData,
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lights = config["lights"] as? [[String: Any]] else { return [:] }
        var result: [String: String] = [:]
        for light in lights where light["enabled"] as? Bool != false {
            if let ip = light["ip"] as? String {
                result[ip] = light["name"] as? String ?? "Key Light"
            }
        }
        return result
    }

    var statusTitle: String {
        if !enabled { return "HomeKit: выключен" }
        if lastError != nil { return "HomeKit: требуется внимание" }
        if desiredLamps.isEmpty { return "HomeKit: ожидаю лампу" }
        guard process?.isRunning == true,
              files.fileExists(atPath: readyURL.path) else { return "HomeKit: запускается…" }
        if let data = try? Data(contentsOf: dataDirectory.appendingPathComponent(".homekit.state")),
           let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let clients = state["paired_clients"] as? [String: Any], !clients.isEmpty {
            return "HomeKit: подключён к Apple Home"
        }
        return "HomeKit: готов к добавлению"
    }

    private var configURL: URL { dataDirectory.appendingPathComponent("config.json") }
    private var readyURL: URL { dataDirectory.appendingPathComponent(".homekit.ready.json") }

    var hasExistingSetup: Bool {
        files.fileExists(atPath: legacyPlistURL.path) ||
        files.fileExists(atPath: dataDirectory.appendingPathComponent(".homekit.state").path)
    }

    private var legacyPlistURL: URL {
        homeDirectory
            .appendingPathComponent("Library/LaunchAgents/com.elgato.homekit-bridge.plist")
    }

    private var existingConfigData: Data? {
        if let data = try? Data(contentsOf: configURL) { return data }
        guard let data = try? Data(contentsOf: legacyPlistURL),
              let agent = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let directory = agent["WorkingDirectory"] as? String else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent("config.json"))
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        lastError = nil
        if enabled { scheduleRestart(after: 0) }
        else {
            pendingRestart?.cancel()
            restartRequested = false
            if let process, process.isRunning { process.terminate() }
        }
        onStatusChanged?()
    }

    func updateLamps(_ lamps: [String: String]) {
        guard desiredLamps != lamps || process == nil else { return }
        desiredLamps = lamps
        do {
            if enabled { try migrateLegacyBridge() }
            // Retain existing order so an upgrade preserves bridged accessory IDs.
            var oldLights: [[String: Any]] = []
            if let data = existingConfigData,
               let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                oldLights = config["lights"] as? [[String: Any]] ?? []
            }
            var ips = oldLights.compactMap { $0["ip"] as? String }.filter { lamps[$0] != nil }
            ips.append(contentsOf: lamps.keys.filter { !ips.contains($0) }.sorted())
            let lights = ips.map { ["ip": $0, "name": lamps[$0]!, "enabled": true] as [String: Any] }
            let data = try JSONSerialization.data(withJSONObject: ["lights": lights], options: .prettyPrinted)
            try data.write(to: configURL, options: .atomic)
            lastError = nil
            if enabled { scheduleRestart(after: 0.5) }
        } catch {
            lastError = error.localizedDescription
            onStatusChanged?()
        }
    }

    func restart() {
        lastError = nil
        scheduleRestart(after: 0)
    }

    func stop() {
        stopping = true
        pendingRestart?.cancel()
        if let process, process.isRunning { process.terminate() }
    }

    func openLog() { NSWorkspace.shared.open(logURL) }

    private func scheduleRestart(after delay: TimeInterval) {
        pendingRestart?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopping, self.enabled else { return }
            if let process = self.process, process.isRunning {
                self.restartRequested = true
                process.terminate()
            } else {
                self.launch()
            }
        }
        pendingRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func launch() {
        guard !stopping, enabled, !desiredLamps.isEmpty else { onStatusChanged?(); return }
        guard files.isExecutableFile(atPath: helperURL.path) else {
            lastError = "В этой сборке отсутствует HomeKit-мост. Установите полную версию приложения."
            onStatusChanged?()
            return
        }
        do {
            try migrateLegacyBridge()
            try files.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !files.fileExists(atPath: logURL.path) { files.createFile(atPath: logURL.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try? files.removeItem(at: readyURL)
            let child = Process()
            child.executableURL = helperURL
            child.arguments = ["--data-dir", dataDirectory.path, "--parent-pid", String(getpid())]
            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONUNBUFFERED"] = "1"
            child.environment = environment
            child.standardOutput = handle
            child.standardError = handle
            child.terminationHandler = { [weak self] child in
                DispatchQueue.main.async {
                    guard let self, self.process === child else { return }
                    self.process = nil
                    try? self.logHandle?.close()
                    self.logHandle = nil
                    guard !self.stopping, self.enabled else { return }
                    if self.restartRequested {
                        self.restartRequested = false
                        self.launch()
                    } else {
                        self.lastError = "HomeKit-мост остановился (код \(child.terminationStatus)). Подробности в журнале."
                        self.scheduleRestart(after: 5)
                    }
                    self.onStatusChanged?()
                }
            }
            try child.run()
            process = child
            logHandle = handle
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        onStatusChanged?()
    }

    private func migrateLegacyBridge() throws {
        let plist = legacyPlistURL
        guard files.fileExists(atPath: plist.path) else { return }
        let data = try Data(contentsOf: plist)
        guard let agent = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              agent["Label"] as? String == "com.elgato.homekit-bridge",
              let directory = agent["WorkingDirectory"] as? String else {
            throw NSError(domain: "HomeKitBridge", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Не удалось прочитать настройки существующего HomeKit-моста."])
        }
        try data.write(to: dataDirectory.appendingPathComponent("legacy-homekit-bridge.plist"), options: .atomic)
        try stopLegacyAgent()
        let source = URL(fileURLWithPath: directory, isDirectory: true)
        for name in ["config.json", ".homekit.state", "accessory_ids.json"] {
            let old = source.appendingPathComponent(name)
            let new = dataDirectory.appendingPathComponent(name)
            if files.fileExists(atPath: old.path), !files.fileExists(atPath: new.path) {
                try files.copyItem(at: old, to: new)
            }
        }
        try files.removeItem(at: plist)
    }

    private static func unloadLegacyAgent() throws {
        let unload = Process()
        unload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        unload.arguments = ["bootout", "gui/\(getuid())/com.elgato.homekit-bridge"]
        unload.standardOutput = FileHandle.nullDevice
        unload.standardError = FileHandle.nullDevice
        try unload.run()
        unload.waitUntilExit()
        if unload.terminationStatus != 0 {
            let check = Process()
            check.executableURL = unload.executableURL
            check.arguments = ["print", "gui/\(getuid())/com.elgato.homekit-bridge"]
            check.standardOutput = FileHandle.nullDevice
            check.standardError = FileHandle.nullDevice
            try check.run()
            check.waitUntilExit()
            if check.terminationStatus == 0 {
                throw NSError(domain: "HomeKitBridge", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Не удалось остановить предыдущий HomeKit-мост."])
            }
        }
    }
}
