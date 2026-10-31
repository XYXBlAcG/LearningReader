import SwiftUI
import LearningCore

struct CourseGlossaryContext {
    let json: String
    let mode: String
    let targets: Set<ReaderDocumentTarget>
    let open: (ReaderDocumentTarget) -> Void
    init(data: Data, mode: String, open: @escaping (ReaderDocumentTarget) -> Void) throws {
        let links = try JSONDecoder().decode(CourseGlossaryLinks.self, from: data)
        targets = Set(links.terms.flatMap(\.notes))
        json = String(decoding: data, as: UTF8.self)
        self.mode = mode
        self.open = open
    }
}

private struct CourseGlossaryKey: EnvironmentKey { static let defaultValue: CourseGlossaryContext? = nil }
extension EnvironmentValues {
    var courseGlossary: CourseGlossaryContext? {
        get { self[CourseGlossaryKey.self] }
        set { self[CourseGlossaryKey.self] = newValue }
    }
}

private struct CourseGlossaryLinks: Decodable {
    struct Term: Decodable { let notes: [ReaderDocumentTarget] }
    let terms: [Term]
}
