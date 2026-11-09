import XCTest
@testable import AndorrCore

final class SearchAndPreviewTests: XCTestCase {
    func testCombinedSearchStatusAndTagAcrossSubjects() {
        let notes = [
            Note(id: "Maths/A.md", title: "Algèbre", subject: "Maths", body: "Une définition", status: .toReview, tags: ["Examen"]),
            Note(id: "Info/B.md", title: "Complexité", subject: "Info", body: "Définition d’un algorithme", status: .toReview, tags: ["examen"]),
            Note(id: "Maths/C.md", title: "Autre", subject: "Maths", body: "Définition", status: .reviewed, tags: ["examen"])
        ]
        XCTAssertEqual(notes.filter(NoteQuery(text: "DEFINITION", onlyToReview: true, tag: "examen").matches).count, 2)
        XCTAssertEqual(notes.filter(NoteQuery(text: "algebre").matches).map(\.id), ["Maths/A.md"])
    }

    func testPreviewRendersMarkdownAndNeutralizesActiveContent() {
        let html = MarkdownRenderer.html("# Titre\n\n**Important**\n\n- Élément\n\n```swift\nlet x = 1\n```\n\n<script>alert(1)</script>\n\n[dangereux](javascript:alert(1))\n\n![image](https://example.com/tracking.png)")
        XCTAssertTrue(html.contains("<h1>Titre</h1>"))
        XCTAssertTrue(html.contains("<strong>Important</strong>"))
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<pre><code>let x = 1"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("href=\"javascript:"))
        XCTAssertFalse(html.contains("<img"))
    }
}
