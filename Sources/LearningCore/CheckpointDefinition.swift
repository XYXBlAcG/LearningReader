import Foundation

public enum CheckpointKind: String, Codable, Sendable { case single, multiple }

public struct CheckpointOption: Codable, Sendable {
    public let id: String
    public let text: String
    public let feedback: String
    public init(id: String, text: String, feedback: String) {
        self.id = id
        self.text = text
        self.feedback = feedback
    }
}

public struct CheckpointDefinition: Codable, Sendable {
    public let id: String
    public let revision: Int
    public let type: CheckpointKind
    public let stem: String
    public let options: [CheckpointOption]
    public let correct: [String]
    public let explanation: String
    public let concept: String
    public let group: String
    public let review: String
    public init(id: String, revision: Int, type: CheckpointKind, stem: String, options: [CheckpointOption], correct: [String], explanation: String, concept: String, group: String, review: String) {
        self.id = id
        self.revision = revision
        self.type = type
        self.stem = stem
        self.options = options
        self.correct = correct
        self.explanation = explanation
        self.concept = concept
        self.group = group
        self.review = review
    }
}
