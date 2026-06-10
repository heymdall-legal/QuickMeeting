# Python Sidecar Bootstrap Design

## Summary

This change makes the bundled Python sidecar reproducible without committing a full copied CPython tree or a committed virtual environment. The repository keeps only the Python source and lockfile, while developers recreate the local runtime with a small bootstrap script.

## Decisions

- Commit `python/main.py`, `python/pyproject.toml`, `python/uv.lock`, setup docs, and bootstrap tooling.
- Do not commit `python/.venv` or `python/lib`.
- Pin the Python runtime to 3.12 so Swift-side path assumptions stay stable.
- Launch `python/lib/bin/python` at runtime.
- Keep a fallback to `python/.venv/bin/python` so older local setups do not break immediately.
- Recreate `python/lib` locally by copying the uv-managed Python distribution instead of committing it to git.
- Use `.venv` only for third-party packages, installed against the copied bundled interpreter.

## Data Flow

1. A developer clones the repo.
2. The developer runs `./scripts/bootstrap_python.sh`.
3. `uv` installs Python 3.12.
4. The bootstrap script copies that Python distribution into `python/lib`.
5. The bootstrap script creates `.venv` using the copied interpreter in `python/lib`.
6. `uv` installs locked dependencies into that active virtualenv with copy-based package linking.
7. Xcode bundles the `python/` folder as a resource.
8. The app launches `python/lib/bin/python` by default and falls back to `python/.venv/bin/python` only when needed.

## Error Handling

- If `uv` is missing, the bootstrap script exits with a clear message.
- If the preferred `.venv` interpreter is absent in a built app bundle, Swift falls back to the legacy path before reporting a missing helper.
- Dependency drift is controlled through `uv.lock`.

## Testing

- Focused `SidecarTranscriptionServiceTests` cover preferred and fallback runtime resolution.
- Manual verification covers the bootstrap script creating `.venv` and the compatibility shim.
