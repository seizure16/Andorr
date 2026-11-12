import SwiftUI
import AppKit
import AndorrCore

struct Palette {
    let colorScheme: ColorScheme

    // Resolve from SwiftUI's current scheme, not a cached dynamic NSColor.
    var sidebar: Color {
        colorScheme == .dark
            ? Color(red: 0.105, green: 0.11, blue: 0.115)
            : Color(red: 0.953, green: 0.949, blue: 0.933)
    }
    var paper: Color {
        colorScheme == .dark ? Color(red: 0.125, green: 0.129, blue: 0.133) : .white
    }
    var selection: Color {
        colorScheme == .dark
            ? Color(red: 0.20, green: 0.22, blue: 0.24)
            : Color(red: 0.87, green: 0.88, blue: 0.88)
    }
    static let accent = Color(red: 0.30, green: 0.38, blue: 0.67)
}

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var palette: Palette { Palette(colorScheme: colorScheme) }
    @Bindable var store: WorkspaceStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 240, ideal: 296, max: 440)
        } detail: {
            if let note = store.draft {
                EditorView(store: store, note: note)
            } else {
                VStack(spacing: 18) {
                    Image(systemName: store.root == nil ? "folder" : "doc.text")
                        .font(.system(size: 42, weight: .ultraLight)).foregroundStyle(.secondary)
                    Text(store.root == nil ? "Vos cours, au même endroit." : "Une place pour vos idées.")
                        .font(.title2.weight(.medium))
                    Text(store.root == nil ? "Ouvrez un dossier pour retrouver vos notes Markdown\net suivre vos révisions." : "Sélectionnez une note ou créez la première.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                    if store.root == nil {
                        Button("Ouvrir un dossier…", action: store.chooseFolder).buttonStyle(.borderedProminent)
                    } else {
                        Button("Créer une note…") { store.showingNewNote = true }.buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(palette.paper)
            }
        }
        .tint(Palette.accent)
        .frame(minWidth: 800, minHeight: 520)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: store.chooseFolder) { Label("Ouvrir un dossier", systemImage: "folder") }
                    .help("Ouvrir un dossier de cours (⌘O)").disabled(store.isBusy)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { store.showingNewNote = true } label: { Label("Nouvelle note", systemImage: "square.and.pencil") }
                    .help("Nouvelle note (⌘N)").disabled(store.root == nil || store.isBusy)
            }
        }
        .overlay(alignment: .top) {
            if store.isBusy {
                ProgressView().controlSize(.small).padding(10).background(.regularMaterial, in: Capsule()).padding(8)
            }
        }
        .sheet(isPresented: $store.showingNewNote) { NewNoteView(store: store) }
        .alert("Impossible de terminer l’opération", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .task { await store.restore() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
        .background(WindowLifecycle(store: store))
    }
}

private struct SidebarView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var palette: Palette { Palette(colorScheme: colorScheme) }
    @Bindable var store: WorkspaceStore
    @AppStorage(PreferenceKeys.showStatuses) private var showStatuses = true
    @AppStorage(PreferenceKeys.showTags) private var showTags = true
    @FocusState private var searchFocused: Bool
    @State private var showingWarnings = false
    @State private var folderExpansion = FolderExpansionState()
    @State private var filterContext = NoteQuery()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher", text: $store.search).textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityLabel("Rechercher dans le titre et le contenu")
                if !store.search.isEmpty {
                    Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain).accessibilityLabel("Effacer la recherche")
                }
            }
            .padding(.horizontal, 10).frame(height: 33)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8)).padding(12)
            filterRow("Toutes les notes", count: store.notes.count, active: store.selectedStatus == nil) { store.selectedStatus = nil }
            ForEach(store.availableStatuses) { status in
                filterRow(status.title, count: store.statusCount(status), active: store.selectedStatus == status) {
                    store.selectedStatus = status
                }
            }

            if !store.allTags.isEmpty {
                HStack {
                    Menu {
                        Button("Tous les tags") { store.selectedTag = nil }
                        Divider()
                        ForEach(store.allTags, id: \.self) { tag in
                            Button("#\(tag)") { store.selectedTag = tag }
                        }
                    } label: {
                        Label(store.selectedTag.map { "#\($0)" } ?? "Filtrer par tag", systemImage: "number")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }.menuStyle(.borderlessButton).fixedSize()
                    Spacer()
                    if store.selectedTag != nil {
                        Button { store.selectedTag = nil } label: { Image(systemName: "xmark").font(.caption) }
                            .buttonStyle(.plain).accessibilityLabel("Retirer le filtre de tag")
                    }
                }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 4)
            }

            if !store.sidebarTree.folders.isEmpty {
                HStack {
                    Text("Dossiers").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                            folderExpansion.setCollapsed(allSubjectsCollapsed ? [] : store.sidebarTree.folderPaths,
                                                         filtering: store.noteQuery.isActive)
                        }
                    } label: {
                        Image(systemName: allSubjectsCollapsed ? "chevron.down" : "chevron.up")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(allSubjectsCollapsed ? "Tout déplier" : "Tout replier")
                    .accessibilityLabel(allSubjectsCollapsed ? "Déplier tous les dossiers" : "Replier tous les dossiers")
                }
                .padding(.horizontal, 20).padding(.top, 8)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sidebarRows) { row in
                        Group {
                            switch row {
                            case .folder(let path, let name, let depth):
                                folderRow(path: path, name: name, depth: depth)
                            case .note(let note, let depth):
                                noteRow(note, depth: depth)
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -5)),
                            removal: .opacity
                        ))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: collapsedPaths)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand(perform: moveSelection)
            .overlay {
                if sidebarRows.isEmpty && store.root != nil {
                    VStack(spacing: 8) {
                        Text(store.notes.isEmpty ? "Aucune note pour le moment" : "Aucune note correspondante").font(.callout)
                        if !store.notes.isEmpty {
                            Button("Effacer les filtres") { store.search = ""; store.selectedStatus = nil; store.selectedTag = nil }
                                .buttonStyle(.link)
                        }
                    }.foregroundStyle(.secondary).padding()
                }
            }
            Divider().opacity(0.5)
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(store.root?.lastPathComponent ?? "Aucun dossier ouvert").lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                if !store.warnings.isEmpty {
                    Button { showingWarnings.toggle() } label: { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
                        .buttonStyle(.plain).help("Certains fichiers n’ont pas pu être lus")
                        .popover(isPresented: $showingWarnings) {
                            ScrollView { Text(store.warnings.joined(separator: "\n\n")).textSelection(.enabled).padding() }.frame(width: 350, height: 220)
                        }
                }
                SettingsLink {
                    Image(systemName: "gearshape").frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Réglages (⌘,)")
                .accessibilityLabel("Ouvrir les réglages")
            }.font(.system(size: 12)).foregroundStyle(.secondary).padding(16).help(store.root?.path ?? "")
        }
        .background(palette.sidebar)
        .onChange(of: store.root) { _, _ in folderExpansion = FolderExpansionState() }
        .onChange(of: store.noteQuery) { _, query in
            folderExpansion.resetFiltered()
            filterContext = query
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusNoteSearch)) { _ in searchFocused = true }
    }

    private var collapsedPaths: Set<String> {
        // A changed query must reveal matches in its very first rendered frame.
        if store.noteQuery.isActive && filterContext != store.noteQuery { return [] }
        return folderExpansion.collapsedPaths(filtering: store.noteQuery.isActive)
    }

    private var sidebarRows: [NoteTreeRow] { store.sidebarTree.rows(collapsed: collapsedPaths) }

    private var allSubjectsCollapsed: Bool {
        let paths = Set(store.sidebarTree.folders.map(\.id))
        return !paths.isEmpty && paths.isSubset(of: collapsedPaths)
    }

    private func folderRow(path: String, name: String, depth: Int) -> some View {
        let expanded = !collapsedPaths.contains(path)
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                folderExpansion.toggle(path, filtering: store.noteQuery.isActive)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .foregroundStyle(.secondary).frame(width: 10)
                Image(systemName: "folder")
                    .font(.system(size: 13)).foregroundStyle(Palette.accent).frame(width: 14)
                Text(name).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary).lineLimit(1).truncationMode(.middle)
            }
            .padding(.leading, CGFloat(depth) * 16)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) { indentationGuides(depth: depth) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(path.replacingOccurrences(of: "/", with: " › "))
        .accessibilityLabel(name)
        .accessibilityValue(expanded ? "Déplié" : "Replié")
        .accessibilityHint(expanded ? "Replier le dossier" : "Déplier le dossier")
    }

    private func noteRow(_ note: Note, depth: Int) -> some View {
        Button { store.requestSelection(note.id) } label: {
            HStack(alignment: .top, spacing: 6) {
                Color.clear.frame(width: 10, height: 1).accessibilityHidden(true)
                Image(systemName: "doc.text").font(.system(size: 12))
                    .foregroundStyle(.tertiary).frame(width: 14).padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Text(note.title).font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary).lineLimit(2)
                        if note.issue != nil {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help(note.issue ?? "")
                        }
                    }
                    if showStatuses || (showTags && !note.tags.isEmpty) {
                        HStack(spacing: 7) {
                            if showStatuses { StatusBadge(status: note.status) }
                            if showTags {
                                Text(note.tags.prefix(3).map { "#\($0)" }.joined(separator: "  "))
                                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                if note.tags.count > 3 {
                                    Text("+\(note.tags.count - 3)").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.leading, CGFloat(depth) * 16)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) { indentationGuides(depth: depth) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 7)
            .fill(store.selectedNoteID == note.id ? palette.selection : .clear))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(store.selectedNoteID == note.id ? [.isSelected] : [])
        .contextMenu {
            ForEach(ReviewStatus.allCases) { status in
                Button(status.title) {
                    Task {
                        await store.select(note.id)
                        if store.draft?.id == note.id { store.setStatus(status) }
                    }
                }.disabled(note.issue != nil || store.isBusy)
            }
        }
    }

    private func indentationGuides(depth: Int) -> some View {
        HStack(spacing: 15) {
            ForEach(0..<depth, id: \.self) { _ in
                Rectangle().fill(.primary.opacity(0.12))
                    .frame(width: 1).frame(maxHeight: .infinity)
            }
        }
        .padding(.leading, 5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard direction == .up || direction == .down else { return }
        let available = sidebarRows.compactMap { row -> Note? in
            if case .note(let note, _) = row { return note }
            return nil
        }
        guard !available.isEmpty else { return }
        let current = available.firstIndex { $0.id == store.selectedNoteID }
        let next = current.map { min(max($0 + (direction == .down ? 1 : -1), 0), available.count - 1) }
            ?? (direction == .down ? 0 : available.count - 1)
        store.requestSelection(available[next].id)
    }

    private func filterRow(_ title: String, count: Int, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).fontWeight(active ? .semibold : .regular)
                Spacer()
                Text("\(count)").font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
            }.font(.system(size: 13)).padding(.horizontal, 12).frame(height: 34)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(.primary)
            .background(active ? palette.selection : .clear, in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 8).padding(.bottom, 2)
            .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

struct StatusBadge: View {
    let status: ReviewStatus
    @Environment(\.colorScheme) private var colorScheme

    private var colors: (text: Color, background: Color) {
        switch (status, colorScheme == .dark) {
        case (.inProgress, false): (Color(red: 0.20, green: 0.32, blue: 0.50), Color(red: 0.86, green: 0.90, blue: 0.95))
        case (.inProgress, true): (Color(red: 0.69, green: 0.78, blue: 0.93), Color(red: 0.19, green: 0.25, blue: 0.34))
        case (.toReview, false): (Color(red: 0.44, green: 0.28, blue: 0.07), Color(red: 0.97, green: 0.91, blue: 0.80))
        case (.toReview, true): (Color(red: 0.94, green: 0.77, blue: 0.47), Color(red: 0.32, green: 0.26, blue: 0.16))
        case (.reviewed, false): (Color(red: 0.17, green: 0.37, blue: 0.27), Color(red: 0.85, green: 0.93, blue: 0.88))
        case (.reviewed, true): (Color(red: 0.61, green: 0.84, blue: 0.69), Color(red: 0.17, green: 0.29, blue: 0.22))
        }
    }
    var body: some View {
        Text(status.title).font(.system(size: 11, weight: .medium))
            .foregroundStyle(colors.text).padding(.horizontal, 8).padding(.vertical, 3)
            .background(colors.background, in: Capsule()).fixedSize()
    }
}

private struct EditorModeSwitch: View {
    @Environment(\.colorScheme) private var colorScheme
    private var palette: Palette { Palette(colorScheme: colorScheme) }
    @Binding var mode: NoteOpeningMode
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NoteOpeningMode.allCases) { option($0) }
        }
        .padding(3)
        .background(palette.sidebar, in: RoundedRectangle(cornerRadius: 7))
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85), value: mode)
        .opacity(isEnabled ? 1 : 0.45)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mode d’affichage de la note")
    }

    private func option(_ option: NoteOpeningMode) -> some View {
        let selected = mode == option
        return Button { mode = option } label: {
            Label(option.title, systemImage: option.icon)
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? Palette.accent : Color.secondary)
                .frame(width: 34, height: 30)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 5).fill(palette.paper)
                            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "editorMode", in: selection)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(EditorModeButtonStyle())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(option.title)
    }
}

private struct EditorModeButtonStyle: ButtonStyle {
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: 5).fill(.primary.opacity(configuration.isPressed ? 0.06 : (hovered && isEnabled ? 0.025 : 0)))
                    .allowsHitTesting(false)
            }
            .onHover { hovered = $0 }
    }
}

private struct EditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var palette: Palette { Palette(colorScheme: colorScheme) }
    @Bindable var store: WorkspaceStore
    let note: Note
    @AppStorage(PreferenceKeys.autoCloseMarkdown) private var autoCloseMarkdown = true
    @AppStorage(PreferenceKeys.editorZoom) private var editorZoom = EditorZoom.defaultScale
    @State private var tagInput = ""
    @State private var addingTag = false
    @State private var confirmReload = false
    private var showingPreview: Bool { store.preview && note.issue == nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                Text(note.title).font(.system(size: 21, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                EditorModeSwitch(mode: $store.editorMode).disabled(note.issue != nil)
            }.padding(.horizontal, 32).padding(.vertical, 18)
            Divider().opacity(0.5)
            HStack(spacing: 10) {
                Menu {
                    ForEach(ReviewStatus.allCases) { status in
                        Button { store.setStatus(status) } label: {
                            if status == note.status { Label(status.title, systemImage: "checkmark") }
                            else { Text(status.title) }
                        }
                    }
                } label: { StatusBadge(status: note.status) }
                    .menuStyle(.borderlessButton).fixedSize().disabled(!store.canEdit)
                    .accessibilityLabel("Statut : \(note.status.title)")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(note.tags, id: \.self) { tag in
                            HStack(spacing: 5) {
                                Button("#\(tag)") { store.selectedTag = tag }.buttonStyle(.plain)
                                Button { store.setTags(note.tags.filter { $0 != tag }) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .semibold)) }
                                    .buttonStyle(.plain).disabled(!store.canEdit).accessibilityLabel("Retirer le tag \(tag)")
                            }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 5)
                                .background(palette.sidebar, in: RoundedRectangle(cornerRadius: 6))
                        }
                        Button { addingTag = true } label: { Label("Tag", systemImage: "plus").font(.system(size: 12)) }
                            .buttonStyle(.plain).foregroundStyle(.secondary).padding(5).disabled(!store.canEdit)
                            .popover(isPresented: $addingTag) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Ajouter un tag").font(.headline)
                                    TextField("examen", text: $tagInput).textFieldStyle(.roundedBorder).onSubmit(addTag)
                                    HStack { Spacer(); Button("Ajouter", action: addTag).keyboardShortcut(.defaultAction).disabled(tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                                }.padding(16).frame(width: 240)
                            }
                    }
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 32).padding(.top, 14).padding(.bottom, 6)

            if let issue = note.issue { messageBanner(issue) }
            if let error = store.saveError {
                VStack(alignment: .leading, spacing: 10) {
                    Label(error, systemImage: "exclamationmark.triangle").font(.callout)
                    HStack {
                        Button("Réessayer") { Task { _ = await store.flush() } }
                        Button("Enregistrer une copie") { Task { await store.saveCopy() } }
                        Button("Recharger le fichier…") { confirmReload = true }
                    }.controlSize(.small)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.09)).padding(.top, 8)
            }

            ZStack {
                MarkdownEditor(text: Binding(get: { store.draft?.body ?? "" }, set: store.setBody),
                               noteID: store.root?.appendingPathComponent(note.id).path ?? note.id, zoom: EditorZoom.normalized(editorZoom),
                               livePreview: store.editorMode == .live && note.issue == nil,
                               editable: store.canEdit && !showingPreview, autoCloseMarkdown: autoCloseMarkdown)
                    .opacity(showingPreview ? 0 : 1)
                    .allowsHitTesting(!showingPreview)
                    .accessibilityHidden(showingPreview)
                if showingPreview {
                    MarkdownPreview(source: note.body, zoom: EditorZoom.normalized(editorZoom))
                }
            }
            Divider().opacity(0.5)
            HStack(spacing: 7) {
                if note.issue != nil {
                    Label("Lecture seule", systemImage: "lock")
                } else if store.saveError != nil {
                    Label("Échec de la sauvegarde", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(note.subject.isEmpty ? "Racine du dossier" : note.subject.replacingOccurrences(of: "/", with: " › ")).lineLimit(1)
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 32).padding(.vertical, 11)
        }
        .background(palette.paper)
        .confirmationDialog("Recharger et abandonner le brouillon ?", isPresented: $confirmReload) {
            Button("Recharger le fichier", role: .destructive) { Task { await store.reloadDiscardingDraft() } }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Les modifications non enregistrées de cette note seront remplacées par le contenu présent sur disque.") }
        .onChange(of: note.id) { _, _ in addingTag = false; tagInput = "" }
    }

    private func addTag() {
        store.setTags(note.tags + [tagInput]); tagInput = ""; addingTag = false
    }
    private func messageBanner(_ message: String) -> some View {
        Label(message, systemImage: "lock.doc").font(.callout).foregroundStyle(.secondary)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.08)).padding(.top, 8)
    }
}

private struct NewNoteView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var subject = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Nouvelle note").font(.title2.weight(.semibold))
            TextField("Titre de la note", text: $title).textFieldStyle(.roundedBorder).focused($titleFocused)
            Picker("Matière", selection: $subject) {
                Text("Racine du dossier").tag("")
                ForEach(store.subjects, id: \.self) { Text($0.replacingOccurrences(of: "/", with: " › ")).tag($0) }
            }
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Créer") { Task { if await store.create(title: title, subject: subject) { dismiss() } } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isBusy)
            }
        }.padding(28).frame(width: 420)
            .onAppear { subject = store.draft?.subject ?? ""; titleFocused = true }
    }
}

extension Notification.Name { static let focusNoteSearch = Notification.Name("focusNoteSearch") }
