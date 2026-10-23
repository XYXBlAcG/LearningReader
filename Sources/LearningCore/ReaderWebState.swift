import Foundation

public struct ReaderWebState: Decodable {
    public struct Visit: Decodable {
        public let kind: String
        public let path: String
        public let time: Double
        public let label: String
        public let missing: Bool
    }
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
