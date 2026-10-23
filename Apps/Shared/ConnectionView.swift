import SwiftUI
import LearningCore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct ConnectionView: View {
    @ObservedObject var model: ReaderModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("githubClientID") private var clientID = ""
    @State private var challenge: DeviceChallenge?
    @State private var loginTask: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            Form {
                Section("GitHub") {
                    LabeledContent("账号", value: model.authorized ? model.account : "尚未登录")
                    TextField("GitHub App Client ID", text: $clientID).autocorrectionDisabled().disabled(model.authenticating)
                    Button(model.authorized ? "重新登录 GitHub" : "登录 GitHub") {
                        loginTask = Task {
                            do {
                                try await model.signIn(clientID: clientID) { challenge = $0 }
                                challenge = nil
                                dismiss()
                                model.sync()
                            } catch is CancellationError { challenge = nil }
                            catch { challenge = nil; model.issue = error.localizedDescription }
                        }
                    }.disabled(clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.authenticating)
                    if model.authorized { Button("退出登录，保留离线课程", role: .destructive) { model.signOut() }.disabled(model.authenticating) }
                }
                if let challenge {
                    Section("在 GitHub 确认登录") {
                        Text(challenge.user_code).font(.title2.monospaced()).textSelection(.enabled)
                        Button("复制验证码") {
                            #if os(iOS)
                            UIPasteboard.general.string = challenge.user_code
                            #else
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(challenge.user_code, forType: .string)
                            #endif
                        }
                        Link("打开 GitHub 验证页面", destination: challenge.verification_uri)
                        Text("确认后返回知序，登录将自动完成。").font(.caption)
                        Button("取消登录") { loginTask?.cancel() }
                    }
                }
                Section {
                    Link("注册 GitHub App", destination: URL(string: "https://github.com/settings/apps/new")!)
                    Link("管理 GitHub App 仓库授权", destination: URL(string: "https://github.com/settings/installations")!)
                    Text("启用 Device Flow，Contents 设为 Read-only，授权需要学习的私有仓库。填写 Client ID；无需 Client Secret 或私钥。").font(.caption).foregroundStyle(.secondary)
                    if let revision = model.snapshot?.revision { LabeledContent("离线版本", value: String(revision.prefix(10))) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("GitHub 设置")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .alert("GitHub 登录", isPresented: Binding(get: { model.issue != nil }, set: { if !$0 { model.issue = nil } })) { Button("知道了") { model.issue = nil } } message: { Text(model.issue ?? "") }
            .onDisappear { loginTask?.cancel() }
        }.frame(minWidth: 320, minHeight: 420)
    }
}
