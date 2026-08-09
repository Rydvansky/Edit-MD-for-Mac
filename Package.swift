// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "EditMDForMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "EditMDForMac", targets: ["EditMDForMac"])
    ],
    targets: [
        .executableTarget(name: "EditMDForMac")
    ]
)
