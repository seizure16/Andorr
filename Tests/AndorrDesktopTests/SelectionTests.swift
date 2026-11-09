import Foundation
import XCTest
@testable import AndorrCore
@testable import AndorrDesktop

private final class SelectionFileAccess: FileAccess, @unchecked Sendable {
    let gate = DispatchSemaphore(value: 0)
    // Configured before requesting a load; no mutations while a read is blocked.
    var blockedName: String?
    var onRead: (() -> Void)?

    func read(_ url: URL) throws -> Data {
        if url.lastPathComponent == blockedName {
            onRead?()
            guard gate.wait(timeout: .now() + 5) == .success else { throw CocoaError(.fileReadUnknown) }
        }
        return try Data(contentsOf: url)
    }
    func write(_ url: URL, operation: (URL) throws -> Void) throws { try operation(url) }
}

final class SelectionTests: XCTestCase {
    @MainActor
    func testSelectionUpdatesImmediatelyAndLatestClickWinsDuringLoading() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let access = SelectionFileAccess()
        let repository = MarkdownRepository(root: root, fileAccess: access)
        let store = WorkspaceStore(repository: repository)
        _ = await store.create(title: "First", subject: "")
        let second = try await repository.create(title: "Second", subject: "")
        let third = try await repository.create(title: "Third", subject: "")
        store.notes += [second.note, third.note]

        let started = expectation(description: "Second note is loading")
        access.blockedName = "Second.md"
        access.onRead = { started.fulfill() }
        defer { access.gate.signal() }
        let worker = try XCTUnwrap(store.requestSelection("Second.md"))
        XCTAssertEqual(store.selectedNoteID, "Second.md")
        XCTAssertEqual(store.draft?.id, "First.md")
        await fulfillment(of: [started], timeout: 2)
        store.requestSelection("Third.md")
        XCTAssertEqual(store.selectedNoteID, "Third.md")
        access.gate.signal()
        await worker.value
        XCTAssertEqual(store.selectedNoteID, "Third.md")
        XCTAssertEqual(store.draft?.id, "Third.md")
        XCTAssertFalse(store.isBusy)
    }

    @MainActor
    func testSaveConflictRestoresSelectionAndKeepsDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MarkdownRepository(root: root, fileAccess: SelectionFileAccess())
        let store = WorkspaceStore(repository: repository)
        _ = await store.create(title: "First", subject: "")
        let second = try await repository.create(title: "Second", subject: "")
        store.notes.append(second.note)
        store.setBody("My unsaved draft")
        try Data("External change".utf8).write(to: root.appendingPathComponent("First.md"))
        let worker = try XCTUnwrap(store.requestSelection("Second.md"))
        XCTAssertEqual(store.selectedNoteID, "Second.md")
        await worker.value
        XCTAssertEqual(store.selectedNoteID, "First.md")
        XCTAssertEqual(store.draft?.body, "My unsaved draft")
        XCTAssertTrue(store.isDirty)
        XCTAssertNotNil(store.saveError)
    }

    @MainActor
    func testMissingFileRestoresSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MarkdownRepository(root: root, fileAccess: SelectionFileAccess())
        let store = WorkspaceStore(repository: repository)
        _ = await store.create(title: "First", subject: "")
        let second = try await repository.create(title: "Second", subject: "")
        store.notes.append(second.note)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Second.md"))
        await store.select("Second.md")
        XCTAssertEqual(store.selectedNoteID, "First.md")
        XCTAssertEqual(store.draft?.id, "First.md")
        XCTAssertNotNil(store.errorMessage)
    }
}
