// One request: what a plugin asked to do, so the owner can approve it with
// Face ID or refuse it. It follows the signed-off Request detail design: the
// changed lines or fields in the compact layout, a two-up diff in the regular
// layout, and the controls on the lower half in the tabletop pose.
import Requests
import SwiftUI

struct RequestView: View {
  let request: Request
  let requests: PhoneRequests
  /// The diff rows, worked out once per request.
  private let rows: [DiffRow]?
  @State private var signing = false
  @State private var refusing = false
  @State private var halfOpen = false
  @State private var failure: String?
  /// Whether an answer is on its way, so a second tap sends nothing.
  @State private var answering = false
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.dismiss) private var dismiss

  init(request: Request, requests: PhoneRequests) {
    self.request = request
    self.requests = requests
    rows = request.lineRows
  }

  var body: some View {
    GeometryReader { geometry in
      let portrait = geometry.size.height > geometry.size.width
      if sizeClass == .regular && halfOpen && portrait {
        tabletop(geometry)
      } else if sizeClass == .regular {
        regular(landscape: !portrait)
      } else {
        ScrollView { compact.padding(.horizontal, 16) }
      }
    }
    .navigationTitle(sizeClass == .regular && !halfOpen ? request.heading : "")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(halfOpen && sizeClass == .regular ? .hidden : .visible, for: .navigationBar)
    .toolbar(halfOpen && sizeClass == .regular ? .hidden : .visible, for: .bottomBar)
    .toolbar { toolbar }
    .background(HingeReader(halfOpen: $halfOpen))
    .sheet(isPresented: $signing) { WhatYouSign(request: request) }
    .sheet(isPresented: $refusing) { RefuseSheet(request: request, refuse: refuse) }
    .alert(
      "Board could not send your answer", isPresented: .constant(failure != nil),
      actions: { Button("OK") { failure = nil } }, message: { Text(failure ?? "") })
  }

  // MARK: Actions

  @ToolbarContentBuilder private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      Button(action: approve) { Label("Approve", systemImage: "faceid") }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .disabled(request.isStale || answering)
    }
    ToolbarItemGroup(placement: .bottomBar) {
      Button(role: .destructive) {
        refusing = true
      } label: {
        Label("Refuse", systemImage: "nosign")
      }
      .tint(.red)
      .disabled(answering)
      Spacer()
      Button {
        signing = true
      } label: {
        Label("What you sign", systemImage: "doc.text")
      }
    }
  }

  /// The inbox closes this screen once the request leaves it.
  private func approve() {
    guard !answering else { return }
    answering = true
    Task {
      defer { answering = false }
      do {
        try await requests.approve(request)
      } catch  where PhoneKey.isCancel(error) {
      } catch {
        failure = error.localizedDescription
      }
    }
  }

  /// Why the refusal failed, which the refuse sheet shows, or nil once sent.
  private func refuse(_ reason: String) async -> String? {
    guard !answering else { return nil }
    answering = true
    defer { answering = false }
    do {
      try await requests.refuse(request, reason: reason)
      refusing = false
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  // MARK: Layouts

  @ViewBuilder private var compact: some View {
    VStack(alignment: .leading, spacing: 0) {
      RequestHeader(request: request)
      if case .action = request.kind {
        decision
        report
      } else if request.isStale {
        Banner(
          symbol: "exclamationmark.triangle", warning: true,
          text:
            "This \(request.noun) changed after \(request.plugin) asked. An approval would not let \(request.plugin) write, because it fits only the version \(request.plugin) saw. Refuse this request, and \(request.plugin) can ask again with the current version."
        )
        changes(stale: true)
      } else if rows == nil {
        priorMissing
      } else {
        changes(stale: false)
        Note(text: "\(request.allows) \(request.limits)")
        NavigationLink {
          WholeFile(request: request, rows: rows ?? [])
        } label: {
          LinkRow(
            symbol: "text.alignleft",
            title: request.effect.record == nil ? "Show the whole file" : "Show the whole record")
        }
      }
    }
  }

  private func regular(landscape: Bool) -> some View {
    Group {
      if case .action = request.kind {
        let layout =
          landscape
          ? AnyLayout(HStackLayout(alignment: .top, spacing: 14))
          : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        ScrollView {
          layout {
            VStack(alignment: .leading, spacing: 0) {
              RequestHeader(request: request)
              decision
            }
            .frame(maxWidth: landscape ? 280 : .infinity, alignment: .leading)
            report
          }
          .padding(.horizontal, 16)
        }
      } else if rows == nil || request.isStale {
        ScrollView { compact.padding(.horizontal, 16) }
      } else {
        VStack(spacing: 0) {
          HStack(alignment: .top, spacing: 12) {
            RequestHeader(request: request).frame(maxWidth: .infinity, alignment: .leading)
            Note(text: "\(request.allows) \(request.limits)").frame(maxWidth: .infinity)
          }
          .padding(.horizontal, 16)
          .padding(.bottom, 6)
          Divider()
          TwoUp(request: request, rows: rows ?? [], landscape: landscape)
        }
      }
    }
  }

  private func tabletop(_ geometry: GeometryProxy) -> some View {
    let insets = geometry.safeAreaInsets
    let fold = (geometry.size.height + insets.top + insets.bottom) / 2 - insets.top
    return VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Badge(plugin: request.plugin, size: 20)
          Text("\(request.plugin) · \(request.boardName)").font(.footnote).foregroundStyle(
            .secondary)
        }
        Text("\(request.heading) · \(request.name)").font(.headline).lineLimit(1)
        Text(request.effect.path).font(.caption.monospaced()).foregroundStyle(.secondary)
        if case .action = request.kind {
          ScrollView { report }
        } else if request.isStale {
          Banner(
            symbol: "exclamationmark.triangle", warning: true,
            text:
              "This \(request.noun) changed after \(request.plugin) asked, so an approval would not fit. Refuse it, and \(request.plugin) can ask again."
          )
        } else if let rows {
          Text(LineDiff.summary(rows)).font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
          TwoUp(
            request: request, rows: rows, landscape: false, headings: false, startAtChange: true)
        } else {
          ScrollView { priorMissing }
        }
      }
      .padding(.horizontal, 14)
      .frame(height: fold, alignment: .top)
      VStack(spacing: 10) {
        HStack(spacing: 8) {
          bigButton("Inbox", "chevron.left") { dismiss() }
          bigButton("Refuse", "nosign", red: true) { refusing = true }.disabled(answering)
          bigButton("What you sign", "doc.text") { signing = true }
        }
        Text(
          {
            if case .action = request.kind {
              return "\(request.plugin) will not ask again until you take this back."
            }
            return "Writes exactly this version, or nothing."
          }()
        )
        .font(.footnote).foregroundStyle(.secondary)
        Button(action: approve) {
          Label("Approve with Face ID", systemImage: "faceid").frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(request.isStale || answering)
        Spacer(minLength: 0)
      }
      .padding(16)
      .frame(height: geometry.size.height - fold)
    }
  }

  private func bigButton(
    _ title: String, _ symbol: String, red: Bool = false, action: @escaping () -> Void
  )
    -> some View
  {
    Button(action: action) {
      VStack(spacing: 2) {
        Image(systemName: symbol)
        Text(title).font(.caption.weight(.semibold))
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .foregroundStyle(red ? Color.red : .primary)
      .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }
    .buttonStyle(.plain)
  }

  // MARK: Parts

  /// What a plain action lets the plugin do, in plain words.
  private var decision: some View {
    VStack(alignment: .leading, spacing: 6) {
      (Text(request.allows).bold()
        + Text(" It will not ask you again until you take the approval back."))
      Text(request.limits).foregroundStyle(.secondary)
    }
    .font(.subheadline)
    .padding(.vertical, 10)
  }

  /// The file a plain action would use now, read from the board.
  @ViewBuilder private var report: some View {
    if let content = request.currentContent {
      Card(title: "What it would \(verb) now") {
        VStack(alignment: .leading, spacing: 6) {
          Text(
            "Read from the board\(requests.shared.map { " at " + $0.formatted(date: .omitted, time: .shortened) } ?? ""). Not part of what you sign."
          )
          .font(.caption).foregroundStyle(.secondary)
          Text(String(decoding: content, as: UTF8.self)).font(.footnote).textSelection(.enabled)
        }
        .padding(10)
      }
    }
  }

  private var verb: String {
    if case .action(let verb) = request.kind { return verb }
    return "write"
  }

  /// The changed lines, or for a record the changed fields.
  @ViewBuilder private func changes(stale: Bool) -> some View {
    if let fields = request.fields {
      Card(
        title:
          "\(fields.changed.count) \(fields.changed.count == 1 ? "field changes" : "fields change")",
        trailing: "\(fields.same.count) the same"
      ) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(fields.changed.enumerated()), id: \.offset) { FieldView(row: $0.element) }
          if !fields.same.isEmpty {
            Text("The same: \(fields.same.joined(separator: ", ")).")
              .font(.caption).foregroundStyle(.secondary).padding(10)
          }
        }
      }
    } else if let rows = rows {
      let changed = rows.filter { !$0.isSame }
      let total = request.kind == .remove ? rows.count : rows.filter { $0.new != nil }.count
      Card(
        title: stale
          ? "\(changed.count) lines change from the version \(request.plugin) saw"
          : "\(changed.count) of \(total) lines change"
      ) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(changed.enumerated()), id: \.offset) { _, row in
            if let old = row.old { DiffLine(number: old.number, text: old.text, side: .removed) }
            if let new = row.new { DiffLine(number: new.number, text: new.text, side: .added) }
          }
        }
      }
    }
  }

  @ViewBuilder private var priorMissing: some View {
    if request.kind == .remove {
      Banner(
        symbol: "info.circle", warning: false,
        text:
          "Board could not fetch the file this removes (blob \(request.effect.prior.map { String($0.prefix(7)) } ?? "")) from your Mac, so it cannot show it. What you sign is unchanged."
      )
    } else {
      priorMissingPut
    }
  }

  @ViewBuilder private var priorMissingPut: some View {
    Banner(
      symbol: "info.circle", warning: false,
      text:
        "Board could not fetch the old version (blob \(request.effect.prior.map { String($0.prefix(7)) } ?? "")) from your Mac, so this shows the new file alone. What you sign is unchanged."
    )
    let lines = LineDiff.lines(request.effect.content ?? "")
    Card(title: "The file after this change", trailing: "\(lines.count) lines") {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
          DiffLine(number: index + 1, text: Marked(line), side: .same)
        }
      }
    }
  }
}

/// The kicker, heading, name and path at the top of a request.
struct RequestHeader: View {
  let request: Request

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Badge(plugin: request.plugin, size: 20)
        Text("\(request.plugin) · \(request.boardName)").font(.footnote).foregroundStyle(.secondary)
      }
      Text(request.heading).font(.title2.bold()).padding(.top, 4)
      Text(request.name).font(.headline)
      Text(request.effect.path).font(.caption.monospaced()).foregroundStyle(.secondary)
    }
  }
}

/// Before left and after right, row by row, so a changed line sits level with
/// its old version. A record shows its changed fields the same way.
struct TwoUp: View {
  let request: Request
  let rows: [DiffRow]
  let landscape: Bool
  var headings = true
  /// Whether to open scrolled to the first changed line.
  var startAtChange = false

  var body: some View {
    VStack(spacing: 0) {
      if headings {
        HStack(spacing: 0) {
          heading("Before", landscape ? "as it is now" : "now")
          heading("After", landscape ? "if you approve" : "if approved")
        }
      }
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 0) {
            if let fields = request.fields {
              ForEach(Array(fields.changed.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 0) {
                  FieldView(row: FieldRow(key: row.key, old: row.old, new: nil))
                  FieldView(row: FieldRow(key: row.key, old: nil, new: row.new))
                }
              }
              if !fields.same.isEmpty {
                Text("The same: \(fields.same.joined(separator: ", ")).")
                  .font(.caption).foregroundStyle(.secondary).padding(10)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            } else {
              ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: 0) {
                  side(row.old, row.isSame ? .same : .removed)
                  side(row.new, row.isSame ? .same : .added)
                }
                .id(index)
              }
            }
          }
        }
        .onAppear {
          if startAtChange, let first = rows.firstIndex(where: { !$0.isSame }) {
            proxy.scrollTo(first, anchor: .top)
          }
        }
      }
    }
  }

  private func heading(_ title: String, _ note: String) -> some View {
    HStack {
      Text(title).fontWeight(.semibold)
      Spacer()
      Text(note)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder private func side(_ line: (number: Int, text: Marked)?, _ side: DiffLine.Side)
    -> some View
  {
    if let line {
      DiffLine(number: line.number, text: line.text, side: side)
    } else {
      Color.clear.frame(maxWidth: .infinity, minHeight: 1)
    }
  }
}

/// Every line of the file, the removed and added lines among them.
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

/// One line of a diff: its number, and its text with the changed words marked.
struct DiffLine: View {
  enum Side { case removed, added, same }
  let number: Int
  let text: Marked
  let side: Side

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text("\(number)").foregroundStyle(.tertiary).frame(width: 22, alignment: .trailing)
      Text(marked(text, side)).frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.caption.monospaced())
    .padding(.horizontal, 10)
    .padding(.vertical, 3)
    .background(side.background)
    .foregroundStyle(side.ink)
  }
}

extension DiffLine.Side {
  var background: Color {
    switch self {
    case .removed: Color.red.opacity(0.1)
    case .added: Color.green.opacity(0.12)
    case .same: .clear
    }
  }

  var ink: Color {
    switch self {
    case .removed: Color(red: 0.71, green: 0.14, blue: 0.09)
    case .added: Color(red: 0.09, green: 0.45, blue: 0.23)
    case .same: .secondary
    }
  }
}

/// `text` with its changed words bold on a stronger tint.
func marked(_ text: Marked, _ side: DiffLine.Side) -> AttributedString {
  var changed = AttributedString(text.changed)
  changed.font = .caption.monospaced().bold()
  changed.backgroundColor = side.ink.opacity(0.16)
  return AttributedString(text.before) + changed + AttributedString(text.after)
}

/// One field of a record, by its key path, before and after.
struct FieldView: View {
  let row: FieldRow

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(row.key).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      if let old = row.old, let new = row.new, old.text.count + new.text.count <= 36 {
        HStack(spacing: 6) {
          value(old, .removed)
          Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
          value(new, .added)
        }
      } else {
        if let old = row.old { value(old, .removed) }
        if let new = row.new { value(new, .added) }
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .bottom) { Divider() }
  }

  private func value(_ text: Marked, _ side: DiffLine.Side) -> some View {
    Text(marked(text, side))
      .font(.caption.monospaced())
      .foregroundStyle(side.ink)
      .padding(.horizontal, 5)
      .padding(.vertical, 2)
      .background(side.background, in: .rect(cornerRadius: 5))
  }
}

struct Card<Content: View>: View {
  let title: String
  var trailing: String?
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(title)
        Spacer()
        if let trailing { Text(trailing) }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(Color(.secondarySystemBackground))
      content
    }
    .clipShape(.rect(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.separator)))
    .padding(.vertical, 12)
  }
}

struct Note: View {
  let text: String

  var body: some View {
    Label(text, systemImage: "info.circle")
      .font(.footnote)
      .foregroundStyle(.secondary)
      .padding(.vertical, 8)
  }
}

struct Banner: View {
  let symbol: String
  let warning: Bool
  let text: String

  var body: some View {
    Label(text, systemImage: symbol)
      .font(.footnote)
      .foregroundStyle(warning ? Color.orange : .secondary)
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        warning ? Color.orange.opacity(0.12) : Color(.secondarySystemBackground),
        in: .rect(cornerRadius: 10)
      )
      .padding(.vertical, 8)
  }
}

struct LinkRow: View {
  let symbol: String
  let title: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: symbol).foregroundStyle(.tint)
      Text(title).foregroundStyle(.primary)
      Spacer()
      Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
    }
    .font(.subheadline)
    .padding(.vertical, 10)
    .overlay(alignment: .top) { Divider() }
  }
}

/// The exact statement Face ID signs, line for line.
struct WhatYouSign: View {
  let request: Request
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let statement = request.effect.approval
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("What you sign").font(.headline)
        Spacer()
        Button("Close") { dismiss() }.fontWeight(.semibold)
      }
      Text(
        "Face ID signs exactly these lines. Board on your Mac checks them before \(request.plugin) may \(request.kind == .change || request.kind == .add ? "write" : "act")."
      )
      .font(.footnote).foregroundStyle(.secondary)
      ScrollView {
        Text(statement)
          .font(.caption2.monospaced())
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
      }
      .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
      Text("\(LineDiff.lines(statement).count) lines. Scroll for the rest.")
        .font(.footnote).foregroundStyle(.secondary)
      Note(
        text: request.effect.prior.map {
          "The effect line stands for this request, its new content and the version it replaces (blob \($0.prefix(7))). That is why this approval cannot write over a later change."
        } ?? "The effect line stands for this request and everything it carries.")
    }
    .padding(16)
    .presentationDragIndicator(.visible)
  }
}

struct RefuseSheet: View {
  let request: Request
  /// Sends the refusal, and returns why it failed or nil once sent.
  let refuse: (String) async -> String?
  @State private var reason = ""
  @State private var sending = false
  @State private var failure: String?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Refuse this request?").font(.headline)
      Text(
        "\(request.plugin) is told no. A refusal is not signed, so it needs no Face ID. If \(request.plugin) asks for the same thing again, it gets the same answer."
      )
      .font(.footnote).foregroundStyle(.secondary)
      TextField(
        "Reason, if you want to give one. \(request.plugin) sees it.", text: $reason,
        axis: .vertical
      )
      .lineLimit(3...6)
      .padding(10)
      .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(.separator)))
      if let failure {
        Text("Board could not send your refusal: \(failure)").font(.footnote).foregroundStyle(.red)
      }
      HStack(spacing: 8) {
        Button("Cancel") { dismiss() }
          .buttonStyle(.bordered).frame(maxWidth: .infinity)
        Button(role: .destructive) {
          sending = true
          failure = nil
          Task {
            failure = await refuse(reason)
            sending = false
          }
        } label: {
          Label("Refuse", systemImage: "nosign").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(sending)
      }
      .controlSize(.large)
    }
    .padding(16)
    .presentationDetents([.medium])
  }
}

#Preview("Task") {
  NavigationStack {
    RequestView(request: PreviewRequests.task, requests: PhoneRequests(preview: []))
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
#Preview("No prior") {
  NavigationStack {
    RequestView(request: PreviewRequests.noPrior, requests: PhoneRequests(preview: []))
  }
}
