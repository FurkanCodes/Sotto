// swift-tools-version: 6.2
import PackageDescription

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
        .executableTarget(
            name: "Sotto",
            dependencies: [
                "SottoCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/Sotto"
        ),
        .testTarget(name: "SottoCoreTests", dependencies: ["SottoCore"], path: "Tests/SottoCoreTests"),
    ]
)
