// One request as a thread: the request at the top, then the owner's replies
// and the plugin's revised versions, oldest first. It follows the signed-off
// chat design: the screen opens scrolled to the latest version, the eyebrow
// and title stay at the top, and the reply field stays at the bottom between
// Refuse and Approve. Beside the request list on the open Duo in landscape, a
// side strip holds Back, Approve, Raw and Refuse instead.
import Requests
import SwiftUI

struct RequestView: View {
  let request: Request
  let requests: PhoneRequests
  /// Closes the thread from the side strip. Nil outside the layout that sets
  /// the thread beside the request list.
  var back: (() -> Void)?
  @State private var signing = Fixture.sheet == "sign"
  @State private var refusing: Request?
  @State private var failure: String?
  @State private var replyFailure: String?
  @State private var draft = ""

  init(request: Request, requests: PhoneRequests, back: (() -> Void)? = nil) {
    self.request = request
    self.requests = requests
    self.back = back
    if Fixture.sheet == "refuse" { _refusing = State(initialValue: request) }
  }

  var body: some View {
    let thread = requests.thread(for: request)
    let canApprove = thread.isApprovable(request) && !request.isStale && !answering
    Group {
      if back != nil {
        HStack(spacing: 0) {
          conversation(thread, canApprove: canApprove)
          strip(canApprove: canApprove)
        }
        .background(Palette.ground)
        .toolbar(.hidden, for: .navigationBar)
      } else {
        conversation(thread, canApprove: canApprove)
          .navigationTitle(request.heading)
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
              Button("What You Sign", systemImage: "signature") { signing = true }
            }
          }
      }
    }
    .sheet(isPresented: $signing) { WhatYouSign(request: request) }
    .refuseAlert($refusing, requests: requests)
    .alert(
      "Board could not send your answer", isPresented: .constant(failure != nil),
      actions: { Button("OK") { failure = nil } }, message: { Text(failure ?? "") }
    )
    .alert(
      "Board could not send your reply", isPresented: .constant(replyFailure != nil),
      actions: { Button("OK") { replyFailure = nil } }, message: { Text(replyFailure ?? "") })
  }

  /// The versions and replies, opening at the bottom, under the fixed title
  /// and above the reply field.
  private func conversation(_ thread: RequestThread, canApprove: Bool) -> some View {
    ScrollView {
      VStack(spacing: 22) {
        ForEach(thread.items) { item in
          switch item {
          case .version(let version):
            VersionView(
              version: version, request: version.id == request.id ? request : version.request,
              shared: requests.shared)
          case .reply(let reply):
            ReplyBubble(reply: reply, waiting: requests.isWaiting(reply, in: request))
          }
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 16)
    }
    .defaultScrollAnchor(Fixture.scrolledUp ? .top : .bottom)
    .background(Palette.ground)
    .safeAreaInset(edge: .top, spacing: 0) {
      ThreadHeader(request: request, versions: thread.versions.count)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(canApprove: canApprove) }
  }

  // MARK: Actions

  /// Refuse, the reply field and Approve; the field alone beside the strip.
  private func bottomBar(canApprove: Bool) -> some View {
    HStack(spacing: 10) {
      if back == nil {
        RoundButton(title: "Refuse", symbol: "xmark") { refusing = request }
          .disabled(answering)
      }
      replyField
      if back == nil {
        RoundButton(
          title: "Approve", symbol: PhoneKey.biometry.symbol, prominent: true, action: approve
        )
        .disabled(!canApprove)
      }
    }
    .padding(.horizontal, 14)
    .padding(.top, 20)
    .padding(.bottom, 8)
    .background(
      LinearGradient(
        stops: [
          .init(color: Palette.ground.opacity(0), location: 0),
          .init(color: Palette.ground, location: 0.45),
        ],
        startPoint: .top, endPoint: .bottom))
  }

  private var replyField: some View {
    HStack(spacing: 6) {
      TextField("Reply to \(request.plugin)", text: $draft)
        .submitLabel(.send)
        .onSubmit(sendReply)
      if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Button(action: sendReply) {
          Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
            .foregroundStyle(Palette.action)
        }
        .accessibilityLabel("Send Reply")
      }
    }
    .font(.system(size: 17))
    .padding(.leading, 16)
    .padding(.trailing, 8)
    .frame(minHeight: 46)
    .background(Capsule().fill(Palette.row).shadow(color: .black.opacity(0.14), radius: 3, y: 1))
  }

  /// Back and Approve at the top of the strip, Raw and Refuse at the bottom.
  private func strip(canApprove: Bool) -> some View {
    VStack(spacing: 18) {
      RoundButton(title: "Back", symbol: "chevron.left", size: 48, labelled: true) { back?() }
      RoundButton(
        title: "Approve", symbol: PhoneKey.biometry.symbol, size: 56, prominent: true,
        labelled: true, action: approve
      )
      .disabled(!canApprove)
      Spacer()
      RoundButton(title: "Raw", symbol: "signature", size: 48, labelled: true) { signing = true }
      RoundButton(title: "Refuse", symbol: "xmark", size: 48, labelled: true) {
        refusing = request
      }
      .disabled(answering)
    }
    .padding(.top, 16)
    .padding(.bottom, 20)
    .frame(width: 84)
  }

  /// Whether an answer to this request is on its way.
  private var answering: Bool { requests.sending.contains(request.id) }

  /// The inbox closes this screen once the request leaves it.
  private func approve() {
    Task {
      do {
        try await requests.approve(request)
      } catch  where PhoneKey.isCancel(error) {
      } catch {
        failure = error.localizedDescription
      }
    }
  }

  /// Keeps the draft when the reply fails, so a second try has it.
  private func sendReply() {
    let text = draft
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    draft = ""
    Task {
      do {
        try await requests.reply(to: request, text: text)
      } catch {
        draft = text
        replyFailure = error.localizedDescription
      }
    }
  }
}

/// The plugin, board and version count over the thing's name, fixed at the
/// top of the thread.
struct ThreadHeader: View {
  let request: Request
  let versions: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(
        ([request.plugin, request.boardName] + (versions > 1 ? ["\(versions) versions"] : []))
          .joined(separator: " · ").uppercased()
      )
      .font(.footnote.weight(.semibold))
      .kerning(0.2)
      .foregroundStyle(Palette.secondary)
      Text(request.name).font(.title2.bold()).lineLimit(2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20)
    .padding(.top, 8)
    .padding(.bottom, 12)
    .background(Palette.ground.opacity(0.94))
    .background(.ultraThinMaterial)
    .overlay(alignment: .bottom) { Divider() }
  }
}

/// A round button: white with a shadow, or blue when prominent, with its
/// title under it in the side strip.
struct RoundButton: View {
  let title: String
  let symbol: String
  var size: CGFloat = 46
  var prominent = false
  var labelled = false
  let action: () -> Void
  @Environment(\.isEnabled) private var enabled

  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: symbol)
          .font(.system(size: size * 0.38, weight: .semibold))
          .foregroundStyle(prominent ? Color.white : Color.primary)
          .frame(width: size, height: size)
          .background(
            Circle().fill(prominent ? Palette.action : Palette.row)
              .shadow(color: .black.opacity(0.14), radius: 3, y: 1))
        if labelled { Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.primary) }
      }
      .opacity(enabled ? 1 : 0.4)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
  }
}

/// One version: its label, what the plugin wants, what changes, and the raw
/// change one tap away. A replaced version is greyed.
struct VersionView: View {
  let version: RequestThread.Version
  /// The version as the screen words it: the open request itself for its own
  /// version.
  let request: Request
  let shared: Date?

  var body: some View {
    let old = !version.isLatest
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text(
          "\(request.plugin) · version \(version.number)"
            + (version.asked.map { " · " + askedLabel($0) } ?? "")
        )
        .foregroundStyle(Palette.secondary)
        Spacer(minLength: 8)
        Text(status).foregroundStyle(version.isLatest ? Palette.action : Palette.secondary)
      }
      .font(.footnote.weight(.semibold))
      Text(request.sentence)
        .font(.system(size: 18))
        .foregroundStyle(old ? Palette.secondary : Palette.text)
      if let answer = version.answer {
        Text(
          answer.approved
            ? "You approved it." : "You refused it\(answer.reason.map { ": " + $0 } ?? "")."
        )
        .font(.footnote)
        .foregroundStyle(Palette.secondary)
      }
      Changes(request: request, latest: version.isLatest, shared: shared)
        .opacity(old ? 0.6 : 1)
    }
  }

  private var status: String {
    if version.isLatest { return "Latest" }
    if let next = version.replacedBy { return "Replaced by version \(next)" }
    if let answer = version.answer { return answer.approved ? "Approved" : "Refused" }
    return ""
  }
}

/// What one version changes, reusing the request screen's diff: the changed
/// fields or lines on a white card, what stays the same, and the whole file.
struct Changes: View {
  let request: Request
  let latest: Bool
  let shared: Date?

  var body: some View {
    let rows = request.lineRows
    VStack(alignment: .leading, spacing: 10) {
      if case .action(let verb) = request.kind {
        card {
          Text(
            "\(request.plugin) can \(verb) from this \(request.target) whenever it runs. It will not ask again until you take the approval back."
          )
          .padding(16)
        }
        if let content = request.currentContent {
          heading("What it would \(verb) now")
          card {
            Text(String(decoding: content, as: UTF8.self)).textSelection(.enabled).padding(16)
          }
          note(
            "Read from the board\(shared.map { " at " + $0.formatted(date: .omitted, time: .shortened) } ?? ""). This text is not part of what you sign. \(request.limits)"
          )
        } else {
          note(request.limits)
        }
      } else if latest && request.isStale {
        card {
          Label {
            Text("This \(request.noun) changed after \(request.plugin) asked.")
          } icon: {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
          }
          .padding(16)
        }
        note(
          "An approval fits only the version \(request.plugin) saw, so it would not let \(request.plugin) write. Refuse, and \(request.plugin) can ask again with the current version."
        )
      } else if let fields = request.fields {
        heading(count(fields.changed.count, "field") + " change")
        card {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(fields.changed.enumerated()), id: \.offset) { index, row in
              if index > 0 { Divider().padding(.leading, 16) }
              VStack(alignment: .leading, spacing: 3) {
                Text(row.key).font(.system(size: 17))
                fieldChange(row).font(.system(size: 15))
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 12)
            }
          }
        }
        note(sameNote(fields.same.isEmpty ? nil : fields.same.joined(separator: ", ")))
      } else if let rows {
        let changed = rows.filter { !$0.isSame }
        let total = request.kind == .remove ? rows.count : rows.filter { $0.new != nil }.count
        heading("\(changed.count) of \(count(total, "line")) change")
        card {
          VStack(spacing: 0) {
            ForEach(Array(changed.enumerated()), id: \.offset) { _, row in
              if let old = row.old { DiffLine(number: old.number, text: old.text, side: .removed) }
              if let new = row.new { DiffLine(number: new.number, text: new.text, side: .added) }
            }
          }
          .padding(.vertical, 8)
        }
        let same = rows.count - changed.count
        note(sameNote(same > 0 ? "the other \(count(same, "line"))" : nil))
      } else {
        let blob = request.effect.prior.map { String($0.prefix(7)) } ?? ""
        note(
          request.kind == .remove
            ? "Board could not fetch the file this removes (blob \(blob)) from your Mac, so it cannot show it. What you sign is unchanged."
            : "Board could not fetch the old version (blob \(blob)) from your Mac, so it cannot show what changes. What you sign is unchanged."
        )
      }
      if case .action = request.kind {
      } else if let rows, !rows.isEmpty {
        card {
          NavigationLink {
            WholeFile(request: request, rows: rows)
          } label: {
            HStack {
              Text("Show the raw change").foregroundStyle(Palette.text)
              Spacer()
              Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .font(.system(size: 17))
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
          }
        }
      }
    }
  }

  /// What stays the same, and for the latest version what approving allows.
  private func sameNote(_ same: String?) -> String {
    let unchanged = same.map { "Nothing else changes: \($0) stay as they are." } ?? ""
    let allows = latest ? "\(request.allows) \(request.limits)" : ""
    return [unchanged, allows].filter { !$0.isEmpty }.joined(separator: " ")
  }

  private func fieldChange(_ row: FieldRow) -> Text {
    var text = Text("")
    if let old = row.old {
      text = text + Text(old.text).strikethrough().foregroundColor(Palette.secondary)
      if row.new != nil { text = text + Text(" → ") }
    }
    if let new = row.new { text = text + Text(new.text).fontWeight(.semibold) }
    return text
  }

  private func count(_ number: Int, _ noun: String) -> String {
    "\(number) \(noun)\(number == 1 ? "" : "s")"
  }

  private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Palette.row)
      .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
  }

  private func heading(_ text: String) -> some View {
    Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.secondary)
      .padding(.horizontal, 2)
  }

  @ViewBuilder private func note(_ text: String) -> some View {
    if !text.isEmpty {
      Text(text).font(.footnote).foregroundStyle(Palette.secondary).padding(.horizontal, 2)
    }
  }
}

/// One of the owner's replies, on the trailing side, with when it was sent.
struct ReplyBubble: View {
  let reply: RequestThread.Reply
  /// Sent from this phone and not yet in the board.
  let waiting: Bool

  var body: some View {
    VStack(spacing: 4) {
      Text("You" + (reply.sent.map { " · " + askedLabel($0) } ?? ""))
        .font(.caption)
        .foregroundStyle(Palette.secondary)
      HStack {
        Spacer(minLength: 60)
        Text(reply.text)
          .font(.system(size: 16))
          .foregroundStyle(.white)
          .padding(.horizontal, 14)
          .padding(.vertical, 9)
          .background(Palette.action, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      }
      if waiting {
        Label("Your Mac saves it to the board when it next shares.", systemImage: "clock")
          .font(.caption)
          .foregroundStyle(Palette.secondary)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
  }
}

struct WholeFile: View {
  let request: Request
  let rows: [DiffRow]

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
          if row.isSame, let new = row.new {
            DiffLine(number: new.number, text: new.text, side: .same)
          } else {
            if let old = row.old { DiffLine(number: old.number, text: old.text, side: .removed) }
            if let new = row.new { DiffLine(number: new.number, text: new.text, side: .added) }
          }
        }
      }
    }
    .navigationTitle(request.name)
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// One line of a diff: its number, if it has one, and its text with the
/// changed words marked.
struct DiffLine: View {
  enum Side { case removed, added, same }
  let number: Int?
  let text: Marked
  let side: Side

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      if let number {
        Text("\(number)").foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
      }
      Text(side.sign).foregroundStyle(.secondary).frame(width: 8)
      Text(marked(text, side)).frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.footnote.monospaced())
    .padding(.horizontal, 12)
    .padding(.vertical, 3)
    .background(side.background)
  }
}

extension DiffLine.Side {
  var sign: String {
    switch self {
    case .removed: "−"
    case .added: "+"
    case .same: ""
    }
  }

  var background: Color {
    switch self {
    case .removed: Color.red.opacity(0.12)
    case .added: Color.green.opacity(0.14)
    case .same: .clear
    }
  }
}

/// `text` with its changed words on a stronger tint.
func marked(_ text: Marked, _ side: DiffLine.Side) -> AttributedString {
  var changed = AttributedString(text.changed)
  changed.backgroundColor = side == .removed ? Color.red.opacity(0.25) : Color.green.opacity(0.3)
  return AttributedString(text.before) + changed + AttributedString(text.after)
}

/// The exact statement Face ID or Touch ID signs, line for line.
struct WhatYouSign: View {
  let request: Request
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let statement = request.effect.approval
    NavigationStack {
      List {
        Section {
          Text(statement)
            .font(.footnote.monospaced())
            .textSelection(.enabled)
        } header: {
          Text(
            "\(PhoneKey.biometry.name) signs exactly these lines. Board on your Mac checks them before \(request.plugin) may \(request.kind == .change || request.kind == .add ? "write" : "act")."
          )
          .textCase(nil)
          .font(.body)
          .foregroundStyle(.primary)
        } footer: {
          Text(
            request.effect.prior.map {
              "The effect line stands for this request, its new content and the version it replaces (blob \($0.prefix(7))). That is why this approval cannot write over a later change."
            } ?? "The effect line stands for this request and everything it carries.")
        }
      }
      .listStyle(.insetGrouped)
      .navigationTitle("What You Sign")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close", systemImage: "xmark") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}

extension View {
  /// The alert that refuses `request`, with an optional reason, once it is
  /// set. A refusal is not signed, so it needs no Face ID or Touch ID.
  func refuseAlert(_ request: Binding<Request?>, requests: PhoneRequests) -> some View {
    modifier(RefuseAlert(request: request, requests: requests))
  }
}

struct RefuseAlert: ViewModifier {
  @Binding var request: Request?
  let requests: PhoneRequests
  @State private var reason = ""
  @State private var failure: String?

  func body(content: Content) -> some View {
    content
      .alert(
        "Refuse This Request?",
        isPresented: Binding(get: { request != nil }, set: { if !$0 { request = nil } }),
        presenting: request
      ) { request in
        TextField("Reason (optional)", text: $reason)
        Button("Cancel", role: .cancel) { reason = "" }
        Button("Refuse", role: .destructive) { refuse(request) }
      } message: { request in
        Text(
          "\(request.plugin) is told no. Board does not sign a refusal, so this needs no \(PhoneKey.biometry.name)."
        )
      }
      .alert(
        "Board could not send your refusal", isPresented: .constant(failure != nil),
        actions: { Button("OK") { failure = nil } }, message: { Text(failure ?? "") })
  }

  /// Keeps the reason when the refusal fails, so a second try has it.
  private func refuse(_ request: Request) {
    Task {
      do {
        try await requests.refuse(request, reason: reason)
        reason = ""
      } catch {
        failure = error.localizedDescription
      }
    }
  }
}

#Preview("Task thread") {
  NavigationStack {
    RequestView(
      request: PreviewRequests.task,
      requests: PhoneRequests(preview: [PreviewRequests.task], threads: PreviewRequests.threads))
  }
}
#Preview("Control") {
  NavigationStack {
    RequestView(request: PreviewRequests.control, requests: PhoneRequests(preview: []))
  }
}
#Preview("Review") {
  NavigationStack {
    RequestView(request: PreviewRequests.review, requests: PhoneRequests(preview: []))
  }
}
#Preview("Stale") {
  NavigationStack {
    RequestView(request: PreviewRequests.stale, requests: PhoneRequests(preview: []))
  }
}
