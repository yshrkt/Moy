// swift-tools-version: 6.4
import PackageDescription

#if TUIST
    import struct ProjectDescription.PackageSettings

    let packageSettings = PackageSettings(productTypes: [:])
#endif

let package = Package(
    name: "Moy",
    dependencies: [
        .package(url: "https://github.com/yshrkt/NanoRedux", exact: "0.1.2"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
    ],
)
