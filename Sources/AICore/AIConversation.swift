import Foundation
import Combine

@MainActor
public final class AIConversation: ObservableObject, Identifiable {
    public let id = UUID()
    public let title: String
    public let profile: AIProfile
    @Published public private(set) var messages: [AIMessage]
    @Published public private(set) var answer = ""
    @Published public private(set) var running = false
    @Published public private(set) var issue: String?
    private let client: AIClient
    private let key: String
    private let system: String
    private var task: Task<Void, Never>?
    private var generation = UUID()

    public init(title: String, profile: AIProfile, key: String, system: String, initial: AIMessage, client: AIClient = AIClient()) {
        self.client = client
        self.title = title; self.profile = profile; self.key = key; self.system = system; messages = [initial]
    }
    public func stop() { generation = UUID(); task?.cancel(); task = nil; running = false }
    public func retry() {
        stop()
        answer = ""; issue = nil; running = true
        let token = generation
        let request = AIRequest(profile: profile, key: key, system: system, messages: messages)
        let client = self.client
        task = Task { [weak self] in
            do {
                try await client.generate(request) { [weak self] text in
                    guard let target = self else { return }
                    await MainActor.run {
                        guard target.generation == token else { return }
                        target.answer = text
                    }
                }
                guard let self, self.generation == token else { return }
                self.running = false; self.task = nil
            } catch {
                guard let self, self.generation == token else { return }
                self.running = false; self.task = nil
                if !Task.isCancelled { self.issue = error.localizedDescription }
            }
        }
    }
    public func followUp(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !running, !value.isEmpty, !answer.isEmpty else { return }
        guard messages.count < 23, messages.reduce(0, { $0 + $1.text.count }) + answer.count + value.count <= 80000 else { issue = AIError.contextLimit.localizedDescription; return }
        messages.append(.init(role: .assistant, text: answer))
        messages.append(.init(role: .user, text: value))
        retry()
    }
    deinit { task?.cancel() }
}
