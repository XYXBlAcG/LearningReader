import Foundation
import SwiftData
import AICore

@available(macOS 14,iOS 17,*)
@MainActor
public final class StudyStore {
    private let container:ModelContainer
    private let context:ModelContext
    private var removed=Set<UUID>()
    private var removedVersions=Set<UUID>()
    private var undoRecords:[StudyRecord]=[]
    public func isDeleted(_ id:UUID)->Bool { removed.contains(id) }
    public var canUndo:Bool { !undoRecords.isEmpty }
    public init(directory:URL?=nil,inMemory:Bool=false) throws {
        let schema=Schema(versionedSchema:StudySchema.self)
        let configuration:ModelConfiguration
        if inMemory { configuration=ModelConfiguration(schema:schema,isStoredInMemoryOnly:true,cloudKitDatabase:.none) }
        else {
            let root=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LearningReader/Study")
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            configuration=ModelConfiguration(schema:schema,url:root.appendingPathComponent("Library.store"),cloudKitDatabase:.none)
        }
        container=try ModelContainer(for:schema,migrationPlan:StudyMigrations.self,configurations:[configuration])
        context=ModelContext(container);context.autosaveEnabled=false
        for entity in try context.fetch(FetchDescriptor<StoredStudy>()) {
            for version in entity.versions where version.status==StudyStatus.generating.rawValue { version.status=StudyStatus.interrupted.rawValue }
        }
        try context.save()
    }
    public func records() throws -> [StudyRecord] {
        try context.fetch(FetchDescriptor<StoredStudy>(sortBy:[SortDescriptor(\.updatedAt,order:.reverse)])).map{try $0.record}
    }
    public func record(_ id:UUID) throws -> StudyRecord? { try entity(id)?.record }
    public func summaries() throws -> [StudySummary] {
        try context.fetch(FetchDescriptor<StoredStudy>(sortBy:[SortDescriptor(\.updatedAt,order:.reverse)])).map { item in
            StudySummary(id:item.id,title:item.title,updatedAt:item.updatedAt,source:try item.source.map{try JSONDecoder().decode(StudySource.self,from:$0)},questionDigest:item.questionDigest,searchText:item.searchText)
        }
    }
    public func upsert(_ incoming:StudyRecord,explicit:Bool=false) throws {
        var record=incoming
        record.versions.removeAll{removedVersions.contains($0.id)}
        guard record.hasAnswer else { return }
        if explicit { removed.remove(record.id) }
        guard !removed.contains(record.id) else { return }
        do {
            if let old=try entity(record.id) {
                if !old.titleEdited { old.title=record.title }
                old.updatedAt=record.updatedAt;old.system=record.system;old.searchText=record.searchText
                let ids=Set(record.versions.map(\.id))
                for obsolete in old.versions where !ids.contains(obsolete.id) { context.delete(obsolete) }
                old.versions.removeAll{!ids.contains($0.id)}
                for (order,version) in record.versions.enumerated() {
                    if let stored=old.versions.first(where:{$0.id==version.id}) {
                        stored.order=order;stored.answer=version.answer;stored.status=version.status.rawValue;stored.issue=version.issue
                    } else { old.versions.append(StoredStudyVersion(version,order:order)) }
                }
            } else { context.insert(try StoredStudy(record)) }
            try context.save()
        } catch { context.rollback();throw error }
    }
    public func rename(_ id:UUID,title:String) throws {
        let name=title.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            if let item=try entity(id) { item.title=name;item.titleEdited=true;try context.save() }
        } catch { context.rollback();throw error }
    }
    public func position(_ id:UUID,value:Double) throws {
        do {if let item=try entity(id) { item.position=max(0,value);try context.save() }}
        catch {context.rollback();throw error}
    }
    public func delete(_ ids:Set<UUID>) throws {
        let entities=try context.fetch(FetchDescriptor<StoredStudy>()).filter{ids.contains($0.id)}
        let snapshots=try entities.map{try $0.record}
        do { entities.forEach(context.delete);try context.save();removed.formUnion(ids);undoRecords=snapshots }
        catch { context.rollback();throw error }
    }
    public func undo() throws {
        let values=undoRecords
        do { for record in values { context.insert(try StoredStudy(record)) };try context.save();undoRecords=[];removed.subtract(values.map(\.id)) }
        catch { context.rollback();throw error }
    }
    public func deleteVersion(recordID:UUID,versionID:UUID) throws {
        guard var record=try records().first(where:{$0.id==recordID}) else { return }
        record.versions.removeAll{$0.id==versionID}
        if record.hasAnswer { try upsert(record,explicit:true);undoRecords=[] } else { try delete([recordID]) }
        removedVersions.insert(versionID)
    }
    private func entity(_ id:UUID) throws -> StoredStudy? {
        var request=FetchDescriptor<StoredStudy>(predicate:#Predicate { $0.id==id })
        request.fetchLimit=1
        return try context.fetch(request).first
    }
    public func backup() throws -> Data { try JSONEncoder().encode(StudyBackup(records:records())) }
    public func restore(_ data:Data) throws {
        let backup=try JSONDecoder().decode(StudyBackup.self,from:StudyArchive.contents(data))
        guard backup.version==1,Set(backup.records.map(\.id)).count==backup.records.count,
              backup.records.allSatisfy({$0.hasAnswer && !$0.title.isEmpty && Set($0.versions.map(\.id)).count==$0.versions.count}) else { throw CocoaError(.fileReadCorruptFile) }
        let existing=Set(try records().map(\.id))
        do {
            for var record in backup.records where !existing.contains(record.id) {
                for index in record.versions.indices where record.versions[index].status == .generating {record.versions[index].status = .interrupted}
                context.insert(try StoredStudy(record))
            }
            try context.save()
            removed.subtract(backup.records.map(\.id));removedVersions.subtract(backup.records.flatMap{$0.versions.map(\.id)})
        } catch { context.rollback();throw error }
    }
}

private struct StudyBackup:Codable {
    var version=1
    let records:[StudyRecord]
}
