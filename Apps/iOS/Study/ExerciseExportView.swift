import SwiftUI
import WebKit
import PDFKit
import LearningCore

struct ExerciseExportView:View {
    @ObservedObject var reader:ReaderController
    @Environment(\.dismiss) private var dismiss
    @State private var answers=false
    @State private var space="medium"
    @State private var generating=false
    @State private var issue:String?
    @State private var paper:ExercisePaper?
    @State private var document:URL?
    @State private var renderer=ExercisePDFRenderer()
    var body:some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("纸张",value:"A4 · 纵向")
                    Picker("作答留白",selection:$space) {
                        Text("无额外留白").tag("none")
                        Text("标准").tag("medium")
                        Text("更多").tag("large")
                    }
                    Toggle("答案另起页附后",isOn:$answers)
                }.disabled(generating)
                if let issue {Text(issue).foregroundStyle(.red)}
                if let paper {
                    Section {
                        LabeledContent("已识别题目",value:"\(paper.questionCount) 题")
                        ForEach(paper.warnings,id:\.self){Text($0).foregroundStyle(.secondary)}
                    }
                }
                Button {
                    issue=nil;paper=nil;document=nil;generating=true
                } label: {
                    HStack {Text("生成 PDF");Spacer();if generating {ProgressView()}}
                }.disabled(generating)
            }
            .background {ExerciseRenderHost(renderer:renderer).frame(width:1,height:1).opacity(0).accessibilityHidden(true)}
            .navigationTitle("导出试卷")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.cancellationAction){Button("完成"){dismiss()}}}
            .sheet(item:Binding(get:{document.map{ExportedExercise(url:$0)}},set:{document=$0?.url})) { exported in
                ExercisePDFPreview(url:exported.url)
            }
            .task(id:generating) {
                guard generating else {return}
                defer {generating=false}
                do {
                    guard let web=reader.webView else {throw ReaderError.missingContent}
                    let raw=try await web.readerJavaScript("return await window.MathReaderBridge.paper(options)",arguments:["options":["answers":answers,"space":space]],world:.page)
                    guard let raw else {throw ReaderError.invalidIndex}
                    let prepared=try JSONDecoder().decode(ExercisePaper.self,from:JSONSerialization.data(withJSONObject:raw))
                    paper=prepared
                    let data=try await renderer.export(prepared)
                    try Task.checkCancellation()
                    let folder=FileManager.default.temporaryDirectory.appendingPathComponent("ExercisePDF/"+UUID().uuidString,isDirectory:true)
                    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                    let name=prepared.title.replacingOccurrences(of:"/",with:"／").replacingOccurrences(of:":",with:"：")
                    let file=folder.appendingPathComponent((name.isEmpty ? "练习试卷":name)+".pdf")
                    try data.write(to:file,options:.atomic)
                    document=file
                }catch is CancellationError {}catch {issue="试卷导出失败："+error.localizedDescription}
            }
        }
    }
}

struct ExportedExercise:Identifiable {
    let url:URL
    var id:URL {url}
}

struct ExerciseRenderHost:UIViewRepresentable {
    let renderer:ExercisePDFRenderer
    func makeUIView(context:Context)->UIView {
        let host=UIView();host.clipsToBounds=true;host.addSubview(renderer.web);return host
    }
    func updateUIView(_ view:UIView,context:Context) {}
}

struct ExercisePDFPreview:UIViewControllerRepresentable {
    let url:URL
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context:Context)->UINavigationController {
        let screen=UIViewController(),pdf=PDFView()
        screen.title=url.deletingPathExtension().lastPathComponent
        pdf.autoScales=true;pdf.displayMode = .singlePageContinuous;pdf.document=PDFDocument(url:url)
        pdf.translatesAutoresizingMaskIntoConstraints=false
        screen.view.addSubview(pdf)
        NSLayoutConstraint.activate([pdf.leadingAnchor.constraint(equalTo:screen.view.leadingAnchor),pdf.trailingAnchor.constraint(equalTo:screen.view.trailingAnchor),pdf.topAnchor.constraint(equalTo:screen.view.topAnchor),pdf.bottomAnchor.constraint(equalTo:screen.view.bottomAnchor)])
        screen.navigationItem.leftBarButtonItem=UIBarButtonItem(title:"完成",primaryAction:UIAction{_ in dismiss()})
        let share=UIBarButtonItem(systemItem:.action)
        share.primaryAction=UIAction{[weak screen,weak share] _ in
            guard let screen else {return}
            let activity=UIActivityViewController(activityItems:[url],applicationActivities:nil)
            activity.popoverPresentationController?.barButtonItem=share
            screen.present(activity,animated:true)
        }
        let printButton=UIBarButtonItem(image:UIImage(systemName:"printer"),style:.plain,target:nil,action:nil)
        printButton.accessibilityLabel="打印"
        printButton.primaryAction=UIAction{[weak printButton] _ in
            guard let printButton else {return}
            let printer=UIPrintInteractionController.shared
            let info=UIPrintInfo(dictionary:nil);info.jobName=url.deletingPathExtension().lastPathComponent;info.outputType = .general
            printer.printInfo=info;printer.printingItem=url
            printer.present(from:printButton,animated:true,completionHandler:nil)
        }
        screen.navigationItem.rightBarButtonItems=[share,printButton]
        return UINavigationController(rootViewController:screen)
    }
    func updateUIViewController(_ controller:UINavigationController,context:Context) {}
}
