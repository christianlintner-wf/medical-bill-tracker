import Foundation

public final class PatientLinksStore: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let storageKey = "submissionPatientLinks"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func links(for patient: Patient) -> PatientLinks {
        allLinks()[patient] ?? PatientLinks()
    }

    public func setLinks(_ links: PatientLinks, for patient: Patient) {
        var all = allLinks()
        all[patient] = links
        save(all)
    }

    private func allLinks() -> [Patient: PatientLinks] {
        guard
            let data = userDefaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([String: PatientLinks].self, from: data)
        else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            Patient(rawValue: key).map { ($0, value) }
        })
    }

    private func save(_ links: [Patient: PatientLinks]) {
        let encodable = Dictionary(uniqueKeysWithValues: links.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
