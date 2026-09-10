import Foundation

/// Один Elgato Key Light: управление через HTTP API (порт 9123).
/// Перед выключением запоминает яркость/температуру и восстанавливает
/// ровно их при следующем включении.
final class KeyLight {
    let name: String
    let ip: String

    private let session: URLSession
    private var lastBrightness: Int?
    private var lastTemperature: Int?

    private var url: URL { URL(string: "http://\(ip):9123/elgato/lights")! }

    init(name: String, ip: String) {
        self.name = name
        self.ip = ip
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        session = URLSession(configuration: config)
    }

    func turnOn() {
        var fields: [String: Int] = ["on": 1]
        if let brightness = lastBrightness { fields["brightness"] = brightness }
        if let temperature = lastTemperature { fields["temperature"] = temperature }
        put(fields)
    }

    func turnOff() {
        fetchState { [weak self] state in
            guard let self else { return }
            if let state {
                if let brightness = state["brightness"] as? Int { self.lastBrightness = brightness }
                if let temperature = state["temperature"] as? Int { self.lastTemperature = temperature }
            }
            self.put(["on": 0])
        }
    }

    func setOn(_ on: Bool) {
        put(["on": on ? 1 : 0])
    }

    func setBrightness(_ value: Int) {
        put(["brightness": max(3, min(100, value))])
    }

    func setTemperature(_ value: Int) {
        put(["temperature": max(143, min(344, value))])
    }

    func fetchState(_ completion: @escaping ([String: Any]?) -> Void) {
        session.dataTask(with: url) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lights = json["lights"] as? [[String: Any]],
                  let first = lights.first else {
                completion(nil)
                return
            }
            completion(first)
        }.resume()
    }

    private func put(_ fields: [String: Int]) {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["numberOfLights": 1, "lights": [fields]]
        )
        session.dataTask(with: request).resume()
    }
}
