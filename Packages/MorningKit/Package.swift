// swift-tools-version: 6.0
import PackageDescription

/// The CLI carries an embedded Info.plist (bundle id + privacy usage strings) so that
/// macOS can attribute Calendar/Reminders permission to it when launchd runs it.
let manifestPath: String = #filePath
let packageDirectory = String(manifestPath[..<(manifestPath.lastIndex(of: "/") ?? manifestPath.endIndex)])
let cliInfoPlist = packageDirectory + "/../../Support/cli-Info.plist"

let package = Package(
    name: "MorningKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MorningKit", targets: ["MorningKit"]),
        .executable(name: "morning-cli", targets: ["morning-cli"]),
    ],
    targets: [
        .target(name: "MorningKit"),
        .executableTarget(
            name: "morning-cli",
            dependencies: ["MorningKit"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", cliInfoPlist]),
            ]
        ),
        .testTarget(name: "MorningKitTests", dependencies: ["MorningKit"]),
    ],
    swiftLanguageModes: [.v6]
)
