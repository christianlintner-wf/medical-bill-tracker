import Foundation

public final class PatientInsuranceAssignmentStore: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let storageKey = "patientPublicInsuranceProvider"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func publicProvider(for patient: Patient) -> InsuranceProvider {
        stored()[patient] ?? Self.defaultPublicProvider(for: patient)
    }

    public func setPublicProvider(_ provider: InsuranceProvider, for patient: Patient) {
        var all = stored()
        all[patient] = provider
        save(all)
    }

    private static func defaultPublicProvider(for patient: Patient) -> InsuranceProvider {
        switch patient {
        case .christian, .melanie, .theresa: return .oegk
        case .kathi, .sarah: return .bva
        }
    }

    private func stored() -> [Patient: InsuranceProvider] {
        guard
            let data = userDefaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([String: InsuranceProvider].self, from: data)
        else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            Patient(rawValue: key).map { ($0, value) }
        })
    }

    private func save(_ assignments: [Patient: InsuranceProvider]) {
        let encodable = Dictionary(uniqueKeysWithValues: assignments.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
