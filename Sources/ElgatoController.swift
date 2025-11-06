import Foundation

class ElgatoController {
    let ipAddress: String
    let port: Int = 9123

    init(ipAddress: String) {
        self.ipAddress = ipAddress
    }

    func turnOn() {
        setLightState(on: true)
    }

    func turnOff() {
        setLightState(on: false)
    }

    private func setLightState(on: Bool) {
        let urlString = "http://\(ipAddress):\(port)/elgato/lights"
        guard let url = URL(string: urlString) else {
            print("Invalid URL: \(urlString)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "numberOfLights": 1,
            "lights": [
                [
                    "on": on ? 1 : 0,
                    "brightness": 100,
                    "temperature": 200
                ]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            print("Failed to serialize JSON: \(error)")
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error controlling Key Light: \(error.localizedDescription)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    print("Key Light turned \(on ? "ON" : "OFF") successfully")
                } else {
                    print("Key Light responded with status code: \(httpResponse.statusCode)")
                }
            }
        }

        task.resume()
    }

    func getStatus(completion: @escaping (Bool?) -> Void) {
        let urlString = "http://\(ipAddress):\(port)/elgato/lights"
        guard let url = URL(string: urlString) else {
            print("Invalid URL: \(urlString)")
            completion(nil)
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error getting Key Light status: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let data = data else {
                completion(nil)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let lights = json["lights"] as? [[String: Any]],
                   let firstLight = lights.first,
                   let on = firstLight["on"] as? Int {
                    completion(on == 1)
                } else {
                    completion(nil)
                }
            } catch {
                print("Error parsing response: \(error)")
                completion(nil)
            }
        }

        task.resume()
    }
}
