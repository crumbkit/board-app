// The signed-off install sheet on the Board window: install on a new Mac,
// update an older install, installing, installed and install stopped. It
// uses the system's styles and accent.
import AppKit
import Installer
import SwiftUI

struct InstallSheet: View {
  let model: InstallModel
  @State private var showOutput = true

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      switch model.phase {
      case .offered:
        if case .update(let from) = model.offer {
          update(from: from)
        } else {
          install
        }
      case .running: running
      case .installed: installed
      case .stopped(let stop): stopped(stop)
      }
    }
    .padding(EdgeInsets(top: 22, leading: 28, bottom: 18, trailing: 28))
    .frame(width: 540)
    .interactiveDismissDisabled(model.running)
  }

  // MARK: Install on a new Mac

  private var install: some View {
    Group {
      Text("Install Board on this Mac").font(.title2.bold())
      Text(
        "Board.app carries a Board release. Installing it puts these on this Mac for your account."
      )
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      VStack(alignment: .leading, spacing: 0) {
        item(
          "terminal", "board and attention-sign",
          Text(
            "Copied to \(code("~/.local/bin")). attention-sign signs orders and approvals with Touch ID."
          ))
        Divider()
        item("doc.text", "Skills", Text("Board's skills, written to \(code("~/.claude/skills"))"))
        Divider()
        item("puzzlepiece.extension", "Plugins", plugins)
        if model.makesPersonalBoard {
          Divider()
          folderRow
        }
      }
      .modifier(Box())
      identitySection
      footer(meta: true) {
        Button("Not Now", action: model.notNow).keyboardShortcut(.cancelAction)
        Button("Install", action: model.install)
          .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
          .disabled(!model.canInstall)
      }
    }
  }

  private var plugins: Text {
    guard let personal = model.survey.personal else {
      return Text(
        "You have no personal board yet, so one is created in the Board folder with six plugins: tasks, evals, runs, rules, plans and share."
      )
    }
    return Text("Enabled in your personal board, \(code(tilde(personal)))")
  }

  /// The folder a new personal board goes in, with Choose… and the reason
  /// the installer would refuse it.
  private var folderRow: some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: "folder").frame(width: 18)
      VStack(alignment: .leading, spacing: 2) {
        Text("Board folder").fontWeight(.semibold)
        code(tilde(model.boardFolder)).foregroundStyle(.secondary)
        if case .refused(let reason) = model.folderCheck {
          Text(homeAsTilde(reason)).font(.caption).foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
      Button("Choose…", action: chooseFolder).controlSize(.small)
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 12)
  }

  /// A folder picker that can create a folder, starting at the folder chosen now.
  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"
    panel.directoryURL = model.boardFolder.deletingLastPathComponent()
    if panel.runModal() == .OK, let url = panel.url { model.choose(url) }
  }

  /// The name and email git lacks, which the installer sets for the account.
  @ViewBuilder private var identitySection: some View {
    if model.asksIdentity {
      @Bindable var model = model
      VStack(alignment: .leading, spacing: 8) {
        Text("Your name for commits").fontWeight(.semibold)
        Text(
          "Your board records who wrote each change. Git has no name or email on this Mac yet, so Board sets them for your account."
        )
        .font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        if let problem = model.identity?.problem {
          Text(problem).font(.caption).foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
              Text("Name").gridColumnAlignment(.trailing)
              TextField("Name", text: $model.gitName).labelsHidden()
                .disabled(model.identity?.name != nil)
            }
            GridRow {
              Text("Email")
              TextField("Email", text: $model.gitEmail).labelsHidden()
                .disabled(model.identity?.email != nil)
            }
            if model.emailRefused {
              GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Text("Enter an email address, such as ana@example.com.")
                  .font(.caption).foregroundStyle(.red)
              }
            }
          }
          .font(.callout)
        }
      }
      .padding(.vertical, 10).padding(.horizontal, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .modifier(Box())
    }
  }

  // MARK: Update an older install

  private func update(from installed: Release?) -> some View {
    Group {
      Text("Update Board").font(.title2.bold())
      Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 4) {
        version("Installed", installed)
        version("This app", model.carried)
      }
      .font(.caption)
      VStack(alignment: .leading, spacing: 0) {
        change(
          "Replaces",
          Text(
            "\(code("board")) and \(code("attention-sign")) in \(code("~/.local/bin")), keeping the old ones as \(code(".prev"))"
          ))
        Divider()
        change("Updates", Text("Board's skills"))
        Divider()
        change("Enables", enables)
        if model.makesPersonalBoard {
          Divider()
          folderRow
        }
        if model.survey.old.contains(.pythonAttention) {
          Divider()
          change("Removes", Text("the old Python attention plugin's links"), muted: true)
        }
      }
      .modifier(Box())
      Text(
        "The Claude Code mods you have installed are updated and keep their on or off state. No new mods are added."
      )
      .font(.caption).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      identitySection
      controlsNote(model.survey.controls.map(\.path), verb: "Updating")
      footer(meta: false) {
        Button("Not Now", action: model.notNow).keyboardShortcut(.cancelAction)
        Button("Update", action: model.install)
          .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
          .disabled(!model.canInstall)
      }
    }
  }

  private var enables: Text {
    let survey = model.survey
    let personal = survey.personal.flatMap { survey.controls.contains($0) ? nil : $0 }
    let others = survey.others.map { code($0.lastPathComponent) }
    var text =
      personal.map { Text("the plugins in \(code(tilde($0)))") }
      ?? (model.makesPersonalBoard
        ? Text(
          "tasks, evals, runs, rules, plans and share in a new personal board in the Board folder")
        : Text("no personal board's plugins"))
    if !others.isEmpty {
      text = Text("\(text), and refreshes the plugins \(listed(others)) already enable")
    }
    return text
  }

  private func version(_ label: String, _ release: Release?) -> some View {
    GridRow {
      Text(label).foregroundStyle(.secondary)
      Text(release?.board.abbreviated(8) ?? "unknown").font(.caption.monospaced().weight(.semibold))
      Text(release?.boardDate?.formatted(.dateTime.day().month(.abbreviated).year()) ?? "")
        .foregroundStyle(.secondary)
    }
  }

  private func change(_ verb: String, _ text: Text, muted: Bool = false) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(verb).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        .frame(width: 62, alignment: .leading)
      text.foregroundStyle(muted ? .secondary : .primary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .font(.callout)
    .padding(.vertical, 7)
    .padding(.horizontal, 12)
  }

  // MARK: Installing

  private var running: some View {
    Group {
      Text(model.updating ? "Updating Board" : "Installing Board").font(.title2.bold())
      VStack(alignment: .leading, spacing: 7) {
        ForEach(InstallProgress.shown, id: \.self) { step in
          let state = model.progress.state(of: step)
          HStack(spacing: 10) {
            symbol(state)
            Text(InstallProgress.labels[step - 1])
              .fontWeight(state == .running ? .semibold : .regular)
              .foregroundStyle(state == .waiting ? .secondary : .primary)
          }
        }
      }
      outputToggle
      if showOutput { output }
      pathNote
      footer(meta: true) {
        Button(model.updating ? "Updating…" : "Installing…") {}.disabled(true)
      }
    }
  }

  @ViewBuilder private func symbol(_ state: StepState) -> some View {
    switch state {
    case .done:
      Image(systemName: "checkmark.circle").foregroundStyle(.green)
        .accessibilityLabel("Done")
    case .warning:
      Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
        .accessibilityLabel("Needs you")
    case .running:
      ProgressView().controlSize(.small).frame(width: 16, height: 16)
        .accessibilityLabel("In progress")
    case .waiting:
      Image(systemName: "circle").foregroundStyle(.secondary)
        .accessibilityLabel("Not started")
    }
  }

  private var outputToggle: some View {
    Button {
      showOutput.toggle()
    } label: {
      Label(
        showOutput ? "Hide Output" : "Show Output",
        systemImage: showOutput ? "chevron.down" : "chevron.right")
    }
    .buttonStyle(.plain)
    .font(.caption)
  }

  private var output: some View {
    ScrollViewReader { scroll in
      ScrollView {
        Text(model.progress.output.joined(separator: "\n"))
          .font(.caption2.monospaced())
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
        Color.clear.frame(height: 0).id("end")
      }
      .frame(height: 96)
      .background(.background, in: .rect(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
      .onChange(of: model.progress.output.count) { scroll.scrollTo("end", anchor: .bottom) }
    }
  }

  @ViewBuilder private var pathNote: some View {
    if let problem = model.pathProblem {
      Text(problem).font(.caption).foregroundStyle(.secondary)
    }
  }

  // MARK: Installed

  private var installed: some View {
    Group {
      Label {
        Text(model.updating ? "Board is up to date" : "Board is installed")
      } icon: {
        Image(systemName: "checkmark.circle").foregroundStyle(.green)
      }
      .font(.title2.bold())
      VStack(alignment: .leading, spacing: 7) {
        ForEach(model.progress.results, id: \.self) { result in
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            switch result.state {
            case .warning(let text):
              Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                .accessibilityLabel("Needs you")
              Text(text).fixedSize(horizontal: false, vertical: true)
            case .done(let text):
              Image(systemName: "checkmark").foregroundStyle(.green).accessibilityLabel("Done")
              Text(text)
            case .running, .waiting:
              EmptyView()
            }
          }
        }
      }
      if model.progress.updatedMods {
        Text("Start a new Claude Code session to load the updated mods.")
          .font(.callout)
          .padding(.vertical, 10).padding(.horizontal, 12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
      }
      controlsNote(model.progress.controls, verb: "Installing")
      pathNote
      if showOutput { output }
      footer(meta: true) {
        Button(showOutput ? "Hide Output" : "Show Output") { showOutput.toggle() }
        Button("Done", action: model.close)
          .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
      }
    }
    .onAppear { showOutput = false }
  }

  // MARK: Install stopped

  private func stopped(_ stop: Stop) -> some View {
    Group {
      Label {
        Text(model.updating ? "Board was not updated" : "Board was not installed")
      } icon: {
        Image(systemName: "xmark.circle").foregroundStyle(.red)
      }
      .font(.title2.bold())
      Text(stop.summary(installed: model.updating ? model.installed?.board.abbreviated(8) : nil))
        .fixedSize(horizontal: false, vertical: true)
      VStack(alignment: .leading, spacing: 6) {
        if !stop.refusal.isEmpty {
          Text(homeAsTilde(stop.refusal)).font(.callout).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
        Text(stop.exit).font(.caption.monospaced()).foregroundStyle(.secondary)
      }
      .padding(.vertical, 10).padding(.horizontal, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.red.opacity(0.1), in: .rect(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.red.opacity(0.3)))
      .accessibilityAddTraits(.isStaticText)
      pathNote
      footer(meta: false) {
        if let path = stop.path {
          Button("Show in Finder") { reveal(path) }
        }
        Button("Close", action: model.close).keyboardShortcut(.cancelAction)
        Button("Try Again", action: model.install)
          .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
      }
    }
  }

  // MARK: Parts

  /// The boards that still name controls, with the migration guide.
  @ViewBuilder private func controlsNote(_ boards: [String], verb: String) -> some View {
    if !boards.isEmpty {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 2) {
          Text(
            boards.count == 1
              ? "1 board still uses controls" : "\(boards.count) boards still use controls"
          )
          .fontWeight(.semibold)
          Text(
            "\(listed(boards.map { code(tilde(URL(fileURLWithPath: $0))) })). \(verb) does not change \(boards.count == 1 ? "it" : "them"); each board is migrated on its own."
          )
          .font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          Button("Open Migration Guide", action: openGuide)
            .buttonStyle(.link).font(.caption).padding(.top, 6)
        }
        Spacer(minLength: 0)
      }
      .padding(.vertical, 10).padding(.horizontal, 12)
      .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }
  }

  private func footer(meta: Bool, @ViewBuilder buttons: () -> some View) -> some View {
    HStack(spacing: 8) {
      if meta, let carried = model.carried {
        Text("Release \(carried.board.abbreviated(8)) · app \(carried.app.abbreviated(7))")
          .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      buttons()
    }
    .padding(.top, 4)
  }

  private func item(_ symbol: String, _ title: String, _ detail: Text) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol).frame(width: 18)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).fontWeight(.semibold)
        detail.font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 12)
  }

  private func openGuide() {
    guard let guide = model.folder?.appendingPathComponent("MIGRATING.md") else { return }
    NSWorkspace.shared.open(guide)
  }

  private func reveal(_ path: String) {
    let url = URL(fileURLWithPath: path)
    if FileManager.default.fileExists(atPath: path) {
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } else {
      NSWorkspace.shared.open(url.deletingLastPathComponent())
    }
  }
}

/// The grouped box that holds a sheet's rows.
private struct Box: ViewModifier {
  func body(content: Content) -> some View {
    content
      .background(.background.opacity(0.6), in: .rect(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
  }
}

/// A path or command, in the monospaced font, inside running text.
private func code(_ text: String) -> Text {
  Text(text).font(.caption.monospaced())
}

/// "a and b", or "a, b and c".
private func listed(_ items: [Text]) -> Text {
  guard var text = items.first else { return Text("") }
  for (index, item) in items.enumerated().dropFirst() {
    text = Text("\(text)\(index == items.count - 1 ? " and " : ", ")\(item)")
  }
  return text
}

/// Text with each path under the home directory written as ~/….
private func homeAsTilde(_ text: String) -> String {
  text.replacingOccurrences(
    of: FileManager.default.homeDirectoryForCurrentUser.path + "/", with: "~/")
}

/// A path under the home directory as ~/…, as a person types it.
private func tilde(_ url: URL) -> String {
  let home = FileManager.default.homeDirectoryForCurrentUser.path
  let path = url.path
  return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
}
