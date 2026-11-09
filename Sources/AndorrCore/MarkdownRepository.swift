import Foundation

public struct LoadedNote: Sendable {
    public var note: Note
    public var bytes: Data
}

public struct WorkspaceIndex: Sendable {
    public var notes: [Note]
    public var subjects: [String]
    public var warnings: [String]
}

/// All file operations execute on this actor, away from the main actor.
public actor MarkdownRepository {
    public let root: URL
    private let fileAccess: any FileAccess

    public init(root: URL) {
        self.root = Self.canonicalRoot(root)
        fileAccess = CoordinatedFileAccess()
    }

    internal init(root: URL, fileAccess: any FileAccess) {
        self.root = Self.canonicalRoot(root)
        self.fileAccess = fileAccess
    }

    public func scan() throws -> WorkspaceIndex {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        var warnings: [String] = []
        guard let files = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, error in
            warnings.append("\(url.lastPathComponent) : \(error.localizedDescription)")
            return true
        }) else { throw CocoaError(.fileReadNoPermission) }
        var notes: [Note] = []
        var subjects = Set<String>()
        for case let url as URL in files {
            do {
                let values = try url.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true { files.skipDescendants(); continue }
                // Enumeration can return /private/var while a selected URL uses
                // /var. Compare path components rather than dropping characters.
                let components = url.pathComponents
                let base = root.pathComponents
                guard components.starts(with: base) else {
                    warnings.append("\(url.lastPathComponent) : chemin inattendu hors du dossier")
                    continue
                }
                let relative = components.dropFirst(base.count).joined(separator: "/")
                if values.isDirectory == true { subjects.insert(relative); continue }
                guard values.isRegularFile == true, url.pathExtension.lowercased() == "md" else { continue }
                notes.append(try load(id: relative).note)
            } catch { warnings.append("\(url.lastPathComponent) : \(error.localizedDescription)") }
        }
        return WorkspaceIndex(notes: notes.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending },
                              subjects: subjects.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, warnings: warnings)
    }

    public func load(id: String) throws -> LoadedNote {
        let url = try checkedURL(id)
        let bytes = try fileAccess.read(url)
        guard let source = String(data: bytes, encoding: .utf8) else { throw NoteError.invalidUTF8 }
        let title = url.deletingPathExtension().lastPathComponent
        let parent = (id as NSString).deletingLastPathComponent
        do {
            let doc = try MarkdownDocument(source: source)
            return LoadedNote(note: Note(id: id, title: title, subject: parent, body: doc.body, status: doc.status, tags: doc.tags), bytes: bytes)
        } catch {
            return LoadedNote(note: Note(id: id, title: title, subject: parent, body: source, issue: error.localizedDescription), bytes: bytes)
        }
    }

    public func save(_ note: Note, expected: Data) throws -> LoadedNote {
        let url = try checkedURL(note.id)
        guard let source = String(data: expected, encoding: .utf8) else { throw NoteError.invalidUTF8 }
        var document = try MarkdownDocument(source: source)
        document.body = note.body; document.status = note.status
        document.tags = MarkdownDocument.normalizedTags(note.tags)
        let bytes = Data(try document.serialized().utf8)
        try fileAccess.write(url) { target in
            guard try Data(contentsOf: target) == expected else { throw NoteError.conflict }
            try bytes.write(to: target, options: .atomic)
        }
        var saved = note; saved.tags = document.tags
        return LoadedNote(note: saved, bytes: bytes)
    }

    public func create(title: String, subject: String, body: String? = nil,
                       status: ReviewStatus = .inProgress, tags: [String] = []) throws -> LoadedNote {
        var name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasSuffix(".md") { name = String(name.dropLast(3)) }
        guard !name.isEmpty, name != ".", name != "..", !name.hasPrefix("."),
              name.rangeOfCharacter(from: .controlCharacters.union(CharacterSet(charactersIn: "/:"))) == nil else {
            throw NoteError.invalidName
        }
        let id = subject.isEmpty ? "\(name).md" : "\(subject)/\(name).md"
        let url = try checkedURL(id)
        var document = try MarkdownDocument(source: body ?? "# \(name)\n\n")
        document.status = status; document.tags = tags
        let bytes = Data(try document.serialized().utf8)
        try fileAccess.write(url) { target in
            guard !FileManager.default.fileExists(atPath: target.path) else { throw NoteError.alreadyExists }
            try bytes.write(to: target, options: .withoutOverwriting)
        }
        return try load(id: id)
    }

    private func checkedURL(_ id: String) throws -> URL {
        guard !id.hasPrefix("/"), !id.split(separator: "/").contains("..") else { throw NoteError.outsideWorkspace }
        let url = root.appendingPathComponent(id)
        // Foundation standardization shortens /private/var to /var. Use the
        // same filesystem canonicalization for both sides of this boundary.
        let resolvedPath: String = url.withUnsafeFileSystemRepresentation { path in
            if let path, let resolved = realpath(path, nil) {
                defer { free(resolved) }
                return String(cString: resolved)
            }
            return Self.canonicalRoot(url.deletingLastPathComponent()).appendingPathComponent(url.lastPathComponent).path
        }
        let resolvedComponents = (resolvedPath as NSString).pathComponents
        guard resolvedComponents.count > root.pathComponents.count,
              resolvedComponents.starts(with: root.pathComponents) else { throw NoteError.outsideWorkspace }
        return url
    }

    private static func canonicalRoot(_ url: URL) -> URL {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path, let canonical = realpath(path, nil) else { return url.standardizedFileURL.resolvingSymlinksInPath() }
            defer { free(canonical) }
            return URL(fileURLWithFileSystemRepresentation: canonical, isDirectory: true, relativeTo: nil)
        }
    }

}

/// An internal seam for storage tests in environments without the macOS
/// filecoordinationd service. Production always uses CoordinatedFileAccess.
internal protocol FileAccess: Sendable {
    func read(_ url: URL) throws -> Data
    func write(_ url: URL, operation: (URL) throws -> Void) throws
}

internal struct CoordinatedFileAccess: FileAccess {
    func read(_ url: URL) throws -> Data {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
            result = Result { try Data(contentsOf: target) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    func write(_ url: URL, operation: (URL) throws -> Void) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { target in
            do { try operation(target) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}
