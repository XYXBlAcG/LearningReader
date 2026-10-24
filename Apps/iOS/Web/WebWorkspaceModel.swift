import SwiftUI
import LearningCore
import WebContent
import WebKit

@MainActor
final class WebWorkspaceModel: ObservableObject {
    enum Presentation: Identifiable {
        case choose(HTMLImportDraft)
        case local(WebPageSource)
        case address
        case browser(URL)
        var id: String {
            switch self {
            case .choose(let draft): return draft.id.uuidString
            case .local(let source): return source.storageID.uuidString
            case .address, .browser: return "website"
            }
        }
    }

    enum ImportKind { case file, folder }
    @Published private(set) var recent: HTMLDocument?
    @Published private(set) var importing = false
    @Published var issue: String?
    @Published var presentation: Presentation?
    @Published var picker: ImportKind?
    private let store: LocalHTMLStore
    private var pending: HTMLImportDraft?
    private var operation: Task<Void, Never>?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = LocalHTMLStore(directory: support.appendingPathComponent("LocalHTML"))
        do { recent = try store.recent() }
        catch { report(error, stage: "恢复最近阅读") }
    }

    func importFile(_ url: URL) {
        guard !importing else { return }
        discardPending()
        guard pending == nil else { return }
        issue = nil
        importing = true
        let store = store
        operation = Task {
            defer { importing = false; operation = nil }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let draft = try await BackgroundWork.run {
                    var result: Result<HTMLImportDraft, Error>?
                    var error: NSError?
                    NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { coordinated in
                        result = Result { try store.prepare(source: coordinated) }
                    }
                    if let error { throw error }
                    guard let result else { throw LocalHTMLError.unavailable }
                    return try result.get()
                }
                if Task.isCancelled { try store.discard(draft); return }
                pending = draft
                if draft.entries.count == 1 { choose(draft.entries[0]) }
                else { presentation = .choose(draft) }
            } catch is CancellationError { }
            catch { report(error, stage: "读取与复制 HTML") }
        }
    }

    func choose(_ entry: String) {
        guard let pending else { return }
        do {
            let previous = recent
            let document = try store.accept(pending, entry: entry)
            self.pending = nil
            recent = document
            if let previous { removeWebsiteData(previous.id) }
            presentation = .local(.local(document, file: try store.fileURL(for: document), root: store.rootURL(for: document)))
        } catch { report(error, stage: "确认 HTML 导入") }
    }

    func openRecent() {
        guard let recent else { return }
        do {
            let document = try store.markOpened(recent)
            self.recent = document
            presentation = .local(.local(document, file: try store.fileURL(for: document), root: store.rootURL(for: document)))
        } catch { report(error, stage: "打开最近 HTML") }
    }

    func clear() {
        do {
            let previous = recent
            try store.clear()
            recent = nil
            if let previous { removeWebsiteData(previous.id) }
        } catch { report(error, stage: "移除 HTML") }
    }

    func discardPending() {
        guard let pending else { return }
        do { try store.discard(pending); self.pending = nil }
        catch { report(error, stage: "取消 HTML 导入") }
    }

    func stop() {
        operation?.cancel()
        discardPending()
    }

    private func removeWebsiteData(_ id: UUID) {
        WKWebsiteDataStore.remove(forIdentifier: id) { [weak self] error in
            if let error { self?.report(error, stage: "清理网页存储") }
        }
    }

    private func report(_ error: Error, stage: String) {
        let failure = error as NSError
        issue = stage + "\n" + failure.localizedDescription + "\n" + failure.domain + " (" + String(failure.code) + ")"
        if let path = failure.userInfo[NSFilePathErrorKey] as? String { issue? += "\n" + path }
    }
}
