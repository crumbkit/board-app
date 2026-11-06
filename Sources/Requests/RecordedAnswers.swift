// The answers to questions the Mac recorded with Board since the app
// launched. A second copy of the phone's `QuestionAnswer` record, such as one
// saved again after a save that failed late, holds the same answer. The Mac
// drops that copy instead of running `plans.answer` again, which Board would
// refuse as already answered.

/// The answers the relay recorded, by record name. The relay keeps one for
/// its lifetime; it is not stored.
public struct RecordedAnswers: Sendable {
  private var answers: [String: QuestionAnswer] = [:]

  public init() {}

  /// Remembers an answer Board recorded.
  public mutating func remember(_ answer: QuestionAnswer) {
    answers[answer.name] = answer
  }

  /// Whether this answer equals one already recorded: the same question,
  /// option and note. A different answer to the same question is not a repeat.
  public func isRepeat(_ answer: QuestionAnswer) -> Bool {
    answers[answer.name] == answer
  }
}
