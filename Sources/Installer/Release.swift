// A Board release, as the release.json beside its install script names it,
// and whether a Mac should be offered the release the app carries.
import Foundation

/// A git commit, by its full hash.
public struct Commit: Sendable, Hashable {
  public let hash: String

  /// A 40-character lowercase hexadecimal hash, or nil.
  public init?(_ hash: String) {
    guard hash.count == 40, hash.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
      return nil
    }
    self.hash = hash
  }

  /// The first `length` characters, as a person reads a commit.
  public func abbreviated(_ length: Int) -> String { String(hash.prefix(length)) }
}

/// Why a release.json was not read as a release.
public enum ReleaseError: Error, Sendable, Hashable {
  /// The file is not JSON with the fields a release has.
  case invalid(String)
}

/// One release: the crumbkit/board and board-app commits it was built from.
public struct Release: Sendable, Hashable {
  /// The id the installer copies the release under.
  public let id: String
  public let board: Commit
  public let app: Commit
  /// When the crumbkit/board commit was made, or nil for a release built
  /// before release.json recorded it.
  public let boardDate: Date?
  /// When the board-app commit was made, or nil for a release built before
  /// release.json recorded it.
  public let appDate: Date?

  private struct File: Decodable {
    let id: String
    let board: String
    let app: String
    let boardDate: String?
    let appDate: String?

    enum CodingKeys: String, CodingKey {
      case id, board
      case app = "board-app"
      case boardDate = "board-date"
      case appDate = "board-app-date"
    }
  }

  public init(json: Data) throws(ReleaseError) {
    let file: File
    do {
      file = try JSONDecoder().decode(File.self, from: json)
    } catch {
      throw .invalid(String(describing: error))
    }
    guard !file.id.isEmpty, !file.id.contains("/") else {
      throw .invalid("the id \(file.id) is not a folder name")
    }
    guard let board = Commit(file.board), let app = Commit(file.app) else {
      throw .invalid("a commit is not a 40-character hash")
    }
    (id, self.board, self.app) = (file.id, board, app)
    boardDate = try Self.date(file.boardDate, "board-date")
    appDate = try Self.date(file.appDate, "board-app-date")
  }

  private static func date(_ text: String?, _ field: String) throws(ReleaseError) -> Date? {
    guard let text else { return nil }
    // Nil is right: the guard turns any parse failure into the refusal.
    guard let parsed = try? Date(text, strategy: .iso8601) else {
      throw .invalid("\(field) \(text) is not an ISO 8601 time")
    }
    return parsed
  }

  /// Whether this release is newer than `other`: a later crumbkit/board
  /// commit, or the same one with a later board-app commit. Nil when either
  /// lacks the dates to tell.
  func isNewer(than other: Release) -> Bool? {
    guard let boardDate, let otherBoard = other.boardDate else { return nil }
    if boardDate != otherBoard { return boardDate > otherBoard }
    guard let appDate, let otherApp = other.appDate else { return nil }
    return appDate > otherApp
  }
}

/// The release ~/.local/share/board/current names.
public enum Installed: Sendable, Hashable {
  /// No current link: Board was never installed from a release.
  case none
  /// The link names this release id. The release is nil when its
  /// release.json cannot be read.
  case release(id: String, Release?)
}

/// What the app offers to do with the release it carries.
public enum Offer: Sendable, Hashable {
  /// No release is installed.
  case install
  /// An older release is installed: this one, or nil when it cannot be
  /// read.
  case update(from: Release?)

  /// Nil when the installed release is the one the app carries, or newer
  /// than it, so the app never offers a downgrade. A release whose age
  /// cannot be told from its dates is offered as an update, since releases
  /// without dates are the older ones.
  public init?(carrying carried: Release, installed: Installed) {
    switch installed {
    case .none: self = .install
    case .release(let id, _) where id == carried.id: return nil
    case .release(_, let release?) where carried.isNewer(than: release) == false: return nil
    case .release(_, let release): self = .update(from: release)
    }
  }
}
