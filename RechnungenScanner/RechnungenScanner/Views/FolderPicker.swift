import SwiftUI
import UniformTypeIdentifiers

struct FolderPicker: UIViewControllerRepresentable {
    let onPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (URL) -> Void

        init(onPicked: @escaping (URL) -> Void) {
            self.onPicked = onPicked
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            onPicked(url)
        }
    }
}
