import SwiftUI
import AICore
import PracticeCore

struct QuestionActions:View {
    let question:StudyQuestion
    @EnvironmentObject private var practice:PracticeWorkspace
    @AppStorage("favoriteReview") private var defaultReview=true
    @AppStorage("askFavoriteReview") private var ask=true
    @State private var choosing=false
    @State private var review=true
    @State private var editing=false
    @State private var feedback=""
    private var record:PracticeItem? {practice.items.first{$0.question==question.question && $0.source?.courseID==question.source?.courseID && $0.source?.path==question.source?.path && $0.source?.anchor==question.source?.anchor}}
    var body:some View {
        VStack(spacing:4) {
            HStack(spacing:32) {
                Button {if record?.favorite==true {save(favorite:false)} else if ask {review=defaultReview;choosing=true}else{review=defaultReview;save(favorite:true)}} label:{Image(systemName:record?.favorite==true ? "star.fill":"star")}.tint(record?.favorite==true ? .orange:.accentColor).accessibilityLabel("收藏题目")
                Button {practice.editQuestion(question){$0.mistake.toggle();if $0.mistake {$0.scheduled=true}};report("错题集已更新")} label:{Image(systemName:record?.mistake==true ? "exclamationmark.circle.fill":"exclamationmark.circle")}.accessibilityLabel("错题集")
                Button {practice.editQuestion(question){_ in};if practice.issue==nil {editing=true}} label:{Image(systemName:record?.notes.isEmpty==false ? "note.text":"square.and.pencil")}.accessibilityLabel("题目笔记")
            }.buttonStyle(.borderless).font(.title3).padding(8)
            if !feedback.isEmpty {Text(feedback).font(.caption).foregroundStyle(.secondary)}
        }
        .sheet(isPresented:$choosing){NavigationStack{Form{Toggle("加入复习",isOn:$review);Toggle("收藏时询问",isOn:$ask);Toggle("默认加入复习",isOn:$defaultReview)}.navigationTitle("收藏题目").toolbar{ToolbarItem(placement:.cancellationAction){Button("取消"){choosing=false}};ToolbarItem(placement:.confirmationAction){Button("收藏"){save(favorite:true);if practice.issue==nil {choosing=false}}}}}.presentationDetents([.medium])}
        .sheet(isPresented:$editing){if let record {PracticeNoteEditor(item:record)}}
    }
    private func save(favorite:Bool){practice.editQuestion(question){$0.favorite=favorite;if favorite {$0.scheduled=review}};report(favorite ? (review ? "已收藏 · 已加入复习":"已收藏"):"已取消收藏")}
    private func report(_ text:String){feedback=practice.issue ?? text;if practice.issue==nil {UINotificationFeedbackGenerator().notificationOccurred(.success)}}
}

struct PracticeNoteEditor:View {
    let item:PracticeItem
    @State private var note:String
    @State private var preview=false
    @EnvironmentObject private var practice:PracticeWorkspace
    @Environment(\.dismiss) private var dismiss
    init(item:PracticeItem){self.item=item;_note=State(initialValue:item.notes)}
    var body:some View {
        NavigationStack {
            VStack {
                Picker("笔记模式",selection:$preview){Text("编辑").tag(false);Text("预览").tag(true)}.pickerStyle(.segmented)
                if preview {GlossaryMarkdownContent(markdown:note)}else{TextEditor(text:$note)}
                Text(practice.issue ?? "自动保存").font(.caption).foregroundStyle(.secondary)
            }.padding().navigationTitle("题目笔记")
            .toolbar{ToolbarItem(placement:.confirmationAction){Button("完成"){practice.update(item){$0.notes=note};if practice.issue==nil {dismiss()}}}}
            .task(id:note){do{try await Task.sleep(for:.milliseconds(500))}catch{return};practice.update(item){$0.notes=note}}
            .onDisappear{practice.update(item){$0.notes=note}}
        }
    }
}
