import Foundation

public enum ReviewConfidence:Int,CaseIterable,Identifiable,Sendable {
    case forgotten=1,uncertain=2,remembered=3
    public var id:Int {rawValue}
    public var title:String {
        switch self {case .forgotten:return "不会";case .uncertain:return "模糊";case .remembered:return "掌握"}
    }
}
