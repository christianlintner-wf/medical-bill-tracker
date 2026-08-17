public enum InvoiceStatus: String, Codable, CaseIterable, Sendable, Comparable, Hashable {
    case open = "Offen"
    case submittedToPublicInsurance = "Krankenkasse eingereicht"
    case publicInsuranceCompleted = "Krankenkasse abgeschlossen"
    case submittedToPrivateInsurance = "Merkur eingereicht"
    case privateInsuranceCompleted = "Merkur abgeschlossen"
    case done = "Erledigt"

    public static func < (lhs: InvoiceStatus, rhs: InvoiceStatus) -> Bool {
        (Self.allCases.firstIndex(of: lhs) ?? 0) < (Self.allCases.firstIndex(of: rhs) ?? 0)
    }
}
