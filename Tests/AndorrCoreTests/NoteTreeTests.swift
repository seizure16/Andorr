import XCTest
@testable import AndorrCore

final class NoteTreeTests: XCTestCase {
    private func note(_ id: String, status: ReviewStatus = .inProgress) -> Note {
        Note(id: id, title: (id as NSString).lastPathComponent,
             subject: (id as NSString).deletingLastPathComponent, body: "", status: status)
    }

    func testBuildsNestedParentsAndPutsFoldersBeforeNotesAtEveryLevel() {
        let tree = NoteTree(notes: [note("Accueil.md"), note("Maths/Intro.md"), note("Maths/Algèbre/Bases.md")])
        XCTAssertEqual(tree.folders.map(\.id), ["Maths"])
        XCTAssertEqual(tree.folders.first?.folders.map(\.name), ["Algèbre"])
        XCTAssertEqual(tree.rows().map(\.id), ["folder:Maths", "folder:Maths/Algèbre", "note:Maths/Algèbre/Bases.md", "note:Maths/Intro.md", "note:Accueil.md"])
        guard case .note(_, depth: 2) = tree.rows()[2] else { return XCTFail("Nested note needs two indentation levels") }
    }

    func testEmptyFoldersAreVisibleAndNamesSortNaturally() {
        let tree = NoteTree(notes: [], directories: ["Chapitre 10", "Chapitre 2/Vide", "Chapitre 2"])
        XCTAssertEqual(tree.rows().map(\.id), ["folder:Chapitre 2", "folder:Chapitre 2/Vide", "folder:Chapitre 10"])
    }

    func testIdenticalFolderNamesHaveDistinctPaths() {
        let tree = NoteTree(notes: [note("Maths/Cours/A.md"), note("Info/Cours/B.md")])
        XCTAssertEqual(tree.folderPaths, ["Maths", "Maths/Cours", "Info", "Info/Cours"])
        let rows = tree.rows(collapsed: ["Info/Cours"])
        XCTAssertFalse(rows.map(\.id).contains("note:Info/Cours/B.md"))
        XCTAssertTrue(rows.map(\.id).contains("note:Maths/Cours/A.md"))
    }

    func testCollapsingParentHidesAllDescendantsButKeepsRootNotes() {
        let tree = NoteTree(notes: [note("Accueil.md"), note("Maths/Algèbre/Bases.md")])
        XCTAssertEqual(tree.rows(collapsed: ["Maths"]).map(\.id), ["folder:Maths", "note:Accueil.md"])
        XCTAssertEqual(tree.rows(collapsed: tree.folderPaths).map(\.id), ["folder:Maths", "note:Accueil.md"])
        XCTAssertEqual(tree.rows().count, 4)
    }

    func testFilteredTreeKeepsOnlyMatchingNotesAndTheirAncestors() {
        let notes = [note("Maths/Cours/A.md", status: .toReview), note("Maths/TD/B.md"), note("Info/C.md")]
        let query = NoteQuery(onlyToReview: true)
        let tree = NoteTree(notes: notes.filter(query.matches))
        XCTAssertEqual(tree.folderPaths, ["Maths", "Maths/Cours"])
        XCTAssertEqual(tree.rows().map(\.id), ["folder:Maths", "folder:Maths/Cours", "note:Maths/Cours/A.md"])
    }

    func testFilteringTemporarilyExpandsPathsWithoutChangingNormalState() {
        var state = FolderExpansionState()
        state.setCollapsed(["Maths", "Info/Cours"], filtering: false)
        XCTAssertTrue(state.collapsedPaths(filtering: true).isEmpty)
        state.toggle("Maths/Cours", filtering: true)
        XCTAssertEqual(state.collapsedPaths(filtering: true), ["Maths/Cours"])
        XCTAssertEqual(state.collapsedPaths(filtering: false), ["Maths", "Info/Cours"])
        state.resetFiltered()
        XCTAssertTrue(state.collapsedPaths(filtering: true).isEmpty)
        XCTAssertEqual(state.collapsedPaths(filtering: false), ["Maths", "Info/Cours"])
    }

    func testRootOnlyAndEmptyTreesHaveNoArtificialGeneralFolder() {
        let tree = NoteTree(notes: [note("B.md"), note("A.md")])
        XCTAssertTrue(tree.folders.isEmpty)
        XCTAssertEqual(tree.rows().map(\.id), ["note:A.md", "note:B.md"])
        XCTAssertTrue(NoteTree(notes: []).rows().isEmpty)
    }
}
