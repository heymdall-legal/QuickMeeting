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
}
