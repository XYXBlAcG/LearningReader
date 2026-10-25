import SwiftUI
import AICore

struct AIActionSettingsView:View {
    @EnvironmentObject private var workspace:AIWorkspace
    @State private var restore=false
    var body:some View {
        List {
            Section {
                ForEach(workspace.settings.actions) { action in
                    NavigationLink { AIActionEditor(action:action) } label: {
                        HStack { Text(action.title);Spacer();if !action.enabled { Text("已停用").foregroundStyle(.secondary) } }
                    }
                }
                .onDelete { indexes in var settings=workspace.settings;settings.actions.remove(atOffsets:indexes);workspace.update(settings) }
                .onMove { from,to in var settings=workspace.settings;settings.actions.move(fromOffsets:from,toOffset:to);workspace.update(settings) }
            }
            Section {
                NavigationLink("添加操作") { AIActionEditor(action:AISelectionAction()) }
                NavigationLink("使用「出一道变式」样例") { AIActionEditor(action:.variation) }
                Button("恢复默认菜单",role:.destructive) { restore=true }
            }
        }
        .navigationTitle("长按菜单操作")
        .toolbar { EditButton() }
        .confirmationDialog("恢复默认菜单将替换当前操作",isPresented:$restore,titleVisibility:.visible) {
            Button("恢复默认",role:.destructive) { var settings=workspace.settings;settings.actions=[.explain];workspace.update(settings) }
        }
    }
}

struct AIActionEditor:View {
    @EnvironmentObject private var workspace:AIWorkspace
    @Environment(\.dismiss) private var dismiss
    @State var action:AISelectionAction
    var body:some View {
        Form {
            Section {
                TextField("按钮名称",text:$action.title)
                Toggle("启用",isOn:$action.enabled)
            }
            Section("任务提示词") { TextEditor(text:$action.prompt).frame(minHeight:240) }
        }
        .navigationTitle(action.title.isEmpty ? "新操作" : action.title)
        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("保存") {
            var settings=workspace.settings
            action.title=action.title.trimmingCharacters(in:.whitespacesAndNewlines)
            if let index=settings.actions.firstIndex(where:{$0.id==action.id}) { settings.actions[index]=action }
            else { settings.actions.append(action) }
            workspace.update(settings)
            if workspace.issue == nil { dismiss() }
        }.disabled(action.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || action.prompt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) } }
    }
}
