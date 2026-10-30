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

@MainActor
final class ExercisePDFRenderer:NSObject,WKNavigationDelegate {
    let web:WKWebView
    private var loading:CheckedContinuation<Void,Error>?
    override init() {
        let configuration=WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        web=WKWebView(frame:CGRect(x:0,y:0,width:510.24,height:720.85),configuration:configuration)
        super.init()
        web.navigationDelegate=self
        web.isOpaque=true
        web.backgroundColor = .white
        web.scrollView.contentInsetAdjustmentBehavior = .never
    }
    func export(_ paper:ExercisePaper) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loading=continuation
            web.loadFileURL(ReaderAssets.reader.appendingPathComponent("exercise-paper.html"),allowingReadAccessTo:ReaderAssets.reader)
        }
        try Task.checkCancellation()
        let payload=try JSONSerialization.jsonObject(with:JSONEncoder().encode(paper))
        _=try await web.readerJavaScript("return await ReaderPaper.render(payload)",arguments:["payload":payload],world:.page)
        try Task.checkCancellation()
        let pages=ExercisePageRenderer(title:paper.title)
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
    let title:String
    override var paperRect:CGRect {CGRect(x:0,y:0,width:595.28,height:841.89)}
    override var printableRect:CGRect {paperRect.insetBy(dx:42.52,dy:42.52)}
    init(title:String) {self.title=title;super.init();headerHeight=18;footerHeight=18}
    override func drawHeaderForPage(at pageIndex:Int,in headerRect:CGRect) {
        (title as NSString).draw(in:headerRect,withAttributes:[.font:UIFont.systemFont(ofSize:8),.foregroundColor:UIColor.darkGray])
    }
    override func drawFooterForPage(at pageIndex:Int,in footerRect:CGRect) {
        let style=NSMutableParagraphStyle();style.alignment = .center
        ("\(pageIndex+1) / \(numberOfPages)" as NSString).draw(in:footerRect,withAttributes:[.font:UIFont.systemFont(ofSize:8),.paragraphStyle:style,.foregroundColor:UIColor.darkGray])
    }
}
