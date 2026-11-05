// The inbox: the questions agents asked the owner and the requests plugins
// asked the owner to answer, each newest first. It follows the signed-off
// Inbox v2 design: a NavigationSplitView with a Boards list and what waits in
// the chosen board, laid out as Mail lays out mailboxes and messages. The
// signed-off "Questions from agents" design adds a Questions section above
// Requests. The tabletop pose puts the Boards list on the lower half. In a
// regular width in landscape, as on the open Duo, an open request's thread or
// an open question sits on the trailing half beside the list.
import Requests
import SwiftUI

/// The boards the inbox can show: every board, or one by its git remote.
enum BoardChoice: Hashable {
  case all
  case board(String)

  var name: String? {
    if case .board(let name) = self { return name }
    return nil
  }
}

struct InboxView: View {
  @State var requests: PhoneRequests
  /// No choice shows every board; the compact split view shows the Boards
  /// list only while nothing is chosen.
  @State private var choice: BoardChoice? = Fixture.boards ? nil : .all
  /// The app opens on All Boards; Back leads to the Boards list.
  @State private var column: NavigationSplitViewColumn = Fixture.boards ? .sidebar : .detail
  /// The Boards sidebar beside the requests, hidden while a request is open so
  /// that it fills the screen.
  @State private var columns: NavigationSplitViewVisibility =
    Fixture.open == nil ? .all : .detailOnly
  @State private var halfOpen = false
  /// The request or question screen open, by request id or question id.
  @State private var path: [String] =
    (Fixture.open?.id ?? Fixture.openQuestion?.id).map { [$0] } ?? []
  @State private var refusing: Request?
  @Environment(\.horizontalSizeClass) private var sizeClass

  var body: some View {
    GeometryReader { geometry in
      let landscape = geometry.size.width > geometry.size.height
      if sizeClass == .regular && halfOpen && !landscape && path.isEmpty {
        tabletop(geometry)
      } else if sizeClass == .regular && landscape, let id = path.first,
        requests.request(id) != nil || requests.question(id) != nil
      {
        beside(id, width: geometry.size.width)
      } else {
        split
      }
    }
    .background(HingeReader(halfOpen: $halfOpen))
    .refuseAlert($refusing, requests: requests)
    .alert(
      requests.refusals.first?.title ?? "",
      isPresented: Binding(
        get: { !requests.refusals.isEmpty }, set: { if !$0 { requests.dismissRefusal() } }),
      presenting: requests.refusals.first
    ) { _ in
      Button("OK") {}
    } message: { refused in
      Text(refused.text)
    }
    .task { await requests.watch() }
    .onChange(of: requests.inbox.boards.map(\.name)) { _, names in
      // A board leaves the list once nothing waits in it.
      if let name = choice?.name, !names.contains(name) { choice = .all }
    }
    .onChange(of: requests.inbox.requests.map(\.id) + requests.inbox.questions.map(\.id)) {
      _, ids in
      // A request or question answered here or elsewhere closes its screen.
      path.removeAll { !ids.contains($0) }
    }
    .onChange(of: path.isEmpty) { _, empty in columns = empty ? .all : .detailOnly }
  }

  private var board: String? { choice?.name }
  private var title: String { board ?? "All Boards" }
  private var shown: [Request] { requests.inbox.requests(in: board) }
  private var shownQuestions: [Question] { requests.inbox.questions(in: board) }

  // MARK: Layouts

  /// The Boards list beside the requests, or behind Back in compact width.
  /// The inbox has no bar items, so the sidebar has no toggle.
  private var split: some View {
    NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $column) {
      BoardsList(inbox: requests.inbox, choice: $choice)
        .navigationTitle("Boards")
        .toolbar(removing: .sidebarToggle)
    } detail: {
      stack(.large)
    }
    .navigationSplitViewStyle(.balanced)
  }

  /// The requests above the fold and the Boards list below it. The fold is
  /// the middle of the whole screen, not of the safe area, whose top and
  /// bottom insets differ.
  private func tabletop(_ geometry: GeometryProxy) -> some View {
    let insets = geometry.safeAreaInsets
    let fold = (geometry.size.height + insets.top + insets.bottom) / 2 - insets.top
    return VStack(spacing: 0) {
      stack(.inline).frame(height: fold)
      BoardsPicker(inbox: requests.inbox, choice: $choice)
        .frame(height: geometry.size.height - fold)
    }
  }

  /// The list on the leading half and the open request's thread or the open
  /// question on the trailing half, with its side strip.
  private func beside(_ id: String, width: CGFloat) -> some View {
    HStack(spacing: 0) {
      NavigationStack {
        RequestList(
          requests: requests, shown: shown, questions: shownQuestions, refusing: $refusing,
          selected: id, select: { path = [$0] }
        )
        .navigationTitle(title)
      }
      .frame(width: width / 2)
      Divider()
      NavigationStack {
        if let request = requests.request(id) {
          RequestView(request: request, requests: requests, back: { path = [] })
        } else if let question = requests.question(id) {
          QuestionView(question: question, requests: requests, back: { path = [] })
        }
      }
      .id(id)
    }
    .overlay(alignment: .bottom) { sentBanner }
  }

  private func stack(_ mode: NavigationBarItem.TitleDisplayMode) -> some View {
    NavigationStack(path: $path) {
      RequestList(
        requests: requests, shown: shown, questions: shownQuestions, refusing: $refusing
      )
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(mode)
      .overlay(alignment: .bottom) { sentBanner }
      .navigationDestination(for: String.self) { id in
        if let request = requests.request(id) {
          RequestView(request: request, requests: requests)
        } else if let question = requests.question(id) {
          QuestionView(question: question, requests: requests)
        }
      }
    }
  }

  /// The banner that says an answer went to the Mac. It hides after a few
  /// seconds.
  @ViewBuilder private var sentBanner: some View {
    if let sent = requests.answerSent {
      Label {
        Text(
          "Answer sent to your Mac. Board records it the next time your Mac shares, within about 10 seconds while it is awake."
        )
      } icon: {
        Image(systemName: "checkmark.circle").foregroundStyle(.green)
      }
      .font(.subheadline)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.row)
          .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
      )
      .padding(.horizontal, 16)
      .padding(.bottom, 8)
      .transition(.move(edge: .bottom).combined(with: .opacity))
      .task(id: sent) {
        try? await Task.sleep(for: .seconds(6))
        withAnimation { requests.hideAnswerSent() }
      }
    }
  }
}

/// The questions and requests of one board, or of every board, each in its
/// own section. It redraws every 30 seconds, so the subtitle says the list is
/// out of date even when no read succeeds, and a row's "Yesterday" moves on
/// at midnight.
struct RequestList: View {
  let requests: PhoneRequests
  let shown: [Request]
  var questions: [Question] = []
  @Binding var refusing: Request?
  /// The request or question that shows beside the list, if any.
  var selected: String?
  /// Opens a request or question beside the list instead of pushing it.
  var select: ((String) -> Void)?

  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      let stale = requests.isOutOfDate(now: context.date)
      List {
        if !questions.isEmpty {
          Section {
            ForEach(questions) { question in
              link(
                question.id,
                QuestionRow(
                  question: question, sending: requests.answering.contains(question.id),
                  now: context.date))
            }
          } header: {
            header("Questions · \(questions.count)", stale: stale, first: true)
          } footer: {
            if stale && shown.isEmpty { staleFooter }
          }
        }
        if !shown.isEmpty {
          Section {
            ForEach(shown) { request in
              let row = RequestRow(
                request: request, versions: requests.thread(for: request).versions.count,
                now: context.date)
              link(request.id, row)
                .swipeActions(edge: .trailing) {
                  // Not a destructive role, which would remove the row before the
                  // alert asks.
                  Button {
                    refusing = request
                  } label: {
                    Label("Refuse", systemImage: "xmark")
                  }
                  .tint(.red)
                  .disabled(requests.sending.contains(request.id))
                }
            }
          } header: {
            header("Requests · \(shown.count)", stale: stale, first: questions.isEmpty)
          } footer: {
            if stale { staleFooter }
          }
        }
      }
      .listStyle(.plain)
      .overlay {
        if shown.isEmpty && questions.isEmpty {
          ContentUnavailableView(
            "Nothing Waiting", systemImage: "tray",
            description: Text(
              "When an agent asks you a question, or a plugin asks before it acts, it appears here."
            ))
        }
      }
      .subtitle(subtitle(stale: stale))
    }
    .refreshable { await requests.refresh() }
  }

  /// A row that opens beside the list, or pushes its screen.
  @ViewBuilder private func link<Row: View>(_ id: String, _ row: Row) -> some View {
    if let select {
      Button {
        select(id)
      } label: {
        row
      }
      .foregroundStyle(.primary)
      .listRowBackground(id == selected ? Palette.action.opacity(0.12) : nil)
    } else {
      NavigationLink(value: id) { row }
    }
  }

  /// A section's header with its count. Before iOS 26 there is no navigation
  /// subtitle, so the first section's header says it.
  private func header(_ text: String, stale: Bool, first: Bool) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      if #unavailable(iOS 26), first, let subtitle = subtitle(stale: stale) {
        Text(subtitle).textCase(nil)
      }
      Text(text)
    }
  }

  private var staleFooter: some View {
    Text(
      "Your Mac shares new questions and requests while it is awake and Board is running on it. Pull down to try again."
    )
    .frame(maxWidth: .infinity)
    .multilineTextAlignment(.center)
  }

  /// The count, or how old the list is when the Mac has stopped sharing.
  private func subtitle(stale: Bool) -> String? {
    if stale, let shared = requests.shared {
      let today = Calendar.current.isDateInToday(shared)
      return
        "Mac last shared requests at \(shared.formatted(date: today ? .omitted : .abbreviated, time: .shortened))"
    }
    let count = shown.count + questions.count
    return count == 0 ? nil : "\(count) Waiting"
  }
}

extension View {
  /// The navigation subtitle, on iOS 26 and later. An empty one shows
  /// nothing, and keeps the list's identity when the count goes.
  @ViewBuilder func subtitle(_ text: String?) -> some View {
    if #available(iOS 26, *) {
      navigationSubtitle(text ?? "")
    } else {
      self
    }
  }
}

struct RequestRow: View {
  let request: Request
  /// How many versions its thread has.
  var versions = 1
  var now = Date()

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline) {
        Text(request.name).font(.headline).lineLimit(2)
        Spacer(minLength: 8)
        Text(askedLabel(request.asked, now: now)).font(.subheadline).foregroundStyle(.secondary)
      }
      Text(request.sentence).font(.subheadline)
      Label {
        Text(request.boardName + (versions > 1 ? " · \(versions) versions" : ""))
      } icon: {
        Image(systemName: "signature").foregroundStyle(.orange)
      }
      .labelStyle(BoardLabel())
      .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
    }
  }
}

/// A question row: the question in two lines, the recommended option or that
/// the answer is on its way, and the board it concerns. It has no swipe
/// action.
struct QuestionRow: View {
  let question: Question
  var sending = false
  var now = Date()

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline) {
        Text(question.question).font(.headline).lineLimit(2)
        Spacer(minLength: 8)
        if let asked = question.askedDate {
          Text(askedLabel(asked, now: now)).font(.subheadline).foregroundStyle(.secondary)
        }
      }
      Text(question.rowLine(sending: sending))
        .font(.subheadline)
        .italic(sending)
        .foregroundStyle(sending ? .secondary : .primary)
        .lineLimit(1)
      Label {
        Text(question.boardName)
      } icon: {
        Image(systemName: "questionmark.bubble").foregroundStyle(.purple)
      }
      .labelStyle(BoardLabel())
      .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
    }
  }
}

/// A small symbol before a row's board name.
struct BoardLabel: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 5) {
      configuration.icon.imageScale(.small)
      configuration.title
    }
  }
}

/// The Boards column: All Boards, then each board with requests waiting. It
/// is a sidebar beside the requests, and an inset grouped screen behind Back.
struct BoardsList: View {
  let inbox: Inbox
  @Binding var choice: BoardChoice?
  @Environment(\.horizontalSizeClass) private var sizeClass

  var body: some View {
    let list = List(selection: $choice) {
      Section {
        NavigationLink(value: BoardChoice.all) {
          row("All Boards", "tray.2", inbox.count(in: nil))
        }
      }
      Section {
        ForEach(inbox.boards, id: \.name) { board in
          NavigationLink(value: BoardChoice.board(board.name)) {
            row(board.name, "folder", board.count)
          }
        }
      } header: {
        Text("Boards")
      } footer: {
        Text(
          "A board is named by its git remote. A board appears here while something waits in it.")
      }
    }
    if sizeClass == .regular {
      list.listStyle(.sidebar)
    } else {
      list.listStyle(.insetGrouped)
    }
  }

  /// The count before the chevron, as Mail shows it. A list badge would
  /// follow the chevron in an inset grouped list.
  private func row(_ name: String, _ symbol: String, _ count: Int) -> some View {
    HStack {
      Label(name, systemImage: symbol)
      Spacer()
      Text("\(count)").foregroundStyle(.secondary)
    }
  }
}

/// The Boards list on the lower half in the tabletop pose, with a checkmark
/// on the chosen board, as in a Settings picker.
struct BoardsPicker: View {
  let inbox: Inbox
  @Binding var choice: BoardChoice?

  var body: some View {
    List {
      Section("Boards") {
        row(.all, "All Boards", "tray.2", inbox.count(in: nil))
        ForEach(inbox.boards, id: \.name) { board in
          row(.board(board.name), board.name, "folder", board.count)
        }
      }
    }
    .listStyle(.insetGrouped)
  }

  private func row(_ value: BoardChoice, _ name: String, _ symbol: String, _ count: Int)
    -> some View
  {
    Button {
      choice = value
    } label: {
      HStack {
        Label(name, systemImage: symbol)
        Spacer()
        Text("\(count)").foregroundStyle(.secondary)
        Image(systemName: "checkmark").foregroundStyle(.tint).opacity(choice == value ? 1 : 0)
      }
    }
    .foregroundStyle(.primary)
  }
}

#Preview("Inbox") {
  InboxView(
    requests: PhoneRequests(preview: PreviewRequests.all, questions: PreviewQuestions.all))
}
#Preview("Answer sent") {
  InboxView(
    requests: PhoneRequests(
      preview: PreviewRequests.all, questions: PreviewQuestions.all,
      answering: [PreviewQuestions.merge.id]))
}
#Preview("Already answered") {
  InboxView(
    requests: PhoneRequests(
      preview: PreviewRequests.all, questions: PreviewQuestions.all,
      refusals: [PreviewQuestions.alreadyAnswered]))
}
#Preview("Empty") { InboxView(requests: PhoneRequests(preview: [])) }
#Preview("Out of date") {
  InboxView(
    requests: PhoneRequests(
      preview: PreviewRequests.all, shared: Date().addingTimeInterval(-3600)))
}
