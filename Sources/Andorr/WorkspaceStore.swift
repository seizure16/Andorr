import AppKit
import Observation
import AndorrCore

@MainActor @Observable
final class WorkspaceStore {
    var root: URL?
    var notes: [Note] = []
    var subjects: [String] = []
    var draft: Note?
    private(set) var selectedNoteID: String?
    var search = ""
    var selectedStatus: ReviewStatus?
    var selectedTag: String?
    var isBusy = false
    var isSaving = false
    var errorMessage: String?
    var saveError: String?
    var warnings: [String] = []
    var showingNewNote = false
    var editorMode = NoteOpeningMode.edit
    var preview: Bool {
        get { editorMode == .preview }
        set { editorMode = newValue ? .preview : .edit }
    }

    @ObservationIgnored private var repository: MarkdownRepository?
    @ObservationIgnored private let access: FolderAccessManager
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private var expectedBytes = Data()
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var savedRevision = 0
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var saveTask: (id: UUID, task: Task<Bool, Never>)?
    @ObservationIgnored private var hasRestored = false
    @ObservationIgnored private var selectionTask: Task<Void, Never>?
    @ObservationIgnored private var isSelecting = false

    init(repository: MarkdownRepository? = nil, preferences: UserDefaults = .standard) {
        self.repository = repository
        self.preferences = preferences
        self.access = FolderAccessManager(preferences: preferences)
    }

    var isDirty: Bool { revision != savedRevision }
    var canEdit: Bool { draft != nil && draft?.issue == nil && !isBusy }
    var noteQuery: NoteQuery { NoteQuery(text: search, status: selectedStatus, tag: selectedTag) }
    var visibleNotes: [Note] {
        notes.filter(noteQuery.matches)
    }
    var sidebarTree: NoteTree {
        NoteTree(notes: visibleNotes, directories: noteQuery.isActive ? [] : subjects)
    }
    var allTags: [String] { Array(Set(notes.flatMap(\.tags))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    var availableStatuses: [ReviewStatus] {
        ReviewStatus.allCases.filter { statusCount($0) > 0 || selectedStatus == $0 }
    }
    func statusCount(_ status: ReviewStatus) -> Int { notes.filter { $0.status == status }.count }
    func restore() async {
        guard !hasRestored else { return }; hasRestored = true
        guard preferences.object(forKey: PreferenceKeys.reopenFolder) as? Bool ?? true else { return }
        do {
            if let url = try access.restore() { await open(url, restoring: true) }
        } catch { errorMessage = "L’accès au dernier dossier n’a pas pu être restauré. Ouvrez-le à nouveau.\n\n\(error.localizedDescription)" }
    }

    func chooseFolder() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.prompt = "Ouvrir"
        panel.message = "Choisissez le dossier contenant vos matières et vos notes Markdown."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await self?.open(url) }
        }
    }

    func open(_ url: URL, restoring: Bool = false) async {
        guard !isBusy else { return }
        isBusy = true; defer { isBusy = false }
        guard await flush() else { return }
        // The panel's security extension remains valid while the initial scan runs.
        let temporaryScope = url.startAccessingSecurityScopedResource()
        defer { if temporaryScope { url.stopAccessingSecurityScopedResource() } }
        do {
            let next = MarkdownRepository(root: url)
            let index = try await next.scan()
            if !restoring { try access.adopt(url) }
            repository = next; root = url; notes = index.notes; subjects = index.subjects; warnings = index.warnings
            draft = nil; selectedNoteID = nil; expectedBytes = Data(); revision = 0; savedRevision = 0; saveError = nil
            search = ""; selectedStatus = nil; selectedTag = nil
            if let first = notes.first { install(try await next.load(id: first.id), applyOpeningMode: true) }
        } catch { errorMessage = error.localizedDescription }
    }

    func select(_ id: String) async {
        if let task = requestSelection(id) { await task.value }
    }

    /// List must receive its new selection synchronously, before any IO awaits.
    @discardableResult
    func requestSelection(_ id: String) -> Task<Void, Never>? {
        guard repository != nil, !isBusy || isSelecting,
              notes.contains(where: { $0.id == id }) else { return nil }
        selectedNoteID = id
        if let selectionTask { return selectionTask }
        guard id != draft?.id else { return nil }
        isSelecting = true; isBusy = true
        let worker = Task<Void, Never> { [weak self] in
            await self?.loadSelection()
        }
        selectionTask = worker
        return worker
    }

    private func loadSelection() async {
        defer { selectionTask = nil; isSelecting = false; isBusy = false }
        guard let repository else { selectedNoteID = draft?.id; return }
        guard await flush() else { selectedNoteID = draft?.id; return }
        while let id = selectedNoteID, id != draft?.id {
            do {
                let loaded = try await repository.load(id: id)
                // A newer click supersedes this result, without moving the highlight back.
                guard selectedNoteID == id else { continue }
                install(loaded, applyOpeningMode: true)
            } catch {
                guard selectedNoteID == id else { continue }
                selectedNoteID = draft?.id
                errorMessage = error.localizedDescription
                return
            }
        }
    }

    func setBody(_ value: String) { mutate(immediate: false) { $0.body = value } }
    func setStatus(_ value: ReviewStatus) { mutate(immediate: true) { $0.status = value } }
    func setTags(_ values: [String]) { mutate(immediate: true) { $0.tags = MarkdownDocument.normalizedTags(values) } }

    private func mutate(immediate: Bool, _ change: (inout Note) -> Void) {
        guard canEdit, var note = draft else { return }
        let before = note; change(&note)
        guard before != note else { return }
        draft = note; revision += 1
        updateIndex(note)
        debounce?.cancel()
        debounce = Task { [weak self] in
            if !immediate { try? await Task.sleep(for: .milliseconds(500)) }
            guard !Task.isCancelled else { return }
            _ = await self?.flush()
        }
    }

    /// A single non-cancellable save worker prevents stale writes. If the draft
    /// changes during an IO await, another snapshot is saved before it finishes.
    func flush() async -> Bool {
        while true {
            let active: (id: UUID, task: Task<Bool, Never>)
            if let current = saveTask { active = current }
            else {
                guard isDirty else { return true }
                active = (UUID(), Task { [weak self] in await self?.saveUntilClean() ?? false })
                saveTask = active
            }
            let success = await active.task.value
            if saveTask?.id == active.id { saveTask = nil }
            guard success else { return false }
            // A new edit may arrive after a worker ends but before its waiters
            // resume. Recheck dirtiness instead of returning a stale success.
        }
    }

    private func saveUntilClean() async -> Bool {
        guard let repository else { return !isDirty }
        isSaving = true; defer { isSaving = false }
        while isDirty, let note = draft {
            let writingRevision = revision
            do {
                let saved = try await repository.save(note, expected: expectedBytes)
                expectedBytes = saved.bytes; savedRevision = writingRevision; saveError = nil
            } catch { saveError = error.localizedDescription; return false }
        }
        return true
    }

    func create(title: String, subject: String) async -> Bool {
        guard !isBusy, let repository else { return false }
        isBusy = true; defer { isBusy = false }
        guard await flush() else { return false }
        do {
            let created = try await repository.create(title: title, subject: subject)
            install(created); updateIndex(created.note)
            search = ""; selectedStatus = nil; selectedTag = nil; preview = false
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func reloadDiscardingDraft() async {
        guard !isBusy, let id = draft?.id, let repository else { return }
        isBusy = true; defer { isBusy = false }
        debounce?.cancel()
        if let saveTask { _ = await saveTask.task.value }
        do { let loaded = try await repository.load(id: id); install(loaded); updateIndex(loaded.note) }
        catch { errorMessage = error.localizedDescription }
    }

    func saveCopy() async {
        guard !isBusy, let note = draft, let repository else { return }
        isBusy = true; defer { isBusy = false }
        debounce?.cancel()
        if let saveTask { _ = await saveTask.task.value }
        do {
            let suffix = String(UUID().uuidString.prefix(8)).lowercased()
            let copy = try await repository.create(title: "\(note.title) — copie \(suffix)", subject: note.subject,
                                                   body: note.body, status: note.status, tags: note.tags)
            install(copy); updateIndex(copy.note)
        } catch { errorMessage = error.localizedDescription }
    }

    func refresh() async {
        guard !isBusy, let repository else { return }
        isBusy = true; defer { isBusy = false }
        guard await flush() else { return }
        do {
            let index = try await repository.scan()
            notes = index.notes; subjects = index.subjects; warnings = index.warnings
            if let id = draft?.id {
                if notes.contains(where: { $0.id == id }) { install(try await repository.load(id: id)) }
                else { draft = nil; selectedNoteID = nil }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func install(_ loaded: LoadedNote, applyOpeningMode: Bool = false) {
        debounce?.cancel(); draft = loaded.note; selectedNoteID = loaded.note.id; expectedBytes = loaded.bytes
        revision = 0; savedRevision = 0; saveError = nil
        if applyOpeningMode {
            editorMode = loaded.note.issue == nil ? NoteOpeningMode.preferred(in: preferences) : .edit
        }
    }

    private func updateIndex(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) { notes[index] = note }
        else { notes.append(note); notes.sort { $0.id.localizedStandardCompare($1.id) == .orderedAscending } }
    }
}
