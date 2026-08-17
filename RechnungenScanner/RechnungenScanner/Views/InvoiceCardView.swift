import SwiftUI
import RechnungenKit

struct InvoiceCardView: View {
    let invoice: Invoice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(invoice.invoiceNumber).font(.headline)
            Text(invoice.amount, format: .currency(code: "EUR"))
            if let providerName = invoice.providerName {
                Text(providerName).font(.caption).foregroundStyle(.secondary)
            }
            Text(invoice.patient.rawValue)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.2)))
            if invoice.remoteRowID == nil {
                Label("Wartet auf Sync", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 1))
    }
}
