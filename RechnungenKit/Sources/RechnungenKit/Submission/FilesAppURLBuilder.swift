import Foundation

public enum FilesAppURLBuilder {
    public static func url(for fileURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "shareddocuments"
        components.path = fileURL.path
        return components.url
    }
}
