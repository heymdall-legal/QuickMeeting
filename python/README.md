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
