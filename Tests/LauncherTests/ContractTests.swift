import Foundation
import XCTest

@testable import Launcher

/// A provider's output decodes into sections of typed items, and output the
/// shell cannot trust is refused with a reason. These tests do not run a
/// provider; RunnerTests does.
final class ContractTests: XCTestCase {
  func testAListingKeepsItsSectionsItemsAndActions() throws {
    let listing = try Fixtures.listing("workspaces.json")
    XCTAssertEqual(listing.sections.map(\.title), ["Running", "Recently stopped"])
    let login = listing.sections[0].items[0]
    XCTAssertEqual(login.id, "workspace:login-fix")
    XCTAssertEqual(login.status, Status(tone: .good, word: "Running"))
    XCTAssertEqual(login.children, ["/usr/local/bin/workspaces", "parts", "login-fix"])
    XCTAssertEqual(login.actions.map(\.id), ["open-web", "copy-branch", "stop"])
    XCTAssertEqual(
      login.actions[0].perform,
      .open(Address(href: URL(string: "http://localhost:3000/")!, reach: .macOnly)))
    guard case .run(let stop) = login.actions[2].perform else { return XCTFail("not a run") }
    XCTAssertEqual(stop.confirm?.preview.last, "--dry-run")
    guard case .workspace(let workspace) = login.body else { return XCTFail("not a workspace") }
    XCTAssertEqual(workspace.apps.map(\.link?.reach), [.macOnly, .public])
    XCTAssertEqual(workspace.updated, Date(timeIntervalSince1970: 1_793_351_520))
  }

  func testAnItemOfAnUnknownTypeIsSkippedAndCounted() throws {
    let listing = try Fixtures.listing("workspaces.json")
    XCTAssertEqual(listing.sections[1].items.map(\.id), ["workspace:search-tuning"])
    XCTAssertEqual(listing.skipped, [Skip(type: "job", count: 1)])
  }

  private func refusal(_ json: String) -> String? {
    do {
      _ = try Listing.decode(Data(json.utf8))
      return nil
    } catch ContractError.invalid(let detail) {
      return detail
    } catch {
      return "\(error)"
    }
  }

  private func workspace(actions: String = "[]", children: String = "null") -> String {
    #"{"kind": "launcher/items/v1", "sections": [{"title": "S", "items": [{"id": "w", "type": "workspace", "title": "w", "actions": "#
      + actions + #", "children": "# + children + #", "data": {"apps": []}}]}]}"#
  }

  func testOnlyWebURLsCanBeOpened() {
    for href in ["file:///Applications/Calculator.app", "ssh://example.com", "javascript:alert(1)"]
    {
      let action =
        #"[{"id": "o", "label": "O", "open": {"href": ""# + href + #"", "reach": "public"}}]"#
      XCTAssertEqual(
        refusal(workspace(actions: action)),
        "sections.[0].items.[0].actions.[0].open.href: only http and https URLs may be opened",
        href)
    }
    let web =
      #"[{"id": "o", "label": "O", "open": {"href": "HTTPS://example.com/", "reach": "public"}}]"#
    XCTAssertNil(refusal(workspace(actions: web)))
  }

  func testEveryCommandMustStartWithAnAbsolutePath() {
    let run = #"[{"id": "r", "label": "R", "run": {"argv": ["rm", "x"]}}]"#
    XCTAssertEqual(
      refusal(workspace(actions: run)),
      "sections.[0].items.[0].actions.[0].run.argv: the argv must start with an absolute path")
    let preview =
      #"[{"id": "r", "label": "R", "run": {"argv": ["/bin/rm", "x"], "confirm": {"preview": []}}}]"#
    XCTAssertNotNil(refusal(workspace(actions: preview)))
    XCTAssertNotNil(refusal(workspace(children: #"["parts"]"#)))
    XCTAssertNil(refusal(workspace(children: #"["/bin/parts"]"#)))
  }

  func testPartsDecodeEvidenceTestRunsAndCommits() throws {
    let listing = try Fixtures.listing("parts.json")
    XCTAssertEqual(listing.sections.map(\.title), ["Evidence", "Test runs", "Commits"])
    XCTAssertEqual(listing.items[0].evidenceFile?.evidence.taskRecord, "tasks/login-fix.md")
    XCTAssertNil(listing.items[1].evidenceFile?.evidence.taskRecord)
    guard case .testRun(let run) = listing.items[3].body else { return XCTFail("not a test run") }
    XCTAssertTrue(run.passed)
    guard case .commit(let commit) = listing.items[4].body else { return XCTFail("not a commit") }
    XCTAssertEqual(commit.link?.reach, .public)
  }

  func testAnUnknownKindIsRefused() throws {
    XCTAssertThrowsError(try Fixtures.listing("unknown-kind.json")) {
      XCTAssertEqual($0 as? ContractError, .unknownKind("launcher/items/v2"))
    }
    XCTAssertThrowsError(try Fixtures.listing("no-kind.json")) {
      XCTAssertEqual($0 as? ContractError, .unknownKind(nil))
    }
  }

  func testOutputThatIsNotJSONIsRefused() throws {
    XCTAssertThrowsError(try Fixtures.listing("not-json.txt")) {
      XCTAssertEqual($0 as? ContractError, .notJSON("it starts not json at all"))
    }
    XCTAssertThrowsError(try Listing.decode(Data("[1]".utf8))) {
      guard case .invalid = $0 as? ContractError else { return XCTFail("\($0)") }
    }
    XCTAssertThrowsError(try Listing.decode(Data())) {
      XCTAssertEqual($0 as? ContractError, .notJSON("it is empty"))
    }
  }

  func testDataOfTheWrongShapeIsRefusedWithWhere() throws {
    XCTAssertThrowsError(try Fixtures.listing("invalid.json")) {
      guard case .invalid(let detail) = $0 as? ContractError else { return XCTFail("\($0)") }
      XCTAssertTrue(detail.contains("data.apps"), detail)
    }
  }

  func testAnActionMustDoExactlyOneThing() throws {
    XCTAssertThrowsError(try Fixtures.listing("two-performs.json")) {
      guard case .invalid(let detail) = $0 as? ContractError else { return XCTFail("\($0)") }
      XCTAssertTrue(detail.contains("exactly one of open, copy and run"), detail)
    }
  }

  func testEveryURLMustSayItsReach() throws {
    XCTAssertThrowsError(try Fixtures.listing("no-reach.json")) {
      guard case .invalid(let detail) = $0 as? ContractError else { return XCTFail("\($0)") }
      XCTAssertTrue(detail.contains("reach"), detail)
    }
  }
}

/// The examples in docs/ decode, so the contract doc and the example
/// provider stay in step with the decoder. These tests run the example
/// provider; they do not check what the app draws from it.
final class DocsExampleTests: XCTestCase {
  private static let docs = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("docs")

  func testTheContractDocsExampleDecodes() throws {
    let doc = try String(
      contentsOf: Self.docs.appendingPathComponent("launcher-contract.md"), encoding: .utf8)
    let start = try XCTUnwrap(doc.range(of: "```json\n"))
    let end = try XCTUnwrap(doc.range(of: "\n```", range: start.upperBound..<doc.endIndex))
    let listing = try Listing.decode(
      Data(doc[start.upperBound..<end.lowerBound].utf8))
    XCTAssertEqual(listing.items.map(\.id), ["workspace:garden-journal"])
    XCTAssertEqual(listing.items[0].actions.count, 3)
  }

  func testTheExampleProviderListsAndItsPartsDecode() async throws {
    let script = Self.docs.appendingPathComponent("launcher-example-provider.sh").path
    let list = await Runner().run([script, "list"])
    XCTAssertNil(list.problem)
    let listing = try Listing.decode(list.stdout)
    XCTAssertEqual(
      listing.items.map(\.id), ["workspace:garden-journal", "workspace:login-fix"])
    XCTAssertEqual(listing.skipped, [Skip(type: "job", count: 1)])

    let children = try XCTUnwrap(listing.items[0].children)
    let parts = await Runner().run(children)
    XCTAssertNil(parts.problem)
    let decoded = try Listing.decode(parts.stdout)
    XCTAssertEqual(decoded.sections.map(\.title), ["Evidence", "Test runs", "Commits"])
    for file in decoded.items.compactMap(\.evidenceFile) {
      XCTAssertTrue(FileManager.default.fileExists(atPath: file.evidence.path), file.name)
    }
  }
}
