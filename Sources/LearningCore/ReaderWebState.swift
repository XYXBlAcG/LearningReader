import Foundation

public struct ReaderWebState: Decodable {
    public struct Visit: Decodable, Identifiable {
        public var id:String { kind+":"+path }
        public let kind: String
        public let path: String
        public let time: Double
        public let label: String
        public let missing: Bool
    }
    public struct Heading:Decodable,Identifiable {
        public let id:String
        public let title:String
        public let level:Int
    }
    public let documentKind:String?
    public let pinnedKeys:[String]?
    public let canUndoHistory:Bool?
    public let outlineItems:[Heading]?
    public let searchStatus:String?
    public let title: String
    public let path: String
    public let hasDocument: Bool
    public let canBack: Bool
    public let canForward: Bool
    public let pinned: Bool
    public let counterpart: String
    public let sidebar: Bool
    public let outline: Bool
    public let panel: String
    public let immersive: Bool
    public let zoom: Double
    public let previews: Bool
    public let history: [Visit]
}
