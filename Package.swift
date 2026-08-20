// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Trans",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Trans", targets: ["Trans"])
    ],
    targets: [
        .executableTarget(
            name: "Trans",
            path: "Sources/Trans",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Vision"),
                .linkedFramework("CoreImage"),
                .linkedFramework("JavaScriptCore"),
                .linkedFramework("Security"),
                .linkedFramework("Translation"),
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(name: "TransTests", dependencies: ["Trans"], path: "Tests/TransTests")
    ],
    swiftLanguageModes: [.v5]
)
