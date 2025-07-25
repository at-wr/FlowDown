// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MemoryKit",
    platforms: [
        .iOS(.v13),
        .macCatalyst(.v13),
        .macOS(.v10_15),
    ],
    products: [
        .library(name: "MemoryKit", targets: ["MemoryKit"]),
    ],
    dependencies: [
        .package(path: "../Storage"),
        .package(url: "https://github.com/objectbox/objectbox-swift-spm.git", from: "4.0.0"),
        .package(url: "https://github.com/CoreOffice/XMLCoder.git", from: "0.17.0"),
    ],
    targets: [
        .target(name: "MemoryKit", dependencies: [
            "Storage",
            .product(name: "ObjectBox", package: "objectbox-swift-spm"),
            "XMLCoder",
        ]),
    ]
)
