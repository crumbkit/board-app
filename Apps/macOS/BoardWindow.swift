// The Board window on the Mac: a sidebar with Waiting, Answered and the
// paired iPhones, and the page of the one selected. It shows what the relay
// is doing and changes nothing the relay does; pairing opens as a sheet.
import AppKit
import Pairing
import Requests
import SSHSig
import SwiftUI

/// A paired phone with the name the Mac kept for it.
struct Phone: Identifiable, Equatable {
  let device: PairedDevice
  /// The name it gave at pairing, or its fallback name.
  let name: String
  /// When it paired, when the Mac kept it.
  let paired: Date?
  var id: String { device.id }
}

/// What the window reads beside the relay: the phones the allowed signers
/// files admit and the requests answered in the last 7 days.
@MainActor
@Observable
final class BoardWindowModel {
  private(set) var phones: [Phone] = []
  private(set) var answered: [AnsweredRequest] = []
  /// The phone whose key each approval's signature names, by effect id.
  private(set) var signers: [String: Phone] = [:]
  /// Why the phones could not be read, or nil.
  private(set) var phonesProblem: String?
  /// Why the answered requests could not be read, or nil.
  private(set) var answeredProblem: String?

  /// Reads again every 10 seconds while the window is open.
  func watch() async {
    while !Task.isCancelled {
      await refresh()
      try? await Task.sleep(for: .seconds(10))
    }
  }

  func refresh() async {
    do {
      let notes = PhoneNotes.all()
      phones = try SignersFiles.paired().map { device in
        Phone(
          device: device, name: notes[device.id]?.name ?? device.fallbackName,
          paired: notes[device.id]?.paired)
      }
      phonesProblem = nil
    } catch {
      phonesProblem =
        "Board could not read the allowed signers files: \(error.localizedDescription)"
    }
    do {
      answered = try await PersonalBoard.answered(
        since: Date().addingTimeInterval(-7 * 86_400), known: answered)
      answeredProblem = nil
    } catch {
      answeredProblem = "Board could not read the answers: \(error.localizedDescription)"
    }
    var signers: [String: Phone] = [:]
    for answered in answered {
      guard let key = answered.answer.signature.flatMap(signingKey(armored:)) else { continue }
      signers[answered.id] = phones.first { $0.device.x963 == key }
    }
    self.signers = signers
  }

  /// When the phone last approved a request in the last 7 days, or nil.
  func lastAnswer(by phone: Phone) -> Date? {
    answered.filter { signers[$0.id] == phone }.map(\.at).max()
  }
}

enum Page: Hashable {
  case waiting
  case answered
  case phone(String)
}

struct BoardWindow: View {
  static let id = "board"
  let relay: RequestRelay
  let openLauncher: () -> Void
  @State private var model = BoardWindowModel()
  @State private var page: Page? = .waiting
  @State private var pairing = false

  var body: some View {
    NavigationSplitView {
      sidebar
    } detail: {
      detail
    }
    .frame(minWidth: 760, minHeight: 460)
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Button(action: openLauncher) {
          Label("Open Launcher", systemImage: "magnifyingglass")
        }
        .help("Open Launcher (⌃⌥Space)")
        Button {
          pairing = true
        } label: {
          Label("Add iPhone", systemImage: "plus").labelStyle(.titleAndIcon)
        }
      }
    }
    .sheet(isPresented: $pairing) {
      PairingSheet {
        pairing = false
        Task { await model.refresh() }
      }
      .frame(width: 560)
    }
    .task { await model.watch() }
  }

  private var sidebar: some View {
    List(selection: $page) {
      Section("Requests") {
        Label("Waiting", systemImage: "tray")
          .badge(relay.waiting.requests.count)
          .tag(Page.waiting)
        Label("Answered", systemImage: "checkmark.circle").tag(Page.answered)
      }
      Section("iPhones") {
        ForEach(model.phones) { phone in
          Label(phone.name, systemImage: "iphone").tag(Page.phone(phone.id))
        }
        if model.phones.isEmpty {
          Button {
            pairing = true
          } label: {
            Label("Add iPhone…", systemImage: "plus.circle")
          }
          .buttonStyle(.plain)
          .foregroundStyle(.tint)
        }
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom) {
      RelayStatus(relay: relay, paired: !model.phones.isEmpty)
    }
    .navigationSplitViewColumnWidth(min: 200, ideal: 220)
  }

  @ViewBuilder private var detail: some View {
    switch page {
    case .answered:
      AnsweredPage(model: model)
        .navigationTitle("Answered")
        .navigationSubtitle("Last 7 days")
    case .phone(let id):
      if let phone = model.phones.first(where: { $0.id == id }) {
        PhonePage(phone: phone, lastAnswer: model.lastAnswer(by: phone)) { pairing = true }
          .navigationTitle(phone.name)
          .navigationSubtitle(phone.paired.map { "Paired \(dated($0))" } ?? "")
      } else {
        waiting
      }
    case .waiting, nil:
      waiting
    }
  }

  private var waiting: some View {
    WaitingPage(relay: relay, phones: model.phones, problem: model.phonesProblem) {
      pairing = true
    }
    .navigationTitle("Waiting")
    .navigationSubtitle(
      relay.waiting.requests.isEmpty ? "" : "\(relay.waiting.requests.count) Waiting")
  }
}

/// The sidebar's footer: whether the relay is sharing, and when it last did.
struct RelayStatus: View {
  let relay: RequestRelay
  let paired: Bool

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      if relay.boardProblem != nil || relay.cloudProblem != nil {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
      } else {
        Circle().fill(paired && relay.lastShared != nil ? .green : .secondary)
          .frame(width: 8, height: 8)
      }
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.callout.weight(.semibold))
        Text(detail).font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(12)
  }

  private var title: String {
    if relay.boardProblem != nil { return "Personal board unreadable" }
    if relay.cloudProblem != nil { return "iCloud unavailable" }
    return paired ? "Sharing with your iPhone" : "Sharing to iCloud"
  }

  private var detail: String {
    let shared =
      relay.lastShared.map { "Last shared at \(clock($0, seconds: true))" } ?? "Not shared yet"
    if relay.boardProblem == nil, relay.cloudProblem == nil, !paired {
      return "No iPhone paired · " + shared.lowercased()
    }
    return shared
  }
}

/// A coloured label under a row, such as "On your iPhone since 14:56".
struct Chip: View {
  let text: String
  let symbol: String
  let tint: Color

  init(_ text: String, _ symbol: String, tint: Color = .secondary) {
    self.text = text
    self.symbol = symbol
    self.tint = tint
  }

  var body: some View {
    Label(text, systemImage: symbol)
      .font(.caption)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .foregroundStyle(tint)
      .background(tint.opacity(0.12), in: .capsule)
  }
}

/// A notice above a page's list, with one button.
struct Banner: View {
  let symbol: String
  let tint: Color
  let title: String
  let message: String
  let button: String?
  let prominent: Bool
  var action: () -> Void = {}

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol).foregroundStyle(tint).font(.title3)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).fontWeight(.semibold)
        Text(message).foregroundStyle(.secondary).font(.callout)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      if let button {
        if prominent {
          Button(button, action: action).buttonStyle(.borderedProminent)
        } else {
          Button(button, action: action)
        }
      }
    }
    .padding(12)
    .background(tint.opacity(0.1), in: .rect(cornerRadius: 10))
  }
}

/// "at 14:57" today, and "on 30 Oct at 14:55" on another day.
func moment(_ date: Date, now: Date = Date()) -> String {
  Calendar.current.isDate(date, inSameDayAs: now) ? "at \(clock(date))" : "on \(dated(date))"
}

/// The date and time, such as "1 Nov at 14:53".
func dated(_ date: Date) -> String {
  "\(date.formatted(.dateTime.day().month(.abbreviated))) at \(clock(date))"
}

/// The time of day, such as 14:57, or 15:02:10 with seconds.
func clock(_ date: Date, seconds: Bool = false) -> String {
  date.formatted(
    seconds ? .dateTime.hour().minute().second() : .dateTime.hour().minute())
}
