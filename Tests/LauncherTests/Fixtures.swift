import Foundation

@testable import Launcher

/// The fixtures under Fixtures/, decoded as the app decodes them.
enum Fixtures {
  static func data(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: "Fixtures/" + name, withExtension: nil) else {
      throw CocoaError(.fileNoSuchFile)
    }
    return try Data(contentsOf: url)
  }

  static func listing(_ name: String) throws -> Listing {
    try Listing.decode(data(name))
  }
}
