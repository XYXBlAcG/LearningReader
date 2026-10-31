import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var model: ReaderModel
    @ObservedObject var reader:ReaderController
    @Environment(\.dismiss) private var dismiss
    @State private var github = false
    @State private var ai = false
    var body: some View {
        NavigationStack {
            Form {
                Section("课程同步") { Button("GitHub 登录与设置") { github = true } }
                Section("学习") {NavigationLink("复习与提醒"){PracticeSettingsView()}}
                Section {
                    Picker("术语自动标注",selection:Binding(get:{reader.state?.glossaryMode ?? "once"},set:{reader.send("glossaryMode",payload:["mode":$0])})) {
                        Text("每篇首次出现").tag("once")
                        Text("全部出现位置").tag("all")
                        Text("关闭自动标注").tag("off")
                    }.disabled(reader.state?.hasDocument != true)
                } header:{Text("阅读辅助")} footer:{Text("每篇首次：只标出当前文章中每个术语第一次出现的位置。设置按当前课程保存；关闭标注后仍可查阅术语库。")}
                Section("讲一讲") { Button("AI 服务与提示词") { ai = true } }
            }
            .navigationTitle("设置")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $github) { ConnectionView(model: model) }
            .sheet(isPresented: $ai) { AISettingsView() }
        }
    }
}
