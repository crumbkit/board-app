// The views the right pane shows: one for each item type the contract
// decodes, and one for each record inside them.
import Launcher
import SwiftUI

/// The selected row's view.
struct DetailPane: View {
  let row: Row?
  let screen: Screen
  let inFailureLevel: Bool

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        content
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder private var content: some View {
    if let preview = screen.preview {
      PreviewView(argv: preview.argv, output: preview.output, runs: preview.runs)
    } else {
      switch row?.kind {
      case .item(let located):
        let item = located.item
        switch item.body {
        case .workspace(let workspace): WorkspaceView(item: item, workspace: workspace)
        case .evidence(let evidence): EvidenceView(item: item, evidence: evidence)
        case .testRun(let run): TestRunView(item: item, run: run)
        case .commit(let commit): CommitView(commit: commit)
        }
      case .action(_, let action): ActionView(action: action)
      case .failure(let failure, _): FailureView(failure: failure, detailed: inFailureLevel)
      case .note(let text): Text(text).foregroundStyle(Palette.secondaryText)
      case .confirm, .cancel, nil: EmptyView()
      }
    }
  }
}

// MARK: Pieces

private struct Heading: View {
  let item: Item

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(item.title).font(.title2.weight(.semibold))
      if let subtitle = item.subtitle {
        Text(subtitle).foregroundStyle(Palette.secondaryText)
      }
      if let status = item.status { StatusBadge(status: status) }
    }
  }
}

/// A label and a value, in a two-column list.
private struct Field: View {
  let label: String
  let value: String
  var mono = false

  var body: some View {
    GridRow(alignment: .firstTextBaseline) {
      Text(label).foregroundStyle(Palette.secondaryText).gridColumnAlignment(.trailing)
      Text(value)
        .font(mono ? .body.monospaced() : .body)
        .textSelection(.enabled)
        .gridColumnAlignment(.leading)
    }
  }
}

/// A URL with its reach in words.
struct LinkLine: View {
  let link: Address

  var body: some View {
    HStack(spacing: 6) {
      Text(link.href.absoluteString).font(.callout.monospaced()).underline().lineLimit(1)
      Text(Self.word(link.reach)).font(.caption).foregroundStyle(Palette.secondaryText)
    }
  }

  static func word(_ reach: Reach) -> String {
    switch reach {
    case .macOnly: "Mac only"
    case .proxyable: "Proxyable"
    case .public: "Public"
    }
  }
}

private func when(_ date: Date) -> String {
  date.formatted(date: .abbreviated, time: .shortened)
}

// MARK: Types

private struct WorkspaceView: View {
  let item: Item
  let workspace: Workspace

  var body: some View {
    Group {
      Heading(item: item)
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
        if let branch = workspace.branch { Field(label: "Branch", value: branch, mono: true) }
        if let updated = workspace.updated { Field(label: "Updated", value: when(updated)) }
      }
      if !workspace.apps.isEmpty {
        Text("Apps").font(.caption.weight(.semibold)).foregroundStyle(Palette.secondaryText)
        ForEach(workspace.apps, id: \.self) { app in
          HStack(spacing: 10) {
            Text(app.name).font(.body.monospaced())
            if let link = app.link { LinkLine(link: link) }
          }
        }
      }
      if !item.actions.isEmpty {
        Text("Actions").font(.caption.weight(.semibold)).foregroundStyle(Palette.secondaryText)
        Text(item.actions.map(\.label).joined(separator: " · "))
          .foregroundStyle(Palette.secondaryText)
      }
    }
  }
}

private struct EvidenceView: View {
  let item: Item
  let evidence: Evidence

  var body: some View {
    Group {
      Heading(item: item)
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
        Field(label: "Kind", value: evidence.kind)
        Field(label: "Size (reported)", value: EvidenceBrowser.size(evidence.size))
        Field(label: "Added", value: when(evidence.added))
        if let record = evidence.taskRecord {
          Field(label: "Task record", value: record, mono: true)
        }
        Field(
          label: "SHA-256 (reported)", value: String(evidence.sha256.prefix(12)), mono: true)
        Field(label: "Path", value: evidence.path, mono: true)
      }
      Text("Space previews the file. ↩ opens it.")
        .font(.caption).foregroundStyle(Palette.secondaryText)
    }
  }
}

private struct TestRunView: View {
  let item: Item
  let run: TestRun

  var body: some View {
    Group {
      Heading(item: item)
      if item.status == nil {
        StatusBadge(
          status: Status(tone: run.passed ? .good : .failed, word: run.passed ? "Passed" : "Failed")
        )
      }
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
        Field(label: "Command", value: run.command, mono: true)
        Field(label: "Finished", value: when(run.finished))
        if let seconds = run.seconds {
          Field(
            label: "Took", value: "\(seconds.formatted(.number.precision(.fractionLength(1)))) s")
        }
      }
      if let summary = run.summary { Text(summary) }
    }
  }
}

private struct CommitView: View {
  let commit: Commit

  var body: some View {
    Group {
      Text(commit.subject).font(.title3.weight(.semibold))
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
        Field(label: "Commit", value: String(commit.sha.prefix(12)), mono: true)
        Field(label: "Author", value: commit.author)
        Field(label: "Date", value: when(commit.date))
      }
      if let link = commit.link { LinkLine(link: link) }
    }
  }
}

// MARK: Records inside the views

private struct ActionView: View {
  let action: Action

  var body: some View {
    Text(action.label).font(.title3.weight(.semibold))
    switch action.perform {
    case .open(let link):
      Text("Opens").foregroundStyle(Palette.secondaryText)
      LinkLine(link: link)
    case .copy(let text):
      Text("Copies").foregroundStyle(Palette.secondaryText)
      Text(text).font(.body.monospaced()).textSelection(.enabled)
    case .run(let run):
      Text(run.confirm == nil ? "Runs" : "Shows a preview, then runs")
        .foregroundStyle(Palette.secondaryText)
      Text(run.argv.joined(separator: " ")).font(.body.monospaced()).textSelection(.enabled)
    }
  }
}

private struct FailureView: View {
  let failure: Failure
  let detailed: Bool

  var body: some View {
    StatusBadge(status: Status(tone: .failed, word: "Failed"))
    Text(failure.reason).fixedSize(horizontal: false, vertical: true)
    if detailed {
      Text("Command").font(.caption.weight(.semibold)).foregroundStyle(Palette.secondaryText)
      Text(failure.argv.joined(separator: " ")).font(.callout.monospaced()).textSelection(.enabled)
      Text("Output").font(.caption.weight(.semibold)).foregroundStyle(Palette.secondaryText)
      Text(failure.output.isEmpty ? "(nothing)" : failure.output)
        .font(.callout.monospaced()).textSelection(.enabled)
    } else {
      Text("↩ shows the command and its output.")
        .font(.caption).foregroundStyle(Palette.secondaryText)
    }
  }
}

/// A confirm step's preview: the command, then its output exactly as
/// printed.
private struct PreviewView: View {
  let argv: [String]
  let output: Loaded<String>
  /// The command the action runs once confirmed.
  let runs: [String]

  var body: some View {
    Text("Runs").font(.caption.weight(.semibold)).foregroundStyle(Palette.secondaryText)
    Text(runs.joined(separator: " ")).font(.callout.monospaced()).textSelection(.enabled)
    Text("Preview").font(.caption.weight(.semibold)).foregroundStyle(Palette.secondaryText)
    Text(argv.joined(separator: " "))
      .font(.callout.monospaced())
      .foregroundStyle(Palette.secondaryText)
      .textSelection(.enabled)
    Divider().overlay(Palette.separator)
    switch output {
    case .loading:
      Text("Running the preview…").foregroundStyle(Palette.secondaryText)
    case .loaded(let text):
      Text(verbatim: text).font(.callout.monospaced()).textSelection(.enabled)
    case .failed(let failure):
      FailureView(failure: failure, detailed: true)
    }
  }
}
