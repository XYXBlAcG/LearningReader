import SwiftUI
import AICore

struct AIHost: ViewModifier {
    @ObservedObject var interaction: AIInteraction
    @EnvironmentObject private var workspace: AIWorkspace
    func body(content: Content) -> some View {
        content
            .sheet(item: $interaction.conversation, onDismiss: { interaction.conversation?.stop() }) { conversation in
                AIConversationView(session: conversation) { interaction.explain($0, workspace: workspace) }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .modifier(AIPhotoHost(source: $interaction.media) { interaction.explain($0, workspace: workspace) })
            .sheet(isPresented: $interaction.showSettings) { AISettingsView() }
            .alert("讲一讲", isPresented: Binding(get: { interaction.issue != nil }, set: { if !$0 { interaction.issue = nil } })) {
                Button("AI 设置") { interaction.issue = nil; interaction.showSettings = true }
                Button("知道了", role: .cancel) { interaction.issue = nil }
            } message: { Text(interaction.issue ?? "") }
    }
}

struct AIConversationView: View {
    @ObservedObject var session: AIConversation
    let onMaterial: (AIMaterial) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var media: AIImageSource?
    @State private var renderingIssue: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text(session.title).lineLimit(1)
                    Spacer()
                    Text(session.profile.model).lineLimit(1)
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal).padding(.vertical, 8)
                AIAnswerView(markdown: transcript, onIssue: { renderingIssue = $0 })
                if session.running { HStack { ProgressView().controlSize(.small); Text("正在讲解").font(.caption); Spacer(); Button("停止") { session.stop() } }.padding(.horizontal).padding(.vertical, 8) }
                if let issue = session.issue { Text(issue).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).padding(.horizontal) }
                if let renderingIssue { Text(renderingIssue).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).padding(.horizontal) }
                HStack(alignment: .bottom) {
                    TextField("继续追问", text: $question, axis: .vertical).lineLimit(1...4)
                    Button { session.followUp(question); if session.running { question = "" } } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .disabled(session.running || session.answer.isEmpty || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("发送追问")
                }.padding()
            }
            .navigationTitle("讲一讲")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { session.stop(); dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("复制回答", systemImage: "doc.on.doc") { UIPasteboard.general.string = session.answer }.disabled(session.answer.isEmpty)
                        Button("重新讲解", systemImage: "arrow.clockwise") { session.retry() }.disabled(session.running)
                        Button("拍照提问", systemImage: "camera") { session.stop(); media = .camera }
                        Button("选择图片", systemImage: "photo") { session.stop(); media = .library }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .modifier(AIPhotoHost(source: $media, onMaterial: onMaterial))
            .onDisappear { session.stop() }
        }
    }
    private var transcript: String {
        let previous = session.messages.dropFirst().map { $0.role == .assistant ? $0.text : "\n\n---\n\n**追问**\n\n" + $0.text }
        return (previous + [session.answer]).joined(separator: "\n\n")
    }
}
