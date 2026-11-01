// Pairing on the Mac: the signed-off "Add … iPhone" sheet, which the window's
// Add iPhone button opens. Before any phone asks, it waits for one.
import LocalAuthentication
import Pairing
import SwiftUI

/// A phone whose reveal matched the challenge, and the code to compare.
struct Offer: Equatable {
  let device: Device
  let code: String
}

@MainActor
@Observable
final class MacPairing {
  private(set) var offer: Offer?
  private(set) var problem: String?
  var scope = Scope.suggested
  private let cloud = PairingCloud()
  /// The challenge this window sent each phone, by device id. It is kept only
  /// here: anything read back from iCloud could have been rewritten.
  private var challenges: [String: Challenge] = [:]
  /// A failure of the owner's own action, kept until the owner acts again.
  private var failure: String?

  func watch() async {
    do { try await cloud.prepare() } catch { problem = Self.explain(error) }
    while !Task.isCancelled {
      do {
        try await step(try await cloud.pendingRequests())
      } catch {
        problem = Self.explain(error)
      }
      try? await Task.sleep(for: .seconds(2))
    }
  }

  /// Sends a challenge to a new request, and offers a request whose reveal
  /// matches the challenge this window pinned.
  private func step(_ pending: [PairingRequest]) async throws {
    guard pending.count <= 1 else {
      show(
        nil,
        problem:
          "Two devices are asking to pair. Cancel on each of them, then pair one at a time.")
      return
    }
    guard let request = pending.first else { return show(nil, problem: nil) }
    guard let challenge = challenges[request.id], challenge.created == request.created else {
      if request.hasReveal {
        show(
          nil,
          problem:
            "This iPhone started pairing before this sheet opened. Cancel on the iPhone, then pair again."
        )
      } else if let challenge = Challenge(
        deviceID: request.id, name: request.name, commitment: request.commitment,
        created: request.created, macNonce: randomNonce())
      {
        // A new request takes down any offer at once, so a swapped request
        // never sits under the owner's click.
        show(nil, problem: nil)
        try await cloud.challenge(request.id, nonce: challenge.macNonce)
        challenges[request.id] = challenge
      } else {
        show(
          nil,
          problem: "A device asked to pair with an id Board does not accept, so it was ignored.")
      }
      return
    }
    switch challenge.check(request.reveal) {
    case .waiting:
      return
    case .offer(let device, let code):
      show(Offer(device: device, code: code), problem: nil)
    case .refused:
      show(
        nil,
        problem:
          "The iPhone's request changed after this Mac answered it, or it did not prove it holds its key, so Board will not add it. Cancel on the iPhone, then pair again."
      )
    }
  }

  private func show(_ offer: Offer?, problem: String?) {
    if offer != self.offer {
      self.offer = offer
      scope = .suggested
      failure = nil
    }
    self.problem = failure ?? problem
  }

  func cancel() async {
    failure = nil
    guard let offer else { return }
    try? await cloud.withdraw(offer.device.id)
    self.offer = nil
  }

  /// Adds the offered phone with the scope the owner picked, and keeps the
  /// name it gave. Both are taken before Touch ID, and the offer must be
  /// unchanged after it. True when the phone was added.
  func add() async -> Bool {
    guard let offer else { return false }
    let scope = self.scope
    failure = nil
    let context = LAContext()
    do {
      try await context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        localizedReason: "add \(offer.device.name) to the keys that may sign for you")
      guard self.offer == offer else { return false }
      try SignersFiles.pair(offer.device, scope: scope)
      PhoneNotes.store(offer.device, at: Date())
      try await cloud.answer(
        offer.device.id, scope: scope, macName: Host.current().localizedName ?? "your Mac")
      self.offer = nil
      return true
    } catch let error as LAError where error.code == .userCancel {
      return false
    } catch {
      failure = Self.explain(error)
      problem = failure
      return false
    }
  }

  private static func explain(_ error: Error) -> String {
    "Board could not finish pairing: \(error.localizedDescription)"
  }
}

/// Removes a paired phone's lines from both allowed signers files after
/// Touch ID, then forgets its name. False when the owner cancels Touch ID.
/// It throws when a file kept the phone's line, naming each such file.
@MainActor
func removePhone(id: String, name: String) async throws -> Bool {
  let context = LAContext()
  // Touch ID alone, as for adding, so the panel offers no password button.
  context.localizedFallbackTitle = ""
  do {
    try await context.evaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics,
      localizedReason: "remove \(name) from the keys that may sign for you")
  } catch let error as LAError where error.code == .userCancel {
    return false
  }
  try SignersFiles.remove(id)
  PhoneNotes.forget(id)
  return true
}

struct PairingSheet: View {
  /// Closes the sheet: after Cancel while it waits, and once a phone is added.
  let close: () -> Void
  @State private var pairing = MacPairing()

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if let offer = pairing.offer {
        ask(offer)
      } else {
        waiting
      }
      if let problem = pairing.problem {
        Text(problem).foregroundStyle(.red).font(.callout)
      }
    }
    .padding(EdgeInsets(top: 28, leading: 28, bottom: 20, trailing: 28))
    .task { await pairing.watch() }
  }

  private var waiting: some View {
    VStack(alignment: .leading, spacing: 14) {
      heading("Add an iPhone", "Open Board on your iPhone.")
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text("Waiting for your iPhone…")
      }
      Text("Both devices need to be signed in to the same iCloud account.")
        .foregroundStyle(.secondary).font(.callout)
      HStack {
        Spacer()
        Button("Cancel", action: close).keyboardShortcut(.cancelAction)
      }
    }
  }

  private func ask(_ offer: Offer) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      heading(
        "Add \(offer.device.name)",
        "Approve requests from your phone when you're away from this Mac.")
      HStack(alignment: .firstTextBaseline, spacing: 14) {
        Text(offer.code).font(.system(size: 30, weight: .semibold).monospacedDigit()).tracking(6)
        Text("Same code on your iPhone? If not, cancel.").foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 0) {
        Text("This iPhone can approve").fontWeight(.semibold).padding(.bottom, 2)
        option(.approvals, "Agent requests", "When an agent wants to write or change a file.")
        Divider()
        option(.orders, "Orders", "Standing instructions every agent follows.")
      }
      HStack(alignment: .top) {
        DisclosureGroup("Details") {
          VStack(alignment: .leading, spacing: 6) {
            Text("Key \(offer.device.fingerprint) · Secure Enclave, Face ID or Touch ID")
            ForEach(SignersFiles.lines(offer.device, scope: pairing.scope), id: \.1) {
              file, line in
              Text(
                "Adds to \(SignersFiles.shown(file)): \(line)"
              )
            }
          }
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.secondary)
        Button("Cancel") { Task { await pairing.cancel() } }
          .keyboardShortcut(.cancelAction)
        Button("Add with Touch ID") { Task { if await pairing.add() { close() } } }
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
      }
    }
  }

  private func heading(_ title: String, _ subtitle: String) -> some View {
    HStack(spacing: 14) {
      Image(systemName: "iphone")
        .font(.title2)
        .frame(width: 44, height: 44)
        .background(.tint.opacity(0.15), in: .rect(cornerRadius: 12))
        .foregroundStyle(.tint)
      VStack(alignment: .leading) {
        Text(title).font(.title2.bold())
        Text(subtitle).foregroundStyle(.secondary)
      }
    }
  }

  private func option(_ scope: Scope, _ title: String, _ detail: String) -> some View {
    Toggle(
      isOn: Binding(
        get: { pairing.scope.contains(scope) },
        set: { if $0 { pairing.scope.insert(scope) } else { pairing.scope.remove(scope) } })
    ) {
      VStack(alignment: .leading) {
        Text(title).fontWeight(.semibold)
        Text(detail).foregroundStyle(.secondary).font(.callout)
      }
    }
    .toggleStyle(.checkbox)
    .padding(.vertical, 10)
  }
}
