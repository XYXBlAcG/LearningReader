#if os(macOS)
import Foundation
import SQLite3

public struct LegacyDesktopState {
    public static var directory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("WebKit/chatgpt.nice114514.mathreader/WebsiteData/Default")
    }
    public static func read(directory: URL, port: Int) -> [String: String] {
        guard port > 0, port <= 65535 else { return [:] }
        var origin = Data([4, 0, 0, 0, 1])
        origin.append(Data("http".utf8))
        origin.append(contentsOf: [9, 0, 0, 0, 1])
        origin.append(Data("127.0.0.1".utf8))
        origin.append(contentsOf: [1, UInt8(port & 255), UInt8((port >> 8) & 255)])
        origin.append(origin)
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [:] }
        for case let file as URL in files where file.lastPathComponent == "localstorage.sqlite3" {
            let originURL = file.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("origin")
            guard (try? Data(contentsOf: originURL)) == origin else { continue }
            var database: OpaquePointer?
            guard sqlite3_open_v2(file.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { if let database { sqlite3_close(database) }; continue }
            defer { sqlite3_close(database) }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "SELECT key,value FROM ItemTable WHERE key LIKE 'reader_%'", -1, &statement, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(statement) }
            var result: [String: String] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let key = sqlite3_column_text(statement, 0), let bytes = sqlite3_column_blob(statement, 1) else { continue }
                let count = Int(sqlite3_column_bytes(statement, 1))
                guard count <= 4 * 1024 * 1024 else { continue }
                if let value = String(data: Data(bytes: bytes, count: count), encoding: .utf16LittleEndian) { result[String(cString: key)] = value }
            }
            return result
        }
        return [:]
    }
}
#endif
