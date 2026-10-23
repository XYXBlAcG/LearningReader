#if os(macOS)
import Foundation
import LearningCore

struct LocalWorkflow {
    static func run(_ workflow: CourseWorkflow, root: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [workflow.program] + workflow.arguments
            process.currentDirectoryURL = root
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
            environment["PYTHONUNBUFFERED"] = "1"
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            guard process.terminationStatus == 0 else { throw ReaderError.course("工作流退出码 \(process.terminationStatus)\n" + output) }
            return output.isEmpty ? "工作流已完成" : output
        }.value
    }
}
#endif
