import XCTest
@testable import RechnungenKit

final class FilesAppURLBuilderTests: XCTestCase {
    func test_url_convertsFileURLToSharedDocumentsScheme() {
        let fileURL = URL(fileURLWithPath: "/private/var/mobile/Containers/Shared/AppGroup/folder/2026/ÖGK")

        let result = FilesAppURLBuilder.url(for: fileURL)

        XCTAssertEqual(result?.scheme, "shareddocuments")
        XCTAssertEqual(result?.path, "/private/var/mobile/Containers/Shared/AppGroup/folder/2026/ÖGK")
    }
}
