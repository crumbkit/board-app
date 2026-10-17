// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "attention-sign",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "SSHSig"),
    .executableTarget(name: "attention-sign", dependencies: ["SSHSig"]),
    .testTarget(name: "SSHSigTests", dependencies: ["SSHSig"]),
  ]
)
