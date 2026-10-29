// Pairing on the phone: "Check the code" while the Mac decides, then
// "You're set". Both screens follow the signed-off pairing design.
import CloudKit
import CryptoKit
import Foundation
import LocalAuthentication
import Pairing
import SwiftUI
import UIKit

@MainActor
@Observable
final class PhonePairing {
  enum Phase {
    case connecting
    case checking(code: String)
    case paired(PairingGrant)
    case failed(String)
  }

  private(set) var phase = Phase.connecting
  private let cloud = PairingCloud()
  private var request: PairingRequest?

  /// What one attempt at pairing ended in.
  private enum Ending {
    case finished
    /// The Mac did not answer within `requestLifetime`; start again.
    case expired
  }

  /// Pairs, starting again with a new commitment whenever an attempt expires.
  func start() async {
    while !Task.isCancelled, await attempt() == .expired {}
  }

  /// Commits to the key and a new nonce, reveals them once the Mac has sent
  /// its challenge, and waits for the Mac's grant.
  private func attempt() async -> Ending {
    phase = .connecting
    do {
      let key = try PhoneKey.load()
      try await cloud.prepare()
      let x963 = key.publicKey.x963Representation
      let phoneNonce = randomNonce()
      var request = PairingRequest(
        id: PhoneKey.deviceID, name: UIDevice.current.name,
        commitment: PairingCode.commitment(x963: x963, phoneNonce: phoneNonce), created: Date())
      try await cloud.publish(request, fresh: true)
      self.request = request
      let challenge = await poll(request) { try await $0.challenge(for: request.id) }
      guard case .found(let macNonce) = challenge else { return challenge.ending }
      let context = LAContext()
      context.localizedReason = "prove this iPhone holds its new Board key"
      let signer = try SecureEnclave.P256.Signing.PrivateKey(
        dataRepresentation: key.dataRepresentation, authenticationContext: context)
      request.proof = try signer.signature(
        for: PairingProof.transcript(x963: x963, phoneNonce: phoneNonce, macNonce: macNonce)
      ).rawRepresentation
      request.x963 = x963
      request.phoneNonce = phoneNonce
      guard isCurrent(request) else { return .finished }
      try await cloud.publish(request, fresh: false)
      guard isCurrent(request) else { return .finished }
      phase = .checking(
        code: PairingCode.code(x963: x963, phoneNonce: phoneNonce, macNonce: macNonce))
      let answer = await poll(request) { try await $0.grant(for: request.id) }
      guard case .found(let grant) = answer, isCurrent(request) else { return answer.ending }
      try? await cloud.withdraw(request.id, grant: true)
      self.request = nil
      phase = .paired(grant)
    } catch {
      phase = .failed(Self.explain(error))
    }
    return .finished
  }

  /// Whether `request` is still the one this screen is pairing with, and not
  /// one that Cancel has replaced.
  private func isCurrent(_ request: PairingRequest) -> Bool {
    self.request?.created == request.created
  }

  /// Withdraws the request and starts again with a new commitment.
  func cancel() async {
    guard let request else { return }
    self.request = nil
    try? await cloud.withdraw(request.id)
    await start()
  }

  private enum Polled<Value> {
    case found(Value)
    case stopped
    case expired

    var ending: Ending { if case .expired = self { .expired } else { .finished } }
  }

  /// Reads `value` every 2 seconds until it is not nil, the request is
  /// cancelled, or the request expires.
  private func poll<Value: Sendable>(
    _ request: PairingRequest, _ value: (PairingCloud) async throws -> Value?
  ) async -> Polled<Value> {
    while !Task.isCancelled, self.request?.created == request.created {
      if Date().timeIntervalSince(request.created) > requestLifetime { return .expired }
      if let found = try? await value(cloud) { return .found(found) }
      try? await Task.sleep(for: .seconds(2))
    }
    return .stopped
  }

  private static func explain(_ error: Error) -> String {
    if let error = error as? LAError {
      return "Board needs Face ID to prove this iPhone holds its key: \(error.localizedDescription)"
    }
    if let error = error as? CKError,
      [.notAuthenticated, .accountTemporarilyUnavailable].contains(error.code)
    {
      return "Sign in to iCloud in Settings, with the account your Mac uses, then open Board again."
    }
    if !SecureEnclave.isAvailable {
      return "This device has no Secure Enclave, so it cannot hold a Board key."
    }
    return "Board could not reach your Mac: \(error.localizedDescription)"
  }
}

struct PairingView: View {
  @State private var pairing = PhonePairing()

  var body: some View {
    NavigationStack {
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 22)
        .toolbar { toolbar }
    }
    .task { await pairing.start() }
  }

  @ViewBuilder private var content: some View {
    switch pairing.phase {
    case .connecting:
      VStack(spacing: 10) {
        ProgressView()
        Text("Connecting to your Mac").font(.title3.bold())
        Text("Making this iPhone's key. It never leaves the phone.").foregroundStyle(.secondary)
        Text("Open Board on your Mac.").foregroundStyle(.secondary)
      }
      .multilineTextAlignment(.center)
    case .checking(let code):
      VStack(spacing: 10) {
        Image(systemName: "laptopcomputer.and.iphone")
          .font(.title)
          .frame(width: 56, height: 56)
          .background(.tint.opacity(0.15), in: .rect(cornerRadius: 16))
          .foregroundStyle(.tint)
        Text("Check the code").font(.title3.bold()).padding(.top, 8)
        Text("Your Mac shows the same six digits.").foregroundStyle(.secondary)
        Text(code)
          .font(.system(size: 34, weight: .semibold).monospacedDigit())
          .tracking(6)
          .padding(.vertical, 22)
        Text("Then choose on your Mac what this iPhone can approve.").foregroundStyle(.secondary)
      }
      .multilineTextAlignment(.center)
    case .paired(let grant):
      VStack(spacing: 10) {
        Image(systemName: "checkmark")
          .font(.title.bold())
          .frame(width: 56, height: 56)
          .background(.tint, in: .circle)
          .foregroundStyle(.white)
        Text("You're set").font(.title3.bold()).padding(.top, 8)
        Text(Self.summary(grant)).foregroundStyle(.secondary)
      }
      .multilineTextAlignment(.center)
    case .failed(let message):
      VStack(spacing: 10) {
        Text("Board couldn't pair").font(.title3.bold())
        Text(message).foregroundStyle(.secondary)
        Button("Try again") { Task { await pairing.start() } }.padding(.top, 8)
      }
      .multilineTextAlignment(.center)
    }
  }

  @ToolbarContentBuilder private var toolbar: some ToolbarContent {
    switch pairing.phase {
    case .checking:
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel", systemImage: "xmark") { Task { await pairing.cancel() } }
      }
    default:
      ToolbarItem(placement: .cancellationAction) { EmptyView() }
    }
  }

  static func summary(_ grant: PairingGrant) -> String {
    var things: [String] = []
    if grant.scope.contains(.approvals) { things.append("agent requests") }
    if grant.scope.contains(.orders) { things.append("orders") }
    let device = UIDevice.current.model
    guard !things.isEmpty else {
      return "This \(device) can see requests from \(grant.macName) but cannot approve them."
    }
    let list = ListFormatter.localizedString(byJoining: things)
    return "This \(device) can approve \(list) from \(grant.macName)."
  }
}
