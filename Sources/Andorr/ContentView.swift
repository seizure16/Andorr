import SwiftUI
import AppKit
import AndorrCore

enum Palette {
    static let sidebar = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(calibratedRed: 0.105, green: 0.11, blue: 0.115, alpha: 1)
        : NSColor(calibratedRed: 0.953, green: 0.949, blue: 0.933, alpha: 1) })
    static let paper = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(calibratedRed: 0.125, green: 0.129, blue: 0.133, alpha: 1) : .white })
    static let accent = Color(red: 0.30, green: 0.38, blue: 0.67)
}

struct ContentView: View {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.paper)
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
    @Bindable var store: WorkspaceStore
    @AppStorage("showStatuses") private var showStatuses = true
    @AppStorage("showTags") private var showTags = true
    @FocusState private var searchFocused: Bool
    @State private var showingWarnings = false

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
            filterRow("Toutes les notes", count: store.notes.count, active: !store.onlyToReview) { store.onlyToReview = false }
            filterRow("À revoir", count: store.reviewCount, active: store.onlyToReview) { store.onlyToReview = true }

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

            List(selection: Binding<String?>(get: { store.draft?.id }, set: { id in
                if let id { Task { await store.select(id) } }
            })) {
                ForEach(store.visibleSubjects, id: \.self) { subject in
                    Section {
                        ForEach(store.visibleNotes.filter { $0.subject == subject }) { note in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 5) {
                                    Text(note.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                                    if note.issue != nil { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help(note.issue ?? "") }
                                }
                                if showStatuses || (showTags && !note.tags.isEmpty) {
                                    HStack(spacing: 7) {
                                        if showStatuses { StatusBadge(status: note.status) }
                                        if showTags {
                                            Text(note.tags.prefix(3).map { "#\($0)" }.joined(separator: "  "))
                                                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                            if note.tags.count > 3 { Text("+\(note.tags.count - 3)").font(.system(size: 10)).foregroundStyle(.secondary) }
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 5).tag(note.id)
                            .accessibilityElement(children: .combine)
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
                    } header: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: subject.isEmpty ? "doc.text" : "folder.fill")
                                .foregroundStyle(subject.isEmpty ? Color.secondary : Palette.accent)
                            Text(subject.isEmpty ? "Général" : subject.replacingOccurrences(of: "/", with: " › "))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .textCase(nil)
                        .padding(.top, 12).padding(.bottom, 6)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)
                    }
                }
            }
            .listStyle(.sidebar).scrollContentBackground(.hidden)
            .overlay {
                if store.visibleNotes.isEmpty && store.root != nil {
                    VStack(spacing: 8) {
                        Text(store.notes.isEmpty ? "Aucune note pour le moment" : "Aucune note correspondante").font(.callout)
                        if !store.notes.isEmpty {
                            Button("Effacer les filtres") { store.search = ""; store.onlyToReview = false; store.selectedTag = nil }
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
            }.font(.system(size: 12)).foregroundStyle(.secondary).padding(16).help(store.root?.path ?? "")
        }
        .background(Palette.sidebar)
        .onReceive(NotificationCenter.default.publisher(for: .focusNoteSearch)) { _ in searchFocused = true }
    }

    private func filterRow(_ title: String, count: Int, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).fontWeight(active ? .semibold : .regular)
                Spacer()
                Text("\(count)").font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
            }.font(.system(size: 13)).padding(.horizontal, 12).frame(height: 34)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(active ? Palette.accent : .primary)
            .background(active ? Palette.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 8).padding(.bottom, 2)
            .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

struct StatusBadge: View {
    let status: ReviewStatus
    var color: Color {
        switch status { case .inProgress: .blue; case .toReview: .orange; case .reviewed: .green }
    }
    var body: some View {
        Text(status.title).font(.system(size: 11, weight: .medium))
            .foregroundStyle(color).padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule()).fixedSize()
    }
}

private struct EditorView: View {
    @Bindable var store: WorkspaceStore
    let note: Note
    @State private var tagInput = ""
    @State private var addingTag = false
    @State private var confirmReload = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                Text(note.title).font(.system(size: 21, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Picker("Mode", selection: $store.preview) {
                    Text("Édition").tag(false)
                    Text("Aperçu").tag(true)
                }.pickerStyle(.segmented).frame(width: 180).labelsHidden().disabled(note.issue != nil)
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
                                .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 6))
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

            if store.preview && note.issue == nil {
                MarkdownPreview(source: note.body)
            } else {
                TextEditor(text: Binding(get: { store.draft?.body ?? "" }, set: store.setBody))
                    .font(.system(size: 14, design: .monospaced)).lineSpacing(6)
                    .scrollContentBackground(.hidden).padding(.horizontal, 27).padding(.vertical, 18)
                    .disabled(!store.canEdit).focused($editorFocused)
                    .accessibilityLabel("Contenu Markdown")
            }
            Divider().opacity(0.5)
            HStack(spacing: 7) {
                if store.isSaving { ProgressView().controlSize(.mini) }
                else { Image(systemName: store.saveError == nil ? "checkmark" : "exclamationmark.triangle").font(.system(size: 10)) }
                Text(store.saveLabel)
                Spacer()
                Text(note.subject.isEmpty ? "Général" : note.subject.replacingOccurrences(of: "/", with: " › ")).lineLimit(1)
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 32).padding(.vertical, 11)
        }
        .background(Palette.paper)
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
                Text("Général · racine du dossier").tag("")
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
