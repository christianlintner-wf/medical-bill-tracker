import SwiftUI
import RechnungenKit
import UIKit

@main
struct RechnungenScannerApp: App {
    @State private var root = CompositionRoot()
    private let bookmarkStore = SubmissionFolderBookmarkStore()
    private let providerLinksStore = InsuranceProviderLinksStore()
    private let patientInsuranceStore = PatientInsuranceAssignmentStore()

    var body: some Scene {
        WindowGroup {
            if let services = root.services {
                RootView(
                    repository: services.repository,
                    syncEngine: services.syncEngine,
                    exportService: SubmissionExportService(fileStorage: services.fileStorage, bookmarkStore: bookmarkStore),
                    providerLinksStore: providerLinksStore,
                    patientInsuranceStore: patientInsuranceStore,
                    bookmarkStore: bookmarkStore,
                    onReload: { root.reload() }
                )
                .id(ObjectIdentifier(services.syncEngine))
            } else {
                SettingsView(
                    keychainService: KeychainService(),
                    bookmarkStore: bookmarkStore,
                    providerLinksStore: providerLinksStore,
                    patientInsuranceStore: patientInsuranceStore,
                    onSaved: { root.reload() }
                )
            }
        }
    }
}

private struct RootView: View {
    let repository: InvoiceRepositoryProtocol
    let syncEngine: SyncEngine
    let exportService: SubmissionExportService
    let providerLinksStore: InsuranceProviderLinksStore
    let patientInsuranceStore: PatientInsuranceAssignmentStore
    let bookmarkStore: SubmissionFolderBookmarkStore
    let onReload: () -> Void

    @State private var boardViewModel: InvoiceBoardViewModel
    @State private var scanFlowStep: ScanFlowStep?
    @State private var selectedInvoice: Invoice?
    @State private var isShowingSettings = false
    @State private var lastSyncError: String?
    @Environment(\.scenePhase) private var scenePhase

    private enum ScanFlowStep: Identifiable {
        case scanning
        case reviewing(Data)

        var id: String {
            switch self {
            case .scanning: return "scanning"
            case .reviewing: return "reviewing"
            }
        }
    }

    init(
        repository: InvoiceRepositoryProtocol,
        syncEngine: SyncEngine,
        exportService: SubmissionExportService,
        providerLinksStore: InsuranceProviderLinksStore,
        patientInsuranceStore: PatientInsuranceAssignmentStore,
        bookmarkStore: SubmissionFolderBookmarkStore,
        onReload: @escaping () -> Void
    ) {
        self.repository = repository
        self.syncEngine = syncEngine
        self.exportService = exportService
        self.providerLinksStore = providerLinksStore
        self.patientInsuranceStore = patientInsuranceStore
        self.bookmarkStore = bookmarkStore
        self.onReload = onReload
        _boardViewModel = State(initialValue: InvoiceBoardViewModel(repository: repository))
    }

    var body: some View {
        InvoiceBoardView(
            viewModel: boardViewModel,
            onSelectInvoice: { selectedInvoice = $0 },
            onAddInvoice: { scanFlowStep = .scanning },
            onShowSettings: { isShowingSettings = true },
            onInvoiceMoved: { Task { await syncAndReload() } }
        )
        .sheet(item: $scanFlowStep) { step in
            Group {
                switch step {
                case .scanning:
                    ScanFlowView(
                        onScanned: { data in scanFlowStep = .reviewing(data) },
                        onCancelled: { scanFlowStep = nil }
                    )
                case .reviewing(let pdfData):
                    ScanReviewFlow(
                        pdfData: pdfData,
                        repository: repository,
                        onSaved: {
                            scanFlowStep = nil
                            Task { await syncAndReload() }
                        }
                    )
                }
            }
            .iPadFullHeightSheet()
        }
        .sheet(item: $selectedInvoice) { invoice in
            NavigationStack {
                InvoiceDetailView(
                    viewModel: InvoiceEditViewModel(
                        invoice: invoice,
                        repository: repository,
                        exportService: exportService,
                        providerLinksStore: providerLinksStore,
                        patientInsuranceStore: patientInsuranceStore
                    )
                )
            }
            .iPadFullHeightSheet()
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(
                keychainService: KeychainService(),
                bookmarkStore: bookmarkStore,
                providerLinksStore: providerLinksStore,
                patientInsuranceStore: patientInsuranceStore,
                onSaved: {
                    isShowingSettings = false
                    onReload()
                },
                syncErrorMessage: lastSyncError
            )
            .iPadFullHeightSheet()
        }
        .task { await syncAndReload() }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await syncAndReload() }
        }
    }

    private func syncAndReload() async {
        await syncEngine.processOutbox()
        await boardViewModel.load()
        lastSyncError = await syncEngine.lastOutboxError()
    }
}

extension View {
    /// Forces a `.sheet` to present at full height on iPad (matching iPhone's
    /// default), while keeping the native swipe-to-dismiss gesture intact.
    /// No-op on iPhone.
    @ViewBuilder
    func iPadFullHeightSheet() -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.presentationDetents([.large])
        } else {
            self
        }
    }
}

private struct ScanReviewFlow: View {
    let pdfData: Data
    let repository: InvoiceRepositoryProtocol
    let onSaved: () -> Void

    @State private var scanViewModel: ScanViewModel
    @State private var providerPickerViewModel: ProviderPickerViewModel

    init(pdfData: Data, repository: InvoiceRepositoryProtocol, onSaved: @escaping () -> Void) {
        self.pdfData = pdfData
        self.repository = repository
        self.onSaved = onSaved
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileStorage = LocalFileStorage(directory: documentsURL.appendingPathComponent("Scans"))
        _scanViewModel = State(initialValue: ScanViewModel(repository: repository, fileStorage: fileStorage))
        _providerPickerViewModel = State(initialValue: ProviderPickerViewModel(repository: repository))
    }

    var body: some View {
        NavigationStack {
            InvoiceFormView(
                viewModel: scanViewModel,
                providerPickerViewModel: providerPickerViewModel,
                pdfData: pdfData,
                onSaved: onSaved
            )
        }
        .task {
            await providerPickerViewModel.load()
            if let cgImage = PDFFirstPageRenderer.renderFirstPageAsCGImage(from: pdfData) {
                let lines = try? await TextRecognizer().recognizeLines(in: cgImage)
                scanViewModel.applyExtractedFields(InvoiceFieldExtractor().extract(from: lines ?? []))
            }
        }
    }
}
