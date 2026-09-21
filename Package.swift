// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Yootube",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Yootube", targets: ["Yootube"])
    ],
    targets: [
        .executableTarget(
            name: "Yootube",
            path: "Sources/Yootube",
            resources: [.copy("PlayerSkin.js"), .copy("Icons")]
        ),
        .testTarget(
            name: "YootubeTests",
            dependencies: ["Yootube"]
        )
    ]
)
