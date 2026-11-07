import Foundation

public struct ReviewEvidence: Codable, Equatable, Sendable {
    public var firstStepIndependent: Bool?
    public var hintLevel: Int?
    public var resultCorrect: Bool?
    public var proofComplete: Bool?
    public var minutes: Double?
    public var error: String?

    public init(firstStepIndependent: Bool? = nil, hintLevel: Int? = nil, resultCorrect: Bool? = nil, proofComplete: Bool? = nil, minutes: Double? = nil, error: String? = nil) {
        self.firstStepIndependent = firstStepIndependent
        self.hintLevel = hintLevel
        self.resultCorrect = resultCorrect
        self.proofComplete = proofComplete
        self.minutes = minutes
        self.error = error
    }

    public func validate() throws {
        guard hintLevel.map({ (0...4).contains($0) }) ?? true,
              minutes.map({ $0 >= 0 && $0.isFinite }) ?? true else { throw CocoaError(.fileReadCorruptFile) }
    }
}

public struct ReviewSession: Codable, Equatable, Sendable {
    public let ids: [UUID]
    public var position = 0
    public var revealed = false
    public var lastGraded: UUID?
    public var evidence: ReviewEvidence?
    public var current: UUID? { ids.indices.contains(position) ? ids[position] : nil }
    public var completed: Bool { current == nil }
    public init(ids: [UUID]) { self.ids = ids }
}
