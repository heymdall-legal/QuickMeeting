## Summary

Prevent the transcription default-model picker from rendering with a persisted selection before installed model statuses have loaded.

## Problem

`ModelsSettingsView` currently renders the default-model `Picker` immediately. The view model restores `defaultModelID` from persisted settings before `load()` refreshes installed model statuses, so the picker can momentarily hold `.some(.largeV3)` while its tagged options only include `nil`. SwiftUI logs an invalid-selection warning and may produce undefined picker behavior during that window.

## Chosen Approach

Add an explicit initial-loading state to `ModelsSettingsViewModel` and render a placeholder row in the settings UI until the first status refresh completes.

## Why This Approach

- Avoids exposing the picker with an invalid selection/tag mismatch.
- Preserves the persisted default model without coercing the UI to `None`.
- Keeps the change local to the settings surface instead of altering storage or manager semantics.

## Implementation Notes

- Add `isLoading` to `ModelsSettingsViewModel`, initialized to `true`.
- Set `isLoading` to `false` after `load()` finishes refreshing statuses and updating `defaultModelID`.
- In `ModelsSettingsSections`, render a non-interactive placeholder when `isLoading` is `true`; render the existing picker once loading completes.
- Add targeted tests covering the initial loading state and the post-load transition.

## Testing

- Extend `ModelsSettingsViewModelTests` to verify the view model starts in loading state and clears that state after `load()`.
- Run the focused settings test suite.
