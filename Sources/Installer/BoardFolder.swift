// The folder a new personal board goes in, and whether the installer may
// make a board there. Install/install makes the same check in step 1 and
// is the one that decides; the sheet checks first so it can say why.
import Foundation

public enum BoardFolder {
  /// What the folder holds, and so whether the installer may use it.
  public enum Check: Sendable, Hashable {
    /// Nothing is there; the installer creates the folder.
    case missing
    /// An empty folder. A `.DS_Store` that Finder wrote does not count.
    case empty
    /// A git repository with no commit and no other file.
    case emptyRepository
    /// A git repository that holds `.board/board.json`.
    case board
    /// The installer refuses the folder, for the reason given.
    case refused(String)

    public var passes: Bool {
      if case .refused = self { return false }
      return true
    }
  }

  /// `~/Board`, where a new personal board goes unless the person picks another folder.
  public static func `default`(home: URL) -> URL { home.appendingPathComponent("Board") }

  public static func check(_ folder: URL) -> Check {
    let files = FileManager.default
    let path = folder.path
    guard let isFolder = isFolder(folder) else {
      return writableAncestor(of: folder)
        ? .missing : .refused("\(path) cannot be created. Choose another folder.")
    }
    guard isFolder else {
      return .refused("\(path) is a file. Choose an empty folder or an existing board.")
    }
    let kind: Check
    let git = folder.appendingPathComponent(".git")
    // Nil is right: a folder that cannot be listed is refused below as holding files.
    let entries = (try? files.contentsOfDirectory(atPath: path))?.filter { $0 != ".DS_Store" }
    if files.fileExists(atPath: git.path)
      && files.fileExists(atPath: folder.appendingPathComponent(".board/board.json").path)
    {
      kind = .board
    } else if entries == [] {
      kind = .empty
    } else if entries == [".git"], !hasCommit(git) {
      kind = .emptyRepository
    } else {
      return .refused(
        "\(path) holds files and is not a board. Choose an empty folder or an existing board.")
    }
    return files.isWritableFile(atPath: path)
      ? kind : .refused("\(path) cannot be written. Choose another folder.")
  }

  /// Whether the git directory has a branch with a commit, loose or packed.
  private static func hasCommit(_ git: URL) -> Bool {
    let heads = git.appendingPathComponent("refs/heads")
    // Nil is right: a repository without refs/heads has no loose branch.
    let loose = (try? FileManager.default.subpathsOfDirectory(atPath: heads.path))?.contains {
      isFolder(heads.appendingPathComponent($0)) == false
    }
    // Nil is right: a repository without packed-refs has no packed branch.
    let packed =
      (try? String(
        contentsOf: git.appendingPathComponent("packed-refs"), encoding: .utf8))?
      .split(separator: "\n").contains { !$0.hasPrefix("#") && $0.contains(" refs/heads/") }
    return loose == true || packed == true
  }

  /// Whether the path, after its links, is a folder; nil when nothing is there.
  private static func isFolder(_ url: URL) -> Bool? {
    // Nil is right: a path that cannot be read holds nothing to check.
    let attributes = try? FileManager.default.attributesOfItem(
      atPath: url.resolvingSymlinksInPath().path)
    return attributes.map { $0[.type] as? FileAttributeType == .typeDirectory }
  }

  /// Whether the nearest folder above `folder` that exists can be written.
  private static func writableAncestor(of folder: URL) -> Bool {
    var parent = folder.deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: parent.path), parent.path != "/" {
      parent = parent.deletingLastPathComponent()
    }
    return FileManager.default.isWritableFile(atPath: parent.path)
  }
}
