import XCTest
@testable import LearningCore

final class CourseNavigationTests:XCTestCase {
    func testTreeUsesIndexedTitlesAndFullDocumentIdentity() throws {
        let data=Data(#"{"notes":[{"path":"lessons/02-矩阵/a.md","label":"矩阵"},{"path":"lessons/01-基础.md","label":"基础"}],"exercises":[]}"#.utf8)
        let index=try CourseNavigationIndex(data:data)
        let tree=index.tree(kind:.note,sectionRoot:"lessons")
        XCTAssertEqual(tree.count,2)
        XCTAssertEqual(tree[0].item?.label,"基础")
        XCTAssertEqual(tree[1].children?.first?.item?.target.path,"lessons/02-矩阵/a.md")
        XCTAssertEqual(tree[1].children?.first?.item?.target.kind,.note)
    }
    func testSupplementalFilesOutsideSectionKeepTheirFullPaths() throws {
        let data=Data(#"{"notes":[{"path":"lessons/a.md","label":"课"},{"path":"extras/b.md","label":"补充"}],"exercises":[]}"#.utf8)
        let tree=try CourseNavigationIndex(data:data).tree(kind:.note,sectionRoot:"lessons")
        XCTAssertEqual(tree.map(\.path),["extras","lessons"])
        XCTAssertEqual(tree[0].children?.first?.path,"extras/b.md")
    }
    func testIndexRejectsEscapingDocumentPaths() {
        XCTAssertThrowsError(try CourseNavigationIndex(data:Data(#"{"notes":[{"path":"../private.md","label":"bad"}],"exercises":[]}"#.utf8)))
    }
}
