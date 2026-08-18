import SwiftData
import Foundation

@ModelActor
public actor LocalStore {
    public func upsertProvider(_ provider: Provider) throws {
        let targetID = provider.id
        let descriptor = FetchDescriptor<ProviderEntity>(predicate: #Predicate { $0.id == targetID })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.remoteRowID = provider.remoteRowID
            existing.name = provider.name
        } else {
            modelContext.insert(ProviderEntity(id: provider.id, remoteRowID: provider.remoteRowID, name: provider.name))
        }
        try modelContext.save()
    }

    public func allProviders() throws -> [Provider] {
        try modelContext.fetch(FetchDescriptor<ProviderEntity>()).map {
            Provider(id: $0.id, remoteRowID: $0.remoteRowID, name: $0.name)
        }
    }

    public func provider(byLocalID id: UUID) throws -> Provider? {
        let descriptor = FetchDescriptor<ProviderEntity>(predicate: #Predicate { $0.id == id })
        guard let entity = try modelContext.fetch(descriptor).first else { return nil }
        return Provider(id: entity.id, remoteRowID: entity.remoteRowID, name: entity.name)
    }

    public func upsertProviderByRemoteID(remoteRowID: String, name: String) throws {
        let descriptor = FetchDescriptor<ProviderEntity>(predicate: #Predicate { $0.remoteRowID == remoteRowID })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.name = name
        } else {
            modelContext.insert(ProviderEntity(remoteRowID: remoteRowID, name: name))
        }
        try modelContext.save()
    }

    public func setProviderRemoteRowID(localID: UUID, remoteRowID: String) throws {
        let descriptor = FetchDescriptor<ProviderEntity>(predicate: #Predicate { $0.id == localID })
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        entity.remoteRowID = remoteRowID
        try modelContext.save()

        let invoiceDescriptor = FetchDescriptor<InvoiceEntity>(predicate: #Predicate { $0.providerID == localID })
        for invoice in try modelContext.fetch(invoiceDescriptor) {
            invoice.providerRemoteRowID = remoteRowID
        }
        try modelContext.save()
    }

    public func upsertInvoice(_ invoice: Invoice) throws {
        let targetID = invoice.id
        let descriptor = FetchDescriptor<InvoiceEntity>(predicate: #Predicate { $0.id == targetID })
        if let existing = try modelContext.fetch(descriptor).first {
            apply(invoice, to: existing)
        } else {
            modelContext.insert(makeEntity(from: invoice))
        }
        try modelContext.save()
    }

    public func allInvoices() throws -> [Invoice] {
        try modelContext.fetch(FetchDescriptor<InvoiceEntity>()).map { try makeInvoice(from: $0) }
    }

    public func invoice(byLocalID id: UUID) throws -> Invoice? {
        let descriptor = FetchDescriptor<InvoiceEntity>(predicate: #Predicate { $0.id == id })
        guard let entity = try modelContext.fetch(descriptor).first else { return nil }
        return try makeInvoice(from: entity)
    }

    public func upsertInvoiceByRemoteID(row: SeaTableRow) throws {
        let remoteID = row.id
        let invoiceNumber = row.fields["Rechnungsnummer"].stringValue ?? ""
        let amount = row.fields["Betrag"].numberValue ?? 0
        let patientRaw = row.fields["Patient"].stringValue ?? Patient.christian.rawValue
        let statusRaw = row.fields["Status"].stringValue ?? InvoiceStatus.open.rawValue
        let providerLinkIDs = row.fields["Arzt"].stringArrayValue ?? []
        let providerRemoteRowID = providerLinkIDs.first
        let date = row.fields["Datum"].stringValue.flatMap(SeaTableDateFormatter.date(from:))

        var providerLocalID: UUID?
        if let providerRemoteRowID {
            let providerDescriptor = FetchDescriptor<ProviderEntity>(predicate: #Predicate { $0.remoteRowID == providerRemoteRowID })
            providerLocalID = try modelContext.fetch(providerDescriptor).first?.id
        }

        let descriptor = FetchDescriptor<InvoiceEntity>(predicate: #Predicate { $0.remoteRowID == remoteID })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.invoiceNumber = invoiceNumber
            existing.amount = Decimal(amount)
            existing.patientRawValue = patientRaw
            if try !hasPendingOutboxEntry(targetLocalID: existing.id, operation: .updateInvoiceStatus) {
                existing.statusRawValue = statusRaw
            }
            existing.providerID = providerLocalID
            existing.providerRemoteRowID = providerRemoteRowID
            let dateSyncPending = try hasPendingOutboxEntry(targetLocalID: existing.id, operation: .updateInvoiceDate)
            print("[DEBUG] upsertInvoiceByRemoteID: remoteID=\(remoteID) remoteDatumField=\(String(describing: row.fields["Datum"])) parsedDate=\(String(describing: date)) currentLocalDate=\(String(describing: existing.date)) dateSyncPending=\(dateSyncPending)")
            if !dateSyncPending {
                existing.date = date
            }
        } else {
            modelContext.insert(InvoiceEntity(
                remoteRowID: remoteID,
                invoiceNumber: invoiceNumber,
                amount: Decimal(amount),
                date: date,
                patientRawValue: patientRaw,
                providerID: providerLocalID,
                providerRemoteRowID: providerRemoteRowID,
                statusRawValue: statusRaw
            ))
        }
        try modelContext.save()
    }

    public func updateInvoiceStatus(id: UUID, status: InvoiceStatus) throws {
        let descriptor = FetchDescriptor<InvoiceEntity>(predicate: #Predicate { $0.id == id })
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        entity.statusRawValue = status.rawValue
        try modelContext.save()
    }

    public func updateInvoiceDate(id: UUID, date: Date) throws {
        let descriptor = FetchDescriptor<InvoiceEntity>(predicate: #Predicate { $0.id == id })
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        entity.date = date
        try modelContext.save()
    }

    public func setInvoiceRemoteRowID(localID: UUID, remoteRowID: String) throws {
        let descriptor = FetchDescriptor<InvoiceEntity>(predicate: #Predicate { $0.id == localID })
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        entity.remoteRowID = remoteRowID
        try modelContext.save()
    }

    public func setInvoiceRemoteFileURL(localID: UUID, url: String) throws {
        let descriptor = FetchDescriptor<InvoiceEntity>(predicate: #Predicate { $0.id == localID })
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        entity.remoteFileURL = url
        try modelContext.save()
    }

    public func enqueueOutboxEntry(operation: OutboxOperation, targetLocalID: UUID) throws {
        modelContext.insert(OutboxEntryEntity(operationRawValue: operation.rawValue, targetLocalID: targetLocalID))
        try modelContext.save()
    }

    public func pendingOutboxEntries() throws -> [OutboxEntryEntity] {
        try modelContext.fetch(FetchDescriptor<OutboxEntryEntity>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    public func hasPendingOutboxEntry(targetLocalID: UUID, operation: OutboxOperation) throws -> Bool {
        let opRaw = operation.rawValue
        let descriptor = FetchDescriptor<OutboxEntryEntity>(
            predicate: #Predicate { $0.targetLocalID == targetLocalID && $0.operationRawValue == opRaw }
        )
        return try !modelContext.fetch(descriptor).isEmpty
    }

    public func hasAnyPendingOutboxEntry(targetLocalID: UUID) throws -> Bool {
        let descriptor = FetchDescriptor<OutboxEntryEntity>(predicate: #Predicate { $0.targetLocalID == targetLocalID })
        return try !modelContext.fetch(descriptor).isEmpty
    }

    public func removeOutboxEntry(id: UUID) throws {
        let descriptor = FetchDescriptor<OutboxEntryEntity>(predicate: #Predicate { $0.id == id })
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        modelContext.delete(entity)
        try modelContext.save()
    }

    public func pruneInvoices(keepingRemoteRowIDs remoteRowIDs: Set<String>) throws {
        let syncedInvoices = try modelContext.fetch(FetchDescriptor<InvoiceEntity>()).filter { $0.remoteRowID != nil }
        guard !(remoteRowIDs.isEmpty && !syncedInvoices.isEmpty) else { return }

        let staleInvoices = syncedInvoices.filter { !remoteRowIDs.contains($0.remoteRowID!) }
        guard !staleInvoices.isEmpty else { return }
        for invoice in staleInvoices {
            try deleteOutboxEntries(targetLocalID: invoice.id)
            modelContext.delete(invoice)
        }
        try modelContext.save()
    }

    public func pruneProviders(keepingRemoteRowIDs remoteRowIDs: Set<String>) throws {
        let syncedProviders = try modelContext.fetch(FetchDescriptor<ProviderEntity>()).filter { $0.remoteRowID != nil }
        guard !(remoteRowIDs.isEmpty && !syncedProviders.isEmpty) else { return }

        let staleProviders = syncedProviders.filter { !remoteRowIDs.contains($0.remoteRowID!) }
        guard !staleProviders.isEmpty else { return }
        for provider in staleProviders {
            modelContext.delete(provider)
        }
        try modelContext.save()
    }

    private func deleteOutboxEntries(targetLocalID: UUID) throws {
        let descriptor = FetchDescriptor<OutboxEntryEntity>(predicate: #Predicate { $0.targetLocalID == targetLocalID })
        for entry in try modelContext.fetch(descriptor) {
            modelContext.delete(entry)
        }
    }

    public func recordOutboxFailure(id: UUID, error: String) throws {
        let descriptor = FetchDescriptor<OutboxEntryEntity>(predicate: #Predicate { $0.id == id })
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        entity.attemptCount += 1
        entity.lastAttemptAt = Date()
        entity.lastErrorDescription = error
        try modelContext.save()
    }

    public func upsertFinding(_ finding: Finding) throws {
        let targetID = finding.id
        let descriptor = FetchDescriptor<FindingEntity>(predicate: #Predicate { $0.id == targetID })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.remoteRowID = finding.remoteRowID
            existing.invoiceID = finding.invoiceID
            existing.invoiceRemoteRowID = finding.invoiceRemoteRowID
            existing.localPDFFileName = finding.localPDFFileName
            existing.remoteFileURL = finding.remoteFileURL
        } else {
            modelContext.insert(FindingEntity(
                id: finding.id,
                remoteRowID: finding.remoteRowID,
                invoiceID: finding.invoiceID,
                invoiceRemoteRowID: finding.invoiceRemoteRowID,
                localPDFFileName: finding.localPDFFileName,
                remoteFileURL: finding.remoteFileURL
            ))
        }
        try modelContext.save()
    }

    public func finding(byLocalID id: UUID) throws -> Finding? {
        let descriptor = FetchDescriptor<FindingEntity>(predicate: #Predicate { $0.id == id })
        guard let entity = try modelContext.fetch(descriptor).first else { return nil }
        return Finding(
            id: entity.id,
            remoteRowID: entity.remoteRowID,
            invoiceID: entity.invoiceID,
            invoiceRemoteRowID: entity.invoiceRemoteRowID,
            localPDFFileName: entity.localPDFFileName,
            remoteFileURL: entity.remoteFileURL
        )
    }

    public func finding(forInvoiceID invoiceID: UUID) throws -> Finding? {
        let descriptor = FetchDescriptor<FindingEntity>(predicate: #Predicate { $0.invoiceID == invoiceID })
        guard let entity = try modelContext.fetch(descriptor).first else { return nil }
        return Finding(
            id: entity.id,
            remoteRowID: entity.remoteRowID,
            invoiceID: entity.invoiceID,
            invoiceRemoteRowID: entity.invoiceRemoteRowID,
            localPDFFileName: entity.localPDFFileName,
            remoteFileURL: entity.remoteFileURL
        )
    }

    public func setFindingRemoteRowID(localID: UUID, remoteRowID: String) throws {
        let descriptor = FetchDescriptor<FindingEntity>(predicate: #Predicate { $0.id == localID })
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        entity.remoteRowID = remoteRowID
        try modelContext.save()
    }

    public func setFindingRemoteFileURL(localID: UUID, url: String) throws {
        let descriptor = FetchDescriptor<FindingEntity>(predicate: #Predicate { $0.id == localID })
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        entity.remoteFileURL = url
        try modelContext.save()
    }

    private func makeEntity(from invoice: Invoice) -> InvoiceEntity {
        InvoiceEntity(
            id: invoice.id,
            remoteRowID: invoice.remoteRowID,
            invoiceNumber: invoice.invoiceNumber,
            amount: invoice.amount,
            date: invoice.date,
            patientRawValue: invoice.patient.rawValue,
            providerID: invoice.providerID,
            providerRemoteRowID: invoice.providerRemoteRowID,
            providerName: invoice.providerName,
            statusRawValue: invoice.status.rawValue,
            localPDFFileName: invoice.localPDFFileName,
            remoteFileURL: invoice.remoteFileURL
        )
    }

    private func apply(_ invoice: Invoice, to entity: InvoiceEntity) {
        entity.remoteRowID = invoice.remoteRowID
        entity.invoiceNumber = invoice.invoiceNumber
        entity.amount = invoice.amount
        entity.date = invoice.date
        entity.patientRawValue = invoice.patient.rawValue
        entity.providerID = invoice.providerID
        entity.providerRemoteRowID = invoice.providerRemoteRowID
        entity.providerName = invoice.providerName
        entity.statusRawValue = invoice.status.rawValue
        entity.localPDFFileName = invoice.localPDFFileName
        entity.remoteFileURL = invoice.remoteFileURL
    }

    private func makeInvoice(from entity: InvoiceEntity) throws -> Invoice {
        var resolvedProviderName = entity.providerName
        if resolvedProviderName == nil, let providerID = entity.providerID {
            let providerDescriptor = FetchDescriptor<ProviderEntity>(predicate: #Predicate { $0.id == providerID })
            resolvedProviderName = try modelContext.fetch(providerDescriptor).first?.name
        }
        let entityID = entity.id
        let hasPending = try entity.remoteRowID == nil || hasAnyPendingOutboxEntry(targetLocalID: entityID)
        return Invoice(
            id: entity.id,
            remoteRowID: entity.remoteRowID,
            invoiceNumber: entity.invoiceNumber,
            amount: entity.amount,
            date: entity.date,
            patient: Patient(rawValue: entity.patientRawValue) ?? .christian,
            providerID: entity.providerID,
            providerRemoteRowID: entity.providerRemoteRowID,
            providerName: resolvedProviderName,
            status: InvoiceStatus(rawValue: entity.statusRawValue) ?? .open,
            localPDFFileName: entity.localPDFFileName,
            remoteFileURL: entity.remoteFileURL,
            hasPendingSync: hasPending
        )
    }
}
