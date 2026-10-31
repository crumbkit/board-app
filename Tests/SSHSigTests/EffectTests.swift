import Foundation
import SSHSig
import XCTest

/// The phone builds the approval statement itself, from the effect record it
/// shows. Board rebuilds the same statement with Board's `Effect::approval`
/// and checks the signature against it, so the two must agree byte for byte.
///
/// Each `Fixtures/effects/<name>.statement` was printed by a program that
/// calls `board_model::Effect::approval` at crumbkit/board 492317cd on
/// `<name>.effect.json`. `vector.*` is Board's own `vectors/signing/v1`
/// approval pair. These tests prove agreement on these inputs only: the
/// fixtures cover text with a prior, a record with unsorted and byte-ordered
/// keys and every number form, a plain action, hidden characters, and a
/// U+FEFF at the start of a string and after an escape. They
/// do not prove agreement on every Unicode version's categories.
final class EffectTests: XCTestCase {
  func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/effects"))
    return try Data(contentsOf: url)
  }

  func testTheStatementEqualsWhatBoardBuildsByteForByte() throws {
    for name in ["task", "control", "review", "note", "bom", "vector"] {
      let effect = try Effect(json: fixture("\(name).effect.json"))
      XCTAssertEqual(
        Data(effect.approval.utf8), try fixture("\(name).statement"), "\(name).statement differs")
    }
  }

  func testTheIdIsTheOneTheStatementNames() throws {
    let effect = try Effect(json: fixture("task.effect.json"))
    XCTAssertEqual(effect.id, "671565ce1902c3e397748d41fede8ae615dc7d3b349c41ebd7e4be5fa8650a72")
  }

  func testADigestWithUppercaseHexReadsAsBoardPrintsIt() throws {
    // control.effect.json spells its digest in uppercase; Board's id uses lowercase.
    let effect = try Effect(json: fixture("control.effect.json"))
    XCTAssertEqual(effect.digest, effect.digest?.lowercased())
  }

  /// Board refuses the first four. It reads an effect of another `$type`,
  /// which the phone refuses, so the phone never signs one.
  func testWhatBoardRefusesIsRefusedAndItsTwinIsRead() throws {
    let base =
      #""$type": "board/effect/v1", "board": "/b", "plugin": "p", "op": "p.do", "path": "/x""#
    XCTAssertNoThrow(try Effect(json: Data("{\(base)}".utf8)))
    XCTAssertThrowsError(try Effect(json: Data("{\(base), \"extra\": 1}".utf8)))
    XCTAssertThrowsError(try Effect(json: Data("{\(base), \"path\": \"/y\"}".utf8)))
    XCTAssertThrowsError(try Effect(json: Data("{\(base), \"digest\": \"sha256:00\"}".utf8)))
    XCTAssertThrowsError(
      try Effect(
        json: Data(
          #"{"$type": "board/seen/v1", "board": "/b", "plugin": "p", "op": "p.do", "path": "/x"}"#
            .utf8)))
  }

  /// Board writes `asked` into every new pending effect. It is read, and it
  /// changes neither the id nor the statement the owner signs.
  func testAskedIsReadAndLeavesTheIdAndStatementAlone() throws {
    let base =
      #""$type": "board/effect/v1", "board": "/b", "plugin": "p", "op": "p.do", "path": "/x""#
    let plain = try Effect(json: Data("{\(base)}".utf8))
    let asked = try Effect(
      json: Data("{\(base), \"asked\": \"2026-10-30T22:44:54.102864Z\"}".utf8))
    XCTAssertEqual(asked.asked, "2026-10-30T22:44:54.102864Z")
    XCTAssertNil(plain.asked)
    XCTAssertEqual(asked.id, plain.id)
    XCTAssertEqual(asked.approval, plain.approval)
    XCTAssertNil(try Effect(json: Data("{\(base), \"asked\": null}".utf8)).asked)
    XCTAssertThrowsError(try Effect(json: Data("{\(base), \"asked\": 1}".utf8))) {
      XCTAssertEqual(($0 as? Effect.Malformed)?.field, "asked")
    }
  }

  func testAPriorBlobIsCheckedByTheIdGitGivesIt() {
    // `printf 'hello\n' | git hash-object --stdin`
    XCTAssertEqual(gitBlobID(Data("hello\n".utf8)), "ce013625030ba8dba906f756967f9e9ca394464a")
  }

  func testNumbersPrintAsSerdeJsonPrintsThem() throws {
    // Each pair is a lexeme and what serde_json 1.0.151 printed for it. Board
    // refuses 123456789012345678901 as lossy before printing; serde_json's
    // form is pinned anyway.
    let printed = [
      "1e20": "1e+20", "1e15": "1000000000000000.0", "1e16": "1e+16",
      "123456789012345678": "123456789012345678", "1.0": "1.0", "1E5": "100000.0", "-0": "-0.0",
      "-0.0": "-0.0", "0.1": "0.1", "0.0001": "0.0001", "0.00001": "0.00001", "1e-5": "0.00001",
      "1.5e-7": "1.5e-7", "12345678901234567890": "12345678901234567890",
      "123456789012345678901": "1.2345678901234568e+20", "2.5e300": "2.5e+300", "5e-324": "5e-324",
      "1.7976931348623157e308": "1.7976931348623157e+308", "100.0": "100.0", "123e18": "1.23e+20",
      "0.000001": "1e-6", "9007199254740993": "9007199254740993", "-1.25e+3": "-1250.0",
      "3.0e0": "3.0",
    ]
    for (lexeme, expected) in printed {
      XCTAssertEqual(try JSONValue.parse(Data(lexeme.utf8)), .number(expected), lexeme)
    }
    XCTAssertThrowsError(try JSONValue.parse(Data("1e400".utf8)))
    XCTAssertThrowsError(try JSONValue.parse(Data("01".utf8)))
  }
}
