import Foundation

public final class InsuranceProviderLinksStore: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let storageKey = "insuranceProviderLinks"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func url(for provider: InsuranceProvider) -> URL? {
        stored()[provider] ?? Self.defaultURL(for: provider)
    }

    public func setURL(_ url: URL?, for provider: InsuranceProvider) {
        var all = stored()
        all[provider] = url
        save(all)
    }

    private static func defaultURL(for provider: InsuranceProvider) -> URL? {
        switch provider {
        case .oegk: return URL(string: "https://meine.oegk.at/cdscontent/?contentid=10007.883235&portal=oegkportal")
        case .bva: return URL(string: "https://www.bvaeb.at")
        case .merkur: return URL(string: "https://www.merkur.at/")
        }
    }

    private func stored() -> [InsuranceProvider: URL] {
        guard
            let data = userDefaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([String: URL].self, from: data)
        else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            InsuranceProvider(rawValue: key).map { ($0, value) }
        })
    }

    private func save(_ links: [InsuranceProvider: URL]) {
        let encodable = Dictionary(uniqueKeysWithValues: links.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
