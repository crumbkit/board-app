// The signed-off install sheet on the Board window: install on a new Mac,
// update an older install, installing, installed and install stopped, and
// the step after Install that lets this Mac sign. It uses the system's
// styles and accent.
import AppKit
import Installer
import Pairing
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
      case .signing: signingStep(model.signing.phase)
      }
    }
    .padding(EdgeInsets(top: 22, leading: 28, bottom: 18, trailing: 28))
    .frame(width: 540)
    .interactiveDismissDisabled(model.running || model.signing.authorizing)
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
          "terminal", "board and board-sign",
          Text(
            "Copied to \(code("~/.local/bin")). board-sign signs orders and approvals with Touch ID."
          ))
        Divider()
        item("doc.text", "Skills", Text("Board's skills, written to \(code("~/.claude/skills"))"))
        Divider()
        item("puzzlepiece.extension", "Plugins", plugins)
      }
      .modifier(Box())
      folderPicker
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

  /// The folder a new personal board goes in, below the box on its own: a
  /// label, a path field, Choose… and the reason the installer would refuse
  /// the folder. It shows only when Board's config names no personal board.
  @ViewBuilder private var folderPicker: some View {
    if model.makesPersonalBoard {
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .center, spacing: 10) {
          Text("Board folder").fontWeight(.semibold).accessibilityHidden(true)
          HStack(spacing: 6) {
            Image(systemName: "folder").font(.system(size: 11)).frame(width: 14, height: 14)
            code(tilde(model.boardFolder)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
          }
          .padding(.vertical, 2).padding(.horizontal, 7)
          .frame(minHeight: 21)
          .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 5))
          .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("Board folder")
          .accessibilityValue(tilde(model.boardFolder))
          Button("Choose…", action: chooseFolder).controlSize(.small)
        }
        if case .refused(let reason) = model.folderCheck {
          Text(homeAsTilde(reason)).font(.caption).foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
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
        if let problem = model.identity?.problem {
          Text(problem).font(.caption).foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          Text(
            "Your board records who wrote each change. Git has no name or email on this Mac yet, so Board sets them for your account."
          )
          .font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
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
            "\(code("board")) and \(code("board-sign")) in \(code("~/.local/bin")), keeping the old ones as \(code(".prev"))"
          ))
        Divider()
        change("Updates", Text("Board's skills"))
        Divider()
        change("Enables", enables)
        if model.survey.old.contains(.pythonAttention) {
          Divider()
          change("Removes", Text("the old Python attention plugin's links"), muted: true)
        }
      }
      .modifier(Box())
      folderPicker
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
        Button("Done", action: model.finish)
          .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
      }
    }
    .onAppear { showOutput = false }
  }

  // MARK: Let this Mac sign

  @ViewBuilder private func signingStep(_ phase: MacSigning.Phase) -> some View {
    switch phase {
    case .checking: checkingKey
    case .noKey(let making): noKey(making: making)
    case .line(let line, let kept, let authorizing):
      signingLine(line, kept: kept, authorizing: authorizing)
    case .written(let kept, let writableBy): written(kept, writableBy: writableBy)
    case .cannotSign(let message, let exit, let making):
      cannotSign(message: message, exit: exit, making: making)
    case .refused(let refusal):
      notAdded(
        lede: "The file was not changed. Read its lines and fix its permissions, then try again.",
        message: refusal.errorDescription ?? "", exit: refusal.summary)
    case .failed(let message):
      notAdded(lede: "The file was not changed.", message: message, exit: nil)
    }
  }

  private var checkingKey: some View {
    Group {
      Text("Let this Mac sign").font(.title2.bold())
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text("Reading this Mac's key…").foregroundStyle(.secondary)
      }
      footer(meta: false) {
        Button("Not Now", action: model.close).keyboardShortcut(.cancelAction)
      }
    }
  }

  /// Before the key exists.
  private func noKey(making: Bool) -> some View {
    Group {
      Text("Let this Mac sign").font(.title2.bold())
      Text(
        "Board asks for Touch ID before it writes an approval or trusts an order you signed. To check those signatures, Board needs this Mac's key in one file."
      )
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      VStack(alignment: .leading, spacing: 0) {
        signingRow(
          "key", "Signing key", status: "Not made yet",
          Text(
            "Made in this Mac's Secure Enclave, so it never leaves the chip. Each signature needs your fingerprint."
          ))
        Divider()
        signingRow(
          "checkmark", "Approvals and orders", status: "Not set up",
          Text(
            "\(code(signersFile)). Board checks your approvals, your own writes under \(code("effects/")) and the orders you sign against it."
          ))
      }
      .modifier(Box())
      signingGuide
      footer(meta: true) {
        Button("Not Now", action: model.close).keyboardShortcut(.cancelAction)
        Button(making ? "Making Key…" : "Make Key") { Task { await model.signing.makeKey() } }
          .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
          .disabled(making)
      }
    }
  }

  /// The key exists and the line is shown; nothing is written yet. While
  /// macOS's Touch ID panel is up, both buttons wait.
  private func signingLine(_ line: String, kept: MacLine.Kept, authorizing: Bool) -> some View {
    Group {
      Text("Let this Mac sign").font(.title2.bold())
      Text("Board adds this line for this Mac's key. Every other line in the file stays as it is.")
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      VStack(alignment: .leading, spacing: 0) {
        signingRow(
          "checkmark", "Approvals and orders", status: nil,
          Text(
            "Adds to \(code(signersFile)). Lets this key sign approvals, your own writes and orders."
          )
        ) {
          Text(line)
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6).padding(.horizontal, 8)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
            .padding(.top, 6)
          Text(kept.sentence).font(.caption).foregroundStyle(.secondary).padding(.top, 4)
        }
      }
      .modifier(Box())
      signingGuide
      footer(meta: false) {
        Button("Not Now", action: model.close).keyboardShortcut(.cancelAction)
          .disabled(authorizing)
        Button {
          Task { await model.signing.add() }
        } label: {
          Label("Add with Touch ID", systemImage: "touchid")
        }
        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
        .disabled(authorizing)
      }
    }
  }

  /// The file has this Mac's line.
  private func written(_ kept: MacLine.Kept, writableBy: String) -> some View {
    Group {
      Label {
        Text("This Mac can sign")
      } icon: {
        Image(systemName: "checkmark.circle").foregroundStyle(.green)
      }
      .font(.title2.bold())
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Image(systemName: "checkmark").foregroundStyle(.green).accessibilityLabel("Done")
        VStack(alignment: .leading, spacing: 2) {
          Text("Approvals and orders: added to \(code(signersFile))")
          Text("\(kept.past) · writable only by \(writableBy)")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      Text("Board asks for Touch ID each time you approve a request or sign an order on this Mac.")
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 10).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
      footer(meta: true) {
        Button("Done", action: model.close)
          .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
      }
    }
  }

  /// board-sign gave no line: no Secure Enclave, no fingerprint enrolled,
  /// or no board-sign.
  private func cannotSign(message: String, exit: String, making: Bool) -> some View {
    Group {
      failedTitle("This Mac cannot sign")
      Text(
        making
          ? "board-sign could not make a key in this Mac's Secure Enclave. The file was not changed. Turn on Touch ID in System Settings and try again, or approve from your iPhone."
          : "board-sign could not read this Mac's key. The file was not changed. Try again, or approve from your iPhone."
      )
      .fixedSize(horizontal: false, vertical: true)
      failure(message: message, exit: exit)
      signingGuide
      footer(meta: false) {
        Button("Close", action: model.close).keyboardShortcut(.cancelAction)
        Button("Try Again") { Task { await model.signing.retry() } }
          .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
      }
    }
  }

  /// Board would not trust the file, or could not read or write it. The
  /// file is unchanged.
  private func notAdded(lede: String, message: String, exit: String?) -> some View {
    Group {
      failedTitle("Board did not add the line")
      Text(lede).fixedSize(horizontal: false, vertical: true)
      failure(message: message, exit: exit)
      footer(meta: false) {
        Button("Show in Finder") { reveal(SignersFiles.board.path) }
        Button("Close", action: model.close).keyboardShortcut(.cancelAction)
        Button("Try Again") { Task { await model.signing.retry() } }
          .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
      }
    }
  }

  private var signersFile: String { SignersFiles.shown(SignersFiles.board) }

  /// Opens SIGNING.md, which the release carries.
  @ViewBuilder private var signingGuide: some View {
    if let guide = model.folder?.appendingPathComponent("SIGNING.md") {
      Button("How Board checks signatures") { NSWorkspace.shared.open(guide) }
        .buttonStyle(.link).font(.callout)
    }
  }

  private func failedTitle(_ title: String) -> some View {
    Label {
      Text(title)
    } icon: {
      Image(systemName: "xmark.circle").foregroundStyle(.red)
    }
    .font(.title2.bold())
  }

  /// A failure's message and, below it, how it ended.
  private func failure(message: String, exit: String?) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(homeAsTilde(message)).font(.callout).textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      if let exit {
        Text(exit).font(.caption.monospaced()).foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 10).padding(.horizontal, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.red.opacity(0.1), in: .rect(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.red.opacity(0.3)))
    .accessibilityAddTraits(.isStaticText)
  }

  /// A row of the signing step's box: a symbol, a title with its state, a
  /// detail, and anything below it.
  private func signingRow(
    _ symbol: String, _ title: String, status: String?, _ detail: Text,
    @ViewBuilder below: () -> some View = { EmptyView() }
  ) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol).frame(width: 18)
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(title).fontWeight(.semibold)
          if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
        }
        detail.font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        below()
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 12)
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
