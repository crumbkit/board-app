import Foundation
import XCTest

@testable import Launcher

/// ↩ on evidence never launches a program, and the preview reads only
/// regular files. The tests use files in a temporary directory; they do
/// not open anything.
final class EvidenceFilesTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("launcher-evidence-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: directory)
  }

  private func file(_ name: String, mode: Int = 0o644) throws -> String {
    let url = directory.appendingPathComponent(name)
    try Data("echo hi\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    return url.path
  }

  func testAReportOpensInItsApp() throws {
    XCTAssertEqual(EvidenceFiles.opening(try file("report.md")), .open)
    XCTAssertEqual(EvidenceFiles.opening(try file("run.log")), .open)
  }

  func testAnExecutableEvidenceFileIsRevealedNotLaunched() throws {
    XCTAssertEqual(EvidenceFiles.opening(try file("report.md", mode: 0o755)), .reveal)
    XCTAssertEqual(EvidenceFiles.opening(try file("tool", mode: 0o700)), .reveal)
  }

  func testAScriptIsRevealedEvenWithoutTheExecuteBit() throws {
    XCTAssertEqual(EvidenceFiles.opening(try file("setup.sh")), .reveal)
    XCTAssertEqual(EvidenceFiles.opening(try file("run.command")), .reveal)
  }

  func testAnAppBundleOrSymlinkIsRevealed() throws {
    let app = directory.appendingPathComponent("Tool.app")
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: false)
    XCTAssertEqual(EvidenceFiles.opening(app.path), .reveal)
    let link = directory.appendingPathComponent("link.md")
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/bin/sh")
    XCTAssertEqual(EvidenceFiles.opening(link.path), .reveal)
  }

  func testAMissingFileIsMissing() {
    XCTAssertEqual(EvidenceFiles.opening(directory.appendingPathComponent("gone").path), .missing)
  }

  func testOnlyARegularFileIsRead() throws {
    let path = try file("run.log")
    XCTAssertEqual(EvidenceFiles.read(path), Data("echo hi\n".utf8))
    XCTAssertEqual(EvidenceFiles.read(path, limit: 4), Data("echo".utf8))
    XCTAssertNil(EvidenceFiles.read(directory.path))
    let link = directory.appendingPathComponent("link.log")
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: path)
    XCTAssertNil(EvidenceFiles.read(link.path))
    XCTAssertFalse(EvidenceFiles.isRegular(link.path))
  }
}
