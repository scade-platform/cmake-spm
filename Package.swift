// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "cmake-spm",
    platforms: [
        .macOS("13.0")
    ],
    dependencies: [
      .package(url: "https://github.com/apple/swift-package-manager.git", branch: "release/5.7"),
      .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.3")

    ],
    targets: [
        .executableTarget(
            name: "cmake-spm",
            dependencies: [
              .product(name: "SwiftPM-auto", package: "swift-package-manager"),
              .product(name: "ArgumentParser", package: "swift-argument-parser")
            ])
    ]
)
