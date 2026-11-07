import WebKit
import AICore
import LearningCore

@MainActor
struct AISelectionCommand {
    let action: AISelectionAction
    let load: @MainActor () async throws -> AIMaterial
}

@MainActor
final class ExplainingWebView: WKWebView, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldReceive touch:UITouch)->Bool {
        let point=touch.location(in:self)
        return marginDoubleTapEnabled && courseSelection && (point.x<20 || point.x>bounds.width-20)
    }
    func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldRecognizeSimultaneouslyWith otherGestureRecognizer:UIGestureRecognizer)->Bool {true}
    var marginDoubleTapEnabled=false
    var onOutlineGesture:(()->Void)?
    @objc private func showOutline(_ gesture:UITapGestureRecognizer){
        guard marginDoubleTapEnabled,courseSelection,gesture.state == .ended else{return}
        let point=gesture.location(in:self)
        guard point.x<20 || point.x>bounds.width-20 else{return}
        callAsyncJavaScript("const node=document.elementFromPoint(x,y);return window.getSelection()?.isCollapsed !== false && (window.visualViewport?.scale ?? 1)===1 && !!node && !node.closest('a,button,input,textarea,select,code,pre,svg,canvas,mjx-container,[data-math-source],.glossary-term,[contenteditable=true]');",arguments:["x":point.x,"y":point.y],in:nil,in:.page){[weak self] result in if case .success(let value)=result,value as? Bool==true {self?.onOutlineGesture?()}}
    }
    var onMark:((@escaping @MainActor () async throws -> AIMaterial,Bool)->Void)?
    var onAction: ((AISelectionCommand) -> Void)?
    var actions: [AISelectionAction] = [.explain]
    var courseSelection = false
    private var bootstrapIssue: String?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame:frame,configuration:configuration)
        let tap=UITapGestureRecognizer(target:self,action:#selector(showOutline(_:)))
        tap.numberOfTapsRequired=2;tap.cancelsTouchesInView=false;tap.delegate=self;addGestureRecognizer(tap)
        do {
            let source=try String(contentsOf:ReaderAssets.reader.appendingPathComponent("explanation.js"),encoding:.utf8)
            configuration.userContentController.addUserScript(WKUserScript(source:source+"\nwindow.ReaderPageSelection=ReaderExplanation.bindWebpage(document);",injectionTime:.atDocumentEnd,forMainFrameOnly:true,in:.defaultClient))
        } catch { bootstrapIssue=error.localizedDescription }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) unavailable") }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with:builder)
        guard builder.system == .context, onAction != nil else { return }
        let world: WKContentWorld = courseSelection ? .page : .defaultClient
        let prepare = courseSelection ? "window.MathReaderBridge?.prepareSelection()" : "window.ReaderPageSelection?.material(); undefined"
        callAsyncJavaScript(prepare,arguments:[:],in:nil,in:world,completionHandler:nil)
        let expectedURL=url
        let items=actions.filter(\.enabled).map { action in
            UIAction(title:action.title,image:UIImage(systemName:"sparkles")) { [weak self] _ in
                guard let self else { return }
                let command=AISelectionCommand(action:action,load:{ [weak self] in
                    guard let self else { throw AISelectionError.documentChanged }
                    return try await self.selectedMaterial(expectedURL:expectedURL)
                })
                self.onAction?(command)
            }
        }
        var menuItems:[UIMenuElement]=[]
        if courseSelection,onMark != nil {
            for (title,note) in [("添加笔记",true),("高亮",false)] {
                menuItems.append(UIAction(title:title,image:UIImage(systemName:note ? "note.text":"highlighter")){[weak self] _ in
                    guard let self else {return}
                    self.onMark?({[weak self] in guard let self else {throw AISelectionError.documentChanged};return try await self.selectedMaterial(expectedURL:expectedURL)},note)
                })
            }
        }
        menuItems.append(contentsOf:items)
        if !menuItems.isEmpty { builder.insertChild(UIMenu(options:.displayInline,children:menuItems),atStartOfMenu:.root) }
    }

    private func selectedMaterial(expectedURL:URL?) async throws -> AIMaterial {
        guard window != nil, url == expectedURL else { throw AISelectionError.documentChanged }
        if let bootstrapIssue, !courseSelection { throw AIError.generation("加载选区脚本："+bootstrapIssue) }
        let script = courseSelection
            ? "if(!window.MathReaderBridge) throw new Error('阅读器桥接未就绪'); return await window.MathReaderBridge.prepareMaterial(window.MathReaderBridge.material())"
            : "if(!window.ReaderPageSelection) throw new Error('选区脚本未就绪'); return window.ReaderPageSelection.material()"
        let world:WKContentWorld=courseSelection ? .page : .defaultClient
        let raw=try await readerJavaScript(script,world:world)
        try Task.checkCancellation()
        guard let raw, !(raw is NSNull) else { throw AISelectionError.noSelection }
        guard let data=raw as? [String:String], let documentID=data["identity"], let document=data["document"], let text=data["text"], !text.isEmpty else { throw AISelectionError.invalidPayload }
        let check = courseSelection ? "return window.MathReaderBridge?.identity() || ''" : "return document.location.href"
        let identity=try await readerJavaScript(check,world:world)
        guard window != nil, url == expectedURL, identity as? String == documentID else { throw AISelectionError.documentChanged }
        let source=StudySource(courseID:data["courseID"] ?? "",kind:data["kind"] ?? "web",path:data["path"] ?? expectedURL?.absoluteString ?? "",anchor:data["anchor"] ?? "",fingerprint:StudySource.hash(document))
        var material=AIMaterial(title:data["title"] ?? "阅读内容",text:text,document:document,question:data["question"],source:source)
        material.selectionPrefix=data["prefix"] ?? "";material.selectionSuffix=data["suffix"] ?? ""
        return material
    }
}
