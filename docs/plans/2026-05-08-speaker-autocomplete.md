**Goal:** Add attendee-name autocomplete to the speaker rename input so meeting attendee hints appear while typing and a clicked suggestion renames the speaker immediately.

**Architecture:** Introduce a small `SpeakerNameInput` SwiftUI component plus a tiny pure helper for suggestion filtering so the matching rules are easy to test without heavy SwiftUI view tests. Keep `MeetingDetailView` responsible for supplying the current speaker name, `meeting.attendeeNames`, and the existing rename callback, while preserving the current rename flow through `ContentView` and `AppViewModel`.

**Tech Stack:** Swift, SwiftUI, Swift Testing, Xcode/macOS test runner

---

### Task 1: Add a testable autocomplete helper

**Files:**
- Create: `QuickMeeting/Views/SpeakerNameInput.swift`
- Create: `QuickMeetingTests/SpeakerNameInputTests.swift`

- [ ] **Step 1: Write the failing filtering tests**

```swift
import Testing
@testable import QuickMeeting

struct SpeakerNameInputTests {
    @Test
    func autocompleteSuggestionsUseCaseInsensitiveSubstringMatching() {
        let suggestions = speakerAutocompleteSuggestions(
            attendeeNames: ["Masha", "Ilya", "Sasha"],
            draft: "ash"
        )

        #expect(suggestions == ["Masha", "Sasha"])
    }

    @Test
    func autocompleteSuggestionsOmitExactCaseInsensitiveMatch() {
        let suggestions = speakerAutocompleteSuggestions(
            attendeeNames: ["Masha", "Masha Ivanova", "Ilya"],
            draft: "masha"
        )

        #expect(suggestions == ["Masha Ivanova"])
    }

    @Test
    func autocompleteSuggestionsHideResultsForEmptyDraft() {
        let suggestions = speakerAutocompleteSuggestions(
            attendeeNames: ["Masha", "Ilya"],
            draft: ""
        )

        #expect(suggestions.isEmpty)
    }

    @Test
    func autocompleteSuggestionsHideResultsWhenNoMatchesExist() {
        let suggestions = speakerAutocompleteSuggestions(
            attendeeNames: ["Masha", "Ilya"],
            draft: "zzz"
        )

        #expect(suggestions.isEmpty)
    }
}
```

- [ ] **Step 2: Run the focused helper tests to verify they fail**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/SpeakerNameInputTests`
Expected: FAIL because `speakerAutocompleteSuggestions(...)` and `SpeakerNameInput.swift` do not exist yet.

- [ ] **Step 3: Write the minimal helper implementation**

```swift
import SwiftUI

func speakerAutocompleteSuggestions(
    attendeeNames: [String],
    draft: String
) -> [String] {
    let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedDraft.isEmpty else {
        return []
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
```

- [ ] **Step 4: Run the focused helper tests to verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/SpeakerNameInputTests`
Expected: PASS.

- [ ] **Step 5: Commit the helper slice**

```bash
git add QuickMeeting/Views/SpeakerNameInput.swift QuickMeetingTests/SpeakerNameInputTests.swift
git commit -m "test: add speaker autocomplete filtering"
```

### Task 2: Build the speaker autocomplete input component

**Files:**
- Modify: `QuickMeeting/Views/SpeakerNameInput.swift`
- Modify: `QuickMeetingTests/SpeakerNameInputTests.swift`

- [ ] **Step 1: Write the failing suggestion-selection tests**

```swift
@Test
func selectionStateReturnsFilteredSuggestionsInOriginalOrder() {
    let state = SpeakerNameInputState(
        attendeeNames: ["Masha", "Sasha", "Pasha"],
        draft: "ash"
    )

    #expect(state.suggestions == ["Masha", "Sasha", "Pasha"])
    #expect(state.showsSuggestions)
}

@Test
func selectingSuggestionUpdatesDraftAndHidesSuggestions() {
    var state = SpeakerNameInputState(
        attendeeNames: ["Masha", "Ilya"],
        draft: "ma"
    )

    let selected = state.selectSuggestion("Masha")

    #expect(selected == "Masha")
    #expect(state.draft == "Masha")
    #expect(state.suggestions.isEmpty)
    #expect(!state.showsSuggestions)
}
```

- [ ] **Step 2: Run the focused component-state tests to verify they fail**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/SpeakerNameInputTests`
Expected: FAIL because `SpeakerNameInputState` does not exist yet.

- [ ] **Step 3: Write the minimal state and view implementation**

```swift
struct SpeakerNameInputState {
    let attendeeNames: [String]
    var draft: String

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
}

struct SpeakerNameInput: View {
    let attendeeNames: [String]
    let onCommit: (String) -> Void
    @State private var state: SpeakerNameInputState

    init(
        displayName: String,
        attendeeNames: [String],
        onCommit: @escaping (String) -> Void
    ) {
        self.attendeeNames = attendeeNames
        self.onCommit = onCommit
        _state = State(initialValue: SpeakerNameInputState(attendeeNames: attendeeNames, draft: displayName))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(
                "Speaker name",
                text: Binding(
                    get: { state.draft },
                    set: { newValue in
                        state.draft = newValue
                        onCommit(newValue)
                    }
                )
            )
            .textFieldStyle(.roundedBorder)

            if state.showsSuggestions {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            let selected = state.selectSuggestion(suggestion)
                            onCommit(selected)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run the focused component-state tests to verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/SpeakerNameInputTests`
Expected: PASS.

- [ ] **Step 5: Commit the input component**

```bash
git add QuickMeeting/Views/SpeakerNameInput.swift QuickMeetingTests/SpeakerNameInputTests.swift
git commit -m "feat: add speaker autocomplete input"
```

### Task 3: Wire speaker autocomplete into meeting detail

**Files:**
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
- Modify: `QuickMeetingTests/SpeakerNameInputTests.swift`

- [ ] **Step 1: Write the failing meeting-detail integration test for empty hints**

```swift
@Test
func suggestionsStayHiddenWhenAttendeeHintsAreUnavailable() {
    let state = SpeakerNameInputState(
        attendeeNames: [],
        draft: "ma"
    )

    #expect(state.suggestions.isEmpty)
    #expect(!state.showsSuggestions)
}
```

- [ ] **Step 2: Run the focused tests to verify the empty-hints behavior is covered**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/SpeakerNameInputTests`
Expected: PASS after the helper and state logic already handle empty attendee lists.

- [ ] **Step 3: Replace the plain speaker `TextField` in `MeetingDetailView` with `SpeakerNameInput`**

```swift
ForEach(transcriptSpeakers) { speaker in
    SpeakerNameInput(
        displayName: resolvedDisplayName(for: speaker.id),
        attendeeNames: meeting.attendeeNames
    ) { newValue in
        updateSpeakerName(newValue, for: speaker.id)
    }
}
```

- [ ] **Step 4: Run the focused speaker-related test set**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/SpeakerNameInputTests -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/MeetingStoreTests`
Expected: PASS for the autocomplete helper tests and no regressions in the attendee persistence or rename-related app behavior.

- [ ] **Step 5: Commit the meeting-detail wiring**

```bash
git add QuickMeeting/Views/MeetingDetailView.swift QuickMeeting/Views/SpeakerNameInput.swift QuickMeetingTests/SpeakerNameInputTests.swift
git commit -m "feat: show attendee autocomplete for speaker names"
```
