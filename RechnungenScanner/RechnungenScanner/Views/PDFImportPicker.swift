import SwiftUI
import UniformTypeIdentifiers

struct PDFImportPicker: UIViewControllerRepresentable {
    let onImported: (Data) -> Void
    let onCancelled: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf])
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImported: onImported, onCancelled: onCancelled)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onImported: (Data) -> Void
        let onCancelled: () -> Void

        init(onImported: @escaping (Data) -> Void, onCancelled: @escaping () -> Void) {
            self.onImported = onImported
            self.onCancelled = onCancelled
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCancelled()
                return
            }
            guard url.startAccessingSecurityScopedResource() else {
                onCancelled()
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else {
                onCancelled()
                return
            }
            onImported(data)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancelled()
        }
    }
}
