import SwiftUI

struct AboutView:View {
    @StateObject private var update=UpdateStatus()
    @AppStorage("updateReminders") private var reminders=true
    @Environment(\.dismiss) private var dismiss
    private var version:String {Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? ""}
    private var build:String {Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? ""}
    var body:some View {
        NavigationStack {
            Form {
                Section {VStack(alignment:.leading,spacing:12){Image("AboutIcon").resizable().frame(width:80,height:80).clipShape(RoundedRectangle(cornerRadius:18));Text("知序").font(.largeTitle.bold());Text("版本 \(version)（\(build)）").foregroundStyle(.secondary).textSelection(.enabled)}.padding(.vertical)}
                Section {Button {Task{await update.check()}}label:{HStack{Text("检查更新");if update.checking {ProgressView()}}}.disabled(update.checking);Text(update.message);if let url=update.url {Link("下载新版本",destination:url)};Toggle("新版本提醒",isOn:$reminders)}
                Section {Link(destination:URL(string:"https://github.com/XYXBlAcG")!){Label("开发者的 GitHub 主页",systemImage:"person.crop.circle")}}
            }.navigationTitle("关于").toolbar{ToolbarItem(placement:.confirmationAction){Button("完成"){dismiss()}}}
        }
    }
}
