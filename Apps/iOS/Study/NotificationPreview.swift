import Foundation

enum NotificationPreview {
    static func text(_ markdown:String)->String {
        guard let value=try? AttributedString(markdown:markdown,options:.init(interpretedSyntax:.full)) else{return markdown.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")}
        var plain="",block:Int?
        for run in value.runs {
            let next=run.presentationIntent?.components.first?.identity
            if !plain.isEmpty,next != block {plain+=" "}
            plain+=String(value[run.range].characters);block=next
        }
        return plain.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
    }
}
