import Foundation
import XCTest
import SwiftUI
import AppKit
@testable import AndorrCore
@testable import AndorrDesktop

private struct SettingsFileAccess: FileAccess {
    func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }
    func write(_ url: URL, operation: (URL) throws -> Void) throws { try operation(url) }
}

final class SettingsTests: XCTestCase {
    private var root: URL!
    private var preferences: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("andorr-settings-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "org.andorr.tests.\(UUID())"
        preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        preferences.removePersistentDomain(forName: suiteName)
        try FileManager.default.removeItem(at: root)
    }

    @MainActor
    func testPaletteFollowsSwiftUIThemeEvenWhenNativeDrawingAppearanceIsStale() throws {
        let nativeDark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let nativeLight = try XCTUnwrap(NSAppearance(named: .aqua))
        for nativeAppearance in [nativeDark, nativeLight] {
            nativeAppearance.performAsCurrentDrawingAppearance {
                let light = Palette(colorScheme: .light)
                let dark = Palette(colorScheme: .dark)
                for (color, expectedRed) in [(light.paper, 1.0), (light.sidebar, 0.953), (light.selection, 0.87),
                                             (dark.paper, 0.125), (dark.sidebar, 0.105), (dark.selection, 0.20)] {
                    guard let resolved = NSColor(color).usingColorSpace(.sRGB) else { return XCTFail("Color must resolve to RGB") }
                    XCTAssertEqual(resolved.redComponent, expectedRed, accuracy: 0.001)
                }
            }
        }
    }

    @MainActor
    func testReturningToSystemUsesSystemThemeInsteadOfPreviousOverride() throws {
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let systemLight = SystemAppearanceObserver.scheme(for: light)
        let systemDark = SystemAppearanceObserver.scheme(for: dark)
        XCTAssertEqual(AppAppearance.dark.resolvedColorScheme(system: systemLight), .dark)
        XCTAssertEqual(AppAppearance.system.resolvedColorScheme(system: systemLight), .light)
        XCTAssertEqual(AppAppearance.light.resolvedColorScheme(system: systemDark), .light)
        XCTAssertEqual(AppAppearance.system.resolvedColorScheme(system: systemDark), .dark)
        // An automatic system change must not override an explicit user choice.
        XCTAssertEqual(AppAppearance.dark.resolvedColorScheme(system: systemDark), .dark)
        XCTAssertEqual(AppAppearance.light.resolvedColorScheme(system: systemLight), .light)
    }

    @MainActor
    func testDisabledRestoreDoesNotResolveSavedBookmarkOrReopenLaterInSession() async {
        preferences.set(Data("invalid bookmark".utf8), forKey: "workspaceBookmark")
        preferences.set(false, forKey: PreferenceKeys.reopenFolder)
        let store = WorkspaceStore(preferences: preferences)
        await store.restore()
        XCTAssertNil(store.root)
        XCTAssertNil(store.errorMessage)
        preferences.set(true, forKey: PreferenceKeys.reopenFolder)
        await store.restore()
        XCTAssertNil(store.root)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testOpeningPreferenceAppliesToNextNoteAndPreservesDraftAndManualModeOnRefresh() async throws {
        let repository = MarkdownRepository(root: root, fileAccess: SettingsFileAccess())
        let store = WorkspaceStore(repository: repository, preferences: preferences)
        _ = await store.create(title: "First", subject: "")
        let second = try await repository.create(title: "Second", subject: "")
        store.notes.append(second.note)
        store.setBody("# My draft\n")
        preferences.set(NoteOpeningMode.preview.rawValue, forKey: PreferenceKeys.openingMode)
        XCTAssertFalse(store.preview)
        XCTAssertEqual(store.draft?.body, "# My draft\n")
        await store.select(second.note.id)
        XCTAssertTrue(store.preview)
        let saved = try await repository.load(id: "First.md")
        XCTAssertEqual(saved.note.body, "# My draft\n")

        store.preview = false
        await store.refresh()
        XCTAssertFalse(store.preview)
        await store.select("First.md")
        XCTAssertTrue(store.preview)

        let nextSession = WorkspaceStore(repository: repository, preferences: preferences)
        nextSession.notes = store.notes
        await nextSession.select(second.note.id)
        XCTAssertTrue(nextSession.preview)
        _ = await nextSession.create(title: "New", subject: "")
        XCTAssertFalse(nextSession.preview)
    }

    @MainActor
    func testUnknownModeFallsBackToEditingAndInvalidMetadataDoesNotOpenPreview() async throws {
        let repository = MarkdownRepository(root: root, fileAccess: SettingsFileAccess())
        let first = try await repository.create(title: "First", subject: "")
        preferences.set("obsolete-mode", forKey: PreferenceKeys.openingMode)
        let store = WorkspaceStore(repository: repository, preferences: preferences)
        store.notes = [first.note]
        await store.select(first.note.id)
        XCTAssertFalse(store.preview)

        let broken = try await repository.create(title: "Broken", subject: "")
        try Data("---\ntags: [unclosed\n---\n# Body".utf8).write(to: root.appendingPathComponent(broken.note.id))
        store.notes.append(broken.note)
        preferences.set(NoteOpeningMode.preview.rawValue, forKey: PreferenceKeys.openingMode)
        await store.select(broken.note.id)
        XCTAssertNotNil(store.draft?.issue)
        XCTAssertFalse(store.preview)
    }
}
