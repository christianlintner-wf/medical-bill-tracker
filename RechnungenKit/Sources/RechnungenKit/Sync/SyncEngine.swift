import Foundation

public enum SyncError: Error, Equatable {
    case dependencyNotReady
}

public actor SyncEngine {
    private let apiClient: SeaTableAPIClientProtocol
    private let localStore: LocalStore
    private let fileStorage: LocalFileStorage

    public init(apiClient: SeaTableAPIClientProtocol, localStore: LocalStore, fileStorage: LocalFileStorage) {
        self.apiClient = apiClient
        self.localStore = localStore
        self.fileStorage = fileStorage
    }

    public func processOutbox() async {
        guard let entries = try? await localStore.pendingOutboxEntries() else { return }
        for entry in entries.reversed() {
            await process(entry: entry)
        }
    }

    private func process(entry: OutboxEntryEntity) async {
        do {
            switch OutboxOperation(rawValue: entry.operationRawValue) {
            case .createProvider:
                try await syncCreateProvider(localID: entry.targetLocalID)
            case .createInvoice:
                try await syncCreateInvoice(localID: entry.targetLocalID)
            case .updateInvoiceStatus:
                try await syncUpdateStatus(localID: entry.targetLocalID)
            case .uploadInvoiceFile:
                try await syncUploadFile(localID: entry.targetLocalID)
            case .none:
                break
            }
            try await localStore.removeOutboxEntry(id: entry.id)
        } catch {
            try? await localStore.recordOutboxFailure(id: entry.id, error: String(describing: error))
        }
    }

    private func syncCreateProvider(localID: UUID) async throws {
        guard let provider = try await localStore.provider(byLocalID: localID), provider.remoteRowID == nil else { return }
        let rowID = try await apiClient.createRow(table: "Arzt", fields: ["Arztname": .string(provider.name)])
        try await localStore.setProviderRemoteRowID(localID: localID, remoteRowID: rowID)
    }

    private func syncCreateInvoice(localID: UUID) async throws {
        guard let invoice = try await localStore.invoice(byLocalID: localID), invoice.remoteRowID == nil else { return }

        var providerRemoteRowID = invoice.providerRemoteRowID
        if providerRemoteRowID == nil, let providerID = invoice.providerID {
            providerRemoteRowID = try await localStore.provider(byLocalID: providerID)?.remoteRowID
            guard providerRemoteRowID != nil else {
                throw SyncError.dependencyNotReady
            }
        }

        var fields: [String: SeaTableValue] = [
            "Rechnungsnummer": .string(invoice.invoiceNumber),
            "Betrag": .number((invoice.amount as NSDecimalNumber).doubleValue),
            "Patient": .string(invoice.patient.rawValue),
            "Status": .string(invoice.status.rawValue)
        ]
        if let providerRemoteRowID {
            fields["Arzt"] = .stringArray([providerRemoteRowID])
        }
        let rowID = try await apiClient.createRow(table: "Arztrechnungen", fields: fields)
        try await localStore.setInvoiceRemoteRowID(localID: localID, remoteRowID: rowID)
    }

    private func syncUpdateStatus(localID: UUID) async throws {
        guard
            let invoice = try await localStore.invoice(byLocalID: localID),
            let remoteRowID = invoice.remoteRowID
        else {
            throw SyncError.dependencyNotReady
        }
        try await apiClient.updateRow(
            table: "Arztrechnungen",
            rowID: remoteRowID,
            fields: ["Status": .string(invoice.status.rawValue)]
        )
    }

    private func syncUploadFile(localID: UUID) async throws {
        guard
            let invoice = try await localStore.invoice(byLocalID: localID),
            let remoteRowID = invoice.remoteRowID,
            let fileName = invoice.localPDFFileName
        else {
            throw SyncError.dependencyNotReady
        }
        let data = try fileStorage.read(fileName: fileName)
        let uploaded = try await apiClient.uploadFile(data: data, fileName: fileName)
        try await apiClient.updateRow(
            table: "Arztrechnungen",
            rowID: remoteRowID,
            fields: ["Arztrechnung": .stringArray([uploaded.url])]
        )
        try await localStore.setInvoiceRemoteFileURL(localID: localID, url: uploaded.url)
    }
}
