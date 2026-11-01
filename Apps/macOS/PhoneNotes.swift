// The name each phone gave when it paired, and when it paired, kept in the
// Mac app's defaults. The allowed signers lines carry only the device id,
// and the phone deletes its iCloud pairing records, so nothing else keeps
// them. They are shown and never trusted: what a phone may sign comes from
// the two files alone.
import Foundation
import Pairing

struct PhoneNote: Codable, Equatable {
  let name: String
  let paired: Date
}

enum PhoneNotes {
  private static let key = "pairedPhones"

  /// Every note, by device id.
  static func all(_ defaults: UserDefaults = .standard) -> [String: PhoneNote] {
    guard let data = defaults.data(forKey: key),
      let notes = try? JSONDecoder().decode([String: PhoneNote].self, from: data)
    else { return [:] }
    return notes
  }

  /// Keeps the device's name and the time, replacing any earlier note.
  static func store(_ device: Device, at date: Date, in defaults: UserDefaults = .standard) {
    var notes = all(defaults)
    notes[device.id] = PhoneNote(name: device.name, paired: date)
    if let data = try? JSONEncoder().encode(notes) { defaults.set(data, forKey: key) }
  }
}
