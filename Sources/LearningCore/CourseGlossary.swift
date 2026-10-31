import Foundation
import JavaScriptCore

public enum CourseGlossary {
    public static let directories = ["术语", "glossary"]
    public static func contains(_ path: String) -> Bool {
        directories.contains(String(path.split(separator: "/").first ?? ""))
    }
    public static func build(root: URL, available: [String], documents: [CourseDocument]) throws -> Data {
        let folders = directories.filter { folder in available.contains { $0.hasPrefix(folder + "/") } }
        guard folders.count <= 1 else { throw ReaderError.course("课程只能使用一个术语目录：术语或 glossary。") }
        let paths = available.filter { contains($0) && $0.lowercased().hasSuffix(".md") && URL(fileURLWithPath: $0).lastPathComponent.lowercased() != "readme.md" }.sorted()
        var sources: [[String: String]] = []
        for path in paths {
            let url = try CoursePath.file(path, in: root)
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 256 * 1024 else { throw ReaderError.course("术语文件超过 256 KB：" + path) }
            sources.append(["path": path, "source": try String(contentsOf: url, encoding: .utf8)])
        }
        let input: [String: Any] = ["sources": sources, "documents": try JSONSerialization.jsonObject(with: JSONEncoder().encode(documents))]
        guard let context = JSContext() else { throw ReaderError.invalidIndex }
        context.evaluateScript(try String(contentsOf: ReaderAssets.reader.appendingPathComponent("glossary-core.js"), encoding: .utf8))
        let json = try JSONSerialization.data(withJSONObject: input)
        guard context.exception == nil,
              let output = context.objectForKeyedSubscript("ReaderGlossaryCore")?.forProperty("buildJSON")?.call(withArguments: [String(decoding: json, as: UTF8.self)])?.toString(),
              context.exception == nil, let data = output.data(using: .utf8) else {
            throw ReaderError.course(context.exception?.toString() ?? "术语索引无效")
        }
        return data
    }
}
