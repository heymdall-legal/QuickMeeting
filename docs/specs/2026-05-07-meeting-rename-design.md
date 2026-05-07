## Meeting Rename Design

### Goal
Add a simple inline way to rename a meeting from the detail view, with desktop-friendly keyboard behavior and persisted validation.

### UI
- Replace the static meeting title in the detail view with an inline editable title field.
- The field shows the current meeting title and supports editing in place.
- Pressing `Return` commits the rename.
- Moving focus away from the field also commits the rename.
- Pressing `Esc` cancels editing and restores the original title.
- If the confirmed title is empty after trimming whitespace, restore the previous title instead of saving.

### Data Flow
- `MeetingDetailView` owns temporary edit state for the current draft title and the original title being edited.
- When the user confirms an edit, `MeetingDetailView` calls a rename action supplied from the app layer.
- `ContentView` delegates that action to `AppViewModel`.
- `AppViewModel` forwards the rename to `MeetingStore`.
- `MeetingStore` trims the title, rejects an empty final value, updates the meeting title and `updatedAt`, then saves the change.

### Model and Validation
- Add a title rename method on `Meeting` so title mutation and `updatedAt` changes stay together.
- Add a meeting rename method on `MeetingStore` so persistence and validation rules live in one place.
- Rejecting an empty title is a business rule, not just a UI rule, so the store should enforce it even if another caller is added later.
- Existing fallback display text of `Untitled Meeting` remains a presentation concern for older data or unexpected empty titles.

### Error Handling
- If persistence fails during rename, the UI restores the previous title instead of leaving an unsaved draft behind.
- Rename failures should surface through the app view model in the same way other meeting actions expose user-visible errors.

### Testing
- Add a store test proving renaming updates the persisted meeting title and `updatedAt` in a fresh context.
- Add a store test proving an empty trimmed title is rejected and the previous title remains unchanged.
- Add an app-view-model test proving successful rename clears any rename error state.
- Add an app-view-model test proving a failed rename reports an error and does not persist a new title.
