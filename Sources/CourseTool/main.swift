import Foundation
import LearningCore

@main
struct CourseTool {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments == ["assets"] { print(ReaderAssets.reader.path); return }
            guard let command = arguments.first, arguments.count >= 2 else {
                print("course validate <目录> [--markdown] | course export <目录> <输出目录> [--markdown] | course archive <ZIP> [--markdown]")
                exit(2)
            }
            let url = URL(fileURLWithPath: arguments[1]).standardizedFileURL
            let configuration: ImportConfiguration = arguments.contains("--markdown") ? .markdown(root: "", excluding: []) : .standard
            if command == "archive" {
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: temporary) }
                let snapshot = try SnapshotStore(directory: temporary).install(archive: url, revision: String(repeating: "a", count: 40), configuration: configuration)
                guard try SnapshotStore(directory: temporary).current()?.course.documents.count == snapshot.course.documents.count else { throw ReaderError.invalidSnapshot }
                _ = try snapshot.resource(path: "/reader/index.html")
                print("快照可安装：\(snapshot.course.manifest.title)，\(snapshot.course.documents.count) 篇文章")
                return
            }
            guard ["validate", "export", "index"].contains(command) else { throw ReaderError.course("未知命令：" + command) }
            let course = try CourseIndexer.build(root: url, configuration: configuration)
            if command == "index" {
                var result: [String: Any] = ["manifest": try JSONSerialization.jsonObject(with: JSONEncoder().encode(course.manifest)), "redirects": try JSONSerialization.jsonObject(with: course.redirects), "media": course.media.sorted()]
                for (name, key) in [("index.json", "files"), ("graph.json", "graph"), ("search-index.json", "search")] {
                    result[key] = try JSONSerialization.jsonObject(with: course.indices[name]!)
                }
                print(String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self))
                return
            }
            if !course.unresolved.isEmpty {
                for issue in course.unresolved { fputs(issue + "\n", stderr) }
                throw ReaderError.course("存在未解析知识链接，请修复后重试。")
            }
            if command == "export" {
                guard arguments.count >= 3, arguments[2] != "--markdown" else { throw ReaderError.course("请指定输出目录。") }
                let output = URL(fileURLWithPath: arguments[2]).standardizedFileURL
                guard !FileManager.default.fileExists(atPath: output.path) else { throw ReaderError.course("输出目录已存在，请选择空的新目录。") }
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                do {
                    try FileManager.default.copyItem(at: ReaderAssets.reader, to: output.appendingPathComponent("reader"))
                    let snapshot = try SnapshotStore(directory: output.appendingPathComponent(".derived")).openLocal(root: url, configuration: configuration)
                    for name in ["config.js", "document-paths.json"] {
                        let destination = output.appendingPathComponent("reader/" + name)
                        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                        try FileManager.default.copyItem(at: snapshot.derived.appendingPathComponent(name), to: destination)
                    }
                    for (name, data) in course.indices {
                        let destination = output.appendingPathComponent("content/" + name)
                        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try data.write(to: destination)
                    }
                    for document in course.documents {
                        let destination = output.appendingPathComponent("content/" + document.kind.rawValue + "/" + document.path)
                        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try Data(document.source.utf8).write(to: destination)
                    }
                    for path in course.media {
                        let destination = output.appendingPathComponent("media/" + path)
                        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try FileManager.default.copyItem(at: CoursePath.file(path, in: course.root), to: destination)
                    }
                    try FileManager.default.removeItem(at: output.appendingPathComponent(".derived"))
                    try Data("<!doctype html><meta charset=\"utf-8\"><meta http-equiv=\"refresh\" content=\"0;url=/reader/index.html\"><a href=\"/reader/index.html\">打开课程</a>".utf8).write(to: output.appendingPathComponent("index.html"))
                } catch { try? FileManager.default.removeItem(at: output); throw error }
            }
            print("课程有效：\(course.manifest.title)，\(course.documents.count) 篇文章，\(course.media.count) 个本地资源")
        } catch {
            fputs(error.localizedDescription + "\n", stderr)
            exit(1)
        }
    }
}
