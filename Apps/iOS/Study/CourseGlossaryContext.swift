import SwiftUI
import LearningCore

struct CourseGlossaryContext {
    let catalog:CourseGlossaryCatalog
    let courseID:String
    let json: String
    let mode: String
    let open: (ReaderDocumentTarget) -> Void
    init(data: Data, courseID:String, mode: String, open: @escaping (ReaderDocumentTarget) -> Void) throws {
        catalog = try JSONDecoder().decode(CourseGlossaryCatalog.self, from: data)
        self.courseID=courseID
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
