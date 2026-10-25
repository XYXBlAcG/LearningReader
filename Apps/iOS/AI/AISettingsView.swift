import SwiftUI
import UIKit
import AICore

struct AISettingsView: View {
    @EnvironmentObject private var workspace: AIWorkspace
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("服务") {
                    ForEach(workspace.settings.profiles) { profile in
                        NavigationLink { AIProfileEditor(profile: profile) } label: {
                            VStack(alignment: .leading) {
                                Text(profile.name.isEmpty ? profile.model : profile.name)
                                Text(profile.model).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.onDelete { indexes in
                        let profiles = indexes.map { workspace.settings.profiles[$0] }
                        profiles.forEach(workspace.remove)
                    }
                    NavigationLink("添加服务") { AIProfileEditor(profile: AIProfile()) }
                }
                Section("默认服务") {
                    Picker("文字", selection: Binding(get: { workspace.settings.textProfileID }, set: { value in
                        var settings = workspace.settings; settings.textProfileID = value; workspace.update(settings)
                    })) {
                        Text("未选择").tag(Optional<UUID>.none)
                        ForEach(workspace.settings.profiles) { profile in Text(profile.name.isEmpty ? profile.model : profile.name).tag(Optional(profile.id)) }
                    }
                    Picker("图片", selection: Binding(get: { workspace.settings.imageProfileID }, set: { value in
                        var settings = workspace.settings; settings.imageProfileID = value; workspace.update(settings)
                    })) {
                        Text("使用文字服务（须支持图片）").tag(Optional<UUID>.none)
                        ForEach(workspace.settings.profiles.filter(\.supportsImages)) { profile in Text(profile.name.isEmpty ? profile.model : profile.name).tag(Optional(profile.id)) }
                    }
                }
                Section {
                    NavigationLink("讲解提示词") { AIPromptEditor() }
                }
            }
            .navigationTitle("AI 设置")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .alert("AI 设置", isPresented: Binding(get: { workspace.issue != nil }, set: { if !$0 { workspace.issue = nil } })) {
                Button("知道了") { workspace.issue = nil }
            } message: { Text(workspace.issue ?? "") }
        }
    }
}

struct AIProfileEditor: View {
    @EnvironmentObject private var workspace: AIWorkspace
    @Environment(\.dismiss) private var dismiss
    @State var profile: AIProfile
    @State private var key = ""
    @State private var status: String?
    @State private var testing = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                TextField("配置名称", text: $profile.name)
                Picker("接口", selection: $profile.api) {
                    ForEach(AIProtocol.allCases, id: \.self) { Text($0.title).tag($0) }
                }.onChange(of: profile.api) { old, new in
                    if profile.baseURL == old.defaultURL { profile.baseURL = new.defaultURL }
                }
                TextField("API 基础地址", text: $profile.baseURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("API Key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("模型 ID", text: $profile.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("支持图片", isOn: $profile.supportsImages)
            }.disabled(testing)
            if let endpoint = try? profile.endpoint() {
                Section("请求地址") { Text(endpoint.absoluteString).font(.caption).textSelection(.enabled) }
            }
            Section {
                Button("测试文字连接") { test(image: false) }.disabled(testing)
                Button("测试图片输入") { test(image: true) }.disabled(testing || !profile.supportsImages)
                if testing { Button("停止测试") { task?.cancel(); testing = false } }
                Text("测试会发送一个小请求，按服务商规则计费。").font(.caption).foregroundStyle(.secondary)
                if let status { Text(status).font(.callout).textSelection(.enabled) }
            }
        }
        .navigationTitle("AI 服务")
        .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button("保存") {
                do { try workspace.save(profile, key: key); dismiss() }
                catch { status = error.localizedDescription }
            }.disabled(testing)
        } }
        .task {
            do { key = try workspace.key(for: profile) }
            catch AIError.missingKey { }
            catch { status = error.localizedDescription }
        }
        .onDisappear { task?.cancel() }
    }

    private func test(image: Bool) {
        testing = true; status = nil
        let configuration = profile, secret = key
        task = Task {
            do {
                let picture: AIImage?
                if image {
                    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 160))
                    let data = renderer.jpegData(withCompressionQuality: 0.85) { context in
                        UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 160))
                        ("2 + 3 = ?" as NSString).draw(at: CGPoint(x: 30, y: 55), withAttributes: [.font: UIFont.systemFont(ofSize: 38), .foregroundColor: UIColor.black])
                    }
                    picture = AIImage(data: data, mimeType: "image/jpeg")
                } else { picture = nil }
                let request = AIRequest(profile: configuration, key: secret, system: "只简短回答用户问题。", messages: [.init(role: .user, text: image ? "请读图中的算式并给出结果。" : "请回复：连接成功。", image: picture)])
                try await AIClient().generate(request) { text in await MainActor.run { status = text } }
                status = (image ? "图片请求完成：\n" : "文字请求完成：\n") + (status ?? "")
            } catch { if !Task.isCancelled { status = error.localizedDescription } }
            testing = false
        }
    }
}

struct AIPromptEditor: View {
    @EnvironmentObject private var workspace: AIWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var image = ""
    @State private var teaching = ""
    @State private var formulas = ""
    var body: some View {
        Form {
            Section("文字讲解") { TextEditor(text: $text).frame(minHeight: 130) }
            Section("图片讲题") { TextEditor(text: $image).frame(minHeight: 130) }
            Section("教学规范") { TextEditor(text: $teaching).frame(minHeight: 240) }
            Section("公式规范") { TextEditor(text: $formulas).frame(minHeight: 200) }
            Section {
                Button("恢复默认提示词") { text = AIPrompts.text; image = AIPrompts.image; teaching = AIPrompts.teaching; formulas = AIPrompts.formulas }
            }
        }
        .navigationTitle("讲解提示词")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存") {
            var settings = workspace.settings; settings.textPrompt = text; settings.imagePrompt = image
            settings.teachingRules = teaching; settings.formulaRules = formulas
            workspace.update(settings)
            if workspace.issue == nil { dismiss() }
        } } }
        .task {
            text = workspace.settings.textPrompt; image = workspace.settings.imagePrompt
            teaching = workspace.settings.teachingRules; formulas = workspace.settings.formulaRules
        }
    }
}
