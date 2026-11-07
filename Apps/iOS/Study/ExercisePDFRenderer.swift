import UIKit
import WebKit
import PDFKit
import LearningCore

struct ExercisePaper:Codable {
    let title:String
    let html:String
    let questionCount:Int
    let warnings:[String]
}

struct ExercisePrintStyle {
    var tex=false
    var fontSize=11.0
    var marginMM=15.0
    var inset:CGFloat {CGFloat(min(35,max(8,marginMM))*72/25.4)}
}

@MainActor
final class ExercisePDFRenderer:NSObject,WKNavigationDelegate {
    let web:WKWebView
    private var loading:CheckedContinuation<Void,Error>?
    override init() {
        let configuration=WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        web=WKWebView(frame:CGRect(origin:.zero,size:ExercisePageRenderer.contentSize),configuration:configuration)
        super.init()
        web.navigationDelegate=self
        web.isOpaque=true
        web.backgroundColor = .white
        web.scrollView.contentInsetAdjustmentBehavior = .never
    }
    func export(_ paper:ExercisePaper,header:Bool=true,footer:Bool=true,style:ExercisePrintStyle=ExercisePrintStyle()) async throws -> Data {
        web.frame.size=CGSize(width:ExercisePageRenderer.pageSize.width-2*style.inset,height:ExercisePageRenderer.pageSize.height-2*style.inset-(header ? ExercisePageRenderer.bandHeight:0)-(footer ? ExercisePageRenderer.bandHeight:0))
        try await withCheckedThrowingContinuation { continuation in
            loading=continuation
            web.loadFileURL(ReaderAssets.reader.appendingPathComponent("exercise-paper.html"),allowingReadAccessTo:ReaderAssets.reader)
        }
        try Task.checkCancellation()
        let payload=try JSONSerialization.jsonObject(with:JSONEncoder().encode(paper))
        _=try await web.readerJavaScript("document.body.dataset.personalized='true';document.body.dataset.tex=tex ? 'true':'false';document.body.style.fontSize=fontSize+'pt';return await ReaderPaper.render(payload)",arguments:["payload":payload,"tex":style.tex,"fontSize":min(18,max(9,style.fontSize))],world:.page)
        try Task.checkCancellation()
        let pages=ExercisePageRenderer(title:paper.title,header:header,footer:footer,inset:style.inset)
        pages.addPrintFormatter(web.viewPrintFormatter(),startingAtPageAt:0)
        pages.prepare(forDrawingPages:NSRange(location:0,length:1))
        guard pages.numberOfPages>0 else {throw ReaderError.course("试卷没有可打印的页面。")}
        let format=UIGraphicsPDFRendererFormat()
        format.documentInfo=[kCGPDFContextTitle as String:paper.title,kCGPDFContextCreator as String:"知序"]
        let data=UIGraphicsPDFRenderer(bounds:pages.paperRect,format:format).pdfData { context in
            for index in 0..<pages.numberOfPages {
                context.beginPage()
                pages.drawPage(at:index,in:pages.paperRect)
            }
        }
        guard let document=PDFDocument(data:data),document.pageCount==pages.numberOfPages else {throw ReaderError.course("PDF 页面生成失败。")}
        return data
    }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {loading?.resume();loading=nil}
    func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error) {loading?.resume(throwing:error);loading=nil}
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {loading?.resume(throwing:error);loading=nil}
}

final class ExercisePageRenderer:UIPrintPageRenderer {
    static let pageSize=CGSize(width:595.28,height:841.89)
    static let margin:CGFloat=42.52
    static let bandHeight:CGFloat=18
    static var contentSize:CGSize {CGSize(width:pageSize.width-2*margin,height:pageSize.height-2*(margin+bandHeight))}
    let title:String
    let inset:CGFloat
    override var paperRect:CGRect {CGRect(origin:.zero,size:Self.pageSize)}
    override var printableRect:CGRect {paperRect.insetBy(dx:inset,dy:inset)}
    init(title:String,header:Bool=true,footer:Bool=true,inset:CGFloat=ExercisePageRenderer.margin) {self.title=title;self.inset=inset;super.init();headerHeight=header ? Self.bandHeight:0;footerHeight=footer ? Self.bandHeight:0}
    override func drawHeaderForPage(at pageIndex:Int,in headerRect:CGRect) {
        guard headerHeight>0 else {return}
        let area=CGRect(x:printableRect.minX,y:printableRect.minY,width:printableRect.width,height:headerHeight)
        (title as NSString).draw(in:area,withAttributes:[.font:UIFont.systemFont(ofSize:8),.foregroundColor:UIColor.darkGray])
    }
    override func drawFooterForPage(at pageIndex:Int,in footerRect:CGRect) {
        guard footerHeight>0 else {return}
        let style=NSMutableParagraphStyle();style.alignment = .center
        let area=CGRect(x:printableRect.minX,y:printableRect.maxY-footerHeight,width:printableRect.width,height:footerHeight)
        ("\(pageIndex+1) / \(numberOfPages)" as NSString).draw(in:area,withAttributes:[.font:UIFont.systemFont(ofSize:8),.paragraphStyle:style,.foregroundColor:UIColor.darkGray])
    }
}
