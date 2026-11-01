import SwiftUI

struct AboutView:View {
    @Environment(\.dismiss) private var dismiss
    private var version:String {Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? ""}
    private var build:String {Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? ""}
    var body:some View {
        NavigationStack {
            Form {
                Section {VStack(alignment:.leading,spacing:12){Text("知序").font(.largeTitle.bold());Text("版本 \\(version)（\\(build)）").foregroundStyle(.secondary).textSelection(.enabled)}.padding(.vertical)}
                Section {Link(destination:URL(string:"https://github.com/XYXBlAcG")!){Label("开发者的 GitHub 主页",systemImage:"person.crop.circle")}}
            }.navigationTitle("关于").toolbar{ToolbarItem(placement:.confirmationAction){Button("完成"){dismiss()}}}
        }
    }
}
