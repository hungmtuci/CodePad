// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CodePad",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodePad", targets: ["CodePad"])
    ],
    targets: [
        .executableTarget(
            name: "CodePad",
            path: "Sources/CodePad",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
