import Foundation
import AICore
import ZIPFoundation
import UniformTypeIdentifiers

public enum StudyArchive {
    public static func package(_ record:StudyRecord,version:StudyVersion) throws -> Data {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let folder=root.appendingPathComponent("LearningReader-Study")
        let assets=folder.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at:assets,withIntermediateDirectories:true)
        var markdown="# "+record.title+"\n\n## 题目\n\n"+record.question+"\n\n## 讲解\n\n"+version.transcript
        if let image=record.initial.image {
            let filename="question."+fileExtension(image.mimeType)
            try image.data.write(to:assets.appendingPathComponent(filename))
            markdown="![题图](assets/"+filename+")\n\n"+markdown
        }
        let expression=try NSRegularExpression(pattern:#"!\[[^\]]*\]\((data:image/[^;]+;base64,([^)]*))\)"#)
        let original=markdown as NSString
        for (index,match) in expression.matches(in:markdown,range:NSRange(location:0,length:original.length)).enumerated().reversed() {
            let raw=original.substring(with:match.range(at:2))
            guard let data=Data(base64Encoded:raw) else {throw CocoaError(.fileReadCorruptFile)}
            let mime=String(original.substring(with:match.range(at:1)).dropFirst(5).prefix{$0 != ";"})
            let name="image-\(index)."+fileExtension(mime)
            try data.write(to:assets.appendingPathComponent(name))
            if let range=Range(match.range(at:1),in:markdown){markdown.replaceSubrange(range,with:"assets/"+name)}
        }
        try Data(markdown.utf8).write(to:folder.appendingPathComponent("lesson.md"))
        try JSONEncoder().encode(Envelope(records:[record])).write(to:folder.appendingPathComponent("record.json"))
        let zip=root.appendingPathComponent("Study.zip")
        try FileManager.default.zipItem(at:folder,to:zip,compressionMethod:.deflate)
        return try Data(contentsOf:zip)
    }
    public static func contents(_ data:Data) throws -> Data {
        guard data.starts(with:[0x50,0x4b]) else {return data}
        let archive=try Archive(data:data,accessMode:.read)
        guard let entry=archive["LearningReader-Study/record.json"],entry.type == .file,entry.uncompressedSize<=256*1024*1024 else {throw CocoaError(.fileReadCorruptFile)}
        var result=Data()
        _=try archive.extract(entry){result.append($0)}
        return result
    }
    private static func fileExtension(_ mime:String)->String {UTType(mimeType:mime)?.preferredFilenameExtension ?? "img"}
    private struct Envelope:Encodable {var version=1;let records:[StudyRecord]}
}
