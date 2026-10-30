// How the launcher treats an evidence file on disk. A provider names the
// path, so the launcher never launches it and reads only regular files.
import Foundation
import UniformTypeIdentifiers

/// What ↩ does with an evidence file.
public enum FileOpening: Sendable, Hashable {
  /// Opens it in its default app.
  case open
  /// Shows it in Finder: it is a program, a script, an app bundle or not a
  /// regular file, and opening it would run it.
  case reveal
  /// Nothing, since no file is there.
  case missing
}

public enum EvidenceFiles {
  /// What ↩ does with the file at `path`.
  public static func opening(_ path: String) -> FileOpening {
    var info = stat()
    guard lstat(path, &info) == 0 else { return .missing }
    guard info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o111 == 0 else { return .reveal }
    let ext = (path as NSString).pathExtension
    guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return .open }
    let runnable: [UTType] = [.executable, .applicationBundle, .script, .shellScript]
    return runnable.contains { type.conforms(to: $0) } ? .reveal : .open
  }

  /// The first `limit` bytes of the file at `path`, or nil unless it is a
  /// regular file. A symlink is not followed.
  public static func read(_ path: String, limit: Int = 1_000_000) -> Data? {
    let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard fd >= 0 else { return nil }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
    return try? handle.read(upToCount: limit) ?? Data()
  }

  /// Whether the path is a regular file, not following a symlink.
  public static func isRegular(_ path: String) -> Bool {
    var info = stat()
    return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG
  }
}
