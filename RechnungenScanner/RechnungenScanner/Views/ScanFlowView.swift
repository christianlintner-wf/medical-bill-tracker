import SwiftUI

struct ScanFlowView: UIViewControllerRepresentable {
    let onScanned: (Data) -> Void
    let onCancelled: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let scanService = ScanService()
        let hostController = UIViewController()
        context.coordinator.scanService = scanService
        DispatchQueue.main.async {
            scanService.presentScanner(from: hostController) { result in
                switch result {
                case .success(let data):
                    onScanned(data)
                case .failure:
                    onCancelled()
                }
            }
        }
        return hostController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var scanService: ScanService?
    }
}
