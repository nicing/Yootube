// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Yootube",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Yootube", targets: ["Yootube"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "Yootube",
            dependencies: ["Sparkle"],
            path: "Sources/Yootube",
            resources: [.copy("PlayerSkin.js"), .copy("Icons")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "YootubeTests",
            dependencies: ["Yootube"]
        )
    ]
)
