// Markdown split into the blocks the preview window draws. Inline syntax,
// such as emphasis and links, stays in each block's text for the view to
// render.
import Foundation

public enum MarkdownBlock: Sendable, Hashable {
  case heading(level: Int, text: String)
  case paragraph(String)
  case bullet(String)
  case numbered(marker: String, text: String)
  case quote(String)
  case code(String)
  case rule

  public static func parse(_ source: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var paragraph: [String] = []
    var code: [String]?

    func flush() {
      if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
      paragraph = []
    }

    for line in source.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("```") {
        if let lines = code {
          blocks.append(.code(lines.joined(separator: "\n")))
          code = nil
        } else {
          flush()
          code = []
        }
        continue
      }
      if code != nil {
        code?.append(line)
        continue
      }
      if trimmed.isEmpty {
        flush()
      } else if let heading = Self.heading(trimmed) {
        flush()
        blocks.append(heading)
      } else if ["---", "***", "___"].contains(trimmed) {
        flush()
        blocks.append(.rule)
      } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
        flush()
        blocks.append(.bullet(String(trimmed.dropFirst(2))))
      } else if let numbered = Self.numbered(trimmed) {
        flush()
        blocks.append(numbered)
      } else if trimmed.hasPrefix(">") {
        flush()
        blocks.append(.quote(trimmed.dropFirst().trimmingCharacters(in: .whitespaces)))
      } else {
        paragraph.append(trimmed)
      }
    }
    if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
    flush()
    return blocks
  }

  private static func heading(_ line: String) -> MarkdownBlock? {
    let hashes = line.prefix { $0 == "#" }.count
    guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
    return .heading(level: hashes, text: String(line.dropFirst(hashes + 1)))
  }

  private static func numbered(_ line: String) -> MarkdownBlock? {
    let digits = line.prefix { $0.isNumber }
    guard !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") else { return nil }
    return .numbered(marker: digits + ".", text: String(line.dropFirst(digits.count + 2)))
  }
}
