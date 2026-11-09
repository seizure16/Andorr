import XCTest
@testable import AndorrCore

final class FrontmatterTests: XCTestCase {
    func testOpeningPlainMarkdownNeverAddsMetadata() throws {
        let source = "# Un cours\n\nUne définition.\n"
        let document = try MarkdownDocument(source: source)
        XCTAssertEqual(document.status, .inProgress)
        XCTAssertEqual(document.tags, [])
        XCTAssertEqual(try document.serialized(), source)
    }

    func testStatusChangeAddsPortableMetadataAndPreservesBody() throws {
        let body = "# Cours\n\nTexte avec accents : révision.\n"
        var document = try MarkdownDocument(source: body)
        document.status = .toReview
        let reopened = try MarkdownDocument(source: document.serialized())
        XCTAssertEqual(reopened.status, .toReview)
        XCTAssertEqual(reopened.body, body)
    }

    func testUnknownNestedMetadataSurvivesStatusChange() throws {
        var document = try MarkdownDocument(source: "---\nstatus: in_progress\nauthor:\n  name: Axel\n  semester: 3\ntags: [cours]\n---\n# Contenu\n")
        document.status = .reviewed
        let saved = try document.serialized()
        XCTAssertTrue(saved.contains("name: Axel"))
        XCTAssertTrue(saved.contains("semester: 3"))
        XCTAssertEqual(try MarkdownDocument(source: saved).body, "# Contenu\n")
    }

    func testBodyOnlyEditPreservesCommentsAndHeaderFormatting() throws {
        let header = "---\n# mon commentaire\nstatus: 'to_review'\ntags: [cours, examen]\ncustom: yes\n---\n"
        var document = try MarkdownDocument(source: header + "Ancien texte")
        document.body = "Nouveau texte"
        XCTAssertEqual(try document.serialized(), header + "Nouveau texte")
    }

    func testCRLFAndBOMSurviveMetadataEdit() throws {
        let source = "\u{FEFF}---\r\nstatus: in_progress\r\n---\r\n# Cours\r\n\r\nTexte\r\n"
        var document = try MarkdownDocument(source: source)
        XCTAssertEqual(try document.serialized(), source)
        document.status = .toReview
        let output = try document.serialized()
        XCTAssertTrue(output.hasPrefix("\u{FEFF}---\r\n"))
        XCTAssertEqual(try MarkdownDocument(source: output).body, "# Cours\r\n\r\nTexte\r\n")
    }

    func testMalformedMetadataIsRejected() {
        for source in ["---\nstatus: [bad\n---\nBody", "---\nstatus: future_status\n---\nBody", "---\ntags: examen\n---\nBody", "---\nstatus: to_review\n", "---\n- a\n- b\n---\nBody"] {
            XCTAssertThrowsError(try MarkdownDocument(source: source), source)
        }
    }

    func testMixedLineEndingsKeepBodyIntact() throws {
        var document = try MarkdownDocument(source: "---\nstatus: in_progress\n---\n# Cours\r\nTexte\r\n")
        document.status = .toReview
        XCTAssertEqual(try MarkdownDocument(source: document.serialized()).body, "# Cours\r\nTexte\r\n")
    }

    func testQuotedAndMultilineTagsAndNormalization() throws {
        let document = try MarkdownDocument(source: "---\nstatus: À revoir\ntags:\n  - 'cours: chapitre 1'\n  - examen\n---\nBody")
        XCTAssertEqual(document.status, .toReview)
        XCTAssertEqual(document.tags, ["cours: chapitre 1", "examen"])
        XCTAssertEqual(MarkdownDocument.normalizedTags([" #Cours ", "cours", "", "  examen  "]), ["Cours", "examen"])
    }
}
