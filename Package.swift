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
        // snow behind a C ABI, copied in by scripts/sync-relay.sh, so this Mac, the phone and the runtime run one Noise.
        .binaryTarget(name: "MemnoxNoise", path: "Vendor/MemnoxNoise.xcframework"),
        // Everything that decides what to say and when, with no AppKit, so it is tested headless.
        .target(name: "MemnoxVoiceCore", dependencies: ["MemnoxNoise"]),
        // The orb, the pill, the microphone and the speaker: a face and a voice over the core.
        .executableTarget(name: "MemnoxVoice", dependencies: ["MemnoxVoiceCore"]),
        .testTarget(name: "MemnoxVoiceCoreTests", dependencies: ["MemnoxVoiceCore"]),
    ]
)
