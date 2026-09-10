import AppKit
import ServiceManagement

/// Elgato Camera Control — приложение в строке меню:
/// - автоматически включает/выключает Key Light вместе с камерой
/// - находит лампы в сети сама (Bonjour) и запоминает их
/// - управление яркостью/температурой прямо из меню (как Control Center)
/// - автозапуск при входе в систему
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    private var lamps: [String: KeyLight] = [:]          // ip -> лампа
    private var lampViews: [String: LampControlView] = [:]
    private let discovery = LampDiscovery()

    private var pollTimer: Timer?
    private var cameraActive = false
    private var turnOffWork: DispatchWorkItem?

    private let defaults = UserDefaults.standard
    private static let lampsKey = "knownLamps"           // [ip: имя]
    private static let loginItemKey = "didAutoEnableLoginItem"

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        // Лампы, найденные в прошлые запуски
        if let saved = defaults.dictionary(forKey: Self.lampsKey) as? [String: String] {
            for (ip, name) in saved {
                lamps[ip] = KeyLight(name: name, ip: ip)
            }
        }

        discovery.onFound = { [weak self] name, ip in
            DispatchQueue.main.async { self?.addLamp(name: name, ip: ip) }
        }
        discovery.start()

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        // Один раз автоматически включаем автозапуск; дальше пользователь
        // управляет галочкой в меню
        if !defaults.bool(forKey: Self.loginItemKey) {
            try? SMAppService.mainApp.register()
            defaults.set(true, forKey: Self.loginItemKey)
        }

        rebuildMenu()
    }

    // MARK: - Камера → свет

    private func poll() {
        let active = CameraMonitor.isCameraActive()
        guard active != cameraActive else { return }
        cameraActive = active

        if active {
            turnOffWork?.cancel()
            turnOffWork = nil
            for lamp in lamps.values { lamp.turnOn() }
        } else {
            // Пауза 2с, чтобы свет не мигал при перезапуске камеры
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                for lamp in self.lamps.values { lamp.turnOff() }
            }
            turnOffWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
        }

        updateIcon()
    }

    private func updateIcon() {
        let symbol = cameraActive ? "lightbulb.fill" : "lightbulb"
        statusItem?.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "Elgato Camera Control"
        )
    }

    // MARK: - Лампы

    private func addLamp(name: String, ip: String) {
        guard lamps[ip] == nil else { return }
        let cleanName = name.isEmpty ? "Key Light" : name
        lamps[ip] = KeyLight(name: cleanName, ip: ip)
        persistLamps()
        rebuildMenu()
    }

    private func persistLamps() {
        var saved: [String: String] = [:]
        for (ip, lamp) in lamps { saved[ip] = lamp.name }
        defaults.set(saved, forKey: Self.lampsKey)
    }

    // MARK: - Меню

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
        // Подтянуть актуальное состояние ламп в слайдеры
        for view in lampViews.values {
            view.lamp.fetchState { state in
                guard let state else { return }
                DispatchQueue.main.async { view.refresh(with: state) }
            }
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let statusTitle: String
        if lamps.isEmpty {
            statusTitle = "🔍 Ищу лампы в сети…"
        } else if cameraActive {
            statusTitle = "📹 Камера активна — свет включён"
        } else {
            statusTitle = "Камера неактивна"
        }
        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        for (ip, lamp) in lamps.sorted(by: { $0.key < $1.key }) {
            menu.addItem(.separator())
            let item = NSMenuItem()
            if let existing = lampViews[ip] {
                item.view = existing
            } else {
                let view = LampControlView(lamp: lamp)
                lampViews[ip] = view
                item.view = view
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(makeItem("Найти лампы в сети", #selector(rediscover)))
        menu.addItem(makeItem("Добавить лампу по IP…", #selector(addLampManually)))
        if !lamps.isEmpty {
            menu.addItem(makeItem("Сбросить список ламп", #selector(forgetLamps)))
        }
        menu.addItem(.separator())

        let login = makeItem("Запускать при входе", #selector(toggleLoginItem))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Завершить",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Действия меню

    @objc private func rediscover() {
        discovery.start()
    }

    @objc private func forgetLamps() {
        lamps.removeAll()
        lampViews.removeAll()
        defaults.removeObject(forKey: Self.lampsKey)
        rebuildMenu()
        discovery.start()
    }

    @objc private func addLampManually() {
        let alert = NSAlert()
        alert.messageText = "Добавить лампу по IP"
        alert.informativeText = "IP адрес виден в роутере или в приложении Elgato Control Center"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "192.168.1.100"
        alert.accessoryView = field
        alert.addButton(withTitle: "Добавить")
        alert.addButton(withTitle: "Отмена")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let ip = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !ip.isEmpty {
                addLamp(name: "Key Light", ip: ip)
            }
        }
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("Login item error: \(error)")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
