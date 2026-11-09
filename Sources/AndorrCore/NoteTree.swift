import Foundation

public struct NoteFolder: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let folders: [NoteFolder]
    public let notes: [Note]
}

public enum NoteTreeRow: Sendable, Identifiable {
    case folder(path: String, name: String, depth: Int)
    case note(Note, depth: Int)

    public var id: String {
        switch self {
        case .folder(let path, _, _): "folder:\(path)"
        case .note(let note, _): "note:\(note.id)"
        }
    }
}

/// Derives an actual hierarchy from filesystem paths. In filtered mode callers
/// supply matching notes only, so only their ancestors are retained.
public struct NoteTree: Sendable {
    public let folders: [NoteFolder]
    public let rootNotes: [Note]
    public let folderPaths: Set<String>

    public init(notes: [Note], directories: [String] = []) {
        var paths = Set<String>()
        for path in directories + notes.map(\.subject) {
            let components = path.split(separator: "/")
            for count in 1..<(components.count + 1) {
                paths.insert(components.prefix(count).joined(separator: "/"))
            }
        }
        let children = Dictionary(grouping: paths) { ($0 as NSString).deletingLastPathComponent }
        let groupedNotes = Dictionary(grouping: notes, by: \.subject)
        func sortedNotes(_ parent: String) -> [Note] {
            (groupedNotes[parent] ?? []).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        func makeFolders(_ parent: String) -> [NoteFolder] {
            (children[parent] ?? []).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { path in
                NoteFolder(id: path, name: (path as NSString).lastPathComponent,
                           folders: makeFolders(path), notes: sortedNotes(path))
            }
        }
        folders = makeFolders("")
        rootNotes = sortedNotes("")
        folderPaths = paths
    }

    public func rows(collapsed: Set<String> = []) -> [NoteTreeRow] {
        var result: [NoteTreeRow] = []
        func append(_ folder: NoteFolder, depth: Int) {
            result.append(.folder(path: folder.id, name: folder.name, depth: depth))
            guard !collapsed.contains(folder.id) else { return }
            for child in folder.folders { append(child, depth: depth + 1) }
            result += folder.notes.map { .note($0, depth: depth + 1) }
        }
        for folder in folders { append(folder, depth: 0) }
        result += rootNotes.map { .note($0, depth: 0) }
        return result
    }
}

/// Filtering has its own temporary expansion state. Clearing a filter restores
/// the user's original folder arrangement without snapshotting view state.
public struct FolderExpansionState {
    private var normal: Set<String> = []
    private var filtered: Set<String> = []

    public init() {}
    public func collapsedPaths(filtering: Bool) -> Set<String> { filtering ? filtered : normal }
    public mutating func setCollapsed(_ paths: Set<String>, filtering: Bool) {
        if filtering { filtered = paths } else { normal = paths }
    }
    public mutating func toggle(_ path: String, filtering: Bool) {
        var paths = collapsedPaths(filtering: filtering)
        if !paths.insert(path).inserted { paths.remove(path) }
        setCollapsed(paths, filtering: filtering)
    }
    public mutating func resetFiltered() { filtered.removeAll() }
}
