import Foundation

public enum ReviewStatus: String, CaseIterable, Sendable, Identifiable {
    case inProgress = "in_progress"
    case toReview = "to_review"
    case reviewed = "reviewed"

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .inProgress: "En cours"
        case .toReview: "À revoir"
        case .reviewed: "Révisé"
        }
    }
}

public struct Note: Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var subject: String
    public var body: String
    public var status: ReviewStatus
    public var tags: [String]
    public var issue: String?

    public init(id: String, title: String, subject: String, body: String,
                status: ReviewStatus = .inProgress, tags: [String] = [], issue: String? = nil) {
        self.id = id; self.title = title; self.subject = subject; self.body = body
        self.status = status; self.tags = tags; self.issue = issue
    }
}

public struct NoteQuery: Sendable, Equatable {
    public var text: String
    public var onlyToReview: Bool
    public var tag: String?

    public init(text: String = "", onlyToReview: Bool = false, tag: String? = nil) {
        self.text = text; self.onlyToReview = onlyToReview; self.tag = tag
    }

    public var isActive: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || onlyToReview || tag != nil
    }

    public func matches(_ note: Note) -> Bool {
        let matchingTag = tag.map { query in
            note.tags.contains { $0.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        } ?? true
        return (!onlyToReview || note.status == .toReview)
        && matchingTag
        && (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (note.title + "\n" + note.body).range(of: text.trimmingCharacters(in: .whitespacesAndNewlines),
                options: [.caseInsensitive, .diacriticInsensitive]) != nil)
    }
}

public enum NoteError: LocalizedError {
    case invalidUTF8, invalidFrontmatter(String), conflict, outsideWorkspace, invalidName, alreadyExists

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8: "Ce fichier n’est pas encodé en UTF-8. Il n’a pas été modifié."
        case .invalidFrontmatter(let reason): "En-tête YAML invalide : \(reason). Le fichier n’a pas été modifié."
        case .conflict: "Le fichier a changé en dehors d’Andorr. Votre brouillon est conservé. Rechargez le fichier ou enregistrez une copie."
        case .outsideWorkspace: "Ce chemin sort du dossier de cours autorisé."
        case .invalidName: "Choisissez un nom sans /, : ou caractère de contrôle."
        case .alreadyExists: "Une note porte déjà ce nom dans cette matière."
        }
    }
}
