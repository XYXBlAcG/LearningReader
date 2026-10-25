import SwiftUI
import LearningCore

struct ReaderToolsView:View {
    let snapshot:CourseSnapshot?
    @ObservedObject var reader:ReaderController
    @Binding var presented:Bool
    let onOpen:(ReaderDocumentTarget)->Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var graph=false
    var body:some View {
        VStack(spacing:0) {
            HStack {
                Picker("阅读辅助",selection:$graph) {
                    Text("本页目录").tag(false)
                    Text("知识关联").tag(true)
                }.pickerStyle(.segmented)
                if sizeClass == .compact { Button("完成") { presented=false } }
            }.padding()
            if graph, let snapshot {
                ReaderGraphView(snapshot:snapshot,kind:reader.state?.documentKind ?? "note",path:reader.state?.path ?? "",onOpen:onOpen).id(snapshot.id)
            } else {
                List(reader.state?.outlineItems ?? []) { heading in
                    Button {
                        guard let state=reader.state,let kind=DocumentKind(rawValue:state.documentKind ?? "") else { return }
                        onOpen(.init(kind:kind,path:state.path,anchor:heading.id))
                    } label: {
                        Text(heading.title).lineLimit(3).padding(.leading,CGFloat(max(0,heading.level-1))*10)
                    }
                }
            }
        }
        .inspectorColumnWidth(min:280,ideal:340,max:480)
    }
}
