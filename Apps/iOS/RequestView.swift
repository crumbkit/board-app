// One request: what a plugin asked to do, so the owner can approve it with
// Face ID or Touch ID, or refuse it. It follows the signed-off Request detail
// v2 design: an inset grouped list of the changed lines or fields in the
// compact layout, a two-up diff in the regular layout, the summary on the
// lower half in the tabletop pose, and Refuse and Approve in the bottom
// toolbar.
import Requests
import SwiftUI

struct RequestView: View {
  let request: Request
  let requests: PhoneRequests
  /// The diff rows, worked out once per request.
  private let rows: [DiffRow]?
  @State private var signing = Fixture.sheet == "sign"
  @State private var refusing: Request?
  @State private var halfOpen = false
  /// Whether the bars sit in a side strip, as on the closed Duo, where
  /// Approve shows its symbol alone.
  @State private var inStrip = false
  @State private var failure: String?
  @Environment(\.horizontalSizeClass) private var sizeClass

  init(request: Request, requests: PhoneRequests) {
    self.request = request
    self.requests = requests
    rows = request.lineRows
    if Fixture.sheet == "refuse" { _refusing = State(initialValue: request) }
  }

  var body: some View {
    GeometryReader { geometry in
      let portrait = geometry.size.height > geometry.size.width
      if sizeClass == .regular && halfOpen && portrait {
        tabletop(geometry)
      } else if sizeClass == .regular {
        regular(landscape: !portrait)
      } else {
        compact
      }
    }
    .onGeometryChange(for: Bool.self) { geometry in
      // The closed Duo's outer display is a compact width far wider than an
      // iPhone's, because the strip takes its side.
      let size = geometry.size
      return size.height > size.width && size.width / size.height > 0.6
    } action: {
      inStrip = $0
    }
    .navigationTitle(request.heading)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { toolbar }
    .background(HingeReader(halfOpen: $halfOpen))
    .sheet(isPresented: $signing) { WhatYouSign(request: request) }
    .refuseAlert($refusing, requests: requests)
    .alert(
      "Board could not send your answer", isPresented: .constant(failure != nil),
      actions: { Button("OK") { failure = nil } }, message: { Text(failure ?? "") })
  }

  // MARK: Actions

  @ToolbarContentBuilder private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      Button("What You Sign", systemImage: "signature") { signing = true }
    }
    ToolbarItemGroup(placement: .bottomBar) {
      Button("Refuse", systemImage: "xmark") { refusing = request }
        .disabled(answering)
      Spacer()
      Button(action: approve) {
        // A bottom bar shows a Label's symbol alone, and Approve needs its
        // word there.
        if inStrip || sizeClass == .regular {
          Label("Approve", systemImage: PhoneKey.biometry.symbol)
        } else {
          HStack(spacing: 6) {
            Image(systemName: PhoneKey.biometry.symbol)
            Text("Approve")
          }
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(request.isStale || answering)
    }
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

  // MARK: Layouts

  private var compact: some View {
    List {
      if case .action = request.kind {
        summary
        decision
        report
      } else if request.isStale {
        summary
        Section {
          Label {
            Text("This \(request.noun) changed after \(request.plugin) asked.")
          } icon: {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
          }
        } footer: {
          Text(
            "An approval fits only the version \(request.plugin) saw, so it would not let \(request.plugin) write. Refuse, and \(request.plugin) can ask again with the current version."
          )
        }
        changes(stale: true)
      } else if rows == nil {
        priorMissing
      } else {
        summary
        changes(stale: false)
        wholeFile
      }
    }
    .listStyle(.insetGrouped)
  }

  @ViewBuilder private func regular(landscape: Bool) -> some View {
    if case .action = request.kind {
      let layout =
        landscape
        ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
      layout {
        List {
          summary
          decision
        }
        List { report }
      }
      .listStyle(.insetGrouped)
    } else if let rows, !request.isStale {
      TwoUp(request: request, rows: rows) {
        VStack(alignment: .leading, spacing: 4) {
          summaryText
          Text("\(request.allows) \(request.limits)")
            .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(16)
      }
    } else {
      compact
    }
  }

  /// The change above the fold, facing the owner, and the summary on the
  /// half that lies on the desk, above the bottom toolbar. The fold is the
  /// middle of the whole screen, not of the safe area.
  private func tabletop(_ geometry: GeometryProxy) -> some View {
    let insets = geometry.safeAreaInsets
    let fold = (geometry.size.height + insets.top + insets.bottom) / 2 - insets.top
    return VStack(spacing: 0) {
      Group {
        if case .action = request.kind {
          List { report }.listStyle(.insetGrouped)
        } else if let rows, !request.isStale {
          TwoUp(request: request, rows: rows, headings: false, startAtChange: true) {
            EmptyView()
          }
        } else {
          compact
        }
      }
      .frame(height: fold)
      List {
        if case .action = request.kind {
          decision
        } else {
          Section {
            VStack(alignment: .leading, spacing: 2) {
              Text(request.name).font(.headline)
              Text(request.sentence)
              Text(
                rows.map { "\(LineDiff.summary($0)). Scroll the upper half for the rest." } ?? ""
              )
              .foregroundStyle(.secondary)
            }
          } footer: {
            Text("\(request.allows) \(request.limits)")
          }
        }
      }
      .listStyle(.insetGrouped)
      .frame(height: geometry.size.height - fold)
    }
  }

  // MARK: Parts

  /// The thing's name, what the plugin wants, and where and when it asked.
  private var summary: some View {
    Section { summaryText }
  }

  private var summaryText: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(request.name).font(.headline)
      Text(request.sentence)
      Text("\(request.boardName) · asked \(askedLabel(request.asked))")
        .foregroundStyle(.secondary)
    }
  }

  /// What a plain action lets the plugin do, in plain words.
  private var decision: some View {
    Section {
      Text(
        "\(request.plugin) can \(verb) from this \(request.target) whenever it runs. It will not ask again until you take the approval back."
      )
    } header: {
      Text("If you approve")
    } footer: {
      Text(request.limits)
    }
  }

  /// The file a plain action would use now, read from the board.
  @ViewBuilder private var report: some View {
    if let content = request.currentContent {
      Section {
        Text(String(decoding: content, as: UTF8.self)).textSelection(.enabled)
      } header: {
        Text("What it would \(verb) now")
      } footer: {
        Text(
          "Read from the board\(requests.shared.map { " at " + $0.formatted(date: .omitted, time: .shortened) } ?? ""). This text is not part of what you sign."
        )
      }
    }
  }

  private var verb: String {
    if case .action(let verb) = request.kind { return verb }
    return "write"
  }

  /// The changed lines, or for a record one section per changed field.
  @ViewBuilder private func changes(stale: Bool) -> some View {
    let footer = stale ? "" : "\(request.allows) \(request.limits)"
    if let fields = request.fields {
      ForEach(Array(fields.changed.enumerated()), id: \.offset) { index, row in
        Section {
          VStack(spacing: 0) {
            if let old = row.old { DiffLine(number: nil, text: old, side: .removed) }
            if let new = row.new { DiffLine(number: nil, text: new, side: .added) }
          }
          .listRowInsets(EdgeInsets())
        } header: {
          Text(row.key).textCase(nil)
        } footer: {
          if index == fields.changed.count - 1 {
            let same =
              fields.same.isEmpty ? "" : "Unchanged: \(fields.same.joined(separator: ", ")).\n"
            Text(same + footer)
          }
        }
      }
    } else if let rows {
      let changed = rows.filter { !$0.isSame }
      let total = request.kind == .remove ? rows.count : rows.filter { $0.new != nil }.count
      Section {
        VStack(spacing: 0) {
          ForEach(Array(changed.enumerated()), id: \.offset) { _, row in
            if let old = row.old { DiffLine(number: old.number, text: old.text, side: .removed) }
            if let new = row.new { DiffLine(number: new.number, text: new.text, side: .added) }
          }
        }
        .listRowInsets(EdgeInsets())
      } header: {
        Text(
          stale
            ? "\(changed.count) lines change from the version \(request.plugin) saw"
            : "\(changed.count) of \(total) lines change")
      } footer: {
        if !footer.isEmpty { Text(footer) }
      }
    }
  }

  private var wholeFile: some View {
    Section {
      NavigationLink {
        WholeFile(request: request, rows: rows ?? [])
      } label: {
        HStack {
          Text(request.effect.record == nil ? "Whole File" : "Whole Record").layoutPriority(1)
          Spacer()
          Text(request.effect.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
  }

  @ViewBuilder private var priorMissing: some View {
    let blob = request.effect.prior.map { String($0.prefix(7)) } ?? ""
    Section {
      summaryText
    } footer: {
      Text(
        request.kind == .remove
          ? "Board could not fetch the file this removes (blob \(blob)) from your Mac, so it cannot show it. What you sign is unchanged."
          : "Board could not fetch the old version (blob \(blob)) from your Mac, so this shows the new file alone. What you sign is unchanged."
      )
    }
    if request.kind != .remove {
      let lines = LineDiff.lines(request.effect.content ?? "")
      Section("The file after this change · \(lines.count) lines") {
        VStack(spacing: 0) {
          ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
            DiffLine(number: index + 1, text: Marked(line), side: .same)
          }
        }
        .listRowInsets(EdgeInsets())
      }
    }
  }
}

/// Before left and after right, row by row, so a changed line sits level with
/// its old version. A record shows its changed fields the same way.
struct TwoUp<Header: View>: View {
  let request: Request
  let rows: [DiffRow]
  var headings = true
  /// Whether to open scrolled to the first changed line.
  var startAtChange = false
  @ViewBuilder let header: Header

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          header
          if headings {
            HStack(spacing: 0) {
              heading("Before · as it is now")
              heading("After · if you approve")
            }
          }
          if let fields = request.fields {
            ForEach(Array(fields.changed.enumerated()), id: \.offset) { _, row in
              Text(row.key).font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 10)
              HStack(alignment: .top, spacing: 0) {
                side(row.old.map { (nil, $0) }, .removed)
                side(row.new.map { (nil, $0) }, .added)
              }
            }
            if !fields.same.isEmpty {
              Text("Unchanged: \(fields.same.joined(separator: ", ")).")
                .font(.footnote).foregroundStyle(.secondary).padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          } else {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
              HStack(alignment: .top, spacing: 0) {
                side(row.old.map { ($0.number, $0.text) }, row.isSame ? .same : .removed)
                side(row.new.map { ($0.number, $0.text) }, row.isSame ? .same : .added)
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

  private func heading(_ title: String) -> some View {
    Text(title)
      .font(.footnote)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 16)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder private func side(_ line: (number: Int?, text: Marked)?, _ side: DiffLine.Side)
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
