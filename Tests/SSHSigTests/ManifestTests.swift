import CryptoKit
import Foundation
import XCTest

/// The vendored vectors are Board's, unchanged. This proves every file in
/// `vectors/signing/v1` has the SHA-256 the manifest gives it and that no file
/// is missing or extra, so a copy edited without its manifest fails. Hidden
/// files such as `.DS_Store` are skipped, and `vectors/signing/README.md`
/// is outside the manifest. It does not prove the manifest is Board's; docs/signing.md names the commit it
/// was copied from.
final class ManifestTests: XCTestCase {
  func testEveryVendoredFileHasTheDigestTheManifestGivesIt() throws {
    let files = try XCTUnwrap(Vectors.manifest()["files"] as? [String: String])
    let root = Vectors.directory.resolvingSymlinksInPath().path + "/"
    let enumerator = try XCTUnwrap(
      FileManager.default.enumerator(
        at: Vectors.directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles))
    var found: [String: String] = [:]
    for case let url as URL in enumerator where !url.hasDirectoryPath {
      let name = String(url.resolvingSymlinksInPath().path.dropFirst(root.count))
      guard name != "manifest.json" else { continue }
      found[name] = SHA256.hash(data: try Data(contentsOf: url)).map {
        unsafe String(format: "%02x", $0)
      }
      .joined()
    }
    XCTAssertEqual(found, files)
  }
}
