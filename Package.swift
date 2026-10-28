// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "board-app",
  platforms: [.macOS(.v14), .iOS(.v17)],
  products: [
    .library(name: "SSHSig", targets: ["SSHSig"]),
    .library(name: "Pairing", targets: ["Pairing"]),
  ],
  targets: [
    .target(name: "SSHSig"),
    .target(name: "Pairing", dependencies: ["SSHSig"]),
    .executableTarget(name: "attention-sign", dependencies: ["SSHSig"]),
    .testTarget(name: "SSHSigTests", dependencies: ["SSHSig"]),
    .testTarget(name: "PairingTests", dependencies: ["Pairing", "SSHSig"]),
  ]
)
