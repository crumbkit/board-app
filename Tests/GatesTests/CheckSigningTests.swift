import Foundation
import Testing

/// `bin/check-signing` refuses a signing import outside the files
/// signing-owners.txt names, also when it is scoped or reached through a
/// symlink, and admits the same import in an owner. Each test
/// runs the script on a directory it writes, with this checkout's owners
/// file. They prove the script's matching on these cases; they do not
/// prove the owners file lists the right owners.
struct CheckSigningTests {
  static let script = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("bin/check-signing")

  /// The script's exit status and standard error on a tree holding `text` at
  /// `path`, or a link at `path` to a file outside the tree holding `text`.
  func check(_ path: String, _ text: String, linked: Bool = false) throws -> (
    status: Int32, error: String
  ) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: outside)
    }
    let file = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    if linked {
      try Data(text.utf8).write(to: outside)
      try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
    } else {
      try Data(text.utf8).write(to: file)
    }
    let process = Process()
    process.executableURL = Self.script
    process.arguments = [root.path]
    let error = Pipe()
    process.standardError = error
    try process.run()
    let output = error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: output, as: UTF8.self))
  }

  @Test func an_import_of_cryptokit_outside_the_owners_fails_and_names_the_file() throws {
    let result = try check("Apps/macOS/Other.swift", "import CryptoKit\n")
    #expect(result.status == 1)
    #expect(result.error.contains("Apps/macOS/Other.swift:1 names CryptoKit"))
  }

  @Test func the_same_import_in_an_owner_passes() throws {
    let result = try check("Sources/SSHSig/Extra.swift", "import CryptoKit\n")
    #expect(result.status == 0)
    #expect(result.error.isEmpty)
  }

  @Test func a_scoped_import_outside_the_owners_fails() throws {
    let result = try check("Apps/macOS/Other.swift", "import struct CryptoKit.SHA256\n")
    #expect(result.status == 1)
  }

  @Test func an_import_reached_through_a_symlink_fails() throws {
    let result = try check("Apps/macOS/Link.swift", "import CryptoKit\n", linked: true)
    #expect(result.status == 1)
    #expect(result.error.contains("Apps/macOS/Link.swift"))
  }

  @Test func a_software_signing_key_outside_the_tests_fails_even_in_an_owner() throws {
    let result = try check("Sources/SSHSig/Key.swift", "SecKeyCreateRandomKey(attributes, nil)\n")
    #expect(result.status == 1)
  }
}
