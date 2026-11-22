import Foundation
import Testing

@testable import Installer

/// A scratch folder that each test owns and removes.
private struct Scratch: ~Copyable {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

  init() throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  deinit {
    // Nil is right: a scratch folder left behind is harmless.
    try? FileManager.default.removeItem(at: url)
  }

  func write(_ path: String, _ text: String = "") throws {
    let file = url.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: file)
  }

  func folder(_ path: String) throws -> URL {
    let folder = url.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }
}

@Test func the_default_folder_is_board_in_the_home_folder() {
  let home = URL(fileURLWithPath: "/Users/ana")
  #expect(BoardFolder.default(home: home).path == "/Users/ana/Board")
}

@Test func a_missing_folder_is_created_by_the_install() throws {
  let scratch = try Scratch()
  let folder = scratch.url.appendingPathComponent("a/Board")
  #expect(BoardFolder.check(folder) == .missing)
}

@Test func an_empty_folder_passes_and_a_finder_ds_store_does_not_count() throws {
  let scratch = try Scratch()
  #expect(BoardFolder.check(try scratch.folder("empty")) == .empty)
  try scratch.write("finder/.DS_Store")
  #expect(BoardFolder.check(scratch.url.appendingPathComponent("finder")) == .empty)
}

@Test func a_git_repository_with_no_commit_passes() throws {
  let scratch = try Scratch()
  try scratch.write("repo/.git/HEAD", "ref: refs/heads/main\n")
  _ = try scratch.folder("repo/.git/refs/heads")
  #expect(BoardFolder.check(scratch.url.appendingPathComponent("repo")) == .emptyRepository)
}

@Test func an_existing_board_passes() throws {
  let scratch = try Scratch()
  try scratch.write("board/.git/HEAD", "ref: refs/heads/main\n")
  try scratch.write("board/.git/refs/heads/main", "0123\n")
  try scratch.write("board/.board/board.json", "{}")
  try scratch.write("board/tasks/a.md", "a")
  #expect(BoardFolder.check(scratch.url.appendingPathComponent("board")) == .board)
}

@Test func a_folder_with_a_file_refuses_and_says_what_to_choose() throws {
  let scratch = try Scratch()
  try scratch.write("notes/todo.txt", "milk")
  let folder = scratch.url.appendingPathComponent("notes")
  #expect(
    BoardFolder.check(folder)
      == .refused(
        "\(folder.path) holds files and is not a board. Choose an empty folder or an existing board."
      ))
}

@Test func a_git_repository_with_a_commit_that_is_not_a_board_refuses() throws {
  let scratch = try Scratch()
  try scratch.write("repo/.git/HEAD", "ref: refs/heads/main\n")
  try scratch.write("repo/.git/refs/heads/main", "0123\n")
  let folder = scratch.url.appendingPathComponent("repo")
  guard case .refused = BoardFolder.check(folder) else {
    Issue.record("a repository with a commit passed")
    return
  }
  try FileManager.default.removeItem(at: folder.appendingPathComponent(".git/refs/heads/main"))
  try scratch.write("repo/.git/packed-refs", "# pack-refs with: peeled\n0123 refs/heads/main\n")
  guard case .refused = BoardFolder.check(folder) else {
    Issue.record("a repository with a packed commit passed")
    return
  }
}

@Test func a_file_at_the_folder_path_refuses() throws {
  let scratch = try Scratch()
  try scratch.write("Board", "not a folder")
  let folder = scratch.url.appendingPathComponent("Board")
  #expect(
    BoardFolder.check(folder)
      == .refused("\(folder.path) is a file. Choose an empty folder or an existing board."))
}

@Test func only_a_folder_that_passes_may_be_installed_into() {
  #expect(BoardFolder.Check.missing.passes)
  #expect(BoardFolder.Check.board.passes)
  #expect(!BoardFolder.Check.refused("x").passes)
}
