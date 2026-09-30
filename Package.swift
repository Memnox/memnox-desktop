// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MemnoxVoice",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MemnoxVoice", targets: ["MemnoxVoice"]),
        .library(name: "MemnoxVoiceCore", targets: ["MemnoxVoiceCore"]),
    ],
    targets: [
        // Everything that decides what to say and when, with no AppKit, so it is tested headless.
        .target(name: "MemnoxVoiceCore"),
        // The orb, the pill, the microphone and the speaker: a face and a voice over the core.
        .executableTarget(name: "MemnoxVoice", dependencies: ["MemnoxVoiceCore"]),
        .testTarget(name: "MemnoxVoiceCoreTests", dependencies: ["MemnoxVoiceCore"]),
    ]
)
