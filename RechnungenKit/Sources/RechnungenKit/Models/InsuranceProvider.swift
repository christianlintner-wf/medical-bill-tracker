public enum InsuranceCategory: Sendable {
    case publicInsurance
    case privateInsurance
}

public enum InsuranceProvider: String, Codable, CaseIterable, Sendable {
    case oegk
    case bva
    case merkur

    public var displayName: String {
        switch self {
        case .oegk: return "ÖGK"
        case .bva: return "BVA"
        case .merkur: return "Merkur"
        }
    }

    public var category: InsuranceCategory {
        switch self {
        case .oegk, .bva: return .publicInsurance
        case .merkur: return .privateInsurance
        }
    }
}

public enum SubmissionPhase: Sendable, Equatable {
    case publicInsurance
    case privateInsurance
}

extension InvoiceStatus {
    public var submissionPhase: SubmissionPhase? {
        switch self {
        case .open, .submittedToPublicInsurance: return .publicInsurance
        case .publicInsuranceCompleted: return .privateInsurance
        case .submittedToPrivateInsurance, .privateInsuranceCompleted, .done: return nil
        }
    }
}
