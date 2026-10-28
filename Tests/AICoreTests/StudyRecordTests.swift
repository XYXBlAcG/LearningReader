import XCTest
@testable import AICore

final class StudyRecordTests:XCTestCase {
    func testAutomaticSavingDefaultsOnForExistingSettings() throws {
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(AISettings())) as! [String:Any]
        object.removeValue(forKey:"autoSaveExplanations")
        let settings=try JSONDecoder().decode(AISettings.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertTrue(settings.autoSaveExplanations)
    }
    func testArchiveRoundTripKeepsQuestionContextVersionsAndNoCredential() throws {
        let material=AIMaterial(title:"文件",text:"选区",document:"全文",question:"完整题干")
        let record=StudyRecord(material:material,initial:try material.message(),system:"教学规范",action:.explain)
        let data=try JSONEncoder().encode(record)
        let restored=try JSONDecoder().decode(StudyRecord.self,from:data)
        XCTAssertEqual(restored.question,"完整题干")
        XCTAssertTrue(restored.initial.text.contains("全文"))
        XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("apiKey"))
        XCTAssertFalse(record.hasAnswer)
    }
}
