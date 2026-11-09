import SwiftUI
import AppKit

@main
struct AndorrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = WorkspaceStore()
    @AppStorage("showStatuses") private var showStatuses = true
    @AppStorage("showTags") private var showTags = true
    @AppStorage("editorZoom") private var editorZoom = EditorZoom.defaultScale

    var body: some Scene {
        Window("Andorr", id: "main") {
            ContentView(store: store)
                .onAppear { delegate.store = store }
        }
        .defaultSize(width: 1120, height: 740)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nouvelle note…") { store.showingNewNote = true }
                    .keyboardShortcut("n").disabled(store.root == nil || store.isBusy)
                Button("Ouvrir un dossier…", action: store.chooseFolder).keyboardShortcut("o").disabled(store.isBusy)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Enregistrer") { Task { _ = await store.flush() } }.keyboardShortcut("s").disabled(store.draft == nil)
                Button("Actualiser le dossier") { Task { await store.refresh() } }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(store.root == nil || store.isBusy)
            }
            CommandGroup(after: .sidebar) {
                Divider()
                Toggle("Afficher les statuts", isOn: $showStatuses)
                Toggle("Afficher les tags", isOn: $showTags)
                Divider()
                Toggle("Aperçu Markdown", isOn: $store.preview).keyboardShortcut("p", modifiers: [.command, .shift]).disabled(store.draft == nil || store.draft?.issue != nil)
                Divider()
                Button("Agrandir le texte") { editorZoom = EditorZoom.adjusted(editorZoom, by: 0.1) }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(store.draft == nil || EditorZoom.normalized(editorZoom) >= EditorZoom.maximum)
                Button("Réduire le texte") { editorZoom = EditorZoom.adjusted(editorZoom, by: -0.1) }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(store.draft == nil || EditorZoom.normalized(editorZoom) <= EditorZoom.minimum)
                Button("Taille du texte par défaut") { editorZoom = EditorZoom.defaultScale }
                    .keyboardShortcut("0", modifiers: .command).disabled(store.draft == nil)
            }
            CommandGroup(after: .textEditing) {
                Button("Rechercher dans les notes") { NotificationCenter.default.post(name: .focusNoteSearch, object: nil) }.keyboardShortcut("f")
            }
        }
    }
}

enum EditorZoom {
    static let defaultScale = 1.0
    static let minimum = 0.7
    static let maximum = 2.0

    static func normalized(_ scale: Double) -> Double {
        guard scale.isFinite else { return defaultScale }
        return min(max(scale, minimum), maximum)
    }

    static func adjusted(_ scale: Double, by step: Double) -> Double {
        normalized(((normalized(scale) + step) * 10).rounded() / 10)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: WorkspaceStore?
    private var terminating = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        guard let store, store.isDirty else { return .terminateNow }
        terminating = true
        Task {
            let saved = await store.flush()
            terminating = false
            sender.reply(toApplicationShouldTerminate: saved)
            if !saved { sender.activate(ignoringOtherApps: true) }
        }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct WindowLifecycle: NSViewRepresentable {
    let store: WorkspaceStore
    func makeCoordinator() -> Coordinator { Coordinator(store: store) }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        DispatchQueue.main.async { view.window?.delegate = coordinator }
    }
    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        let store: WorkspaceStore
        var closing = false
        init(store: WorkspaceStore) { self.store = store }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard store.isDirty else { return true }
            guard !closing else { return false }
            closing = true
            Task {
                let saved = await store.flush()
                closing = false
                if saved { sender.performClose(nil) }
            }
            return false
        }
    }
}
