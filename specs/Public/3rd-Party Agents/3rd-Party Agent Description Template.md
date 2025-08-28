# <Agent Tool> — Integration Notes

## Overview

Summarize what this tool does and how Agents‑Workflow uses it.

## Credentials

- Environment variables: list supported vars and precedence.
- Config files/locations: paths to mount read‑only if available.
- Host agents/sockets: whether forwarding is supported.
- Minimal test/probe command to validate auth.

## Execution Hooks

- How commands are invoked inside sessions.
- Points where timeline SessionMoments should be emitted.
- Any stderr/stdout peculiarities affecting recording.

## Time‑Travel Considerations

- Side effects on the filesystem and how to snapshot effectively (FsSnapshots).
- Required quiesce/flush operations before creating an FsSnapshot (if any).

## Known Issues

- Platform quirks, rate limits, stability notes.
