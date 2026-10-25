import WebKit

@MainActor
extension WKWebView {
    func readerJavaScript(_ body:String,arguments:[String:Any] = [:],world:WKContentWorld = .page) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            callAsyncJavaScript(body,arguments:arguments,in:nil,in:world) { result in
                switch result {
                case .success(let value): continuation.resume(returning:value)
                case .failure(let error): continuation.resume(throwing:error)
                }
            }
        }
    }
}
