// swift-tools-version:6.2
import PackageDescription

// Logic, parsing and storage targets, and every test target.
let baseSettings: [SwiftSetting] = [
  .swiftLanguageMode(.v6),
  // An async function runs on its caller's actor unless it is marked
  // @concurrent (SE-0461).
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  // A main-actor type's conformances are main-actor too (SE-0470).
  .enableUpcomingFeature("InferIsolatedConformances"),
  // Every existential type is spelled `any P` (SE-0335).
  .enableUpcomingFeature("ExistentialAny"),
  // A member is visible only in files that import its module (SE-0444).
  .enableUpcomingFeature("MemberImportVisibility"),
  // Every unsafe construct is marked `unsafe` (SE-0458).
  .strictMemorySafety(),
]

// Targets that hold views, view models or other user-interface code (BASE-4).
let interfaceSettings: [SwiftSetting] =
  baseSettings + [
    .defaultIsolation(MainActor.self)
  ]

let package = Package(
  name: "board-app",
  platforms: [.macOS(.v14), .iOS(.v17)],
  products: [
    .library(name: "SSHSig", targets: ["SSHSig"]),
    .library(name: "Pairing", targets: ["Pairing"]),
    .library(name: "Requests", targets: ["Requests"]),
    .library(name: "Launcher", targets: ["Launcher"]),
    .library(name: "Installer", targets: ["Installer"]),
  ],
  targets: [
    .target(name: "SSHSig", swiftSettings: baseSettings),
    .target(name: "Pairing", dependencies: ["SSHSig"], swiftSettings: baseSettings),
    .target(name: "Requests", dependencies: ["SSHSig"], swiftSettings: baseSettings),
    .target(name: "Launcher", swiftSettings: baseSettings),
    .target(name: "Installer", dependencies: ["Launcher"], swiftSettings: baseSettings),
    .executableTarget(
      name: "attention-sign", dependencies: ["SSHSig"], swiftSettings: interfaceSettings),
    .testTarget(
      name: "SSHSigTests", dependencies: ["SSHSig"], resources: [.copy("Fixtures")],
      swiftSettings: baseSettings),
    .testTarget(
      name: "PairingTests", dependencies: ["Pairing", "SSHSig"], swiftSettings: baseSettings),
    .testTarget(
      name: "RequestsTests", dependencies: ["Requests", "SSHSig"], resources: [.copy("Fixtures")],
      swiftSettings: baseSettings),
    .testTarget(
      name: "LauncherTests", dependencies: ["Launcher"], resources: [.copy("Fixtures")],
      swiftSettings: baseSettings),
    .testTarget(
      name: "InstallerTests", dependencies: ["Installer", "Launcher"], swiftSettings: baseSettings),
    .testTarget(name: "GatesTests", swiftSettings: baseSettings),
  ]
)
