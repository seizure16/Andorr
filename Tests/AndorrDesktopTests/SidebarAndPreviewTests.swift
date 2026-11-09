import XCTest
import AndorrCore
@testable import AndorrDesktop

final class SidebarAndPreviewTests: XCTestCase {
    @MainActor
    func testFoldersPrecedeRootNotesAndKeepNaturalOrder() {
        let store = WorkspaceStore()
        store.notes = [
            Note(id: "Accueil.md", title: "Accueil", subject: "", body: ""),
            Note(id: "Réseaux/Routage.md", title: "Routage", subject: "Réseaux", body: ""),
            Note(id: "Algorithmique/Tris.md", title: "Tris", subject: "Algorithmique", body: ""),
            Note(id: "Algorithmique/Graphes.md", title: "Graphes", subject: "Algorithmique", body: "")
        ]
        XCTAssertEqual(store.sidebarTree.folders.map(\.id), ["Algorithmique", "Réseaux"])
        XCTAssertEqual(store.sidebarTree.rootNotes.map(\.id), ["Accueil.md"])
        store.search = "Routage"
        XCTAssertEqual(store.sidebarTree.folders.map(\.id), ["Réseaux"])
        store.search = "Accueil"
        XCTAssertTrue(store.sidebarTree.folders.isEmpty)
        XCTAssertEqual(store.sidebarTree.rootNotes.map(\.id), ["Accueil.md"])
    }

    @MainActor
    func testFilteringKeepsAncestorFoldersAndTemporarilyHidesEmptyFolders() {
        let store = WorkspaceStore()
        store.subjects = ["Maths", "Maths/Cours", "Maths/TD", "Vide"]
        store.notes = [
            Note(id: "Maths/Cours/A.md", title: "A", subject: "Maths/Cours", body: "", status: .toReview),
            Note(id: "Maths/TD/B.md", title: "B", subject: "Maths/TD", body: "", status: .reviewed)
        ]
        XCTAssertTrue(store.sidebarTree.folderPaths.contains("Vide"))
        store.onlyToReview = true
        XCTAssertEqual(store.sidebarTree.folderPaths, ["Maths", "Maths/Cours"])
        store.onlyToReview = false
        XCTAssertTrue(store.sidebarTree.folderPaths.contains("Vide"))
        XCTAssertTrue(store.sidebarTree.folderPaths.contains("Maths/TD"))
    }

    func testPreviewAllowsSyntheticHTMLLoadAndLocalAnchors() {
        XCTAssertEqual(PreviewNavigationPolicy.decision(for: nil, userActivatedLink: false), .allowLocal)
        XCTAssertEqual(PreviewNavigationPolicy.decision(for: URL(string: "about:blank"), userActivatedLink: false), .allowLocal)
        XCTAssertEqual(PreviewNavigationPolicy.decision(for: URL(string: "about:blank#definition"), userActivatedLink: true), .allowLocal)
    }

    func testOnlyUserActivatedWebAndMailLinksOpenExternally() throws {
        for destination in ["https://example.com", "http://example.com", "mailto:cours@example.com"] {
            let url = try XCTUnwrap(URL(string: destination))
            XCTAssertEqual(PreviewNavigationPolicy.decision(for: url, userActivatedLink: true), .openExternal(url))
            XCTAssertEqual(PreviewNavigationPolicy.decision(for: url, userActivatedLink: false), .cancel)
        }
    }

    func testPreviewRejectsUnexpectedSchemesAndMissingLinkDestination() throws {
        for destination in ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,hello", "andorr:unexpected", "about:config"] {
            let url = try XCTUnwrap(URL(string: destination))
            XCTAssertEqual(PreviewNavigationPolicy.decision(for: url, userActivatedLink: true), .cancel)
            XCTAssertEqual(PreviewNavigationPolicy.decision(for: url, userActivatedLink: false), .cancel)
        }
        XCTAssertEqual(PreviewNavigationPolicy.decision(for: nil, userActivatedLink: true), .cancel)
    }
}
