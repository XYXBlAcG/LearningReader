import Foundation
import WebKit
import LearningCore

extension ReaderSurface.Coordinator {
    func checkpoint(_ message:WKScriptMessage,reply:@escaping(Any?,String?)->Void) {
        Task { @MainActor in
            do {
                guard message.webView===controller.webView,message.frameInfo.isMainFrame,
                      message.frameInfo.request.url?.scheme=="mathreader",message.frameInfo.request.url?.host=="local",
                      message.frameInfo.request.url?.path=="/reader/index.html" else {throw ReaderError.invalidPath}
                let command=try JSONDecoder().decode(CheckpointRequest.self,from:JSONSerialization.data(withJSONObject:message.body))
                if checkpointService==nil {
                    guard let data=snapshot.course.indices["checkpoints.json"] else {throw ReaderError.invalidIndex}
                    checkpointService=CheckpointService(courseID:sourceID,locations:try JSONDecoder().decode([CheckpointLocation].self,from:data))
                }
                guard let checkpointService else {throw ReaderError.invalidIndex}
                reply(try JSONSerialization.jsonObject(with:JSONEncoder().encode(try await checkpointService.request(command))),nil)
            } catch {reply(nil,error.localizedDescription)}
        }
    }
}
