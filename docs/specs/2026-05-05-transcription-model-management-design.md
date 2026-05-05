# Transcription Model Management Design

## Summary

This design adds a dedicated macOS Settings window to QuickMeeting and introduces a `Models` settings pane for managing local transcription models. The scope of this slice is limited to model management only: listing supported models, downloading a model on explicit user action, deleting downloaded models, and selecting a default model for future transcription use. Actual transcription execution remains out of scope.

The implementation will use the open-source `argmax-oss-swift` package as the underlying Whisper runtime integration. QuickMeeting will support exactly these transcription models in this slice:

- `tiny`
- `small`
- `large-v3-v20240930_626MB`

The app will not auto-download any model. All downloads must begin from an explicit user click in the UI.

## Goals

- Add a dedicated Settings window that can expand to cover future app settings.
- Add a `Models` pane inside Settings for transcription model management.
- Support downloading, deleting, and inspecting the supported transcription models.
- Persist a default model selection for future transcription flows.
- Keep Argmax-specific behavior behind an internal service boundary rather than exposing it directly to the UI.

## Non-Goals

- Running transcription jobs
- Meeting-level transcription UI
- Background or automatic model downloads
- Support for user-supplied custom model repositories
- Support for models beyond `tiny`, `small`, and pinned `large-v3-v20240930_626MB`
- Parallel multi-model downloads in the initial version

## Product Decisions

- Settings will live in a dedicated macOS Settings window, not embedded in the main meeting window.
- The first settings pane will be `Models`.
- Model downloads start only when the user clicks `Download`.
- `large-v3` is pinned to the exact Argmax identifier `large-v3-v20240930_626MB`.
- The app will store a default transcription model selection even though transcription itself is not yet implemented.

## UI Design

### Settings Shell

QuickMeeting will add a dedicated Settings window using standard macOS app behavior. The settings experience should be structured to scale as the app grows.

Initial structure:

- Sidebar-based Settings window
- First pane: `Models`

Future panes such as `General`, `Recording`, `Export`, or similar can be added later without reshaping the window architecture.

### Models Pane

The `Models` pane will display a fixed list of supported transcription models. The pane should not query a remote model catalog or expose arbitrary runtime models.

Each model row will show:

- Display name
- Short speed/quality description
- Installation state
- Installed size when available
- Progress while downloading
- Contextual action button

Supported row actions:

- `Download` when the model is not installed
- `Delete` when the model is installed
- Disabled action state while the model is downloading

The pane will also include a default model selector:

- The selector is enabled only when at least one supported model is installed.
- The selector displays only currently installed supported models.
- If no models are installed, the selector shows an empty or placeholder state.

### Suggested Copy

Model descriptions should help users choose without needing technical knowledge.

- `Tiny`: Fastest download and best for debugging or quick tests.
- `Small`: Balanced speed and accuracy for everyday use.
- `Large v3`: Highest accuracy, largest download, best for production-quality transcription.

This copy can be refined during implementation, but the intent should remain stable.

## Architecture

### Overview

The feature should be split into app-facing model management logic, package-specific Argmax integration, and view-model-driven SwiftUI presentation. SwiftUI should never talk to Argmax APIs directly.

Dependency flow:

`Settings UI -> ModelsSettingsViewModel -> TranscriptionModelManager -> Argmax adapter + settings persistence`

### Core Types

#### `TranscriptionModelCatalog`

Static app-owned catalog that defines the supported models and presentation metadata.

Responsibilities:

- Define the supported model set
- Map app-level model identifiers to Argmax identifiers
- Provide display names and descriptions
- Provide stable sort order

The catalog is the source of truth for which models QuickMeeting supports.

#### `TranscriptionModel`

An app-owned type representing a supported model. It should not be a raw package string in UI-facing code.

Suggested fields:

- `id`
- `displayName`
- `argmaxModelID`
- `summary`
- `sortOrder`

#### `TranscriptionModelManager`

App-facing service boundary for model management.

Responsibilities:

- Report supported models and their current local status
- Download a model on demand
- Delete a downloaded model
- Report in-flight state for the UI
- Read and write the default model selection
- Validate persisted default selection against actual installed models

This type should be defined as a protocol-backed service boundary so the UI and tests are isolated from Argmax implementation details.

#### `ArgmaxWhisperModelStore`

Concrete integration adapter responsible for dealing with `argmax-oss-swift`.

Responsibilities:

- Trigger model acquisition for a selected Argmax model identifier
- Discover whether a supported model exists on disk
- Read model folder metadata needed for installed size and path inspection
- Delete downloaded model folders
- Translate package-specific errors into app-level failures

Any assumptions about Argmax cache layout or model folder conventions should be isolated to this adapter.

#### `ModelSettingsStore`

Lightweight persistence component for settings data such as the default transcription model.

Responsibilities:

- Persist the default model identifier
- Clear invalid selections
- Remain independent from model installation state

`UserDefaults` is sufficient for this slice.

### View Models

#### `SettingsViewModel`

Lightweight shell-level view model for settings navigation if needed. It may be minimal in the first version, but the settings structure should leave room for future panes.

#### `ModelsSettingsViewModel`

View-model layer for the `Models` pane.

Responsibilities:

- Expose model rows to SwiftUI
- Load model state from `TranscriptionModelManager`
- Start downloads
- Handle deletion confirmation flow
- Bind the default model selector
- Surface user-facing error messages

## Data and State Model

### Supported Model State

Each supported model should have an explicit state derived from local inspection plus any active operation state.

Suggested state cases:

- `notInstalled`
- `downloading(progress: Double?)`
- `installed(sizeInBytes: Int64, installedAt: Date?)`
- `failed(message: String)`

Notes:

- `progress` may be indeterminate if Argmax does not expose reliable progress callbacks for the chosen integration path.
- `installedAt` is optional and should only be surfaced if it can be read cheaply and reliably from local metadata.

### Source of Truth

- Installed model state should be derived from the filesystem through the model-store adapter.
- The app should not persist an independent “installed models” list.
- The default model selection should be stored separately in settings persistence.

This ensures the app can recover correctly if model files are removed outside the app or left partially downloaded.

## Workflow Design

### Open Settings

1. User opens the app’s Settings window.
2. The Settings shell renders the `Models` pane.
3. `ModelsSettingsViewModel` requests current model statuses from `TranscriptionModelManager`.
4. The UI renders the supported models in a stable order.

### Download Model

1. User clicks `Download` on a supported model row.
2. The row enters `downloading`.
3. `TranscriptionModelManager` starts a model download through `ArgmaxWhisperModelStore`.
4. If progress is available, the row updates accordingly. If not, it shows indeterminate progress.
5. On success, the row enters `installed`.
6. If no default model is currently selected, the newly installed model becomes the default automatically.

Rules:

- Never overwrite an existing default selection automatically.
- If this is the first installed supported model, it becomes the default.

### Delete Model

1. User clicks `Delete` for an installed model.
2. App asks for confirmation.
3. `TranscriptionModelManager` requests deletion through `ArgmaxWhisperModelStore`.
4. On success, the row returns to `notInstalled`.
5. If the deleted model was the default:
   - switch to another installed model in stable priority order if one exists
   - otherwise clear the default selection

### Select Default Model

1. User chooses an installed model from the default-model control.
2. `ModelsSettingsViewModel` writes the selection through `TranscriptionModelManager`.
3. The setting persists through `ModelSettingsStore`.

The control should not allow selecting a model that is not currently installed.

## Concurrency and Operation Rules

To keep the first version predictable:

- Allow only one active model download at a time.
- Disable the delete action for a model while that model is downloading.
- Disable starting a second model download while another download is in progress.
- A failed download should leave the model retryable.

This is intentionally conservative and can be relaxed later if the UX needs concurrent downloads.

## Error Handling

The feature should surface clear, friendly errors while preserving enough detail internally for debugging.

Expected failure cases:

- network or remote fetch failure during model download
- incomplete or corrupted downloaded model folder
- deletion failure due to filesystem error
- persisted default model points to a model no longer installed
- Argmax integration failure when resolving a supported model

Rules:

- Failed downloads must not mark the model as installed.
- Deletion failure must leave the model row in installed state.
- Invalid default selections must be cleared or replaced during state refresh.
- User-facing error presentation should be concise and retry-friendly.

## Integration with Existing Architecture

This slice extends the architecture described in [quickmeeting-architecture-design.md](/Users/heymdall/Developer/QuickMeeting/docs/quickmeeting-architecture-design.md) by introducing a real `ModelManager`-like subsystem and a dedicated settings shell.

Expected app-level additions:

- settings window scene or command wiring in `QuickMeetingApp`
- app-level construction and injection of `TranscriptionModelManager`
- settings entry point in the app menu using standard macOS conventions

This slice should not yet modify meeting transcription workflows beyond preparing the model-management foundation they will eventually depend on.

## Testing Strategy

### Unit Tests

- `TranscriptionModelCatalog` exposes exactly the supported pinned models in stable order.
- Default-selection persistence works and invalid selections are rejected.
- Installed-state refresh reflects filesystem contents.
- Download success transitions state from `notInstalled` to `downloading` to `installed`.
- Download failure transitions state to `failed` and preserves retry.
- Deleting the default model updates or clears the default selection correctly.

### View-Model Tests

- `ModelsSettingsViewModel` renders supported model rows from manager state.
- Download button availability matches state.
- Delete button availability matches state.
- Default model selector only includes installed models.
- User-facing error state is set when manager operations fail.

### UI/Integration Coverage

- Settings window opens and shows the `Models` pane.
- The `Models` pane loads without triggering any automatic downloads.
- A supported installed model appears as installed after app relaunch.

## Implementation Notes

- Keep the package integration behind app-owned protocols from the start.
- Prefer deriving installation state from disk rather than mirroring it into persisted app metadata.
- Avoid coupling the model-management implementation to meeting or transcription code paths in this slice.
- Use app-owned naming and identifiers in UI code, with Argmax model identifiers confined to the catalog and adapter layers.

## Open Decisions Resolved

- Settings location: dedicated macOS Settings window
- Download trigger: explicit user click only
- Supported model list: fixed and app-owned
- `large-v3` variant: pinned to `large-v3-v20240930_626MB`
- Scope boundary: no transcription execution in this slice
