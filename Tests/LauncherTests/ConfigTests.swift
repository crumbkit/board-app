import Foundation
import XCTest

@testable import Launcher

/// The config loads only from a regular file the owner alone can write.
/// The tests use files in a temporary directory, not the real config.
final class ConfigTests: XCTestCase {
  private var directory: URL!
  private var file: URL { directory.appendingPathComponent("launcher.json") }
  private let valid =
    #"{"providers": [{"name": "Workspaces", "list": ["/usr/local/bin/ws", "list"]}]}"#

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("launcher-config-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: directory)
  }

  private func write(_ text: String, mode: Int = 0o600) throws {
    try Data(text.utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path)
  }

  private func refusal(owner: uid_t = getuid()) -> ConfigRefusal? {
    do {
      _ = try Config.load(from: file, owner: owner)
      return nil
    } catch {
      return error
    }
  }

  func testAnOwnedPrivateFileLoads() throws {
    try write(valid)
    let config = try Config.load(from: file)
    XCTAssertEqual(
      config.providers, [Provider(name: "Workspaces", list: ["/usr/local/bin/ws", "list"])])
  }

  func testAFileOthersCanReadButNotWriteLoads() throws {
    try write(valid, mode: 0o644)
    XCTAssertNil(refusal())
  }

  func testAMissingFileSaysWhereProvidersGo() {
    XCTAssertEqual(refusal(), .missing(file.path))
  }

  func testAFileTheGroupCanWriteIsRefused() throws {
    try write(valid, mode: 0o620)
    XCTAssertEqual(refusal(), .writableByOthers(file.path))
  }

  func testAFileAnyoneCanWriteIsRefused() throws {
    try write(valid, mode: 0o602)
    XCTAssertEqual(refusal(), .writableByOthers(file.path))
  }

  func testASymlinkIsRefusedEvenToAGoodFile() throws {
    let target = directory.appendingPathComponent("real.json")
    try Data(valid.utf8).write(to: target)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
    XCTAssertEqual(refusal(), .symlink(file.path))
  }

  func testAFileAnotherUserOwnsIsRefused() throws {
    try write(valid)
    XCTAssertEqual(refusal(owner: getuid() + 1), .notOwned(file.path))
  }

  func testInvalidJSONIsRefused() throws {
    try write(#"{"providers": "none"}"#)
    guard case .invalid = refusal() else { return XCTFail("loaded") }
  }

  func testARelativeListCommandIsRefused() throws {
    try write(#"{"providers": [{"name": "Workspaces", "list": ["ws", "list"]}]}"#)
    guard case .invalid(_, let reason) = refusal() else { return XCTFail("loaded") }
    XCTAssertTrue(reason.contains("absolute path"), reason)
  }
}

extension ConfigTests {
  func testTwoProvidersWithOneNameAreRefused() throws {
    try write(
      #"{"providers": [{"name": "A", "list": ["/bin/echo"]}, {"name": "A", "list": ["/bin/date"]}]}"#
    )
    guard case .invalid(_, let reason) = refusal() else { return XCTFail("loaded") }
    XCTAssertEqual(reason, "two providers are named A")
  }

  func testADirectoryIsRefused() throws {
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    XCTAssertEqual(refusal(), .unreadable(file.path, "it is not a file"))
  }
}
