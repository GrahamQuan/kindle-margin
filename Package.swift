// swift-tools-version: 5.10
import PackageDescription
import Foundation
// Explicit development dependency prefix; release bundles must use embedded, signed libraries.
let mtpPrefix = ProcessInfo.processInfo.environment["KINDLE_MARGIN_MTP_PREFIX"]
let deviceDependencies: [Target.Dependency] = mtpPrefix == nil ? ["KindleDomain"] : ["KindleDomain", "CLibMTP"]
let mtpSwiftSettings: [SwiftSetting] = mtpPrefix.map { [.unsafeFlags(["-Xcc", "-I" + $0 + "/include"])] } ?? []
let mtpLinkSettings: [LinkerSetting] = mtpPrefix.map { [.unsafeFlags(["-L" + $0 + "/lib", "-Xlinker", "-rpath", "-Xlinker", $0 + "/lib"])] } ?? []
let package = Package(
    name: "KindleMargin", platforms: [.macOS(.v14)],
    products: [.executable(name: "KindleMargin", targets: ["KindleMargin"])],
    targets: [
        .systemLibrary(name: "CLibMTP", path: "Packages/CLibMTP"),
        .systemLibrary(name: "CZlib", path: "Packages/CZlib"),
        .systemLibrary(name: "CSQLite", path: "Packages/CSQLite"),
        .target(name: "KindleDomain", path: "Packages/KindleDomain"),
        .target(name: "KindleClippings", dependencies: ["KindleDomain"], path: "Packages/KindleClippings"),
        .target(name: "KindleDictionary", dependencies: ["KindleDomain"], path: "Packages/KindleDictionary"),
        .target(name: "KindleDevice", dependencies: deviceDependencies, path: "Packages/KindleDevice", swiftSettings: mtpSwiftSettings, linkerSettings: mtpLinkSettings),
        .target(name: "KindleConversion", dependencies: ["KindleDomain", "CZlib"], path: "Packages/KindleConversion"),
        .target(name: "KindlePersistence", dependencies: ["KindleDomain", "CSQLite"], path: "Packages/KindlePersistence"),
        .target(name: "KindleApplication", dependencies: ["KindleDomain"], path: "Packages/KindleApplication"),
        .target(name: "Features", dependencies: ["KindleApplication", "KindleDomain"], path: "Features"),
        .executableTarget(name: "KindleMargin", dependencies: ["Features", "KindleApplication", "KindlePersistence", "KindleClippings", "KindleDictionary", "KindleDevice", "KindleConversion"], path: "App", resources: [.process("Resources")]),
        .executableTarget(name: "KindleMarginChecks", dependencies: ["Features", "KindleApplication", "KindlePersistence", "KindleClippings", "KindleDictionary", "KindleDevice", "KindleConversion"], path: "Tests")
    ])
