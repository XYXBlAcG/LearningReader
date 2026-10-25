import SwiftUI

struct ReadingHistoryView:View {
    @ObservedObject var reader:ReaderController
    @Environment(\.dismiss) private var dismiss
    @State private var query=""
    var body:some View {
        NavigationStack {
            List {
                if reader.state?.canUndoHistory == true {
                    Button("撤销上次删除或清空",systemImage:"arrow.uturn.backward") { reader.send("undoHistory") }
                }
                ForEach((reader.state?.history ?? []).filter{query.isEmpty || $0.label.localizedCaseInsensitiveContains(query)}) { visit in
                    HStack {
                        Button {
                            reader.send("openHistory",payload:["kind":visit.kind,"path":visit.path]);dismiss()
                        } label: { Text(visit.label).foregroundStyle(visit.missing ? Color.secondary : Color.primary).lineLimit(3) }
                            .disabled(visit.missing)
                    }
                    .swipeActions(edge:.leading,allowsFullSwipe:true) {
                        Button("删除",role:.destructive) { reader.send("deleteHistory",payload:["kind":visit.kind,"path":visit.path]) }
                    }
                }
            }
            .searchable(text:$query,prompt:"搜索阅读历史")
            .navigationTitle("历史记录")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("清空") { reader.send("clearHistory") }.disabled(reader.state?.history.isEmpty != false) }
                ToolbarItem(placement:.confirmationAction) { Button("完成") { dismiss() } }
            }
            .onDisappear { reader.send("discardHistoryUndo") }
        }
    }
}
