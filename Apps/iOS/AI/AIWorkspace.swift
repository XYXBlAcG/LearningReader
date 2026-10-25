import SwiftUI
import AICore

@MainActor
final class AIWorkspace: ObservableObject {
    static let keyService = "chatgpt.nice114514.MathLearning.ai"
    @Published private(set) var settings = AISettings()
    @Published var issue: String?
    private let store: AISettingsStore

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LearningReader/AI")
        store = AISettingsStore(url: root.appendingPathComponent("settings.json"))
        do { settings = try store.load() }
        catch { issue = "无法读取 AI 设置：" + error.localizedDescription }
    }

    func key(for profile: AIProfile) throws -> String {
        guard let data = try KeychainStore.read(service: Self.keyService, account: profile.id.uuidString), let key = String(data: data, encoding: .utf8), !key.isEmpty else { throw AIError.missingKey }
        return key
    }

    func save(_ profile: AIProfile, key: String, asTextDefault:Bool = false) throws {
        _ = try profile.endpoint()
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.missingKey }
        var updated = settings
        if let index = updated.profiles.firstIndex(where: { $0.id == profile.id }) { updated.profiles[index] = profile }
        else { updated.profiles.append(profile) }
        if updated.textProfileID == nil || asTextDefault { updated.textProfileID = profile.id }
        if !profile.supportsImages && updated.imageProfileID == profile.id { updated.imageProfileID = nil }
        let previous = try KeychainStore.read(service: Self.keyService, account: profile.id.uuidString)
        try KeychainStore.save(Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8), service: Self.keyService, account: profile.id.uuidString)
        do { try store.save(updated); settings = updated; issue = nil }
        catch {
            try KeychainStore.save(previous, service: Self.keyService, account: profile.id.uuidString)
            throw error
        }
    }

    func update(_ updated: AISettings) {
        do { try store.save(updated); settings = updated; issue = nil }
        catch { issue = error.localizedDescription }
    }

    func remove(_ profile: AIProfile) {
        do {
            var updated = settings
            updated.profiles.removeAll { $0.id == profile.id }
            if updated.textProfileID == profile.id { updated.textProfileID = nil }
            if updated.imageProfileID == profile.id { updated.imageProfileID = nil }
            try store.save(updated)
            settings = updated
            try KeychainStore.save(nil, service: Self.keyService, account: profile.id.uuidString)
            issue = nil
        } catch { issue = error.localizedDescription }
    }

    func conversation(for material: AIMaterial, action:AISelectionAction = .explain, includeDocument:Bool = true) throws -> AIConversation {
        guard let profile = settings.profile(forImage: material.image != nil) else {
            throw material.image == nil ? AIError.configuration : AIError.imageUnsupported
        }
        return AIConversation(title:material.title,profile:profile,key:try key(for:profile),system:AIPrompts.system(settings:settings,image:material.image != nil,action:action),initial:try material.message(includeDocument:includeDocument),actionTitle:action.title)
    }
}

@MainActor
final class AIInteraction: ObservableObject {
    @Published var invocation: AIInvocation?
    @Published var showSettings = false
    @Published var media: AIImageSource?
    func explain(_ material: AIMaterial, workspace: AIWorkspace) {
        begin(AISelectionCommand(action:.explain,load:{material}),workspace:workspace)
    }
    func begin(_ command:AISelectionCommand,workspace:AIWorkspace) {
        invocation?.cancel()
        let run=AIInvocation(action:command.action,askForContext:workspace.settings.askForContext,includeDocument:workspace.settings.includeDocumentByDefault)
        invocation=run
        run.prepare(load:command.load)
    }
}

