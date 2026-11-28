import Foundation
import Testing

@testable import board_sign

/// board-sign keeps the Mac's key at ~/.config/board/secure-enclave-key and
/// moves attention-sign's key there on first run. Each test uses a home in a
/// temporary directory and a file of test bytes, never a real key.
struct KeyFileTests {
  let home: URL
  let keys: KeyFile

  init() throws {
    home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    keys = KeyFile(home: home)
  }

  @Test func the_key_is_kept_in_boards_config_folder() {
    #expect(keys.current.path == home.path + "/.config/board/secure-enclave-key")
    #expect(keys.attention.path == home.path + "/.config/attention/secure-enclave-key")
  }

  @Test func only_the_attention_key_is_moved_and_a_link_left_at_its_old_path() throws {
    try write(keys.attention, "blob")
    #expect(keys.locate() == .found(keys.current))
    #expect(try String(contentsOf: keys.current, encoding: .utf8) == "blob")
    #expect(
      try FileManager.default.destinationOfSymbolicLink(atPath: keys.attention.path)
        == keys.current.path)
    #expect(try String(contentsOf: keys.attention, encoding: .utf8) == "blob")
  }

  @Test func only_boards_key_is_used_as_it_is() throws {
    try write(keys.current, "blob")
    #expect(keys.locate() == .found(keys.current))
    #expect(!FileManager.default.fileExists(atPath: keys.attention.path))
  }

  @Test func with_both_keys_boards_is_used_and_neither_changes() throws {
    try write(keys.current, "board")
    try write(keys.attention, "attention")
    #expect(keys.locate() == .found(keys.current))
    #expect(try String(contentsOf: keys.current, encoding: .utf8) == "board")
    #expect(try String(contentsOf: keys.attention, encoding: .utf8) == "attention")
  }

  @Test func with_neither_key_nothing_is_made() {
    #expect(keys.locate() == .none(keys.current))
    #expect(!FileManager.default.fileExists(atPath: keys.current.path))
    #expect(!FileManager.default.fileExists(atPath: keys.attention.path))
  }

  @Test func a_move_that_fails_uses_the_key_where_it_is_and_names_the_error() throws {
    try write(keys.attention, "blob")
    // A file where Board's folder should be, so the move cannot make it.
    try write(home.appendingPathComponent(".config/board"), "not a folder")
    guard case .unmoved(let file, let problem) = keys.locate() else {
      Issue.record("the key moved")
      return
    }
    #expect(file == keys.attention)
    #expect(problem.contains(keys.current.path), "\(problem)")
    #expect(try String(contentsOf: keys.attention, encoding: .utf8) == "blob")
  }

  private func write(_ file: URL, _ text: String) throws {
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: file)
  }
}
