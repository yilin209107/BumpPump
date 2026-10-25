// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "BumpPump", platforms: [.macOS(.v13)], products: [.executable(name: "BumpPump", targets: ["BumpPump"])], targets: [.systemLibrary(name: "CSQLite"), .executableTarget(name: "BumpPump", dependencies: ["CSQLite"])])
