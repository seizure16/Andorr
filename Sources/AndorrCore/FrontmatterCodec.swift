import Foundation
import Yams

/// Keeps the original header verbatim when only the body changes. Unknown YAML
/// values survive metadata edits; comments/formatting may then be normalized.
public struct MarkdownDocument {
    public var body: String
    public var status: ReviewStatus
    public var tags: [String]
    private var header: String?
    private var fields: [String: Any]
    private var originalStatus: ReviewStatus
    private var originalTags: [String]
    private var newline: String
    private var bom: String

    public init(source: String) throws {
        var text = source
        bom = text.hasPrefix("\u{FEFF}") ? "\u{FEFF}" : ""
        if !bom.isEmpty { text.removeFirst() }
        newline = text.contains("\r\n") ? "\r\n" : "\n"
        fields = [:]; header = nil
        if text == "---" { throw NoteError.invalidFrontmatter("délimiteur de fermeture manquant") }
        if let opening = text.range(of: "\\A---(?:\\r\\n|\\n)", options: .regularExpression) {
            newline = text[opening].hasSuffix("\r\n") ? "\r\n" : "\n"
            guard let closing = text.range(of: "(?m)^(?:---|\\.\\.\\.)(?:\\r\\n|\\n|\\z)", options: .regularExpression,
                                           range: opening.upperBound..<text.endIndex) else {
                throw NoteError.invalidFrontmatter("délimiteur de fermeture manquant")
            }
            let yaml = String(text[opening.upperBound..<closing.lowerBound])
            do {
                if let decoded = try Yams.load(yaml: yaml) {
                    guard let mapping = decoded as? [String: Any] else {
                        throw NoteError.invalidFrontmatter("un dictionnaire est attendu")
                    }
                    fields = mapping
                }
            } catch { throw NoteError.invalidFrontmatter(error.localizedDescription) }
            header = String(text[..<closing.upperBound])
            body = String(text[closing.upperBound...])
        } else { body = text }

        if let value = fields["status"] {
            guard let raw = value as? String,
                  let parsed = ReviewStatus(rawValue: raw) ?? ReviewStatus.allCases.first(where: { $0.title == raw }) else {
                throw NoteError.invalidFrontmatter("statut non reconnu")
            }
            status = parsed
        } else { status = .inProgress }
        if let value = fields["tags"] {
            guard let parsed = value as? [String] else { throw NoteError.invalidFrontmatter("tags doit être une liste de textes") }
            tags = Self.normalizedTags(parsed)
        } else { tags = [] }
        originalStatus = status; originalTags = tags
    }

    public func serialized() throws -> String {
        if status == originalStatus && tags == originalTags {
            return bom + (header ?? "") + body
        }
        var updated = fields
        updated["status"] = status.rawValue
        updated["tags"] = Self.normalizedTags(tags)
        let yaml = try Yams.dump(object: updated, sortKeys: true)
            .replacingOccurrences(of: "\n", with: newline)
        return bom + "---" + newline + yaml + "---" + newline + body
    }

    public static func normalizedTags(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard !tag.isEmpty, seen.insert(tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted else { return nil }
            return tag
        }
    }
}
