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
    @Published private(set) var documents: [HTMLDocument] = []
    @Published private(set) var importResults: [String] = []
    @Published private(set) var failedFiles: [URL] = []
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
        do { documents = try store.documents() }
        catch { report(error, stage: "恢复最近阅读") }
    }

    func importFiles(_ urls: [URL]) {
        guard !importing else { return }
        discardPending()
        guard pending == nil else { return }
        issue = nil
        importing = true
        importResults = []
        failedFiles = []
        let store = store
        operation = Task {
            defer { importing = false; operation = nil }
            for url in urls {
            if Task.isCancelled { break }
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
                if draft.entries.count == 1 {
                    let document = try store.accept(draft, entry: draft.entries[0])
                    pending = nil
                    documents = try store.documents()
                    importResults.append(url.lastPathComponent + " · 已导入")
                    if urls.count == 1 { open(document) }
                } else { presentation = .choose(draft); return }
            } catch is CancellationError { }
            catch {
                failedFiles.append(url)
                importResults.append(url.lastPathComponent + " · " + error.localizedDescription)
                discardPending()
            }
            }
        }
    }

    func choose(_ entry: String) {
        guard let pending else { return }
        do {
            let document = try store.accept(pending, entry: entry)
            self.pending = nil
            documents = try store.documents()
            presentation = .local(.local(document, file: try store.fileURL(for: document), root: store.rootURL(for: document)))
        } catch { report(error, stage: "确认 HTML 导入") }
    }

    func open(_ document: HTMLDocument) {
        do {
            let document = try store.markOpened(document)
            documents = try store.documents()
            presentation = .local(.local(document, file: try store.fileURL(for: document), root: store.rootURL(for: document)))
        } catch { report(error, stage: "打开最近 HTML") }
    }

    func remove(_ document: HTMLDocument) {
        do {
            try store.remove(document)
            documents = try store.documents()
            removeWebsiteData(document.id)
        } catch { report(error, stage: "移除 HTML") }
    }

    func rename(_ document: HTMLDocument, title: String) {
        do { try store.rename(document, title: title); documents = try store.documents() }
        catch { report(error, stage: "修改网页名称") }
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
