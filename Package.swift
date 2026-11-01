// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "de-monitor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "de-monitor", targets: ["DEMonitorCLI"]),
        .executable(name: "de-monitor-app", targets: ["MonitorApp"]),
    ],
    targets: [
        .target(
            name: "DisplaySwitcherCore",
            path: "Sources/DisplaySwitcherCore"
        ),
        .executableTarget(
            name: "DEMonitorCLI",
            dependencies: ["DisplaySwitcherCore"],
            path: "Sources/DEMonitorCLI"
        ),
        .executableTarget(
            name: "MonitorApp",
            dependencies: ["DisplaySwitcherCore"],
            path: "Sources/MonitorApp"
        ),
        .testTarget(
            name: "DisplaySwitcherCoreTests",
            dependencies: ["DisplaySwitcherCore"],
            path: "Tests/DisplaySwitcherCoreTests"
        ),
    ]
)
