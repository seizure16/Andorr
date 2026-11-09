import XCTest
@testable import AndorrCore

final class RepositoryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("andorr-tests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Maths/Algèbre"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testMilestoneSurvivesNewRepositoryAndRebuiltIndex() async throws {
        let source = "# Espaces vectoriels\n\nUne base est une famille libre et génératrice.\n"
        let path = "Maths/Algèbre/Espaces vectoriels.md"
        try Data(source.utf8).write(to: root.appendingPathComponent(path))
        let repository = makeRepository(root: root)
        var loaded = try await repository.load(id: path)
        loaded.note.status = .toReview
        _ = try await repository.save(loaded.note, expected: loaded.bytes)

        let relaunched = makeRepository(root: root)
        let index = try await relaunched.scan()
        let filtered = index.notes.filter(NoteQuery(onlyToReview: true).matches)
        XCTAssertEqual(filtered.map(\.id), [path], "Index warnings: \(index.warnings)")
        XCTAssertEqual(filtered.first?.body, source)
        XCTAssertEqual(filtered.first?.subject, "Maths/Algèbre")
    }

    func testExternalChangeCannotBeOverwritten() async throws {
        let repository = makeRepository(root: root)
        var loaded = try await repository.create(title: "Note", subject: "Maths")
        let external = "# Modification externe\n"
        try Data(external.utf8).write(to: root.appendingPathComponent(loaded.note.id), options: .atomic)
        loaded.note.status = .toReview
        do {
            _ = try await repository.save(loaded.note, expected: loaded.bytes)
            XCTFail("A conflict must be reported")
        } catch NoteError.conflict {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(loaded.note.id), encoding: .utf8), external)
    }

    func testSuccessiveBodyAndMetadataWritesUseLatestSnapshot() async throws {
        let repository = makeRepository(root: root)
        var loaded = try await repository.create(title: "Révision", subject: "")
        loaded.note.status = .toReview
        loaded = try await repository.save(loaded.note, expected: loaded.bytes)
        loaded.note.body += "Texte ajouté.\n"
        loaded.note.tags = ["examen"]
        _ = try await repository.save(loaded.note, expected: loaded.bytes)
        let reopened = try await makeRepository(root: root).load(id: loaded.note.id)
        XCTAssertEqual(reopened.note.status, .toReview)
        XCTAssertEqual(reopened.note.tags, ["examen"])
        XCTAssertTrue(reopened.note.body.hasSuffix("Texte ajouté.\n"))
    }

    func testScanKeepsRootNotesAndEmptySubjectsAndIgnoresHiddenFiles() async throws {
        let repository = makeRepository(root: root)
        _ = try await repository.create(title: "Accueil", subject: "")
        try Data("# caché".utf8).write(to: root.appendingPathComponent(".hidden.md"))
        try Data("pdf".utf8).write(to: root.appendingPathComponent("annexe.pdf"))
        let index = try await repository.scan()
        XCTAssertEqual(index.notes.map(\.id), ["Accueil.md"], "Index warnings: \(index.warnings)")
        XCTAssertEqual(index.notes.first?.subject, "")
        XCTAssertTrue(index.subjects.contains("Maths/Algèbre"))
    }

    func testInvalidMetadataIsVisibleAndCannotBeSaved() async throws {
        let repository = makeRepository(root: root)
        let text = "---\ntags: [unclosed\n---\n# Note\n"
        try Data(text.utf8).write(to: root.appendingPathComponent("Cassée.md"))
        let index = try await repository.scan()
        XCTAssertNotNil(index.notes.first?.issue, "Index warnings: \(index.warnings)")
        let loaded = try await repository.load(id: "Cassée.md")
        do { _ = try await repository.save(loaded.note, expected: loaded.bytes); XCTFail("Invalid YAML must not be rewritten") }
        catch {}
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Cassée.md"), encoding: .utf8), text)
    }

    func testDuplicateAndEscapingNamesAreRejected() async throws {
        let repository = makeRepository(root: root)
        _ = try await repository.create(title: "Cours", subject: "")
        do { _ = try await repository.create(title: "Cours", subject: ""); XCTFail("Duplicate accepted") } catch NoteError.alreadyExists {} catch { XCTFail("\(error)") }
        do { _ = try await repository.create(title: "../dehors", subject: ""); XCTFail("Invalid name accepted") } catch NoteError.invalidName {} catch { XCTFail("\(error)") }
        do { _ = try await repository.create(title: "Cours", subject: ".."); XCTFail("Escaping path accepted") } catch NoteError.outsideWorkspace {} catch { XCTFail("\(error)") }
    }

    func testSymlinksCannotEscapeWorkspace() async throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("andorr-outside-\(UUID())")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("# Externe".utf8).write(to: outside.appendingPathComponent("Secret.md"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Lien"), withDestinationURL: outside)
        let repository = makeRepository(root: root)
        let index = try await repository.scan()
        XCTAssertTrue(index.notes.isEmpty)
        do { _ = try await repository.load(id: "Lien/Secret.md"); XCTFail("Symlink escaped root") } catch NoteError.outsideWorkspace {} catch { XCTFail("\(error)") }
    }
}
