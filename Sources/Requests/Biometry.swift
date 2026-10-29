/// What a device signs with, by the name and symbol the screens show.
/// PhoneKey reads which one the device has.
public enum Biometry: Sendable, Equatable, CaseIterable {
  case faceID, touchID, opticID

  public var name: String {
    switch self {
    case .faceID: "Face ID"
    case .touchID: "Touch ID"
    case .opticID: "Optic ID"
    }
  }

  /// The SF Symbol for it.
  public var symbol: String {
    switch self {
    case .faceID: "faceid"
    case .touchID: "touchid"
    case .opticID: "opticid"
    }
  }
}
