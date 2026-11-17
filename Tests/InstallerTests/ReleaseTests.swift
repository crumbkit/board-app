import Foundation
import Testing

@testable import Installer

private let board = "e3d2cb16a7c3cc566f611eaf2219e04ae6a9218a"
private let app = "acbf7236b1c4aa1fd0d9c2b3e4f5a6b7c8d9e0f1"

private func json(_ fields: [String: String]) throws -> Data {
  try JSONSerialization.data(withJSONObject: fields)
}

@Test func a_release_reads_its_id_commits_and_date() throws {
  let release = try Release(
    json: json([
      "id": "board-e3d2cb16a7c3.app-acbf7236b1c4", "board": board, "board-app": app,
      "board-date": "2026-11-16T10:52:49Z",
    ]))
  #expect(release.id == "board-e3d2cb16a7c3.app-acbf7236b1c4")
  #expect(release.board.abbreviated(8) == "e3d2cb16")
  #expect(release.app.abbreviated(7) == "acbf723")
  #expect(release.boardDate == Date(timeIntervalSince1970: 1_794_826_369))
}

@Test func a_release_from_before_the_date_was_recorded_has_none() throws {
  let release = try Release(
    json: json([
      "id": "board-e3d2cb16a7c3.attention-000000000000.app-acbf7236b1c4", "board": board,
      "attention": "0000000000000000000000000000000000000000", "board-app": app,
    ]))
  #expect(release.boardDate == nil)
}

@Test func a_release_without_a_commit_is_refused() {
  #expect(throws: ReleaseError.self) {
    try Release(json: json(["id": "board-x", "board": "not a commit", "board-app": app]))
  }
  #expect(throws: ReleaseError.self) { try Release(json: Data("[]".utf8)) }
}

@Test func nothing_installed_offers_an_install() throws {
  let carried = try Release(json: json(["id": "new", "board": board, "board-app": app]))
  #expect(Offer(carrying: carried, installed: .none) == .install)
}

@Test func the_same_release_installed_offers_nothing() throws {
  let carried = try Release(json: json(["id": "new", "board": board, "board-app": app]))
  #expect(Offer(carrying: carried, installed: .release(id: "new", carried)) == nil)
}

@Test func a_release_installed_before_dates_were_recorded_offers_an_update_from_it() throws {
  let carried = try Release(json: json(["id": "new", "board": board, "board-app": app]))
  let old = try Release(json: json(["id": "old", "board": app, "board-app": app]))
  #expect(Offer(carrying: carried, installed: .release(id: "old", old)) == .update(from: old))
  #expect(
    Offer(carrying: carried, installed: .release(id: "older", nil)) == .update(from: nil))
}

private func dated(_ id: String, board boardDate: String, app appDate: String) throws -> Release {
  try Release(
    json: json([
      "id": id, "board": board, "board-app": app, "board-date": boardDate,
      "board-app-date": appDate,
    ]))
}

@Test func a_newer_board_commit_offers_an_update() throws {
  let carried = try dated("new", board: "2026-11-17T10:00:00Z", app: "2026-11-10T10:00:00Z")
  let old = try dated("old", board: "2026-11-16T10:00:00Z", app: "2026-11-12T10:00:00Z")
  #expect(Offer(carrying: carried, installed: .release(id: "old", old)) == .update(from: old))
}

@Test func the_same_board_commit_with_a_newer_app_offers_an_update() throws {
  let carried = try dated("new", board: "2026-11-16T10:00:00Z", app: "2026-11-17T10:00:00Z")
  let old = try dated("old", board: "2026-11-16T10:00:00Z", app: "2026-11-10T10:00:00Z")
  #expect(Offer(carrying: carried, installed: .release(id: "old", old)) == .update(from: old))
}

@Test func an_older_carried_release_offers_nothing() throws {
  let carried = try dated("old", board: "2026-11-16T10:00:00Z", app: "2026-11-17T10:00:00Z")
  let newer = try dated("new", board: "2026-11-17T10:00:00Z", app: "2026-11-10T10:00:00Z")
  #expect(Offer(carrying: carried, installed: .release(id: "new", newer)) == nil)
  let sameBoard = try dated("new", board: "2026-11-16T10:00:00Z", app: "2026-11-18T10:00:00Z")
  #expect(Offer(carrying: carried, installed: .release(id: "new", sameBoard)) == nil)
}
