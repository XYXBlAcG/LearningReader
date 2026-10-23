#if os(macOS)
import XCTest
import LearningCore
@testable import LearningReader

final class WorkflowTests: XCTestCase {
    @MainActor
    func testStreamingPreservesUTF8AcrossPipeReads() async throws {
        var output = ""
        let workflow = CourseWorkflow(title: "test", program: "/bin/sh", arguments: ["-c", "printf '\\347'; sleep 0.1; printf '\\237\\245\\345\\272\\217\\n'"])
        try await LocalWorkflow.run(workflow, root: FileManager.default.temporaryDirectory) { output += $0 }
        XCTAssertEqual(output, "知序\n工作流已完成")
    }

    @MainActor
    func testFailureRetainsStreamedOutput() async {
        var output = ""
        let workflow = CourseWorkflow(title: "test", program: "/bin/sh", arguments: ["-c", "printf 'failed\\n'; exit 7"])
        do {
            try await LocalWorkflow.run(workflow, root: FileManager.default.temporaryDirectory) { output += $0 }
            XCTFail("Expected process failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("7"))
            XCTAssertEqual(output, "failed\n")
        }
    }
}
#endif
