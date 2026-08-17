import VisionKit
import UIKit
import PDFKit

public enum ScanServiceError: Error {
    case pdfGenerationFailed
    case cancelled
}

final class ScanService: NSObject {
    typealias Completion = (Result<Data, Error>) -> Void

    private var completion: Completion?

    func presentScanner(from viewController: UIViewController, completion: @escaping Completion) {
        self.completion = completion
        let scannerViewController = VNDocumentCameraViewController()
        scannerViewController.delegate = self
        viewController.present(scannerViewController, animated: true)
    }
}

extension ScanService: VNDocumentCameraViewControllerDelegate {
    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        controller.dismiss(animated: true)
        let pdfDocument = PDFDocument()
        for pageIndex in 0..<scan.pageCount {
            let image = scan.imageOfPage(at: pageIndex)
            if let pdfPage = PDFPage(image: image) {
                pdfDocument.insert(pdfPage, at: pdfDocument.pageCount)
            }
        }
        guard let data = pdfDocument.dataRepresentation() else {
            completion?(.failure(ScanServiceError.pdfGenerationFailed))
            completion = nil
            return
        }
        completion?(.success(data))
        completion = nil
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
        completion?(.failure(ScanServiceError.cancelled))
        completion = nil
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        controller.dismiss(animated: true)
        completion?(.failure(error))
        completion = nil
    }
}
