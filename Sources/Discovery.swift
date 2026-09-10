import Foundation

/// Автообнаружение Elgato-ламп в сети через Bonjour (_elg._tcp)
final class LampDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {

    /// Вызывается для каждой найденной лампы: (имя, IPv4-адрес)
    var onFound: ((String, String) -> Void)?

    private var browser: NetServiceBrowser?
    private var pending: Set<NetService> = []

    func start() {
        stop()
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForServices(ofType: "_elg._tcp.", inDomain: "local.")
        self.browser = browser
    }

    func stop() {
        browser?.stop()
        browser = nil
        pending.removeAll()
    }

    // MARK: - NetServiceBrowserDelegate

    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didFind service: NetService,
                           moreComing: Bool) {
        service.delegate = self
        pending.insert(service)
        service.resolve(withTimeout: 10)
    }

    // MARK: - NetServiceDelegate

    func netServiceDidResolve(_ sender: NetService) {
        defer { pending.remove(sender) }
        guard let ip = Self.ipv4Address(from: sender.addresses) else { return }
        onFound?(sender.name, ip)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        pending.remove(sender)
    }

    // MARK: - Helpers

    private static func ipv4Address(from addresses: [Data]?) -> String? {
        for data in addresses ?? [] {
            let ip: String? = data.withUnsafeBytes { raw -> String? in
                guard let base = raw.baseAddress else { return nil }
                let family = base.assumingMemoryBound(to: sockaddr.self).pointee.sa_family
                guard family == sa_family_t(AF_INET) else { return nil }
                var addr = base.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                    return nil
                }
                return String(cString: buffer)
            }
            if let ip { return ip }
        }
        return nil
    }
}
