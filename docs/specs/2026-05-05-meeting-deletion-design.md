## Meeting Deletion Design

### Goal
Add a clear, explicit way to delete a meeting from the detail view, and remove its recording artifacts from disk at the same time.

### UI
- Add a destructive `Delete Meeting` button to the detail pane.
- Tapping the button opens a confirmation alert before deletion.
- The button is disabled for the active or recoverable recording session so we do not delete a meeting that the recorder still depends on.

### Data Flow
- `MeetingDetailView` triggers a delete action supplied by `ContentView`.
- `ContentView` delegates the deletion to `AppViewModel`.
- `AppViewModel` removes on-disk meeting artifacts through `MeetingFileStore`, then removes the persisted `Meeting` record through `MeetingStore`.
- If deletion succeeds, the existing selection sync logic picks the next available meeting or clears the detail pane.

### Filesystem Cleanup
- `MeetingFileStore` owns artifact deletion.
- When possible, deletion removes the whole meeting artifact folder.
- If the folder is already gone but the audio file still exists, remove the file directly.
- Missing files are treated as already cleaned up rather than as an error.

### Error Handling
- If filesystem cleanup or persistence deletion fails, the UI shows a user-visible error alert.
- No partial success is reported as a success.

### Testing
- Add a store-level test proving artifact deletion removes the meeting folder and its `.wav` file.
- Add an app-view-model test proving meeting deletion removes both persisted data and artifacts.
- Add coverage for the “cannot delete active meeting” rule through view-model behavior.
