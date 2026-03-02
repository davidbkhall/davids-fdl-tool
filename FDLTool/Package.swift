// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FDLTool",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FDLTool", targets: ["FDLTool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0"),
    ],
    targets: [
        .executableTarget(
            name: "FDLTool",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            path: "Sources/FDLTool"
        ),
        .testTarget(
            name: "FDLToolTests",
            dependencies: ["FDLTool"],
            path: "Tests/FDLToolTests"
        ),
    ]
)
