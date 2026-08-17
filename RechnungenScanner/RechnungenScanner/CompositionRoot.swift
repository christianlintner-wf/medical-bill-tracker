import Observation
import SwiftData
import RechnungenKit
import Foundation

@Observable
final class CompositionRoot {
    struct Services {
        let repository: InvoiceRepositoryProtocol
        let syncEngine: SyncEngine
    }

    private(set) var services: Services?

    init() {
        reload()
    }

    func reload() {
        guard let token = (try? KeychainService().readAPIToken()) ?? nil, !token.isEmpty else {
            services = nil
            return
        }

        let apiClient = SeaTableAPIClient(configuration: .init(apiToken: token))
        let container = try! ModelContainer(for: ProviderEntity.self, InvoiceEntity.self, OutboxEntryEntity.self)
        let localStore = LocalStore(modelContainer: container)
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileStorage = LocalFileStorage(directory: documentsURL.appendingPathComponent("Scans"))
        let repository = SeaTableInvoiceRepository(apiClient: apiClient, localStore: localStore)
        let syncEngine = SyncEngine(apiClient: apiClient, localStore: localStore, fileStorage: fileStorage)
        services = Services(repository: repository, syncEngine: syncEngine)
    }
}
