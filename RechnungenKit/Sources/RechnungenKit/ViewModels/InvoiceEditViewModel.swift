import Observation
import Foundation

@Observable
public final class InvoiceEditViewModel {
    public var invoice: Invoice
    public var finding: Finding?
    public var errorMessage: String?
    public var exportMessage: String?
    public private(set) var didDelete = false

    private let repository: InvoiceRepositoryProtocol
    private let exportService: SubmissionExportService
    private let providerLinksStore: InsuranceProviderLinksStore
    private let patientInsuranceStore: PatientInsuranceAssignmentStore

    public init(
        invoice: Invoice,
        repository: InvoiceRepositoryProtocol,
        exportService: SubmissionExportService,
        providerLinksStore: InsuranceProviderLinksStore,
        patientInsuranceStore: PatientInsuranceAssignmentStore
    ) {
        self.invoice = invoice
        self.repository = repository
        self.exportService = exportService
        self.providerLinksStore = providerLinksStore
        self.patientInsuranceStore = patientInsuranceStore
    }

    public var submissionTarget: InsuranceProvider? {
        switch invoice.status.submissionPhase {
        case .publicInsurance: return patientInsuranceStore.publicProvider(for: invoice.patient)
        case .privateInsurance: return .merkur
        case nil: return nil
        }
    }

    public func updateStatus(_ newStatus: InvoiceStatus) async {
        invoice.status = newStatus
        do {
            try await repository.updateStatus(invoiceID: invoice.id, newStatus: newStatus)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func updateDate(_ newDate: Date) async {
        invoice.date = newDate
        do {
            try await repository.updateDate(invoiceID: invoice.id, newDate: newDate)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func delete() async {
        guard invoice.status == .open else {
            errorMessage = "Nur offene Rechnungen können gelöscht werden."
            return
        }
        do {
            try await repository.deleteInvoice(invoiceID: invoice.id)
            didDelete = true
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func loadFinding() async {
        finding = try? await repository.finding(forInvoiceID: invoice.id)
    }

    public func exportForSubmission() {
        guard let target = submissionTarget else { return }
        do {
            _ = try exportService.export(invoice: invoice, finding: finding)
            exportMessage = "Dateien für \(target.displayName) vorbereitet."
            errorMessage = nil
        } catch {
            errorMessage = Self.describeExportError(error)
            exportMessage = nil
        }
    }

    public func openSubmissionFolder() -> URL? {
        guard submissionTarget != nil else { return nil }
        do {
            let destination = try exportService.destinationFolder(for: invoice)
            errorMessage = nil
            return FilesAppURLBuilder.url(for: destination)
        } catch {
            errorMessage = Self.describeExportError(error)
            return nil
        }
    }

    public func portalURL() -> URL? {
        guard let target = submissionTarget else { return nil }
        return providerLinksStore.url(for: target)
    }

    private static func describeExportError(_ error: Error) -> String {
        switch error {
        case SubmissionExportService.ExportError.missingDate:
            return "Bitte zuerst ein Rechnungsdatum ergänzen."
        case SubmissionExportService.ExportError.missingInvoiceFile:
            return "Keine gescannte Rechnung vorhanden."
        case SubmissionFolderBookmarkStore.ResolveError.notConfigured:
            return "Bitte zuerst einen Einreichungs-Ordner in den Einstellungen wählen."
        case SubmissionFolderBookmarkStore.ResolveError.bookmarkStale, SubmissionFolderBookmarkStore.ResolveError.accessDenied:
            return "Zugriff auf den Einreichungs-Ordner verloren - bitte in den Einstellungen neu wählen."
        default:
            return String(describing: error)
        }
    }
}
