import SwiftUI
import AICore

struct AIInvocationView: View {
    @ObservedObject var invocation:AIInvocation
    let onMaterial:(AIMaterial)->Void
    @EnvironmentObject private var workspace:AIWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var settings=false
    var body:some View {
        Group {
            if let conversation=invocation.conversation {
                AIConversationView(session:conversation,onMaterial:onMaterial)
            } else {
                NavigationStack {
                    VStack(spacing:20) {
                        if invocation.preparing { ProgressView("正在读取选区与文章") }
                        else if let issue=invocation.issue {
                            Image(systemName:"exclamationmark.triangle").font(.largeTitle)
                            Text(issue).textSelection(.enabled)
                            Button("复制诊断") { UIPasteboard.general.string=invocation.action.title+"\n"+issue }
                            Button("AI 设置") { settings=true }
                            if invocation.material != nil { Button("重试") { start() }.buttonStyle(.borderedProminent) }
                        } else if let material=invocation.material {
                            Text(material.title).font(.headline).lineLimit(2)
                            Text(material.text).font(.callout).lineLimit(5).foregroundStyle(.secondary)
                            Toggle("使用整篇文章作为上下文",isOn:$invocation.includeDocument)
                            Button("开始"+invocation.action.title) { start() }.buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(24).frame(maxWidth:.infinity,maxHeight:.infinity)
                    .navigationTitle(invocation.action.title).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { invocation.cancel();dismiss() } } }
                }
            }
        }
        .task { automaticallyStart() }
        .onChange(of:invocation.preparing) { automaticallyStart() }
        .sheet(isPresented:$settings) { AISettingsView() }
    }
    private func automaticallyStart() {
        if !invocation.preparing && !invocation.needsContextChoice && invocation.issue == nil && invocation.conversation == nil { start() }
    }
    private func start() {
        invocation.start { material,action,include in try workspace.conversation(for:material,action:action,includeDocument:include) }
    }
}
