import SwiftUI

func speakerAutocompleteSuggestions(
    attendeeNames: [String],
    draft: String
) -> [String] {
    let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedDraft.isEmpty else {
        return attendeeNames
    }

    let normalizedDraft = trimmedDraft.localizedLowercase

    return attendeeNames.filter { attendeeName in
        let normalizedAttendeeName = attendeeName.localizedLowercase
        guard normalizedAttendeeName != normalizedDraft else {
            return false
        }

        return normalizedAttendeeName.contains(normalizedDraft)
    }
}

func speakerRenameSuggestions(
    attendeeNames: [String],
    draft: String
) -> [String] {
    speakerAutocompleteSuggestions(
        attendeeNames: attendeeNames.filter { !QMSpeakerPalette.isUnnamed($0) },
        draft: draft
    )
}

struct SpeakerNameInputState {
    var attendeeNames: [String]
    var draft: String

    mutating func updateDraft(_ newValue: String) {
        draft = newValue
    }

    var suggestions: [String] {
        speakerAutocompleteSuggestions(
            attendeeNames: attendeeNames,
            draft: draft
        )
    }

    var showsSuggestions: Bool {
        !suggestions.isEmpty
    }

    mutating func selectSuggestion(_ suggestion: String) -> String {
        draft = suggestion
        return suggestion
    }

    func commitDraft(currentDisplayName: String) -> String? {
        guard draft != currentDisplayName else {
            return nil
        }

        return draft
    }
}

struct SpeakerNameInput: View {
    let displayName: String
    let attendeeNames: [String]
    let onCommit: (String) -> Void

    @State private var state: SpeakerNameInputState
    @FocusState private var isFocused: Bool

    init(
        displayName: String,
        attendeeNames: [String],
        onCommit: @escaping (String) -> Void
    ) {
        self.displayName = displayName
        self.attendeeNames = attendeeNames
        self.onCommit = onCommit
        _state = State(
            initialValue: SpeakerNameInputState(
                attendeeNames: attendeeNames,
                draft: displayName
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(
                "Speaker name",
                text: Binding(
                    get: { state.draft },
                    set: { newValue in
                        state.updateDraft(newValue)
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit {
                commitDraftIfNeeded()
            }

            if state.showsSuggestions {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(state.suggestions.enumerated()), id: \.offset) { _, suggestion in
                        Button {
                            let selected = state.selectSuggestion(suggestion)
                            onCommit(selected)
                        } label: {
                            Text(suggestion)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }
                }
            }
        }
        .onChange(of: displayName) { _, newValue in
            if state.draft != newValue {
                state.draft = newValue
            }
        }
        .onChange(of: attendeeNames) { _, newValue in
            state.attendeeNames = newValue
        }
        .onChange(of: isFocused) { _, newValue in
            if !newValue {
                commitDraftIfNeeded()
            }
        }
    }

    private func commitDraftIfNeeded() {
        guard let committedDraft = state.commitDraft(currentDisplayName: displayName) else {
            return
        }

        onCommit(committedDraft)
    }
}
