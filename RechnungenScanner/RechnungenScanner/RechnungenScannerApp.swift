import SwiftUI
import RechnungenKit

@main
struct RechnungenScannerApp: App {
    @State private var root = CompositionRoot()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if let services = root.services {
                RootView(repository: services.repository, syncEngine: services.syncEngine)
            } else {
                SettingsView(keychainService: KeychainService(), onSaved: { root.reload() })
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, let syncEngine = root.services?.syncEngine else { return }
            Task { await syncEngine.processOutbox() }
        }
    }
}

private struct RootView: View {
    let repository: InvoiceRepositoryProtocol
    let syncEngine: SyncEngine

    @State private var boardViewModel: InvoiceBoardViewModel
    @State private var scanFlowStep: ScanFlowStep?
    @State private var selectedInvoice: Invoice?

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

    init(repository: InvoiceRepositoryProtocol, syncEngine: SyncEngine) {
        self.repository = repository
        self.syncEngine = syncEngine
        _boardViewModel = State(initialValue: InvoiceBoardViewModel(repository: repository))
    }

    var body: some View {
        InvoiceBoardView(
            viewModel: boardViewModel,
            onSelectInvoice: { selectedInvoice = $0 },
            onAddInvoice: { scanFlowStep = .scanning }
        )
        .sheet(item: $scanFlowStep) { step in
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
                        Task {
                            await syncEngine.processOutbox()
                            await boardViewModel.load()
                        }
                    }
                )
            }
        }
        .sheet(item: $selectedInvoice) { invoice in
            NavigationStack {
                InvoiceDetailView(viewModel: InvoiceEditViewModel(invoice: invoice, repository: repository))
            }
        }
        .task { await syncEngine.processOutbox() }
    }
}

private struct ScanReviewFlow: View {
    let pdfData: Data
    let repository: InvoiceRepositoryProtocol
    let onSaved: () -> Void

    @State private var scanViewModel: ScanViewModel
    @State private var providerPickerViewModel: ProviderPickerViewModel
    @State private var extractedFields: ExtractedInvoiceFields?

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
                providers: providerPickerViewModel.providers,
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
