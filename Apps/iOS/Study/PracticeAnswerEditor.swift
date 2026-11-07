import SwiftUI
import PracticeCore

struct PracticeAnswerEditor: View {
    let item: PracticeItem
    @EnvironmentObject private var practice: PracticeWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(item: PracticeItem) {
        self.item = item
        _text = State(initialValue: item.answer)
    }

    var body: some View {
        NavigationStack {
            VStack {
                TextEditor(text: $text).font(.body).padding()
                if let issue = practice.issue { Text(issue).foregroundStyle(.red).padding() }
            }
            .navigationTitle("参考答案 · Markdown")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        practice.update(item) { $0.answer = text }
                        if practice.issue == nil { dismiss() }
                    }
                }
            }
        }
    }
}
