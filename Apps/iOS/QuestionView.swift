// One question an agent asked, with its options as a choice list, the
// agent's reasons, the owner's note and the details behind a disclosure. It
// follows the signed-off "Questions from agents" design: nothing is chosen
// when it opens, and Answer stays off until an option is chosen, or until the
// note has words when "Something else" is chosen. An answer is not signed, so
// it needs no Face ID. Beside the inbox on the open Duo in landscape, a side
// strip holds Back and Answer instead of the bars.
import Requests
import SwiftUI

struct QuestionView: View {
  let question: Question
  let requests: PhoneRequests
  /// Closes the question from the side strip. Nil outside the layout that
  /// sets the question beside the inbox.
  var back: (() -> Void)?
  @State private var choice: QuestionChoice?
  @State private var note = ""
  @State private var details = false
  @State private var failure: String?
  @Environment(\.dismiss) private var dismiss

  init(question: Question, requests: PhoneRequests, back: (() -> Void)? = nil) {
    self.question = question
    self.requests = requests
    self.back = back
    switch Fixture.on ? Fixture.chosen : nil {
    case "other"?:
      _choice = State(initialValue: .other)
    case let id?:
      _choice = State(initialValue: .option(id))
      _note = State(initialValue: Fixture.note ?? "")
      _details = State(initialValue: Fixture.note != nil)
    case nil: break
    }
  }

  var body: some View {
    let ready =
      question.canAnswer(choice, note: note) && !requests.answering.contains(question.id)
    Group {
      if back != nil {
        HStack(spacing: 0) {
          form
          strip(ready: ready)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
      } else {
        form
          .navigationTitle("Question")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
              Spacer()
              // A label of its own, since a toolbar shows a Label's icon alone.
              Button(action: send) {
                HStack(spacing: 6) {
                  Image(systemName: "paperplane")
                  Text("Answer")
                }
              }
              .buttonStyle(.borderedProminent)
              .disabled(!ready)
            }
          }
      }
    }
    .alert(
      "Board could not send your answer", isPresented: .constant(failure != nil),
      actions: { Button("OK") { failure = nil } }, message: { Text(failure ?? "") })
  }

  private var form: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Text(question.question).font(.headline)
          Text(
            ([question.boardName] + (question.askedDate.map { ["asked " + askedLabel($0)] } ?? []))
              .joined(separator: " · ")
          )
          .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        if let blocks = question.blocks {
          VStack(alignment: .leading, spacing: 2) {
            Text("Waiting on this").font(.subheadline).foregroundStyle(.secondary)
            Text(blocks).font(.subheadline)
          }
        }
      }
      Section("Choose one") {
        ForEach(question.options, id: \.id) { option in
          optionRow(
            option.text, chosen: choice == .option(option.id),
            recommended: option.id == question.recommendation
          ) { choice = .option(option.id) }
        }
        optionRow("Something else, in my note", chosen: choice == .other, recommended: false) {
          choice = .other
        }
      }
      if let why = question.why {
        Section("Why the agent recommends it") { Text(why).font(.subheadline) }
      }
      if let unchecked = question.note {
        Section("What the agent could not check") { Text(unchecked).font(.subheadline) }
      }
      Section {
        TextField("Optional. The agent reads it with your choice.", text: $note, axis: .vertical)
          .lineLimit(3...)
      } header: {
        Text("Your note")
      } footer: {
        if choice == .other && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Text("Write what you want instead. Answer turns on once the note has words.")
        }
      }
      Section {
        DisclosureGroup("Details", isExpanded: $details) {
          detail("Question", question.path)
          if let session = question.session { detail("Asked by", session) }
          if let mount = question.mount { detail("Repository", mount) }
        }
      }
    }
    .listStyle(.insetGrouped)
  }

  /// One row of the choice list: a radio circle, the option's text, and a
  /// tag on the recommended option.
  private func optionRow(
    _ text: String, chosen: Bool, recommended: Bool, choose: @escaping () -> Void
  ) -> some View {
    Button(action: choose) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
          .font(.title2)
          .foregroundStyle(chosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
        VStack(alignment: .leading, spacing: 6) {
          Text(text).foregroundStyle(.primary)
          if recommended {
            Text("Recommended")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.tint)
              .padding(.horizontal, 8)
              .padding(.vertical, 2)
              .background(Capsule().fill(.tint.opacity(0.12)))
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(chosen ? .isSelected : [])
  }

  private func detail(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.footnote).foregroundStyle(.secondary)
      Text(value).font(.footnote.monospaced()).textSelection(.enabled)
    }
  }

  /// Back at the top of the strip and Answer at the bottom.
  private func strip(ready: Bool) -> some View {
    VStack(spacing: 18) {
      RoundButton(title: "Back", symbol: "chevron.left", size: 48, labelled: true) { back?() }
      Spacer()
      RoundButton(
        title: "Answer", symbol: "paperplane", size: 56, prominent: true, labelled: true,
        action: send
      )
      .disabled(!ready)
    }
    .padding(.top, 16)
    .padding(.bottom, 20)
    .frame(width: 84)
  }

  /// Sends the answer and goes back to the inbox, which says it was sent.
  private func send() {
    Task {
      do {
        try await requests.answer(question, choice: choice, note: note)
        if let back { back() } else { dismiss() }
      } catch {
        failure = error.localizedDescription
      }
    }
  }
}

#Preview("Question") {
  NavigationStack {
    QuestionView(
      question: PreviewQuestions.merge,
      requests: PhoneRequests(preview: [], questions: PreviewQuestions.all))
  }
}
#Preview("Question with a note") {
  NavigationStack {
    QuestionView(
      question: PreviewQuestions.review,
      requests: PhoneRequests(preview: [], questions: PreviewQuestions.all))
  }
}
