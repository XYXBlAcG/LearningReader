import SwiftUI
import LearningCore
import AICore
import PracticeCore

@main
struct LearningReaderApp: App {
    @StateObject private var model = ReaderModel()
    @StateObject private var ai = AIWorkspace()
    @AppStorage("appearance") private var appearance = AppearancePreference.system
    var body: some Scene {
        WindowGroup {
            LearningView(model: model)
                .environmentObject(ai)
                .environmentObject(ai.study)
                .environmentObject(ai.practice)
                .environmentObject(ai.annotations)
                .frame(minWidth: 320, minHeight: 420)
                .preferredColorScheme(appearance.scheme)
        }
    }
}

struct LearningView: View {
    @ObservedObject var model: ReaderModel
    @StateObject private var reader = ReaderController()
    @StateObject private var journal=LearningJournal()
    @StateObject private var classroom=ClassroomWorkspace()
    @State private var classrooms=false
    @State private var tab=LearningTab.home
    @State private var reviewID:UUID?
    @State private var chapterSource:LearningLocation?
    @AppStorage("learningBar") private var bar=LearningBarPreference.visible
    @AppStorage("outlineDoubleTap") private var outlineDoubleTap=false
    @StateObject private var update=UpdateStatus()
    @StateObject private var interaction = AIInteraction()
    @EnvironmentObject private var ai: AIWorkspace
    @Environment(\.scenePhase) private var scenePhase
    @State private var courses = false
    @State private var settings = false
    @State private var about=false
    @State private var personalAnnotation:CourseAnnotation?
    @State private var annotationLibrary=false
    @State private var markChoices:[String]=[]
    @State private var chooseMark=false
    @State private var glossaryPresentation:GlossaryPresentation?
    @State private var history = false
    @State private var localStudies=false
    @State private var practiceLibrary=false
    @State private var annotationRecord:StudyRecord?
    @State private var exportPaper=false
    @State private var reference:ReferenceStudy?
    @State private var tools = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body:some View {
        readerDetail
        .tint(Color(red:0.06,green:0.59,blue:0.46))
        .modifier(AIHost(interaction:interaction))
        .onChange(of:currentLocation){_,_ in
            if let location=currentLocation {journal.record(location)}
        }
        .onChange(of:outlineDoubleTap){_,value in reader.marginDoubleTapEnabled=value}
    }
    private var rootTabs:some View {
        TabView(selection:$tab){
            NavigationStack{LearningHomeView(model:model,reader:reader,journal:journal,onContinue:{reviewID=nil;tab = .study},onReview:startReview,onOpen:openLocation,onSettings:{settings=true},onCourses:{tab = .catalog},onClassroom:{classrooms=true}).toolbar{navigationMenu}}.toolbar(bar.hides(tab) ? .hidden:.visible,for:.tabBar).tabItem{Label("主界面",systemImage:"house")}.tag(LearningTab.home)
            NavigationStack{courseSidebar.toolbar{navigationMenu}}.toolbar(bar.hides(tab) ? .hidden:.visible,for:.tabBar).tabItem{Label("目录",systemImage:"list.bullet")}.tag(LearningTab.catalog)
            NavigationStack{
                ZStack {
                    readerContent.opacity(reviewID==nil ? 1:0).allowsHitTesting(reviewID==nil).accessibilityHidden(reviewID != nil)
                    if let reviewID {PracticeDetailView(id:reviewID).toolbar{ToolbarItem(placement:.topBarLeading){Button("回到正文"){self.reviewID=nil}};navigationMenu}}
                }
            }.toolbar(bar.hides(tab) ? .hidden:.visible,for:.tabBar).tabItem{Label("学习",systemImage:"book")}.tag(LearningTab.study)
        }
    }
    @ToolbarContentBuilder private var navigationMenu:some ToolbarContent {
        ToolbarItem(placement:.topBarTrailing){Menu{
            ForEach(LearningTab.allCases){page in Button(page.title,systemImage:page.symbol){tab=page}}
            Button("课堂记录",systemImage:"pencil.and.list.clipboard"){classrooms=true}
            Button("设置",systemImage:"gearshape"){settings=true}
        }label:{Image(systemName:"ellipsis.circle")}.accessibilityLabel("页面与设置")}
    }
    @ViewBuilder private var courseSidebar:some View {
        if let snapshot=model.snapshot {
            NativeCourseSidebar(snapshot:snapshot,reader:reader,onCourses:{courses=true},onStudies:{localStudies=true},onOpen:open).id(snapshot.id)
        } else {
            List {
                Button("课程仓库",systemImage:"books.vertical") { courses=true }
                Button("本地讲解",systemImage:"tray.full") { localStudies=true }
                Button("今日复习与错题集",systemImage:"star"){practiceLibrary=true}
            }.navigationTitle("课程目录")
        }
    }
    @ViewBuilder private var readerMenu:some View {
        Section("页面"){ForEach(LearningTab.allCases){page in Button(page.title,systemImage:page.symbol){tab=page}}}
        Button("课堂记录",systemImage:"pencil.and.list.clipboard"){classrooms=true}
        Button("加入章节回顾",systemImage:"calendar.badge.plus"){chapterSource=currentLocation}.disabled(currentLocation==nil)
        Button("搜索", systemImage: "magnifyingglass") { tab = .catalog }
        Button("前进", systemImage: "chevron.right") { reader.send("forward") }.disabled(reader.state?.canForward != true)
        Button("历史记录", systemImage: "clock") { history = true }
        Button("课程术语库",systemImage:"text.book.closed") {reader.send("glossary")}.disabled(reader.state?.hasDocument != true)
        Button("本地讲解",systemImage:"tray.full") {localStudies=true}
        Button("笔记与高亮",systemImage:"highlighter"){annotationLibrary=true}
        Button("今日复习与错题集",systemImage:"star"){practiceLibrary=true}
        Section("讲一讲") {
            Button("拍照提问", systemImage: "camera") { interaction.media = .camera }
            Button("选择图片", systemImage: "photo") { interaction.media = .library }
        }
        Button("对应笔记或练习", systemImage: "arrow.left.arrow.right") { reader.send("counterpart") }.disabled(reader.state?.counterpart.isEmpty != false)
        Button(reader.state?.pinned == true ? "取消置顶" : "置顶本页", systemImage: "pin") { reader.send("pin") }
        Button("导出试卷 PDF",systemImage:"printer") {exportPaper=true}
            .disabled(reader.state?.documentKind != "exercise" || reader.state?.hasDocument != true)
        Section("阅读") {
            Button("放大正文", systemImage: "textformat.size.larger") { reader.send("zoomIn") }
            Button("缩小正文", systemImage: "textformat.size.smaller") { reader.send("zoomOut") }
            Button(reader.state?.previews == true ? "关闭三维预览" : "开启三维预览", systemImage: "cube") { reader.send("previews") }
        }
        Section {
            Button("刷新课程", systemImage: "arrow.clockwise") { model.sync() }.disabled(model.syncing || model.selected == nil)
            Button("课程仓库", systemImage: "books.vertical") { courses = true }
            Button("设置", systemImage: "gearshape") { settings = true }
            Button("关于",systemImage:"info.circle"){about=true}
        }
    }
    private var readerContent:some View {
        Group {
            if let snapshot = model.snapshot, let source = model.selected {
                ReaderSurface(snapshot: snapshot, sourceID: source.id, legacy: model.legacyReadingState, legacyState: model.legacyState, controller: reader, onError: { model.issue = $0 }).id(source.id + snapshot.id)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "book.pages").font(.system(size: 48)).foregroundStyle(.tint)
                    Text(model.selected?.title ?? "知序").font(.title)
                    Text(model.status).font(.callout).foregroundStyle(.secondary)
                    Button("添加或切换课程") { courses = true }.buttonStyle(.borderedProminent)
                    Button("设置") { settings = true }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(reader.state?.title ?? model.selected?.title ?? "知序")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if reviewID==nil {
                ToolbarItem(placement:.topBarLeading) {
                    Button { reader.send("back") } label: { Image(systemName:"arrow.uturn.backward") }
                        .disabled(reader.state?.canBack != true).accessibilityLabel("返回原文")
                }
                ToolbarItem(placement:.topBarTrailing) {
                    Button { tools.toggle() } label: { Image(systemName:"sidebar.right") }
                        .accessibilityLabel("本页目录与知识关联")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu { readerMenu } label: { Image(systemName: "ellipsis.circle") }.help("阅读与同步设置")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 8) {
                if model.syncing { ProgressView().controlSize(.small) }
                Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Button { model.sync() } label: { Image(systemName: "arrow.clockwise") }.disabled(model.syncing || model.selected == nil)
            }.padding(.horizontal, 14).padding(.vertical, 7).background(.bar)
        }
        .inspector(isPresented:$tools) {
            ReaderToolsView(snapshot:model.snapshot,reader:reader,presented:$tools,onOpen:open)
        }
    }
    private var studyPresentations:some View {
        rootTabs
            .fullScreenCover(item:$reference){ReferenceStudyView(study:$0).environment(\.courseGlossary,courseGlossary)}
            .sheet(item:$glossaryPresentation){presentation in NativeGlossaryView(presentation:presentation,onOpen:open)}
            .sheet(isPresented:$exportPaper){ExerciseExportView(reader:reader)}
            .sheet(item:$annotationRecord){record in NavigationStack{SavedStudyView(initial:record,onSource:{source in annotationRecord=nil;ai.study.onOpenSource?(source)})}}
            .sheet(isPresented:$practiceLibrary){PracticeLibraryView(courseTitles: Dictionary(uniqueKeysWithValues: model.library.sources.map { ($0.id, $0.title) }))}
            .sheet(isPresented:$localStudies){StudyLibraryView(courseID:model.selected?.id)}
    }
    private var personalPresentations:some View {
        studyPresentations
            .sheet(isPresented: $courses) { CourseLibraryView(model: model) }
            .sheet(item:$personalAnnotation){AnnotationEditor(item:$0)}
            .sheet(isPresented:$annotationLibrary){AnnotationLibraryView()}
            .confirmationDialog("选择笔记或讲解",isPresented:$chooseMark,titleVisibility:.visible){
                ForEach(markChoices,id:\.self){id in Button(ai.annotations.items.first(where:{$0.id.uuidString==id})?.quote ?? ai.study.records.first(where:{$0.id.uuidString==id})?.title ?? "查看记录"){openMark(id)}}
            }
    }
    private var readerDetail:some View {
        personalPresentations
            .sheet(isPresented:$about){AboutView()}
            .sheet(isPresented:$classrooms){ClassroomLibraryView(workspace:classroom,model:model,source:currentLocation)}
            .sheet(item:$chapterSource){source in ChapterReviewEditor(source:source,journal:journal,onRead:{openLocation(source)})}
            .sheet(isPresented: $settings) { AppSettingsView(model: model,reader:reader) }
            .sheet(isPresented: $history) { ReadingHistoryView(reader: reader) }
            .alert("知序", isPresented: Binding(get: { model.issue != nil }, set: { if !$0 { model.issue = nil } })) {
                Button("知道了") { model.issue = nil }
            } message: { Text(model.issue ?? "") }
            .alert("软件更新",isPresented:Binding(get:{update.url != nil},set:{if !$0 {update.url=nil}})){if let url=update.url {Link("下载新版本",destination:url)};Button("稍后",role:.cancel){update.url=nil}}message:{Text(update.message)}
            .task {
                reader.onOutlineGesture={tools=true}
                reader.marginDoubleTapEnabled=outlineDoubleTap
                ai.practice.onOpenQuestion=startReview
                ai.study.onOpenSource={source in
                    reference=nil;localStudies=false
                    Task {
                        guard let course=model.library.sources.first(where:{$0.id==source.courseID}),let kind=DocumentKind(rawValue:source.kind) else {model.issue="原课程已移除，保存的题目和讲解仍可离线阅读。";return}
                        if model.selected?.id != course.id {await model.select(course)}
                        var anchor=source.anchor
                        if let current=model.snapshot?.course.documents.first(where:{$0.kind==kind && $0.path==source.path}),!source.fingerprint.isEmpty,StudySource.hash(current.source) != source.fingerprint {
                            anchor="";model.issue="原文已更新，已打开当前文件；已保存的讲解保留原题快照。"
                        }
                        let target=ReaderDocumentTarget(kind:kind,path:source.path,anchor:anchor)
                        reader.pendingOpen=(course.id,target)
                        if reader.webView != nil,reader.loadedSourceID==course.id && reader.state?.hasDocument==true {reader.open(target);reader.pendingOpen=nil}
                        reviewID=nil;tab = .study
                    }
                }
                reader.onReference={items,document,selectedID in
                    var questions=items
                    for index in questions.indices {questions[index].source?.courseID=model.selected?.id ?? ""}
                    reference=ReferenceStudy(questions:questions,document:document,selectedID:selectedID)
                }
                ai.practice.onOpen={practiceLibrary=true}
                reader.onCheckpointMistake={ai.practice.captureCheckpoint($0,courseID:$1)}
                reader.onGlossary={ids in
                    do {
                        guard let data=model.snapshot?.course.indices["glossary.json"] else {throw ReaderError.invalidIndex}
                        glossaryPresentation=GlossaryPresentation(catalog:try JSONDecoder().decode(CourseGlossaryCatalog.self,from:data),courseID:model.selected?.id ?? "",selected:ids)
                    }catch{model.issue=error.localizedDescription}
                }
                reader.annotationData={ai.study.annotations(courseID:model.selected?.id ?? "")+ai.annotations.marks(courseID:model.selected?.id ?? "")}
                reader.onAnnotationStatus={ids in let next=Set(ids);if ai.annotations.unresolved != next {ai.annotations.unresolved=next}}
                reader.onAnnotation={ids in if ids.count>1 {markChoices=ids;chooseMark=true}else if let id=ids.first {openMark(id)}}
                reader.onMark={load,note in
                    Task {@MainActor in
                        do {
                            let material=try await load()
                            guard let source=material.source,["note","exercise"].contains(source.kind) else {throw AISelectionError.invalidPayload}
                            guard source.courseID==model.selected?.id else {throw AISelectionError.documentChanged}
                            var item=CourseAnnotation(source:source,quote:material.text,prefix:material.selectionPrefix,suffix:material.selectionSuffix)
                            item.highlighted = !note
                            personalAnnotation=item
                        }catch{model.issue=error.localizedDescription}
                    }
                }
                reader.onSelection = { interaction.begin($0, workspace: ai) }
                reader.selectionActions=ai.settings.actions
                await model.start()
                await update.check(automatic:true)
            }
            .onReceive(ai.annotations.$items){_ in Task{@MainActor in reader.refreshAnnotations()}}
            .onReceive(ai.study.$records){_ in Task{@MainActor in reader.refreshAnnotations()}}
            .onReceive(ai.study.$hiddenAnnotations){_ in Task{@MainActor in reader.refreshAnnotations()}}
            .onReceive(NotificationCenter.default.publisher(for:UIApplication.significantTimeChangeNotification)){_ in ai.practice.refresh()}
            .onReceive(ai.$settings) { reader.selectionActions=$0.actions }
            .onChange(of: model.library.selectedID) { _ in reader.state = nil }
            .onChange(of: scenePhase) { value in if value == .active { ai.practice.refresh();model.sync(automatic: true);Task{await update.check(automatic:true)} } else {ai.study.flush()} }
    }
    private var currentLocation:LearningLocation? {
        guard let course=model.selected,let state=reader.state,state.hasDocument,let kind=state.documentKind,kind=="note" || kind=="exercise" else{return nil}
        return LearningLocation(course:course,kind:kind,path:state.path,title:state.title)
    }
    private func startReview(_ id:UUID){tools=false;reviewID=id;tab = .study}
    private func openLocation(_ source:LearningLocation){
        guard let course=model.library.sources.first(where:{$0.id==source.courseID || LearningLocation(course:$0,kind:source.kind,path:source.path,title:source.title).courseKey==source.courseKey}),let kind=DocumentKind(rawValue:source.kind) else{model.issue="原课程已移除，请重新添加对应课程。";return}
        Task{@MainActor in
            if model.selected?.id != course.id {await model.select(course)}
            guard model.selected?.id==course.id,model.snapshot?.course.documents.contains(where:{$0.kind==kind && $0.path==source.path})==true else{model.issue="原章节已移动或不在当前课程中，请从目录重新选择。";return}
            let target=ReaderDocumentTarget(kind:kind,path:source.path)
            reader.pendingOpen=(course.id,target)
            if reader.webView != nil,reader.loadedSourceID==course.id && reader.state?.hasDocument==true {reader.open(target);reader.pendingOpen=nil}
            reviewID=nil;tab = .study
        }
    }
    private func openMark(_ value:String){
        guard let id=UUID(uuidString:value) else {return}
        if let item=ai.annotations.items.first(where:{$0.id==id && $0.source.courseID==model.selected?.id}){personalAnnotation=item}
        else if let record=ai.study.record(id),record.source?.courseID==model.selected?.id {annotationRecord=record}
    }
    private var courseGlossary: CourseGlossaryContext? {
        guard let data=model.snapshot?.course.indices["glossary.json"] else { return nil }
        return try? CourseGlossaryContext(data:data,courseID:model.selected?.id ?? "",mode:reader.state?.glossaryMode ?? "once") { target in
            reference=nil
            open(target)
        }
    }
    private func open(_ target:ReaderDocumentTarget) {
        reviewID=nil;tab = .study
        if let course=model.selected {reader.pendingOpen=(course.id,target)}
        if reader.webView != nil,reader.loadedSourceID==model.selected?.id,reader.state?.hasDocument==true {reader.open(target);reader.pendingOpen=nil}
        if sizeClass == .compact { tools=false }
    }

}
