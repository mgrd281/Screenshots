// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tendedero",
    platforms: [.macOS(.v14)],
    targets: [
        // Resources holds the translations, and InfoPlist macOS's questions
        // in each language. scripts/build-app.sh copies them into the app, so
        // SwiftPM leaves them alone.
        .executableTarget(name: "Tendedero", path: "Sources/Tendedero", exclude: ["Resources", "InfoPlist"]),
        // The logic that needs no screen, checked by CI at every push.
        .testTarget(name: "TendederoTests", dependencies: ["Tendedero"], path: "Tests/TendederoTests"),
    ]
)
