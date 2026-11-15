// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MacUtilBar", platforms: [.macOS(.v14)], products: [.executable(name: "MacUtilBar", targets: ["MacUtilBar"])], targets: [
    .target(name: "MacUtilBarCore"),
    .executableTarget(name: "MacUtilBar", dependencies: ["MacUtilBarCore"]),
    .testTarget(name: "MacUtilBarCoreTests", dependencies: ["MacUtilBarCore"]),
    .testTarget(name: "MacUtilBarTests", dependencies: ["MacUtilBar", "MacUtilBarCore"])
])
