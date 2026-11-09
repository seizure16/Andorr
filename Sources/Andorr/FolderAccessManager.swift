import AppKit

@MainActor
final class FolderAccessManager {
    private var activeURL: URL?
    private var hasScope = false
    private let key = "workspaceBookmark"
    private let preferences: UserDefaults

    init(preferences: UserDefaults = .standard) { self.preferences = preferences }

    func restore() throws -> URL? {
        guard let data = preferences.data(forKey: key) else { return nil }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        let granted = url.startAccessingSecurityScopedResource()
        release()
        activeURL = url; hasScope = granted
        if stale { try remember(url) }
        return url
    }

    func adopt(_ url: URL) throws {
        let granted = url.startAccessingSecurityScopedResource()
        do { try remember(url) }
        catch { if granted { url.stopAccessingSecurityScopedResource() }; throw error }
        release()
        activeURL = url; hasScope = granted
    }

    private func remember(_ url: URL) throws {
        let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        preferences.set(data, forKey: key)
    }

    func release() {
        if hasScope { activeURL?.stopAccessingSecurityScopedResource() }
        activeURL = nil; hasScope = false
    }
}
