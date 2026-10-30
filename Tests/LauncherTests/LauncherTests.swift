import Foundation
import XCTest

@testable import Launcher

/// The screen model: what each level lists, how typing filters, what each
/// key does and what the footer shows. The tests drive the model with
/// decoded fixtures; they do not draw the panel or press real keys.
final class LauncherTests: XCTestCase {
  private func launcher() throws -> Launcher {
    var launcher = Launcher()
    launcher.providers = [
      ProviderState(
        provider: Provider(name: "Workspaces", list: ["/usr/local/bin/workspaces", "list"]),
        listing: .loaded(try Fixtures.listing("workspaces.json")))
    ]
    return launcher
  }

  private func titles(_ launcher: Launcher) -> [String] { launcher.screen.rows.map(\.title) }

  /// The command a `.run` effect runs.
  private func argv(_ effect: Effect) -> [String]? {
    guard case .run(_, let action) = effect, case .run(let run) = action.perform else { return nil }
    return run.argv
  }

  func testAnItemWithMoreThanTwoActionsOpensSoEveryActionIsInReach() throws {
    let json = #"""
      {"kind": "launcher/items/v1", "sections": [{"title": "Running", "items": [{
        "id": "workspace:garden-journal", "type": "workspace", "title": "garden-journal",
        "actions": [
          {"id": "a", "label": "Copy A", "copy": "a"},
          {"id": "b", "label": "Copy B", "copy": "b"},
          {"id": "c", "label": "Copy C", "copy": "c"}],
        "data": {"apps": []}}]}]}
      """#
    var launcher = Launcher()
    launcher.providers = [
      ProviderState(
        provider: Provider(name: "Notes", list: ["/bin/notes"]),
        listing: .loaded(try Listing.decode(Data(json.utf8))))
    ]
    XCTAssertEqual(launcher.hints.map(\.label), ["Open", "Copy A", "Close"])
    XCTAssertEqual(launcher.activate(alternate: true), .copy("a"))
    XCTAssertEqual(launcher.activate(), .none, "no parts to load")
    XCTAssertEqual(titles(launcher), ["Copy A", "Copy B", "Copy C"])
    launcher.move(2)
    XCTAssertEqual(launcher.activate(), .copy("c"))
  }

  func testAFailedActionShowsAtTheTopUntilTheNextAction() throws {
    var launcher = try launcher()
    let failure = Failure(
      reason: "The command exited with status 1", argv: ["/usr/local/bin/workspaces"],
      output: "no such workspace")
    launcher.actionFailure = ActionFailure(label: "Start workspace", failure: failure)
    let row = try XCTUnwrap(launcher.screen.rows.first)
    XCTAssertEqual(row.title, "Start workspace")
    XCTAssertEqual(row.status, Status(tone: .failed, word: "Failed"))
    XCTAssertEqual(launcher.screen.sections.first?.title, "Last action")
    XCTAssertEqual(launcher.activate(), .none)
    XCTAssertEqual(launcher.path.last, .failure(failure, provider: "Start workspace"))
  }

  func testTheTopLevelListsTheProvidersSectionsAndTheSkippedCount() throws {
    let screen = try launcher().screen
    XCTAssertNil(screen.chip)
    XCTAssertEqual(
      screen.sections.map(\.title), ["Running", "Recently stopped", "Workspaces"])
    XCTAssertEqual(
      screen.rows.map(\.title),
      ["login-fix", "search-tuning", "1 job item skipped: Board.app has no view for job"])
  }

  func testEveryWordMustMatchTheTitleSubtitleOrKeywords() throws {
    var launcher = try launcher()
    launcher.query = "auth"
    XCTAssertEqual(titles(launcher), ["login-fix"])
    launcher.query = "WEB login"
    XCTAssertEqual(titles(launcher), ["login-fix"])
    launcher.query = "web search"
    XCTAssertEqual(titles(launcher), ["Nothing matches."])
    launcher.query = "tuning"
    XCTAssertEqual(titles(launcher), ["search-tuning"])
  }

  func testNothingMatchingSaysSoInsteadOfGoingBlank() throws {
    var launcher = Launcher()
    launcher.providers = [
      ProviderState(
        provider: Provider(name: "Workspaces", list: ["/bin/true"]),
        listing: .loaded(Listing(sections: [])))
    ]
    XCTAssertEqual(titles(launcher), ["Nothing is listed."])
    launcher.query = "x"
    XCTAssertEqual(titles(launcher), ["Nothing matches."])
  }

  func testArrowsMoveTheSelectionWithinTheRows() throws {
    var launcher = try launcher()
    XCTAssertEqual(launcher.selected?.title, "login-fix")
    launcher.move(1)
    XCTAssertEqual(launcher.selected?.title, "search-tuning")
    launcher.move(5)
    XCTAssertEqual(
      launcher.selected?.kind, .note("1 job item skipped: Board.app has no view for job"))
    launcher.move(-9)
    XCTAssertEqual(launcher.selected?.title, "login-fix")
  }

  func testEnterDescendsAndAsksForThePartsOnce() throws {
    var launcher = try launcher()
    guard case .loadParts(let located) = launcher.activate() else { return XCTFail("no load") }
    XCTAssertEqual(located.item.id, "workspace:login-fix")
    let screen = launcher.screen
    XCTAssertEqual(screen.chip, "login-fix")
    XCTAssertEqual(screen.placeholder, "Search this workspace")
    XCTAssertEqual(screen.sections.map(\.title), ["Actions", "Parts"])
    XCTAssertEqual(screen.rows.last?.title, "Loading Workspaces…")

    launcher.parts[located.key] = .loaded(try Fixtures.listing("parts.json"))
    XCTAssertEqual(
      launcher.screen.sections.map(\.title), ["Actions", "Evidence", "Test runs", "Commits"])
    XCTAssertEqual(launcher.escape(), .none)
    XCTAssertEqual(launcher.selected?.title, "login-fix")
    XCTAssertEqual(launcher.activate(), .none, "parts already loaded are not loaded again")
  }

  func testInsideAnItemTypingFiltersItsParts() throws {
    var launcher = try launcher()
    guard case .loadParts(let located) = launcher.activate() else { return XCTFail("no load") }
    launcher.parts[located.key] = .loaded(try Fixtures.listing("parts.json"))
    launcher.query = "log"
    XCTAssertEqual(titles(launcher), ["run.log"])
    launcher.query = "copy"
    XCTAssertEqual(titles(launcher), ["Copy branch"])
  }

  func testEscAndBackspaceInAnEmptyFieldGoBack() throws {
    var launcher = try launcher()
    XCTAssertFalse(launcher.backspace(), "at the top the field takes backspace")
    _ = launcher.activate()
    launcher.query = "x"
    XCTAssertFalse(launcher.backspace(), "a field with text takes backspace")
    launcher.query = ""
    XCTAssertTrue(launcher.backspace())
    XCTAssertTrue(launcher.path.isEmpty)
    XCTAssertEqual(launcher.escape(), .close)
  }

  func testActionsOpenCopyAndRun() throws {
    var launcher = try launcher()
    _ = launcher.activate()
    XCTAssertEqual(launcher.activate(), .open(URL(string: "http://localhost:3000/")!))
    launcher.move(1)
    XCTAssertEqual(launcher.activate(), .copy("login-fix"))
    XCTAssertTrue(Effect.copy("x").closesPanel)
    XCTAssertTrue(Effect.close.closesPanel)
    XCTAssertFalse(
      Effect.loadParts(Located(provider: "p", item: launcher.providers[0].listing.item0))
        .closesPanel)
  }

  func testCommandEnterRunsTheSecondAction() throws {
    var launcher = try launcher()
    // Enter descends into login-fix, so its second action is its first.
    XCTAssertEqual(
      launcher.activate(alternate: true), .open(URL(string: "http://localhost:3000/")!))
    XCTAssertTrue(launcher.path.isEmpty)
    launcher.move(1)
    // search-tuning has no parts, so Enter runs its first action and ⌘↩ its second.
    XCTAssertEqual(launcher.activate(alternate: true), .copy("search-tuning"))
    XCTAssertEqual(
      argv(launcher.activate()), ["/usr/local/bin/workspaces", "start", "search-tuning"])
  }

  func testARunWithAConfirmShowsThePreviewWithCancelSelected() throws {
    var launcher = try launcher()
    _ = launcher.activate()
    launcher.move(2)
    guard case .runPreview(let located, let action) = launcher.activate() else {
      return XCTFail("no preview")
    }
    var screen = launcher.screen
    XCTAssertEqual(screen.preview?.argv.last, "--dry-run")
    XCTAssertEqual(screen.preview?.runs, ["/usr/local/bin/workspaces", "stop", "login-fix"])
    XCTAssertEqual(screen.preview?.output, .loading)
    XCTAssertEqual(screen.rows.map(\.title), ["Cancel"], "nothing to confirm before the preview")

    launcher.previews[Launcher.previewKey(located, action)] = .loaded("Would stop web and api\n")
    screen = launcher.screen
    XCTAssertEqual(screen.preview?.output, .loaded("Would stop web and api\n"))
    XCTAssertEqual(screen.rows.map(\.title), ["Stop workspace", "Cancel"])
    XCTAssertEqual(launcher.selected?.title, "Cancel")
    XCTAssertEqual(launcher.activate(), .none)
    XCTAssertEqual(launcher.selected?.title, "Stop workspace", "cancel goes back to the action")

    XCTAssertEqual(launcher.activate(), .runPreview(located, action), "each confirm runs afresh")
    launcher.previews[Launcher.previewKey(located, action)] = .loaded("Would stop web and api\n")
    launcher.move(-1)
    XCTAssertEqual(argv(launcher.activate()), ["/usr/local/bin/workspaces", "stop", "login-fix"])
  }

  func testAFailedPreviewOffersOnlyCancel() throws {
    var launcher = try launcher()
    _ = launcher.activate()
    launcher.move(2)
    guard case .runPreview(let located, let action) = launcher.activate() else {
      return XCTFail("no preview")
    }
    launcher.previews[Launcher.previewKey(located, action)] = .failed(
      Failure(reason: "The command exited with status 1", argv: ["/x"], output: "no"))
    XCTAssertEqual(launcher.screen.rows.map(\.title), ["Cancel"])
  }

  func testAFailedProviderIsAFailedRowAndEnterShowsItsDetails() throws {
    var launcher = try launcher()
    let failure = Failure(
      reason: "The command took longer than the timeout and was stopped",
      argv: ["/usr/local/bin/slow"], output: "partial")
    launcher.providers.append(
      ProviderState(
        provider: Provider(name: "Slow", list: ["/usr/local/bin/slow"]), listing: .failed(failure)))
    launcher.query = "nothing matches this"
    let row = try XCTUnwrap(launcher.screen.rows.first)
    XCTAssertEqual(row.title, "Slow")
    XCTAssertEqual(row.status, Status(tone: .failed, word: "Failed"))
    XCTAssertEqual(row.subtitle, failure.reason)
    launcher.query = ""
    launcher.selectedID = row.id
    XCTAssertEqual(launcher.provider, "Slow")
    XCTAssertEqual(launcher.activate(), .none)
    XCTAssertEqual(launcher.path.last, .failure(failure, provider: "Slow"))
    XCTAssertEqual(launcher.hints.map(\.key), ["esc"])
  }

  func testInvalidOutputBecomesAFailureWithTheStartOfTheOutput() throws {
    let result = RunResult(
      argv: ["/usr/local/bin/ws"], outcome: .exited(status: 0), stdout: Data("oops".utf8),
      stderr: Data())
    guard case .failed(let failure) = Loaded<Listing>.listing(result)
    else { return XCTFail("decoded") }
    XCTAssertEqual(failure.reason, "The output is not JSON: it starts oops")
    XCTAssertEqual(failure.output, "oops")
    XCTAssertEqual(failure.argv, ["/usr/local/bin/ws"])
  }

  func testARefusedConfigIsShownAboveTheList() {
    var launcher = Launcher()
    launcher.problem = ConfigRefusal.symlink("/Users/sam/.config/board/launcher.json").description
    XCTAssertEqual(launcher.screen.notice, launcher.problem)
    XCTAssertEqual(launcher.screen.rows, [])
  }

  func testSpaceOpensTheEvidencePreviewOnlyOnAnEvidenceRow() throws {
    var launcher = try launcher()
    XCTAssertNil(launcher.space(), "a workspace row lets the field type a space")
    guard case .loadParts(let located) = launcher.activate() else { return XCTFail("no load") }
    launcher.parts[located.key] = .loaded(try Fixtures.listing("parts.json"))
    launcher.move(4)
    XCTAssertEqual(launcher.selected?.title, "screen.png")
    guard case .preview(let browser) = launcher.space() else { return XCTFail("no preview") }
    XCTAssertEqual(browser.files.map(\.name), ["report.md", "screen.png", "run.log"])
    XCTAssertEqual(browser.position, "2 of 3")
    XCTAssertEqual(launcher.activate(), .openFile("/tmp/login-fix/screen.png"))
  }

  func testTheFooterNamesTheProviderAndTheKeys() throws {
    var launcher = try launcher()
    XCTAssertEqual(launcher.provider, "Workspaces")
    XCTAssertEqual(launcher.hints.map(\.label), ["Open", "Open web", "Close"])
    launcher.move(1)
    XCTAssertEqual(launcher.hints.map(\.label), ["Start workspace", "Copy name", "Close"])
    launcher.move(-1)
    _ = launcher.activate()
    XCTAssertEqual(launcher.hints.map(\.label), ["Open web", "Back"])
  }

  func testASelectionSurvivesARefreshWhileItIsListed() throws {
    var launcher = try launcher()
    launcher.move(1)
    launcher.providers[0].listing = .loaded(try Fixtures.listing("workspaces.json"))
    XCTAssertEqual(launcher.selected?.title, "search-tuning")
  }

  func testResetStartsAgainAtTheTop() throws {
    var launcher = try launcher()
    _ = launcher.activate()
    launcher.query = "web"
    launcher.reset()
    XCTAssertTrue(launcher.path.isEmpty)
    XCTAssertEqual(launcher.query, "")
    XCTAssertEqual(launcher.selected?.title, "login-fix")
  }
}

extension Loaded where Value == Listing {
  fileprivate var item0: Item {
    guard case .loaded(let listing) = self else { fatalError("not loaded") }
    return listing.items[0]
  }
}
