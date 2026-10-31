// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LearningReader",
    platforms: [.macOS(.v13), .iOS(.v18)],
    products: [
        .library(name: "LearningCore", targets: ["LearningCore"]),
        .library(name: "WebContent", targets: ["WebContent"]),
        .library(name: "AICore", targets: ["AICore"]),
        .library(name:"PracticeCore",targets:["PracticeCore"]),
        .library(name:"StudyLibrary",targets:["StudyLibrary"]),
        .executable(name: "LearningReader", targets: ["LearningReader"]),
        .executable(name: "course", targets: ["CourseTool"])
    ],
    dependencies: [.package(url:"https://github.com/open-spaced-repetition/swift-fsrs.git",revision:"4fbaf20184d62f82a9f44f343337c61a2c5483e9"),.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")],
    targets: [
        .target(name: "LearningCore", dependencies: ["ZIPFoundation"], resources: [.copy("Resources")]),
        .target(name: "WebContent"),
        .target(name: "AICore"),
        .target(name:"PracticeCore",dependencies:["AICore",.product(name:"FSRS",package:"swift-fsrs")]),
        .testTarget(name:"PracticeCoreTests",dependencies:["PracticeCore","AICore"]),
        .target(name:"StudyLibrary",dependencies:["AICore","ZIPFoundation"]),
        .executableTarget(name: "LearningReader", dependencies: ["LearningCore"], path: "Apps", exclude: ["iOS"], sources: ["Shared", "macOS"]),
        .executableTarget(name: "CourseTool", dependencies: ["LearningCore"]),
        .testTarget(name: "WebContentTests", dependencies: ["WebContent"]),
        .testTarget(name: "AICoreTests", dependencies: ["AICore"]),
        .testTarget(name:"StudyLibraryTests",dependencies:["StudyLibrary","AICore"]),
        .testTarget(name: "LearningCoreTests", dependencies: ["LearningCore", "ZIPFoundation"]),
        .testTarget(name: "WorkflowTests", dependencies: ["LearningReader", "LearningCore"])
    ],
    swiftLanguageModes: [.v5]
)
