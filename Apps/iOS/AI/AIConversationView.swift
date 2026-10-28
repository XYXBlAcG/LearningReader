import SwiftUI
import AICore

struct AIHost: ViewModifier {
    @ObservedObject var interaction: AIInteraction
    @EnvironmentObject private var workspace: AIWorkspace
    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get:{interaction.invocation},set:{value in
                if value == nil { interaction.invocation?.cancel() }
                interaction.invocation=value
            })) { invocation in
                AIInvocationView(invocation:invocation,onMaterial:{interaction.explain($0,workspace:workspace)})
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .modifier(AIPhotoHost(source: $interaction.media) { interaction.explain($0, workspace: workspace) })
            .sheet(isPresented: $interaction.showSettings) { AISettingsView() }
    }
}

struct AIConversationView: View {
    @ObservedObject var session: AIConversation
    let onMaterial: (AIMaterial) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library:StudyWorkspace
    @Environment(\.scenePhase) private var phase
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
                StudyComparisonView(question:session.record.question,image:session.record.initial.image) {
                    MarkdownContentView(markdown:transcript,followsOutput:true,onIssue:{renderingIssue=$0})
                }
                HStack {
                    Text(library.saving.contains(session.id) ? "正在保存到本地":library.records.contains(where:{$0.id==session.id}) ? "已保存到本地，后续追问自动更新":"未保存到本地").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("保存"){library.save(session.record)}.disabled(!session.record.hasAnswer)
                }.padding(.horizontal)
                if let issue=library.issue { Text(issue).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding(.horizontal) }
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
            .navigationTitle(session.actionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { session.stop(); dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("保存到本地",systemImage:"square.and.arrow.down"){library.save(session.record)}.disabled(!session.record.hasAnswer)
                        Button("复制回答", systemImage: "doc.on.doc") { UIPasteboard.general.string = session.answer }.disabled(session.answer.isEmpty)
                        Button("重新讲解", systemImage: "arrow.clockwise") { session.retry() }.disabled(session.running)
                        Button("拍照提问", systemImage: "camera") { session.stop(); media = .camera }
                        Button("选择图片", systemImage: "photo") { session.stop(); media = .library }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .modifier(AIPhotoHost(source: $media, onMaterial: onMaterial))
            .onDisappear { session.stop();library.flush(session.id) }
            .onChange(of:phase){ if phase != .active {library.flush(session.id)} }
        }
    }
    private var transcript: String {
        session.transcript
    }
}
