// swift-tools-version: 6.2
import Foundation
import PackageDescription

/// transcribe.cpp's static libraries, built by scripts/build-transcribe.sh.
let transcribeLibraries = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Vendor/transcribe/lib").path

let package = Package(
    name: "Sotto",
    platforms: [.macOS("26.0")],
    dependencies: [
        // `traits: []` drops FluidAudio's NeMo text-normalization engine (~8 MB);
        // Sotto only uses its speech recognition and voice detection.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: []),
    ],
    targets: [
        // Platform-independent logic. No AppKit, SwiftUI or FluidAudio here.
        .target(name: "SottoCore", path: "Sources/SottoCore"),
        .target(name: "SottoEngineProtocol", path: "Sources/SottoEngineProtocol"),
        .systemLibrary(name: "CTranscribe", path: "Sources/CTranscribe"),
        .executableTarget(
            name: "Sotto",
            dependencies: [
                "SottoCore",
                "SottoEngineProtocol",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/Sotto"
        ),
        // The XPC helper that runs transcribe.cpp models in their own process.
        .executableTarget(
            name: "SottoEngine",
            dependencies: ["CTranscribe", "SottoEngineProtocol"],
            path: "Sources/SottoEngine",
            linkerSettings: [.unsafeFlags(["-L", transcribeLibraries])]
        ),
        .testTarget(name: "SottoCoreTests", dependencies: ["SottoCore"], path: "Tests/SottoCoreTests"),
    ]
)
