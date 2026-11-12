import Foundation

@main
struct HomeKitBridgeLifecycle {
    static func wait(_ condition: () -> Bool, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        precondition(condition(), "Timed out waiting for HomeKit helper lifecycle")
    }

    static func main() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let data = root.appendingPathComponent("data")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let helper = root.appendingPathComponent("test-helper")
        try """
        #!/bin/sh
        data_dir="$2"
        count_file="$data_dir/launch-count"
        count=0
        if [ -f "$count_file" ]; then count=$(cat "$count_file"); fi
        echo $((count + 1)) > "$count_file"
        trap 'rm -f "$data_dir/.homekit.ready.json"; exit 0' TERM INT
        echo '{"paired_clients":{"test-controller":true}}' > "$data_dir/.homekit.state"
        echo '{"port":51826}' > "$data_dir/.homekit.ready.json"
        while :; do sleep 0.1; done
        """.write(to: helper, atomically: true, encoding: .utf8)
        try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let bridge = HomeKitBridge(dataDirectory: data, helperURL: helper, homeDirectory: root)
        defer { bridge.stop() }
        let ready = data.appendingPathComponent(".homekit.ready.json")
        let count = data.appendingPathComponent("launch-count")
        precondition(!bridge.enabled && !bridge.hasExistingSetup)
        bridge.updateLamps(["192.0.2.1": "Test lamp"])
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        precondition(!files.fileExists(atPath: count.path), "HomeKit must stay off on fresh installs")
        print("PASS fresh installation does not launch HomeKit")

        bridge.setEnabled(true)
        wait { files.fileExists(atPath: ready.path) }
        precondition(bridge.statusTitle == "HomeKit: подключён к Apple Home")
        bridge.setEnabled(false)
        wait { !files.fileExists(atPath: ready.path) }
        precondition(files.fileExists(atPath: data.appendingPathComponent(".homekit.state").path))
        precondition(bridge.statusTitle == "HomeKit: выключен")
        print("PASS disabling HomeKit stops the helper and retains pairing")

        bridge.setEnabled(true)
        wait { files.fileExists(atPath: ready.path) }
        let launches = try String(contentsOf: count, encoding: .utf8)
        precondition(launches.trimmingCharacters(in: .whitespacesAndNewlines) == "2")
        bridge.setEnabled(false)
        wait { !files.fileExists(atPath: ready.path) }
        print("PASS HomeKit can be enabled again without duplicate helpers")

        let legacyHome = root.appendingPathComponent("legacy-home")
        let legacyProject = root.appendingPathComponent("legacy-project")
        let agents = legacyHome.appendingPathComponent("Library/LaunchAgents")
        try files.createDirectory(at: agents, withIntermediateDirectories: true)
        try files.createDirectory(at: legacyProject, withIntermediateDirectories: true)
        let state = Data("{\"mac\":\"AA:BB:CC:DD:EE:FF\",\"paired_clients\":{\"test-controller\":true}}".utf8)
        try state.write(to: legacyProject.appendingPathComponent(".homekit.state"))
        let config = Data("{\"lights\":[{\"ip\":\"192.0.2.1\",\"name\":\"Existing lamp\"}]}".utf8)
        try config.write(to: legacyProject.appendingPathComponent("config.json"))
        let agent = try PropertyListSerialization.data(fromPropertyList: [
            "Label": "com.elgato.homekit-bridge", "WorkingDirectory": legacyProject.path
        ], format: .xml, options: 0)
        let plist = agents.appendingPathComponent("com.elgato.homekit-bridge.plist")
        try agent.write(to: plist)
        let migratedData = root.appendingPathComponent("migrated-data")
        var stoppedLegacy = false
        let migrated = HomeKitBridge(dataDirectory: migratedData, helperURL: helper,
            homeDirectory: legacyHome, stopLegacyAgent: { stoppedLegacy = true })
        migrated.setEnabled(true)
        migrated.updateLamps(["192.0.2.1": "Existing lamp"])
        migrated.stop()
        precondition(stoppedLegacy)
        let copiedState = try Data(contentsOf: migratedData.appendingPathComponent(".homekit.state"))
        precondition(copiedState == state, "Migration must preserve the exact existing pairing")
        precondition(!files.fileExists(atPath: plist.path))
        precondition(files.fileExists(atPath: migratedData.appendingPathComponent("legacy-homekit-bridge.plist").path))
        print("PASS legacy migration preserves bridge identity and pairing, and saves the agent backup")
    }
}
