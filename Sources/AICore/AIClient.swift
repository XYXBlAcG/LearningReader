import Foundation

public final class AIClient: Sendable {
    private let session: URLSession
    private let ownsSession: Bool
    public init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 300
        self.session = session ?? URLSession(configuration: configuration, delegate: AIRedirectPolicy(), delegateQueue: nil)
        ownsSession = session == nil
    }
    deinit { if ownsSession { session.invalidateAndCancel() } }

    public func generate(_ request: AIRequest, onThinking: @Sendable () async -> Void = {}, onText: @Sendable (String) async -> Void) async throws {
        let (bytes, response) = try await session.bytes(for: request.urlRequest())
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidStream }
        guard (200..<300).contains(http.statusCode) else { throw AIError.service(http.statusCode) }
        guard http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true else { throw AIError.invalidStream }
        var parser = SSEParser()
        var line = Data()
        var output = ""
        var published = Date.distantPast
        var completed = false
        for try await byte in bytes {
            try Task.checkCancellation()
            line.append(byte)
            guard line.count <= 2_000_000 else { throw AIError.invalidStream }
            if byte != 10 { continue }
            for data in try parser.append(line) {
                for event in try AIStream.decode(data, api: request.profile.api) {
                    switch event {
                    case .text(let text):
                        output += text
                        guard output.count <= 160000 else { throw AIError.outputLimit }
                    case .thinking: await onThinking()
                    case .completed: completed = true
                    }
                }
            }
            line.removeAll(keepingCapacity: true)
            if Date().timeIntervalSince(published) >= 0.12 || completed {
                await onText(output); published = Date()
            }
            if completed { break }
        }
        if !completed {
            for data in try parser.append(line) + parser.finish() {
                for event in try AIStream.decode(data, api: request.profile.api) {
                    switch event { case .text(let text): output += text; case .thinking: await onThinking()
                    case .completed: completed = true }
                }
            }
        }
        try Task.checkCancellation()
        await onText(output)
        guard completed else { throw AIError.incomplete }
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.empty }
    }
}

private final class AIRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
