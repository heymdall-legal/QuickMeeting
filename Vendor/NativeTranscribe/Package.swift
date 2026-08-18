// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NativeTranscribe",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "NativeTranscribeRuntime",
            targets: ["NativeTranscribeRuntime"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "CTranscribe",
            url: "https://github.com/handy-computer/transcribe.cpp/releases/download/v0.2.0/TranscribeCpp.xcframework.zip",
            checksum: "5fffd4557d561ab6e45edd2445978682a513c1cd030c5a330c8519c5b27b64d9"
        ),
        .target(
            name: "NativeTranscribeRuntime",
            dependencies: ["CTranscribe"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("z"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
            ]
        ),
    ]
)
