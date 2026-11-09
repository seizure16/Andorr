import Foundation
@testable import AndorrCore

/// Use only when the runner cannot reach filecoordinationd. All parsing,
/// conflict detection and actual disk writes remain production code.
private struct DirectTestFileAccess: FileAccess {
    func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }
    func write(_ url: URL, operation: (URL) throws -> Void) throws { try operation(url) }
}

func makeRepository(root: URL) -> MarkdownRepository {
    if ProcessInfo.processInfo.environment["ANDORR_TEST_COORDINATION"] == "direct" {
        return MarkdownRepository(root: root, fileAccess: DirectTestFileAccess())
    }
    return MarkdownRepository(root: root)
}
