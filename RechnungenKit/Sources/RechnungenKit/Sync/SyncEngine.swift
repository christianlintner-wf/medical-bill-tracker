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
        for entry in entries {
            await process(entry: entry)
        }
    }

    public func lastOutboxError() async -> String? {
        guard let entries = try? await localStore.pendingOutboxEntries() else { return nil }
        return entries.compactMap(\.lastErrorDescription).first
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
            case .createFinding:
                try await syncCreateFinding(localID: entry.targetLocalID)
            case .uploadFindingFile:
                try await syncUploadFindingFile(localID: entry.targetLocalID)
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
        if let date = invoice.date {
            fields["Datum"] = .string(SeaTableDateFormatter.string(from: date))
        }
        let rowID = try await apiClient.createRow(table: "Arztrechnungen", fields: fields)
        // SeaTable silently drops values written to link columns through createRow/updateRow
        // (verified against the real API) - the link must be set via the dedicated links endpoint.
        if let providerRemoteRowID {
            try await apiClient.addLink(table: "Arztrechnungen", column: "Arzt", rowID: rowID, otherRowID: providerRemoteRowID)
        }
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
            fields: ["Arztrechnung": .fileArray([SeaTableFileValue(name: uploaded.name, size: uploaded.size, url: uploaded.url)])]
        )
        try await localStore.setInvoiceRemoteFileURL(localID: localID, url: uploaded.url)
    }

    private func syncCreateFinding(localID: UUID) async throws {
        guard let finding = try await localStore.finding(byLocalID: localID), finding.remoteRowID == nil else { return }

        let resolvedInvoiceRemoteRowID: String?
        if let invoiceRemoteRowID = finding.invoiceRemoteRowID {
            resolvedInvoiceRemoteRowID = invoiceRemoteRowID
        } else {
            resolvedInvoiceRemoteRowID = try await localStore.invoice(byLocalID: finding.invoiceID)?.remoteRowID
        }
        guard let invoiceRemoteRowID = resolvedInvoiceRemoteRowID else {
            throw SyncError.dependencyNotReady
        }

        let rowID = try await apiClient.createRow(table: "Befunde", fields: [:])
        // Same as the Arzt link on Arztrechnungen: SeaTable drops link values written through
        // createRow/updateRow, so the Befunde<->Arztrechnungen link must go through addLink.
        try await apiClient.addLink(table: "Arztrechnungen", column: "Befunde", rowID: invoiceRemoteRowID, otherRowID: rowID)
        try await localStore.setFindingRemoteRowID(localID: localID, remoteRowID: rowID)
    }

    private func syncUploadFindingFile(localID: UUID) async throws {
        guard
            let finding = try await localStore.finding(byLocalID: localID),
            let remoteRowID = finding.remoteRowID,
            let fileName = finding.localPDFFileName
        else {
            throw SyncError.dependencyNotReady
        }
        let data = try fileStorage.read(fileName: fileName)
        let uploaded = try await apiClient.uploadFile(data: data, fileName: fileName)
        try await apiClient.updateRow(
            table: "Befunde",
            rowID: remoteRowID,
            fields: ["Befund": .fileArray([SeaTableFileValue(name: uploaded.name, size: uploaded.size, url: uploaded.url)])]
        )
        try await localStore.setFindingRemoteFileURL(localID: localID, url: uploaded.url)
    }
}
