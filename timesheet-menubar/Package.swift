// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TimesheetMenuBar",
    platforms: [
        .macOS(.v13) // MenuBarExtra requires macOS 13 (Ventura) or newer.
    ],
    products: [
        .executable(name: "TimesheetMenuBar", targets: ["TimesheetMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "TimesheetMenuBar",
            path: "Sources/TimesheetMenuBar"
        )
    ]
)
