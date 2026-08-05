// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MDDesignMacOS",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MDDesignMacOS", targets: ["MDDesignMacOS"])
    ],
    targets: [
        .executableTarget(name: "MDDesignMacOS")
    ]
)
