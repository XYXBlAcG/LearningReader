import XCTest
import WebKit
import PDFKit
@testable import LearningReader

final class ReaderPDFTests:XCTestCase {
    @MainActor
    func testRealCoursePrintPaginationAndAnswerIsolation() async throws {
        let renderer=ExercisePDFRenderer()
        let scene=UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.first
        let window=scene.map{UIWindow(windowScene:$0)} ?? UIWindow(frame:CGRect(x:0,y:0,width:600,height:850))
        let controller=UIViewController();window.rootViewController=controller
        controller.view.addSubview(renderer.web);window.isHidden=false
        defer {window.isHidden=true}
        let bundle=Bundle(for:Self.self)
        let folder=try XCTUnwrap(bundle.url(forResource:"paper-fixtures",withExtension:nil))
        var counts:[String:Int]=[:]
        for name in ["questions","answers","long"] {
            let payload=try JSONDecoder().decode(ExercisePaper.self,from:Data(contentsOf:folder.appendingPathComponent(name+".json")))
            XCTAssertEqual(payload.questionCount,2)
            let data=try await renderer.export(payload)
            let document=try XCTUnwrap(PDFDocument(data:data))
            XCTAssertGreaterThan(document.pageCount,0)
            for index in 0..<document.pageCount {
                let page=try XCTUnwrap(document.page(at:index)),size=page.bounds(for:.mediaBox).size
                XCTAssertEqual(size.width,595.28,accuracy:0.1)
                XCTAssertEqual(size.height,841.89,accuracy:0.1)
            }
            let text=document.string ?? ""
            if name=="questions" {XCTAssertFalse(text.contains("参考答案"));XCTAssertFalse(text.contains("不能。"))}
            if name=="answers" {XCTAssertTrue(text.contains("参考答案"));XCTAssertGreaterThan(document.pageCount,1)}
            if name=="long" {
                XCTAssertGreaterThan(document.pageCount,2)
                XCTAssertTrue(document.page(at:document.pageCount-1)?.string?.contains("85") == true)
                let math=try await renderer.web.readerJavaScript("return {formulas:document.querySelectorAll('mjx-container').length,errors:document.querySelectorAll('[data-mjx-error],mjx-merror').length,images:[...document.images].every(i=>i.complete&&i.naturalWidth>0)}",world:.page) as? [String:Any]
                XCTAssertEqual(math?["formulas"] as? Int,87)
                XCTAssertEqual(math?["errors"] as? Int,0)
                XCTAssertEqual(math?["images"] as? Bool,true)
            }
            let attachment=XCTAttachment(data:data,uniformTypeIdentifier:"com.adobe.pdf")
            attachment.name=name+".pdf";attachment.lifetime = .keepAlways
            add(attachment)
            counts[name]=document.pageCount
        }
        XCTAssertGreaterThan(counts["answers"] ?? 0,counts["questions"] ?? 0)
    }
}
