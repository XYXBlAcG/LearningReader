import SwiftUI
import AICore
import StudyLibrary
import UniformTypeIdentifiers

@MainActor
final class StudyWorkspace:ObservableObject {
    @Published private(set) var records:[StudySummary]=[]
    @Published var issue:String?
    @Published private(set) var canUndo=false
    @Published private(set) var saving=Set<UUID>()
    var onOpenSource:((StudySource)->Void)?
    private var store:StudyStore?
    private var pending:[UUID:StudyRecord]=[:]
    private var tasks:[UUID:Task<Void,Never>]=[:]
    init() {
        do { store=try StudyStore();try reload() }
        catch { issue="无法打开本地讲解库："+error.localizedDescription }
    }
    func record(_ id:UUID)->StudyRecord? {
        do {return try requiredStore().record(id)}
        catch {issue=error.localizedDescription;return nil}
    }
    func receive(_ record:StudyRecord,automatic:Bool) {
        guard automatic || records.contains(where:{$0.id==record.id}), store?.isDeleted(record.id) != true,record.hasAnswer else { return }
        pending[record.id]=record;saving.insert(record.id)
        if record.versions.last?.status != .generating { flush(record.id);return }
        if tasks[record.id] == nil {
            tasks[record.id]=Task { [weak self] in
                try? await Task.sleep(nanoseconds:800_000_000)
                guard !Task.isCancelled else { return }
                self?.flush(record.id)
            }
        }
    }
    func flush(_ id:UUID?=nil) {
        let ids=id.map{[$0]} ?? Array(pending.keys)
        for key in ids {
            tasks.removeValue(forKey:key)?.cancel()
            guard let record=pending[key] else { continue }
            perform { try requiredStore().upsert(record);pending.removeValue(forKey:key);saving.remove(key) }
        }
    }
    func save(_ record:StudyRecord) { perform { try requiredStore().upsert(record,explicit:true) } }
    func rename(_ id:UUID,title:String) { perform { try requiredStore().rename(id,title:title) } }
    func delete(_ ids:Set<UUID>) {
        perform {
            try requiredStore().delete(ids)
            for id in ids { tasks.removeValue(forKey:id)?.cancel();pending.removeValue(forKey:id);saving.remove(id) }
        }
    }
    func undo() { perform { try requiredStore().undo() } }
    func position(_ id:UUID,_ value:Double) { perform { try requiredStore().position(id,value:value) } }
    func deleteVersion(_ id:UUID,version:UUID) { perform { try requiredStore().deleteVersion(recordID:id,versionID:version) } }
    func backup()->Data? {
        do { flush();guard pending.isEmpty else {throw CocoaError(.fileWriteUnknown)};return try requiredStore().backup() }
        catch { issue=error.localizedDescription;return nil }
    }
    func restore(_ data:Data) { perform { try requiredStore().restore(data) } }
    private func requiredStore() throws -> StudyStore {
        guard let store else { throw CocoaError(.fileReadUnknown) }
        return store
    }
    private func reload() throws { records=try requiredStore().summaries();canUndo=store?.canUndo == true }
    private func perform(_ operation:() throws -> Void) {
        do { try operation();try reload();issue=nil }
        catch { issue="本地讲解未保存："+error.localizedDescription }
    }
}

struct StudyDataDocument:FileDocument {
    static var readableContentTypes:[UTType] { [.json,.plainText,.zip,UTType(importedAs:"net.daringfireball.markdown")] }
    var data:Data
    init(data:Data) { self.data=data }
    init(configuration:ReadConfiguration) throws { guard let data=configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) };self.data=data }
    func fileWrapper(configuration:WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}
