import PDFKit
import CoreGraphics
import UIKit

enum PDFFirstPageRenderer {
    static func renderFirstPageAsCGImage(from pdfData: Data) -> CGImage? {
        guard
            let document = PDFDocument(data: pdfData),
            let page = document.page(at: 0)
        else {
            return nil
        }
        let pageRect = page.bounds(for: .mediaBox)
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(pageRect)
            context.cgContext.translateBy(x: 0, y: pageRect.size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        return image.cgImage
    }
}
