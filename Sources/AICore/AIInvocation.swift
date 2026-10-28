import Foundation
import Combine

@MainActor
public final class AIInvocation: ObservableObject, Identifiable {
    public let id = UUID()
    public let action: AISelectionAction
    @Published public private(set) var preparing = true
    @Published public private(set) var material: AIMaterial?
    @Published public private(set) var issue: String?
    @Published public private(set) var needsContextChoice = false
    @Published public var includeDocument: Bool
    @Published public var conversation: AIConversation?
    private let askForContext: Bool
    private var reading: Task<Void,Never>?
    private var deadline: Task<Void,Never>?

    public init(action: AISelectionAction, askForContext: Bool, includeDocument: Bool) {
        self.action=action; self.askForContext=askForContext; self.includeDocument=includeDocument
    }
    public init(conversation:AIConversation) {
        action=conversation.record.action;askForContext=false;includeDocument=true
        preparing=false;self.conversation=conversation
    }
    public func prepare(timeoutNanoseconds: UInt64 = 8_000_000_000, load: @escaping @MainActor () async throws -> AIMaterial) {
        reading?.cancel(); deadline?.cancel()
        reading = Task { [weak self] in
            do {
                let value = try await load()
                guard !Task.isCancelled, let self, self.preparing else { return }
                self.deadline?.cancel()
                self.material=value
                self.needsContextChoice=self.askForContext && !value.document.isEmpty && value.image == nil
                if value.document.isEmpty { self.includeDocument=false }
                self.preparing=false
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.fail("读取材料：" + error.localizedDescription)
            }
        }
        deadline=Task { [weak self] in
            do { try await Task.sleep(nanoseconds:timeoutNanoseconds) }
            catch { return }
            guard let self, self.preparing else { return }
            self.reading?.cancel()
            self.fail(AISelectionError.timeout.localizedDescription)
        }
    }
    public func start(make: (AIMaterial,AISelectionAction,Bool) throws -> AIConversation) {
        guard let material, !preparing else { return }
        needsContextChoice=false; issue=nil
        do { let session=try make(material,action,includeDocument); conversation=session; session.retry() }
        catch { fail(error.localizedDescription) }
    }
    public func fail(_ message: String) { deadline?.cancel(); preparing=false; needsContextChoice=false; issue=message }
    public func cancel() { reading?.cancel(); deadline?.cancel(); conversation?.stop() }
    deinit { reading?.cancel(); deadline?.cancel() }
}
