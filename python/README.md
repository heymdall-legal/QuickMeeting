# Python Sidecar

This directory contains the source for the transcription sidecar used by QuickMeeting.

## What is committed

- `main.py`
- `pyproject.toml`
- `uv.lock`

## What is generated locally

- `.venv/`
- `lib/`

The app launches `python/lib/bin/python` at runtime and loads third-party packages from `python/.venv`. The bootstrap script recreates the full bundled interpreter under `python/lib` from a uv-managed Python install, so the app bundle does not depend on a developer-local `~/.local/share/uv/...` path.

## Setup

From the repository root:

```bash
./scripts/bootstrap_python.sh
```

That script:

1. installs Python 3.12 through `uv`
2. copies the uv-managed Python runtime into `python/lib`
3. creates `python/.venv` against that bundled interpreter
4. installs locked dependencies into `.venv`

## Re-locking dependencies

When dependency versions change:

```bash
cd python
uv lock --python 3.12
```

# Interface

Interface

This repository contains a CLI script, `example.py`, that runs transcription and speaker diarization for a single audio file.

The script is designed to be machine-readable on `stdout`: it prints newline-delimited JSON objects that represent status updates and the final result.

## Invocation

Run the script as:

```bash
python main.py --input-file PATH --hf-token TOKEN [options]
```

Required arguments:

- `--input-file PATH`
  Path to the input audio file.
  Parsed as a filesystem path.
  Must exist and must be a regular file.

- `--hf-token TOKEN`
  Hugging Face access token.
  Passed through as a string.
  Also exported to the process environment as `HF_TOKEN`.

Optional arguments:

- `--hf-home PATH`
  Path to a Hugging Face cache/home directory.
  Parsed as a filesystem path.
  If provided, exported to the process environment as `HF_HOME`.

- `--language CODE`
  Language hint for Whisper.
  Passed through as a string.
  Example: `en`, `ru`.

- `--initial-prompt TEXT`
  Initial prompt for Whisper.
  Passed through as a string.

- `--known-speakers-file PATH`
  Path to a JSON file with known speaker profiles.
  Parsed as a filesystem path.
  Must exist and must be a regular file.

## Known Speakers File Format

`--known-speakers-file` must point to JSON in one of these shapes:

1. A top-level array of speaker objects.
2. An object with a `speakers` field containing that array.

Each speaker object must contain:

- `id`: non-empty string
- `centroid`: non-empty array of numbers — a single embedding vector, **or**
- `centroids`: non-empty array of embedding vectors — multiple samples for the same speaker

Use `centroids` when you have more than one recording of the same speaker; the script compares the meeting speaker against each stored vector and takes the best match.

Example with a single centroid:

```json
[
  {
    "id": "alice",
    "centroid": [0.12, -0.33, 0.91]
  },
  {
    "id": "bob",
    "centroid": [0.44, 0.05, -0.18]
  }
]
```

Example with multiple centroids:

```json
[
  {
    "id": "alice",
    "centroids": [
      [0.12, -0.33, 0.91],
      [0.15, -0.30, 0.88]
    ]
  },
  {
    "id": "bob",
    "centroid": [0.44, 0.05, -0.18]
  }
]
```

If the JSON shape is invalid, the script exits with an error event on `stdout`.

## Stdout Contract

The script prints JSON objects to `stdout`, one per line.

Wrappers should treat `stdout` as a stream of events:

1. Zero or more progress events.
2. One final terminal event:
   either `{"status":"completed",...}` or `{"status":"error",...}`.

The script starts by printing:

```json
{"status":"running"}
```

After that it may print progress events during model downloads, transcription, and diarization.

### Event: `running`

Printed once, before pipeline execution begins.

```json
{
  "status": "running"
}
```

### Event: `downloading`

Printed during Hugging Face model or file downloads.

Fields:

- `status`: always `"downloading"`
- `percent`: integer from `1` to `100`
- `file`: optional string, usually a model/file name
- `bytes_downloaded`: optional integer
- `bytes_total`: optional integer

Example:

```json
{
  "status": "downloading",
  "percent": 42,
  "file": "mlx-community/whisper-turbo/model.bin",
  "bytes_downloaded": 42000000,
  "bytes_total": 100000000
}
```

Notes:

- Multiple `downloading` events can be emitted.
- Percent values are milestone-style integers and may advance one point at a time.

### Event: `transcribing`

Printed during Whisper transcription progress.

Fields:

- `status`: always `"transcribing"`
- `percent`: integer from `1` to `100`

Example:

```json
{
  "status": "transcribing",
  "percent": 77
}
```

### Event: `diarization`

Printed during speaker diarization progress.

Fields:

- `status`: always `"diarization"`
- `step`: string step name reported by the diarization pipeline
- `percent`: integer from `1` to `100`

Example:

```json
{
  "status": "diarization",
  "step": "segmentation",
  "percent": 15
}
```

### Event: `completed`

Printed once when processing succeeds.

Fields:

- `status`: always `"completed"`
- `speakers`: array of detected meeting speakers
- `segments`: array of transcript segments

Shape:

```json
{
  "status": "completed",
  "speakers": [
    {
      "id": "SPEAKER_00",
      "matched_id": "alice",
      "probability": 0.913,
      "centroid": [0.12, -0.33, 0.91]
    }
  ],
  "segments": [
    {
      "speaker": "SPEAKER_00",
      "start": 0.0,
      "end": 2.481,
      "text": "Hello everyone"
    }
  ]
}
```

`speakers` fields:

- `id`: diarization speaker id produced for this meeting, string
- `matched_id`: matched known speaker id, string or `null`
- `probability`: cosine similarity for a matched or candidate speaker, number or `null`
- `centroid`: detected speaker embedding centroid, array of numbers or `null`

`segments` fields:

- `speaker`: diarization speaker id, string
- `start`: segment start time in seconds, rounded to 3 decimals
- `end`: segment end time in seconds, rounded to 3 decimals
- `text`: transcript text for the segment, string

Speaker matching behavior:

- `matched_id` is set when the script finds either a strong match or a candidate match against `--known-speakers-file`.
- `probability` is only populated for matched/candidate speakers.
- If no known speakers file is provided, `matched_id` and `probability` are usually `null`.

### Event: `error`

Printed once when the script fails.

Fields:

- `status`: always `"error"`
- `reason`: human-readable string

Example:

```json
{
  "status": "error",
  "reason": "input file does not exist: /path/to/file.m4a"
}
```

Errors can happen because of:

- missing or invalid CLI arguments
- missing input files
- invalid known speakers JSON
- runtime failures from dependencies such as `ffmpeg`, transcription, diarization, or model downloads

## Exit Codes

- `0`: success, after emitting a `completed` event
- `1`: failure, after emitting an `error` event

## Wrapper Notes

For a programmatic wrapper, the safest assumptions are:

- Read `stdout` line by line.
- Parse every line as JSON. Ignore lines, that cannot be parsed.
- Expect progress events in any quantity, including none.
- Stop on the first terminal event with `status` equal to `completed` or `error`.
- Use the process exit code as a secondary success/failure signal.
- Do not rely on free-form human text being printed by the script itself; the intended contract is JSON events on `stdout`.
