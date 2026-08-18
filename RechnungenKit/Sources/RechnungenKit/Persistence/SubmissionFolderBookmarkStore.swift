import Foundation

public final class SubmissionFolderBookmarkStore: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let storageKey = "submissionFolderBookmark"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public enum ResolveError: Error, Equatable {
        case notConfigured
        case bookmarkStale
        case accessDenied
    }

    public var isConfigured: Bool {
        userDefaults.data(forKey: storageKey) != nil
    }

    public func save(folderURL: URL) throws {
        let bookmark = try folderURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        userDefaults.set(bookmark, forKey: storageKey)
    }

    public func resolvedFolderURL() throws -> URL {
        guard let bookmark = userDefaults.data(forKey: storageKey) else {
            throw ResolveError.notConfigured
        }
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        if isStale {
            refreshBookmark(for: url)
        }
        return url
    }

    private func refreshBookmark(for url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        userDefaults.set(refreshed, forKey: storageKey)
    }

    public func withAccess<T>(_ body: (URL) throws -> T) throws -> T {
        let url = try resolvedFolderURL()
        guard url.startAccessingSecurityScopedResource() else {
            throw ResolveError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        return try body(url)
    }
}
