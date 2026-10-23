// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LearningReader",
    platforms: [.macOS(.v13), .iOS(.v18)],
    products: [
        .library(name: "LearningCore", targets: ["LearningCore"]),
        .executable(name: "LearningReader", targets: ["LearningReader"]),
        .executable(name: "course", targets: ["CourseTool"])
    ],
    dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")],
    targets: [
        .target(name: "LearningCore", dependencies: ["ZIPFoundation"], resources: [.copy("Resources")]),
        .executableTarget(name: "LearningReader", dependencies: ["LearningCore"], path: "Apps/Shared"),
        .executableTarget(name: "CourseTool", dependencies: ["LearningCore"]),
        .testTarget(name: "LearningCoreTests", dependencies: ["LearningCore", "ZIPFoundation"])
    ],
    swiftLanguageModes: [.v5]
)
