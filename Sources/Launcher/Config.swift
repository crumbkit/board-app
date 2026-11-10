// The launcher's provider config, ~/.config/board/launcher.json. Anyone who
// can write it chooses what the launcher runs, so it is loaded only when the
// owner alone can write it.
import Foundation

/// A command that lists items for the launcher's top level.
public struct Provider: Codable, Sendable, Hashable {
  /// The name the footer and a failure row show.
  public let name: String
  /// The listing command, run from argv with no shell.
  public let list: [String]
}

public struct Config: Codable, Sendable, Hashable {
  public let providers: [Provider]

  /// Where the config lives under a home directory.
  public static func file(home: URL) -> URL {
    home.appendingPathComponent(".config/board/launcher.json")
  }
}

/// Why the config was not loaded. The panel shows the description.
public enum ConfigRefusal: Error, Sendable, Hashable, CustomStringConvertible {
  case missing(String)
  case symlink(String)
  case notOwned(String)
  case writableByOthers(String)
  case unreadable(String, String)
  case invalid(String, String)

  public var description: String {
    switch self {
    case .missing(let path):
      "No providers are set up. Add them to \(path)."
    case .symlink(let path):
      "\(path) is a symlink, so Board.app did not load it. Replace it with a file you own."
    case .notOwned(let path):
      "\(path) belongs to another user, so Board.app did not load it."
    case .writableByOthers(let path):
      "\(path) can be written by other users, so Board.app did not load it. Run chmod go-w on it."
    case .unreadable(let path, let reason):
      "Board.app could not read \(path): \(reason)"
    case .invalid(let path, let reason):
      "\(path) is not a valid launcher config: \(reason)"
    }
  }
}

extension Config {
  /// Loads the config at `file`, refusing a symlink, a file another user
  /// owns, and a file the group or others can write. `owner` is the user id
  /// that must own it, by default this process's.
  public static func load(from file: URL, owner: uid_t = getuid()) throws(ConfigRefusal) -> Config {
    let path = file.path
    // O_NOFOLLOW refuses a symlink, and the checks and the read use the one
    // descriptor, so the file cannot be swapped between them.
    let fd = unsafe open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard fd >= 0 else {
      switch errno {
      case ENOENT: throw .missing(path)
      case ELOOP: throw .symlink(path)
      default: throw .unreadable(path, unsafe String(cString: strerror(errno)))
      }
    }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    var info = stat()
    guard unsafe fstat(fd, &info) == 0 else {
      throw .unreadable(path, unsafe String(cString: strerror(errno)))
    }
    guard info.st_mode & S_IFMT == S_IFREG else { throw .unreadable(path, "it is not a file") }
    guard info.st_uid == owner else { throw .notOwned(path) }
    guard info.st_mode & (S_IWGRP | S_IWOTH) == 0 else { throw .writableByOthers(path) }
    let data: Data
    do {
      data = try handle.readToEnd() ?? Data()
    } catch {
      throw .unreadable(path, error.localizedDescription)
    }
    let config: Config
    do {
      config = try JSONDecoder().decode(Config.self, from: data)
    } catch {
      throw .invalid(path, "it must be {\"providers\": [{\"name\": …, \"list\": [argv]}]}")
    }
    if let bad = config.providers.first(where: { $0.list.first?.hasPrefix("/") != true }) {
      throw .invalid(path, "the list argv of \(bad.name) must start with an absolute path")
    }
    var names = Set<String>()
    if let twice = config.providers.first(where: { !names.insert($0.name).inserted }) {
      throw .invalid(path, "two providers are named \(twice.name)")
    }
    return config
  }
}
