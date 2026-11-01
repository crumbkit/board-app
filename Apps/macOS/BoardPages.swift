// The Board window's pages: the requests waiting, the requests answered in
// the last 7 days, and a paired iPhone.
import AppKit
import Pairing
import Requests
import SwiftUI

/// The requests waiting in the personal board, by board, with what the Mac
/// knows of each: whether iCloud holds it and the owner's latest reply.
struct WaitingPage: View {
  let relay: RequestRelay
  let phones: [Phone]
  /// Why the phones could not be read, or nil.
  let problem: String?
  let addPhone: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 8) {
        if let cloud = relay.cloudProblem {
          Banner(
            symbol: "exclamationmark.triangle.fill", tint: .orange,
            title: phones.isEmpty
              ? "Board is not sharing requests" : "Your iPhone is not getting new requests",
            message: [cloud.message, cloud.advice].compactMap { $0 }.joined(separator: " "),
            button: cloud.advice == nil ? nil : "Open iCloud Settings…", prominent: false
          ) {
            if let url = URL(
              string: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings")
            {
              NSWorkspace.shared.open(url)
            }
          }
        }
        if phones.isEmpty, problem == nil {
          Banner(
            symbol: "info.circle.fill", tint: .accentColor, title: "No iPhone is paired",
            message:
              "Pair one to approve or refuse requests when you are away from this Mac. Until then, answer them with board answer.",
            button: "Add iPhone…", prominent: true, action: addPhone)
        }
        ForEach([relay.boardProblem, problem].compactMap { $0 }, id: \.self) {
          Text($0).foregroundStyle(.red).font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding([.horizontal, .top], 16)
      if relay.waiting.requests.isEmpty {
        ContentUnavailableView(
          "No Requests", systemImage: "tray",
          description: Text("When a plugin asks before it acts, its request appears here."))
      } else {
        List {
          ForEach(relay.waiting.boards, id: \.name) { board in
            Section(board.name) {
              ForEach(relay.waiting.requests(in: board.name)) { request in
                WaitingRow(
                  request: request, thread: relay.threads[request.id],
                  chip: chip(request))
              }
            }
          }
          Section {
          } footer: {
            Text(footer).foregroundStyle(.secondary).font(.callout)
          }
        }
        .listStyle(.inset)
      }
    }
  }

  /// What the Mac knows of the request's way to the phone.
  private func chip(_ request: Request) -> Chip? {
    if phones.isEmpty {
      return Chip("Waiting in the board · no iPhone to answer it", "tray")
    }
    let since = relay.sharedSince[request.id]
    if relay.cloudProblem != nil {
      return since.map {
        Chip(
          "Shared at \(clock($0)) · new answers cannot arrive", "exclamationmark.triangle.fill",
          tint: .orange)
      } ?? Chip("Not shared · iCloud failed", "exclamationmark.triangle.fill", tint: .orange)
    }
    return since.map { Chip("On your iPhone since \(clock($0))", "iphone", tint: .blue) }
  }

  private var footer: String {
    if relay.cloudProblem != nil {
      return
        "Board tries iCloud again every 10 seconds. Requests it shared earlier stay on your iPhone, but answers from it wait until iCloud works."
    }
    if phones.isEmpty {
      return "Board keeps sharing requests to iCloud, so a phone you pair sees them at once."
    }
    return
      "Answer on your iPhone. Board shares new requests every 10 seconds while it runs, and hands your answers to board."
  }
}

/// One waiting request, worded as the phone's inbox words it.
struct WaitingRow: View {
  let request: Request
  let thread: RequestThread?
  let chip: Chip?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      RequestLines(request: request, sentence: request.sentence, when: request.asked)
      if let chip { chip }
      if let reply = thread?.replies.last {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "arrowshape.turn.up.left").foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 1) {
            Text(reply.text)
            if let sent = reply.sent {
              Text("You replied from your iPhone \(moment(sent))")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
      }
    }
    .padding(.vertical, 4)
  }
}

/// A request's name and time, its sentence and the first line of its text.
struct RequestLines: View {
  let request: Request
  let sentence: String
  let when: Date

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline) {
        Text(request.name).font(.headline).lineLimit(2)
        Spacer(minLength: 8)
        Text(askedLabel(when)).foregroundStyle(.secondary)
      }
      Text(sentence)
      if let summary = request.summary {
        Text(summary).foregroundStyle(.secondary).lineLimit(2)
      }
    }
  }
}

/// What Board recorded in `effects/seen/` over the last 7 days, by day and
/// board, newest first.
struct AnsweredPage: View {
  let model: BoardWindowModel

  var body: some View {
    VStack(spacing: 0) {
      if let problem = model.answeredProblem {
        Text(problem).foregroundStyle(.red).font(.callout)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding([.horizontal, .top], 16)
      }
      if model.answered.isEmpty {
        ContentUnavailableView(
          "No Answers", systemImage: "checkmark.circle",
          description: Text("Requests you answered in the last 7 days appear here."))
      } else {
        List {
          ForEach(groups, id: \.title) { group in
            Section(group.title) {
              ForEach(group.answered) { answered in
                VStack(alignment: .leading, spacing: 4) {
                  RequestLines(
                    request: answered.request, sentence: answered.request.askedSentence,
                    when: answered.request.asked)
                  chip(answered)
                }
                .padding(.vertical, 4)
              }
            }
          }
          Section {
          } footer: {
            Text(
              "From effects/seen in the personal board. A refusal carries no signature, so it names no device."
            )
            .foregroundStyle(.secondary).font(.callout)
          }
        }
        .listStyle(.inset)
      }
    }
  }

  /// "Today · owner/board", and so on, each title once, in the order
  /// its first answer came.
  private var groups: [(title: String, answered: [AnsweredRequest])] {
    var out: [(title: String, answered: [AnsweredRequest])] = []
    for answered in model.answered {
      let day = Calendar.current.isDateInToday(answered.at) ? "Today" : askedLabel(answered.at)
      let title = "\(day) · \(answered.request.boardName)"
      if let index = out.firstIndex(where: { $0.title == title }) {
        out[index].answered.append(answered)
      } else {
        out.append((title, [answered]))
      }
    }
    return out
  }

  private func chip(_ answered: AnsweredRequest) -> Chip {
    let answer = answered.answer
    let time = clock(answered.at)
    guard answer.approved else {
      let reason = answer.reason.map { " · “\($0)”" } ?? ""
      return Chip("Refused at \(time)\(reason)", "xmark.circle.fill", tint: .red)
    }
    let on = model.signers[answered.id].map { " on \($0.name)" } ?? ""
    return Chip("Approved\(on) at \(time)", "checkmark.circle.fill", tint: .green)
  }
}

/// A paired iPhone: what it may approve and its key, from the two allowed
/// signers files.
struct PhonePage: View {
  let phone: Phone
  /// When it last approved a request in the last 7 days, or nil.
  let lastAnswer: Date?
  let pairAgain: () -> Void

  var body: some View {
    Form {
      Section {
        HStack(spacing: 14) {
          Image(systemName: "iphone")
            .font(.title2)
            .frame(width: 44, height: 44)
            .background(.tint.opacity(0.15), in: .rect(cornerRadius: 12))
            .foregroundStyle(.tint)
          VStack(alignment: .leading) {
            Text(phone.name).font(.title2.bold())
            Text(
              "Secure Enclave key, Face ID or Touch ID"
                + (lastAnswer.map { " · last answered \(moment($0))" } ?? "")
            )
            .foregroundStyle(.secondary)
          }
        }
      }
      Section("This iPhone can approve") {
        allowed(.approvals, "Agent requests", "When an agent wants to write or change a file.")
        allowed(.orders, "Orders", "Standing instructions every agent follows.")
      }
      Section("Key") {
        LabeledContent("Fingerprint") {
          Text(phone.device.fingerprint ?? "Board could not read this key")
            .font(.system(.body, design: .monospaced)).textSelection(.enabled)
        }
        LabeledContent("Device") {
          Text(phone.device.id).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        }
        LabeledContent("Lines") {
          VStack(alignment: .trailing, spacing: 2) {
            ForEach(lines, id: \.self) { Text($0) }
          }
          .font(.system(.body, design: .monospaced)).textSelection(.enabled)
        }
      }
      Section {
        HStack {
          Spacer()
          Button("Pair Again to Change…", action: pairAgain)
        }
      }
    }
    .formStyle(.grouped)
  }

  /// Each file the phone has a line in, and the namespaces the line admits.
  private var lines: [String] {
    [
      (SignersFiles.board, phone.device.boardLine),
      (SignersFiles.attention, phone.device.attentionLine),
    ]
    .compactMap { file, line in
      line.map {
        "\(SignersFiles.shown(file)) · \(PairedDevice.namespaces($0).joined(separator: ", "))"
      }
    }
  }

  private func allowed(_ scope: Scope, _ title: String, _ detail: String) -> some View {
    let yes = phone.device.scope.contains(scope)
    return HStack(alignment: .firstTextBaseline, spacing: 10) {
      Image(systemName: yes ? "checkmark.circle.fill" : "minus.circle")
        .foregroundStyle(yes ? .green : .secondary)
      VStack(alignment: .leading) {
        Text(title).fontWeight(.semibold)
        Text(detail).foregroundStyle(.secondary).font(.callout)
      }
    }
  }
}
