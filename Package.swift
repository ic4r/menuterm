// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MenuTerm",
    platforms: [.macOS("14.4")],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.99.1"),
    ],
    targets: [
        .executableTarget(
            name: "MenuTerm",
            dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "Sources/MenuTerm"
        ),
    ]
)
