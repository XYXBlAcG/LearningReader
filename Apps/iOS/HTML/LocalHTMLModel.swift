import SwiftUI
import LearningCore
import LocalHTML
import WebKit

@MainActor
final class LocalHTMLModel: ObservableObject {
    enum Presentation: Identifiable {
        case choose(HTMLImportDraft)
        case read(HTMLDocument, file: URL, root: URL)
        var id: UUID {
            switch self {
            case .choose(let draft): return draft.id
            case .read(let document, _, _): return document.id
            }
        }
    }

    @Published private(set) var recent: HTMLDocument?
    @Published private(set) var importing = false
    @Published var issue: String?
    @Published var presentation: Presentation?
    private let store: LocalHTMLStore
    private var pending: HTMLImportDraft?
    private var operation: Task<Void, Never>?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = LocalHTMLStore(directory: support.appendingPathComponent("LocalHTML"))
        do { recent = try store.recent() }
        catch { issue = error.localizedDescription }
    }

    func importFile(_ url: URL) {
        guard !importing else { return }
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
            catch { issue = error.localizedDescription }
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
            presentation = .read(document, file: try store.fileURL(for: document), root: store.rootURL(for: document))
        } catch { issue = error.localizedDescription }
    }

    func openRecent() {
        guard let recent else { return }
        do {
            let document = try store.markOpened(recent)
            self.recent = document
            presentation = .read(document, file: try store.fileURL(for: document), root: store.rootURL(for: document))
        } catch { issue = error.localizedDescription }
    }

    func clear() {
        do {
            let previous = recent
            try store.clear()
            recent = nil
            if let previous { removeWebsiteData(previous.id) }
        }
        catch { issue = error.localizedDescription }
    }

    private func removeWebsiteData(_ id: UUID) {
        WKWebsiteDataStore.remove(forIdentifier: id) { [weak self] error in
            if let error { self?.issue = error.localizedDescription }
        }
    }

    func discardPending() {
        operation?.cancel()
        guard let pending else { return }
        do { try store.discard(pending); self.pending = nil }
        catch { issue = error.localizedDescription }
    }
}
