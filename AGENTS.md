# AGENTS.md

## Keep Command Output Low-Noise

- Prefer narrow test runs over broad ones. Use `-only-testing:` and targeted suites whenever possible.
- For long-running commands, start them once and poll for status instead of requesting large output dumps repeatedly.
- Keep command output caps small by default. Only ask for more output when the tail is not enough to diagnose the issue.
- Prefer focused reads like `rg` and `sed -n` over dumping whole files or logs.
- Reuse a stable `-derivedDataPath` for related `xcodebuild` runs when possible to reduce rebuild noise.
- When a command fails, inspect the final error lines or targeted follow-up output instead of pulling the full build transcript into context.
