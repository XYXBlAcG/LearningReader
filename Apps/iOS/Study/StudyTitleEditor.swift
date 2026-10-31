import SwiftUI

struct StudyTitleEditor:View {
    let onSave:(String)->String?
    @Environment(\.dismiss) private var dismiss
    @State private var title:String
    @State private var issue:String?
    init(initial:String,onSave:@escaping(String)->String?) {
        self.onSave=onSave;_title=State(initialValue:initial)
    }
    var body:some View {
        NavigationStack {
            VStack(alignment:.leading,spacing:12) {
                TextEditor(text:$title).font(.body).padding(8).background(.quaternary,in:RoundedRectangle(cornerRadius:12)).accessibilityLabel("讲解标题")
                if let issue {Text(issue).foregroundStyle(.red)}
            }.padding().navigationTitle("修改标题").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button("取消"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button("保存"){
                    issue=onSave(title.trimmingCharacters(in:.whitespacesAndNewlines))
                    if issue==nil {dismiss()}
                }.disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
            }
        }.presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
    }
}
