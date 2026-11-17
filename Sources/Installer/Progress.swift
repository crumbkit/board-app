// What Install/install prints, read line by line into the progress the
// install sheet shows, and how a run ended. INSTALL.md and
// docs/bundle-install.md list the lines.
import Foundation
import Launcher

/// The longest an install may run before the app stops it.
public let installTimeout: Duration = .seconds(600)

/// One line the installer printed on standard output.
public enum InstallerLine: Sendable, Hashable {
  /// `::step <n> <label>`: step n starts.
  case step(Int, String)
  /// `::done <n> <summary>`: step n finished.
  case done(Int, String)
  /// `::warn <n> <summary>`: step n finished and left something for the person.
  case warning(Int, String)
  /// `::controls <path>`: a known board still names the controls plugin.
  case controls(String)
  /// `::path <path>`: the path the refusal names.
  case path(String)
  /// `::refusal <message>`: why the installer stopped, the same message it
  /// prints on standard error after `install: `.
  case refusal(String)
  /// Any other line, for a person.
  case text(String)

  public init(_ line: String) {
    let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
    let rest = parts.dropFirst().joined(separator: " ")
    switch parts.first {
    case "::controls" where !rest.isEmpty: self = .controls(rest)
    case "::path" where !rest.isEmpty: self = .path(rest)
    case "::refusal" where !rest.isEmpty: self = .refusal(rest)
    case "::step", "::done", "::warn":
      guard parts.count == 3, let step = Int(parts[1]), InstallProgress.steps.contains(step)
      else {
        self = .text(line)
        return
      }
      let text = String(parts[2])
      self =
        switch parts[0] {
        case "::step": .step(step, text)
        case "::done": .done(step, text)
        default: .warning(step, text)
        }
    default: self = .text(line)
    }
  }
}

/// How one step stands.
public enum StepState: Sendable, Hashable {
  case waiting
  case running
  /// Finished, with the installer's summary.
  case done(String)
  /// Finished, leaving something for the person, which the summary says.
  case warning(String)
}

/// A step's result, in the order the installer reported it.
public struct StepResult: Sendable, Hashable {
  public let step: Int
  public let state: StepState
}

/// What the installer has printed so far.
public struct InstallProgress: Sendable, Hashable {
  /// The label of each step, which Install/install prints on its ::step
  /// lines. A test checks that the two lists match.
  public static let labels = [
    "Check this Mac", "Copy the release", "Install board and attention-sign", "Install skills",
    "Enable plugins in your boards", "Install Claude Code mods",
    "Remove board-controls and attention-approve",
  ]
  public static let steps = 1...labels.count

  /// The last step that started, or 0 before any has.
  public private(set) var started = 0
  public private(set) var results: [StepResult] = []
  /// Every line for a person, from both streams, in the order they came.
  public private(set) var output: [String] = []
  /// The boards that still name controls.
  public private(set) var controls: [String] = []
  /// The path the refusal names, if the installer named one.
  public private(set) var path: String?
  /// What standard error said since the last step started.
  private var errors: [String] = []
  /// The installer's `::refusal` message. Standard output carries it because
  /// the two streams are read apart, so a refusal on standard error can
  /// arrive before the `::step` line that clears `errors`.
  private var refused: String?

  public init() {}

  public mutating func read(_ line: RunLine) {
    guard line.stream == .stdout else {
      output.append(line.text)
      errors.append(line.text)
      return
    }
    switch InstallerLine(line.text) {
    case .step(let step, _):
      started = step
      errors = []
    case .done(let step, let text): results.append(StepResult(step: step, state: .done(text)))
    case .warning(let step, let text):
      results.append(StepResult(step: step, state: .warning(text)))
    case .controls(let board): controls.append(board)
    case .path(let path): self.path = path
    case .refusal(let text): refused = text
    case .text(let text): output.append(text)
    }
  }

  public func state(of step: Int) -> StepState {
    if let result = results.last(where: { $0.step == step }) { return result.state }
    return step == started ? .running : .waiting
  }

  /// What the step's tools said on standard error, then the installer's own
  /// refusal. Without a `::refusal` line, standard error's `install: ` lines
  /// stand in for it.
  public var refusal: String {
    guard let refused else {
      return errors.map { $0.hasPrefix("install: ") ? String($0.dropFirst(9)) : $0 }
        .joined(separator: "\n")
    }
    return (errors.filter { !$0.hasPrefix("install: ") } + [refused]).joined(separator: "\n")
  }
}

/// Where a stopped install was.
public enum Stage: Sendable, Hashable {
  /// During this step.
  case step(Int)
}

/// An install that did not finish.
public struct Stop: Sendable, Hashable {
  public let stage: Stage
  /// What the installer said, which can be empty.
  public let refusal: String
  /// The path the refusal names, for Show in Finder.
  public let path: String?
  /// How the installer ended, such as "install exited 1".
  public let exit: String

  /// What the stop left behind, in a sentence or two. `installed` is the
  /// installed release's short commit, when one is installed.
  public func summary(installed: String?) -> String {
    let still = installed.map { " The installed release, \($0), still runs." } ?? ""
    switch stage {
    case .step(1):
      return "The installer stopped while checking this Mac, before it changed anything." + still
    case .step(2):
      return "The installer stopped while copying the release, and changed nothing else." + still
    case .step(3):
      return
        "The installer stopped while installing board and attention-sign. Each binary it replaced is kept as .prev in ~/.local/share/board."
    case .step(4):
      return
        "The installer stopped while installing skills. board and attention-sign are new, and the skills are still the old ones."
    case .step(5):
      return
        "The installer stopped while enabling plugins in your boards. The boards it finished keep their change."
    case .step(6), .step(7):
      return
        "The installer stopped while changing the Claude Code mods. Everything else is installed."
    case .step:
      return "The installer stopped."
    }
  }
}

/// How an install ended.
public enum InstallOutcome: Sendable, Hashable {
  case installed
  case stopped(Stop)

  public init(_ progress: InstallProgress, exit: RunOutcome) {
    let ended: String
    switch exit {
    case .exited(0):
      self = .installed
      return
    case .exited(let status): ended = "install exited \(status)"
    case .timedOut:
      ended =
        "install took longer than \(installTimeout.components.seconds / 60) minutes and was stopped"
    case .overCap: ended = "install printed more than Board.app keeps and was stopped"
    case .notStarted(let reason): ended = "install could not start: \(reason)"
    }
    let stage: Stage =
      switch progress.started {
      case 0: .step(1)
      case let step: .step(step)
      }
    self = .stopped(Stop(stage: stage, refusal: progress.refusal, path: progress.path, exit: ended))
  }
}
