// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LocalAgentServer",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "LocalAgentServer",
            path: "Sources/LocalAgentServer"
        )
    ]
)
