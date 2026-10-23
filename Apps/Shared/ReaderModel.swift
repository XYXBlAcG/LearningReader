import SwiftUI
import LearningCore

@MainActor
final class ReaderModel: ObservableObject {
    @Published private(set) var library = CourseLibrary()
    @Published private(set) var snapshot: CourseSnapshot?
    @Published private(set) var syncing = false
    @Published private(set) var authenticating = false
    @Published private(set) var authorized = false
    @Published private(set) var account = ""
    @Published private(set) var status = "添加课程，开始学习"
    @Published var issue: String?
    @Published var draft: CourseDraft?
    @Published var preparing = false
    @Published var workflowRunning = false
    @Published var workflowLog: String?
    private let client = GitHubClient()
    private let authorization = DeviceAuthorization()
    private let directory: URL
    private var generation = UUID()
    private var lastAttempt = Date.distantPast
    private var started = false
    private(set) var legacyState: [String: String] = [:]
    private var operation: Task<Void, Never>?
    var selected: CourseSource? { library.sources.first { $0.id == library.selectedID } }
    var legacyReadingState: Bool {
        if selected?.repositoryID == LegacyMigration.repositoryID { return true }
        #if os(macOS)
        return selected?.localPath != nil && selected?.localPath == UserDefaults.standard.string(forKey: "learningProject")
        #else
        return false
        #endif
    }
    private var libraryURL: URL { directory.appendingPathComponent("library.json") }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("LearningReader")
    }

    func start() async {
        guard !started else { return }
        started = true
        do {
            let credential = try Credentials.read()
            authorized = credential != nil
            account = credential?.login ?? ""
            library = try CourseLibrary.read(at: libraryURL)
            if library.sources.isEmpty, let migrated = try LegacyMigration.migrate(to: directory) {
                library.sources = [migrated]
                library.selectedID = migrated.id
                try library.save(at: libraryURL)
            }
            #if os(macOS)
            if let path = UserDefaults.standard.string(forKey: "learningProject") {
                legacyState = LegacyDesktopState.read(directory: LegacyDesktopState.directory, port: UserDefaults.standard.integer(forKey: "readerPort:" + path))
                if library.sources.isEmpty, FileManager.default.fileExists(atPath: path) {
                    let source = CourseSource.local(URL(fileURLWithPath: path), configuration: .standard)
                    library.sources = [source]
                    library.selectedID = source.id
                    try library.save(at: libraryURL)
                }
            }
            #endif
            if let source = selected { await select(source) }
        } catch { issue = error.localizedDescription; status = "准备失败，请重试" }
    }

    func signIn(clientID: String, onChallenge: @escaping (DeviceChallenge) -> Void) async throws {
        guard !authenticating, !syncing else { return }
        authenticating = true
        defer { authenticating = false }
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let challenge = try await authorization.begin(clientID: id)
        UserDefaults.standard.set(id, forKey: "githubClientID")
        onChallenge(challenge)
        var credential = try await authorization.authorize(challenge: challenge, clientID: id)
        credential.login = try await client.login(token: credential.accessToken)
        try Credentials.save(credential)
        authorized = true
        account = credential.login ?? ""
    }

    func signOut() {
        operation?.cancel()
        generation = UUID()
        syncing = false
        do {
            try Credentials.save(nil)
            authorized = false
            account = ""
            status = "已退出登录 · 离线内容保留"
        } catch { issue = error.localizedDescription }
    }

    func select(_ source: CourseSource) async {
        operation?.cancel()
        generation = UUID()
        library.selectedID = source.id
        snapshot = nil
        syncing = false
        do {
            try library.save(at: libraryURL)
            if source.localPath == nil { snapshot = try SnapshotStore(directory: sourceDirectory(source)).current() }
            status = snapshot == nil ? "正在准备课程…" : "离线内容已就绪"
            sync()
        } catch { issue = error.localizedDescription; status = "无法读取课程" }
    }

    func sync(automatic: Bool = false) {
        guard let source = selected, !syncing, !authenticating else { return }
        if automatic && Date().timeIntervalSince(lastAttempt) < 60 { return }
        lastAttempt = Date()
        syncing = true
        let ticket = generation
        operation = Task {
            defer { if generation == ticket { syncing = false } }
            do {
                let prepared: CourseSnapshot
                let store = SnapshotStore(directory: sourceDirectory(source))
                if let local = source.localPath {
                    status = "正在读取本地课程…"
                    prepared = try await BackgroundWork.run {
                        try store.openLocal(root: URL(fileURLWithPath: local), configuration: source.configuration)
                    }
                } else if let repository = source.repository {
                    status = "正在检查课程更新…"
                    let token = try await accessToken(required: source.isPrivate)
                    let revision = try await client.latestCommit(repository: repository, branch: source.branch, token: token)
                    try Task.checkCancellation()
                    guard generation == ticket else { return }
                    if revision == snapshot?.revision { status = "已是最新 · " + Date().formatted(date: .omitted, time: .shortened); return }
                    status = "正在下载课程…"
                    let archive = try await client.download(revision: revision, repository: repository, token: token)
                    defer { try? FileManager.default.removeItem(at: archive) }
                    try Task.checkCancellation()
                    guard generation == ticket else { return }
                    status = "正在生成目录与知识关联…"
                    prepared = try await BackgroundWork.run {
                        try store.install(archive: archive, revision: revision, configuration: source.configuration)
                    }
                } else { throw ReaderError.invalidRepository }
                try Task.checkCancellation()
                guard generation == ticket, library.selectedID == source.id else { return }
                snapshot = prepared
                if let index = library.sources.firstIndex(where: { $0.id == source.id }) { library.sources[index].title = prepared.course.manifest.title }
                try library.save(at: libraryURL)
                status = "已同步 · " + Date().formatted(date: .omitted, time: .shortened)
            } catch is CancellationError { }
            catch {
                guard generation == ticket else { return }
                status = snapshot == nil ? "下载未完成" : "同步未完成 · 离线内容保留"
                if !automatic { issue = error.localizedDescription }
            }
        }
    }

    func preview(repository value: String, branch: String, root: String, markdown: Bool, excluding: [String]) async {
        guard !preparing else { return }
        preparing = true
        defer { preparing = false }
        do {
            let repository = try Repository(value)
            let metadata: GitHubClient.Metadata
            do { metadata = try await client.metadata(repository: repository) }
            catch {
                switch error {
                case ReaderError.authorization, ReaderError.unavailable(404):
                    let token = try await accessToken(required: true)
                    metadata = try await client.metadata(repository: repository, token: token)
                default: throw error
                }
            }
            let selectedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? metadata.default_branch : branch.trimmingCharacters(in: .whitespacesAndNewlines)
            let configuration = ImportConfiguration(root: root.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")), markdown: markdown, excluding: excluding)
            let source = CourseSource.remote(repository: try Repository(metadata.full_name), repositoryID: metadata.id, branch: selectedBranch, configuration: configuration, isPrivate: metadata.private)
            let token = try await accessToken(required: metadata.private)
            let revision = try await client.latestCommit(repository: repository, branch: selectedBranch, token: token)
            let archive = try await client.download(revision: revision, repository: repository, token: token)
            defer { try? FileManager.default.removeItem(at: archive) }
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("course-preview-" + UUID().uuidString)
            var retained = false
            defer { if !retained { try? FileManager.default.removeItem(at: staging) } }
            let prepared = try await BackgroundWork.run { try SnapshotStore(directory: staging).install(archive: archive, revision: revision, configuration: configuration) }
            if Task.isCancelled { try? FileManager.default.removeItem(at: staging); return }
            draft = .init(source: source, snapshot: prepared, staging: staging)
            retained = true
        } catch is CancellationError { }
        catch { issue = error.localizedDescription }
    }

    func previewLocal(_ url: URL, markdown: Bool, excluding: [String]) async {
        guard !preparing else { return }
        preparing = true
        defer { preparing = false }
        do {
            let source = CourseSource.local(url, configuration: .init(root: "", markdown: markdown, excluding: excluding))
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("course-preview-" + UUID().uuidString)
            var retained = false
            defer { if !retained { try? FileManager.default.removeItem(at: staging) } }
            let prepared = try await BackgroundWork.run { try SnapshotStore(directory: staging).openLocal(root: url, configuration: source.configuration) }
            if Task.isCancelled { try? FileManager.default.removeItem(at: staging); return }
            draft = .init(source: source, snapshot: prepared, staging: staging)
            retained = true
        } catch is CancellationError { }
        catch { issue = error.localizedDescription }
    }

    func acceptDraft() async {
        guard let draft else { return }
        do {
            var source = draft.source
            source.title = draft.snapshot.course.manifest.title
            let destination = sourceDirectory(source)
            if source.localPath == nil && !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: draft.staging, to: destination)
            }
            if let index = library.sources.firstIndex(where: { $0.id == source.id }) { library.sources[index] = source }
            else { library.sources.append(source) }
            discardDraft()
            await select(source)
        } catch { issue = error.localizedDescription }
    }

    func discardDraft() {
        if let draft { try? FileManager.default.removeItem(at: draft.staging) }
        draft = nil
    }

    func remove(_ source: CourseSource) async {
        guard !syncing else { return }
        do {
            let updated = library.sources.filter { $0.id != source.id }
            let removingSelected = library.selectedID == source.id
            library.sources = updated
            if removingSelected { generation = UUID(); operation?.cancel(); snapshot = nil; library.selectedID = nil }
            try library.save(at: libraryURL)
            let path = sourceDirectory(source)
            if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
            if removingSelected, let next = updated.first { await select(next) }
            else if updated.isEmpty { status = "添加课程，开始学习" }
        } catch { issue = error.localizedDescription }
    }

    #if os(macOS)
    func runWorkflow() async {
        guard selected?.localPath != nil, let snapshot, let workflow = snapshot.course.manifest.workflow, !workflowRunning else { return }
        workflowRunning = true
        defer { workflowRunning = false }
        workflowLog = nil
        do { try await LocalWorkflow.run(workflow, root: snapshot.course.root) { [weak self] in self?.workflowLog = $0 } }
        catch { workflowLog = error.localizedDescription }
    }
    #endif

    private func sourceDirectory(_ source: CourseSource) -> URL { directory.appendingPathComponent("courses/" + source.id) }

    private func accessToken(required: Bool) async throws -> String? {
        guard required else { return nil }
        guard var credential = try Credentials.read() else { throw ReaderError.authorization }
        if let expiresAt = credential.expiresAt, expiresAt.timeIntervalSinceNow < 60 {
            credential = try await authorization.refresh(credential)
            try Credentials.save(credential)
        }
        return credential.accessToken
    }
}

struct CourseDraft: Identifiable {
    let id = UUID()
    let source: CourseSource
    let snapshot: CourseSnapshot
    let staging: URL
}
