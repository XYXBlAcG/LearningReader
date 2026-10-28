import Foundation
import Combine

@MainActor
public final class AIConversation:ObservableObject,Identifiable {
    @Published public private(set) var record:StudyRecord
    public let id:UUID
    public var title:String { record.title }
    public var actionTitle:String { record.action.title }
    public let profile:AIProfile
    public var messages:[AIMessage] { [record.initial]+(current?.input ?? []) }
    public var answer:String { current?.answer ?? "" }
    public var running:Bool { current?.status == .generating }
    public var issue:String? { current?.issue }
    public var transcript:String {current?.transcript ?? ""}
    private var selectedVersionID:UUID?
    private var currentIndex:Int? {if let selectedVersionID {return record.versions.firstIndex{$0.id==selectedVersionID}};return record.versions.indices.last}
    private var current:StudyVersion? {currentIndex.map{record.versions[$0]}}
    public var onUpdate:((StudyRecord)->Void)?
    private let client:AIClient
    private let key:String
    private var task:Task<Void,Never>?
    private var generation=UUID()

    public init(title:String,profile:AIProfile,key:String,system:String,initial:AIMessage,actionTitle:String="讲一讲",client:AIClient=AIClient(),material:AIMaterial?=nil,action:AISelectionAction?=nil,restored:StudyRecord?=nil,selectedVersionID:UUID?=nil) {
        self.selectedVersionID=selectedVersionID
        self.client=client;self.profile=profile;self.key=key
        let value=restored ?? StudyRecord(material:material ?? AIMaterial(title:title,text:title),initial:initial,system:system,action:action ?? AISelectionAction(title:actionTitle,prompt:""))
        record=value;id=value.id
        record.system=system
    }
    public func stop() {
        generation=UUID();task?.cancel();task=nil
        if running,let index=currentIndex { record.versions[index].status = .stopped;publish() }
    }
    public func retry() { generate(input:current?.input ?? []) }
    private func generate(input:[AIMessage]) {
        stop()
        selectedVersionID=nil
        record.versions.append(.init(input:input,model:profile.modelID,service:profile.name))
        let token=generation
        let request=AIRequest(profile:profile,key:key,system:record.system,messages:[record.initial]+input)
        task=Task { [weak self,client] in
            do {
                try await client.generate(request) { [weak self] text in
                    guard let target=self else { return }
                    await MainActor.run {
                        guard target.generation==token else { return }
                        target.record.versions[target.record.versions.count-1].answer=text;target.publish()
                    }
                }
                guard let self,self.generation==token else { return }
                self.record.versions[self.record.versions.count-1].status = .complete
                self.task=nil;self.publish()
            } catch {
                guard let self,self.generation==token else { return }
                self.record.versions[self.record.versions.count-1].status = .interrupted
                if !Task.isCancelled { self.record.versions[self.record.versions.count-1].issue=error.localizedDescription }
                self.task=nil;self.publish()
            }
        }
    }
    public func followUp(_ text:String) {
        let value=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !running,!value.isEmpty,!answer.isEmpty else { return }
        let input=(current?.input ?? [])+[.init(role:.assistant,text:answer),.init(role:.user,text:value)]
        do { try AIInputBudget.validate([record.initial]+input);generate(input:input) }
        catch {
            if let index=currentIndex { record.versions[index].issue=error.localizedDescription;publish() }
        }
    }
    private func publish() { record.updatedAt=Date();onUpdate?(record) }
    deinit { task?.cancel() }
}
