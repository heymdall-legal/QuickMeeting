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
    func autocompleteSuggestionsReturnFullStoredListForEmptyDraft() {
        let suggestions = speakerAutocompleteSuggestions(
            attendeeNames: ["Masha", "Ilya"],
            draft: ""
        )

        #expect(suggestions == ["Masha", "Ilya"])
    }

    @Test
    func autocompleteSuggestionsHideResultsWhenNoMatchesExist() {
        let suggestions = speakerAutocompleteSuggestions(
            attendeeNames: ["Masha", "Ilya"],
            draft: "zzz"
        )

        #expect(suggestions.isEmpty)
    }

    @Test
    func renamePopoverSuggestionsFilterAttendeesCaseInsensitively() {
        let suggestions = speakerRenameSuggestions(
            attendeeNames: ["Masha", "Ilya", "Sasha"],
            draft: "ASH"
        )

        #expect(suggestions == ["Masha", "Sasha"])
    }

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

    @Test
    func suggestionsStayHiddenWhenAttendeeHintsAreUnavailable() {
        let state = SpeakerNameInputState(
            attendeeNames: [],
            draft: "ma"
        )

        #expect(state.suggestions.isEmpty)
        #expect(!state.showsSuggestions)
    }

    @Test
    func suggestionListHeightIsCappedForLongAttendeeLists() {
        #expect(SpeakerNameInputLayout.suggestionListHeight(suggestionCount: 0) == 0)
        #expect(SpeakerNameInputLayout.suggestionListHeight(suggestionCount: 3) < SpeakerNameInputLayout.maxSuggestionListHeight)
        #expect(SpeakerNameInputLayout.suggestionListHeight(suggestionCount: 60) == SpeakerNameInputLayout.maxSuggestionListHeight)
    }

    @Test
    func commitDraftReturnsTrailingWhitespaceWhenEditWasOnlyTypedLocally() {
        var state = SpeakerNameInputState(
            attendeeNames: ["Vasia Pupkin"],
            draft: "Vasia"
        )

        state.updateDraft("Vasia ")

        #expect(state.commitDraft(currentDisplayName: "Vasia") == "Vasia ")
    }

    @Test
    func commitDraftSkipsUnchangedDraft() {
        let state = SpeakerNameInputState(
            attendeeNames: ["Vasia Pupkin"],
            draft: "Vasia"
        )

        #expect(state.commitDraft(currentDisplayName: "Vasia") == nil)
    }
}
