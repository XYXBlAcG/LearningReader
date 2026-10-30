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
        web=WKWebView(frame:CGRect(origin:.zero,size:ExercisePageRenderer.contentSize),configuration:configuration)
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
    static let pageSize=CGSize(width:595.28,height:841.89)
    static let margin:CGFloat=42.52
    static let bandHeight:CGFloat=18
    static var contentSize:CGSize {CGSize(width:pageSize.width-2*margin,height:pageSize.height-2*(margin+bandHeight))}
    let title:String
    override var paperRect:CGRect {CGRect(origin:.zero,size:Self.pageSize)}
    override var printableRect:CGRect {paperRect.insetBy(dx:Self.margin,dy:Self.margin)}
    init(title:String) {self.title=title;super.init();headerHeight=Self.bandHeight;footerHeight=Self.bandHeight}
    override func drawHeaderForPage(at pageIndex:Int,in headerRect:CGRect) {
        let area=CGRect(x:printableRect.minX,y:printableRect.minY,width:printableRect.width,height:headerHeight)
        (title as NSString).draw(in:area,withAttributes:[.font:UIFont.systemFont(ofSize:8),.foregroundColor:UIColor.darkGray])
    }
    override func drawFooterForPage(at pageIndex:Int,in footerRect:CGRect) {
        let style=NSMutableParagraphStyle();style.alignment = .center
        let area=CGRect(x:printableRect.minX,y:printableRect.maxY-footerHeight,width:printableRect.width,height:footerHeight)
        ("\(pageIndex+1) / \(numberOfPages)" as NSString).draw(in:area,withAttributes:[.font:UIFont.systemFont(ofSize:8),.paragraphStyle:style,.foregroundColor:UIColor.darkGray])
    }
}
