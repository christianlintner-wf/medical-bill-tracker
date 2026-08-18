import Foundation

public enum InsuranceTarget: String, CaseIterable, Sendable {
    case oegk
    case merkur

    public var displayName: String {
        switch self {
        case .oegk: return "ÖGK"
        case .merkur: return "Merkur"
        }
    }
}

extension InvoiceStatus {
    public var submissionTarget: InsuranceTarget? {
        switch self {
        case .open, .submittedToPublicInsurance: return .oegk
        case .publicInsuranceCompleted: return .merkur
        case .submittedToPrivateInsurance, .privateInsuranceCompleted, .done: return nil
        }
    }
}
