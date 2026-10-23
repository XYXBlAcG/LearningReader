#if os(macOS)
import Foundation
import LearningCore

struct LocalWorkflow {
    static func run(_ workflow: CourseWorkflow, root: URL, onOutput: @escaping @MainActor @Sendable (String) -> Void) async throws {
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
            var pending = Data()
            while true {
                let data = pipe.fileHandleForReading.availableData
                if data.isEmpty { break }
                pending.append(data)
                if let newline = pending.lastIndex(of: 10) {
                    let end = pending.index(after: newline)
                    await onOutput(String(decoding: pending[..<end], as: UTF8.self))
                    pending.removeSubrange(..<end)
                }
            }
            if !pending.isEmpty { await onOutput(String(decoding: pending, as: UTF8.self)) }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw ReaderError.course("工作流退出码 \(process.terminationStatus)") }
            await onOutput("工作流已完成")
        }.value
    }
}
#endif
