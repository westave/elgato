import AppKit

/// Панель управления одной лампой внутри меню: кнопка питания,
/// слайдеры цветовой температуры и яркости (как в Elgato Control Center).
final class LampControlView: NSView {

    let lamp: KeyLight

    private let powerButton: NSButton
    private let tempSlider: NSSlider
    private let brightnessSlider: NSSlider
    private var isOn = false

    private var pendingSend: (() -> Void)?
    private var flushTimer: Timer?

    init(lamp: KeyLight) {
        self.lamp = lamp

        powerButton = NSButton(
            image: NSImage(systemSymbolName: "power", accessibilityDescription: "Вкл/выкл")!,
            target: nil, action: nil
        )
        // Elgato: слева холодный (143 mireds ≈ 7000K), справа тёплый (344 ≈ 2900K)
        tempSlider = NSSlider(value: 200, minValue: 143, maxValue: 344, target: nil, action: nil)
        brightnessSlider = NSSlider(value: 50, minValue: 3, maxValue: 100, target: nil, action: nil)

        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 104))

        powerButton.target = self
        powerButton.action = #selector(togglePower)
        powerButton.isBordered = false
        powerButton.frame = NSRect(x: 14, y: 72, width: 24, height: 24)
        powerButton.contentTintColor = .tertiaryLabelColor
        addSubview(powerButton)

        let nameLabel = NSTextField(labelWithString: lamp.name)
        nameLabel.font = .boldSystemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.frame = NSRect(x: 44, y: 74, width: 222, height: 18)
        addSubview(nameLabel)

        addIcon("snowflake", x: 14, y: 42)
        tempSlider.target = self
        tempSlider.action = #selector(temperatureChanged)
        tempSlider.frame = NSRect(x: 38, y: 40, width: 204, height: 22)
        addSubview(tempSlider)
        addIcon("flame", x: 248, y: 42)

        addIcon("sun.min", x: 14, y: 12)
        brightnessSlider.target = self
        brightnessSlider.action = #selector(brightnessChanged)
        brightnessSlider.frame = NSRect(x: 38, y: 10, width: 204, height: 22)
        addSubview(brightnessSlider)
        addIcon("sun.max.fill", x: 248, y: 12)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    /// Обновить контролы по актуальному состоянию лампы (не шлёт команд)
    func refresh(with state: [String: Any]) {
        if let on = state["on"] as? Int { setPowerUI(on == 1) }
        if let brightness = state["brightness"] as? Int {
            brightnessSlider.doubleValue = Double(brightness)
        }
        if let temperature = state["temperature"] as? Int {
            tempSlider.doubleValue = Double(temperature)
        }
    }

    // MARK: - Actions

    @objc private func togglePower() {
        setPowerUI(!isOn)
        lamp.setOn(isOn)
    }

    @objc private func temperatureChanged() {
        let value = Int(tempSlider.doubleValue)
        throttle { [lamp] in lamp.setTemperature(value) }
    }

    @objc private func brightnessChanged() {
        let value = Int(brightnessSlider.doubleValue)
        throttle { [lamp] in lamp.setBrightness(value) }
    }

    // MARK: - Helpers

    private func setPowerUI(_ on: Bool) {
        isOn = on
        powerButton.contentTintColor = on ? .systemOrange : .tertiaryLabelColor
    }

    private func addIcon(_ symbolName: String, x: CGFloat, y: CGFloat) {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return }
        let view = NSImageView(image: image)
        view.contentTintColor = .secondaryLabelColor
        view.frame = NSRect(x: x, y: y, width: 18, height: 18)
        addSubview(view)
    }

    /// Слайдер шлёт значения непрерывно — ограничиваем до ~7 запросов/с,
    /// последнее значение отправляется всегда.
    private func throttle(_ send: @escaping () -> Void) {
        pendingSend = send
        guard flushTimer == nil else { return }

        if let first = pendingSend {
            pendingSend = nil
            first()
        }

        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let queued = self.pendingSend {
                self.pendingSend = nil
                queued()
            } else {
                self.flushTimer?.invalidate()
                self.flushTimer = nil
            }
        }
        // .common — чтобы таймер работал, пока открыто меню
        RunLoop.main.add(timer, forMode: .common)
        flushTimer = timer
    }
}
