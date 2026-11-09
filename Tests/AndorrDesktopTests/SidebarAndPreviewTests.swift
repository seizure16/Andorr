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
        XCTAssertEqual(store.visibleSubjects, ["Algorithmique", "Réseaux", ""])
        store.search = "Routage"
        XCTAssertEqual(store.visibleSubjects, ["Réseaux"])
        store.search = "Accueil"
        XCTAssertEqual(store.visibleSubjects, [""])
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
