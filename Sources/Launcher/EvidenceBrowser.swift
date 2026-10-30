// The evidence preview window's state: which of an item's evidence files it
// shows, its name search, and the metadata comparison at its foot.
import Foundation

/// How the preview window draws a file.
public enum PreviewKind: Sendable, Hashable {
  case markdown, image, text, other

  public static func of(path: String) -> PreviewKind {
    let ext = (path as NSString).pathExtension.lowercased()
    if ["md", "markdown"].contains(ext) { return .markdown }
    if ["png", "jpg", "jpeg", "gif", "heic", "tiff", "webp", "bmp"].contains(ext) { return .image }
    let text = [
      "txt", "log", "json", "jsonl", "yaml", "yml", "toml", "xml", "csv", "tsv", "swift", "rs",
      "go",
      "rb", "py", "js", "ts", "tsx", "sh", "c", "h", "diff", "patch", "ini", "cfg",
    ]
    return text.contains(ext) || ext.isEmpty ? .text : .other
  }
}

/// One evidence file with the title its item gave it.
public struct EvidenceFile: Sendable, Hashable {
  public let id: String
  public let title: String
  public let evidence: Evidence

  public var name: String { (evidence.path as NSString).lastPathComponent }
  public var previewKind: PreviewKind { .of(path: evidence.path) }
}

extension Item {
  /// The item as an evidence file, when it is one.
  var evidenceFile: EvidenceFile? {
    guard case .evidence(let evidence) = body else { return nil }
    return EvidenceFile(id: id, title: title, evidence: evidence)
  }
}

/// A row of the comparison: a label and the value for the previous, current
/// and next file. Nil where there is no such file.
public struct ComparisonRow: Sendable, Hashable {
  public let label: String
  public let previous: String?
  public let current: String
  public let next: String?
}

public struct EvidenceBrowser: Sendable, Hashable {
  public let files: [EvidenceFile]
  public private(set) var index: Int
  /// Whether the name search covers the preview.
  public private(set) var searching = false
  public var query = "" {
    didSet { searchIndex = 0 }
  }
  public private(set) var searchIndex = 0

  init(files: [EvidenceFile], index: Int) {
    precondition(!files.isEmpty, "an evidence browser needs a file")
    self.files = files
    self.index = min(max(index, 0), files.count - 1)
  }

  public var current: EvidenceFile { files[index] }

  /// "2 of 5".
  public var position: String { "\(index + 1) of \(files.count)" }

  public var hasPrevious: Bool { index > 0 }
  public var hasNext: Bool { index < files.count - 1 }

  public mutating func move(_ delta: Int) {
    index = min(max(index + delta, 0), files.count - 1)
  }

  // MARK: Search

  /// The files whose name contains every word of the query.
  public var matches: [EvidenceFile] {
    let words = query.lowercased().split(whereSeparator: \.isWhitespace)
    return files.filter { file in
      let name = file.name.lowercased()
      return words.allSatisfy { name.contains($0) }
    }
  }

  public mutating func openSearch() {
    searching = true
    query = ""
  }

  public mutating func moveSearch(_ delta: Int) {
    let count = matches.count
    guard count > 0 else { return }
    searchIndex = min(max(searchIndex + delta, 0), count - 1)
  }

  /// Shows the chosen match and closes the search. Esc closes it without a
  /// choice.
  public mutating func closeSearch(choosing: Bool) {
    if choosing, matches.indices.contains(searchIndex),
      let chosen = files.firstIndex(of: matches[searchIndex])
    {
      index = chosen
    }
    searching = false
  }

  // MARK: Comparison

  public var comparison: [ComparisonRow] {
    let previous = hasPrevious ? files[index - 1].evidence : nil
    let next = hasNext ? files[index + 1].evidence : nil
    let rows: [(String, (Evidence) -> String)] = [
      ("Kind", \.kind),
      ("Size (reported)", { Self.size($0.size) }),
      ("Added", { Self.date($0.added) }),
      ("Task record", { $0.taskRecord ?? "—" }),
      ("SHA-256 (reported)", { String($0.sha256.prefix(12)) }),
    ]
    return rows.map { label, value in
      ComparisonRow(
        label: label, previous: previous.map(value), current: value(current.evidence),
        next: next.map(value))
    }
  }

  /// "12 KB", in the units Finder uses.
  public static func size(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }

  /// "2026-10-30 09:12", in UTC so it reads the same on every Mac.
  public static func date(_ date: Date) -> String {
    let format = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()
      .dateTimeSeparator(.space).time(includingFractionalSeconds: false)
    return String(date.formatted(format).prefix(16))
  }
}
