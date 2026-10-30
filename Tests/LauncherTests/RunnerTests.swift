import Foundation
import XCTest

@testable import Launcher

/// The runner runs argv directly, kills a command at the timeout or the
/// output cap, and reports why. It uses system commands, not real providers.
final class RunnerTests: XCTestCase {
  func testItCapturesOutputAndStatus() async {
    let result = await Runner().run(["/bin/echo", "hello", "$HOME"])
    XCTAssertEqual(result.outcome, .exited(status: 0))
    // No shell expands $HOME.
    XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "hello $HOME\n")
    XCTAssertNil(result.problem)
  }

  func testANonZeroExitIsAProblemWithItsOutput() async {
    let result = await Runner().run(["/bin/ls", "/no/such/place"])
    XCTAssertNotEqual(result.outcome, .exited(status: 0))
    XCTAssertNotNil(result.problem)
    XCTAssertTrue(result.outputStart().contains("/no/such/place"))
  }

  func testACommandPastTheTimeoutIsKilled() async {
    let start = Date()
    let result = await Runner(timeout: .milliseconds(300)).run(["/bin/sleep", "10"])
    XCTAssertEqual(result.outcome, .timedOut)
    XCTAssertLessThan(Date().timeIntervalSince(start), 3)
  }

  func testACommandThatIgnoresTermIsKilled() async {
    let start = Date()
    let result = await Runner(timeout: .milliseconds(200)).run([
      "/bin/sh", "-c", "trap '' TERM; while :; do sleep 0.05; done",
    ])
    XCTAssertEqual(result.outcome, .timedOut)
    XCTAssertLessThan(Date().timeIntervalSince(start), 4)
  }

  func testATimeoutStopsWhatTheCommandStarted() async throws {
    // The trailing `:` stops sh from replacing itself with sleep, so sleep
    // is a child of sh, in the command's process group.
    let marker = "sleep 31.\(Int.random(in: 100...999))"
    let result = await Runner(timeout: .milliseconds(300)).run(["/bin/sh", "-c", "\(marker); :"])
    XCTAssertEqual(result.outcome, .timedOut)
    var left = true
    for _ in 0..<20 where left {
      let found = await Runner().run(["/usr/bin/pgrep", "-f", marker])
      left = found.outcome == .exited(status: 0)
      if left { try await Task.sleep(for: .milliseconds(100)) }
    }
    XCTAssertFalse(left, "\(marker) is still running")
  }

  func testACommandPastTheCapIsKilledAndItsOutputCut() async {
    let result = await Runner(cap: 1000).run(["/usr/bin/yes"])
    XCTAssertEqual(result.outcome, .overCap)
    XCTAssertEqual(result.stdout.count, 1000)
  }

  func testOutputExactlyAtTheCapIsKept() async {
    let result = await Runner(cap: 6).run(["/bin/echo", "hello"])
    XCTAssertEqual(result.outcome, .exited(status: 0))
    XCTAssertEqual(result.stdout.count, 6)
  }

  func testARelativeCommandIsNotRun() async {
    let result = await Runner().run(["echo", "hello"])
    XCTAssertEqual(result.outcome, .notStarted("argv[0] must be an absolute path"))
  }

  func testAMissingCommandIsNotStarted() async {
    let result = await Runner().run(["/no/such/command"])
    guard case .notStarted = result.outcome else { return XCTFail("\(result.outcome)") }
  }
}
