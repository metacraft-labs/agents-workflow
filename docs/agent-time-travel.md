## Agent Time-Travel — Product and Technical Specification

### Summary

Agent Time-Travel lets a user review an agent’s coding session and jump back to precise moments in time to intervene by inserting a new chat message. Seeking to a timestamp restores the corresponding filesystem state using snapshot anchors. The feature integrates across CLI, TUI, WebUI, and REST, and builds on the snapshot provider model referenced by other docs (see `docs/fs-snapshots/overview.md`).

### Goals

- Enable scrubbing through an agent session with exact visual terminal playback and consistent filesystem state.
- Allow the user to pause at any moment, inspect the workspace at that time, and branch a new session with an injected instruction.
- Provide first-class support for ZFS/Btrfs/NILFS2 where available; offer robust fallbacks on APFS (macOS), VSS (Windows), and non‑CoW Linux.
- Expose a consistent API and UX across WebUI, TUI, and CLI.

### Non-Goals

- Full semantic capture of each application’s internal state (e.g., Vim buffers). We replay terminal output and restore filesystem state.
- Reflowing terminal content to arbitrary sizes. Playback uses a fixed terminal grid with recorded resize events.
- A kernel-level journaling subsystem; we rely on filesystem snapshots and pragmatic fallbacks.

### Concepts and Terminology

- **Recording (cast)**: A terminal I/O timeline (e.g., asciinema v2). Visually faithful to what the user saw; does not encode TUI semantics.
- **Marker**: A labeled point in the recording timeline (auto or manual). Used for navigation.
- **Anchor**: A marker that has an associated filesystem snapshot reference (snapshots are created near-synchronously with the marker).
- **Frame/Poster**: A visual state at a specific timestamp; the player can seek and render the frame.
- **Timeline**: The ordered set of events (log, markers, anchors, resizes) across a session.
- **Branch**: A new session created from an anchor’s filesystem state with an injected chat message.

### Architecture Overview

- **Recorder**: Captures terminal output as an asciinema cast (preferred) or ttyrec; emits markers at logical boundaries (e.g., per-command).
- **Anchor Manager**: Creates and tracks snapshot anchors; maintains mapping {timestamp → snapshotId}.
- **Snapshot Provider Abstraction**: Chooses provider per host (ZFS → Btrfs → APFS/VSS → NILFS2/Overlay → copy). See Provider Matrix below.
- **Timeline Service (REST)**: Lists anchors/markers, seeks, and branches; streams timeline events via SSE.
- **Players (WebUI/TUI)**: Embed the recording; render markers; orchestrate seek/branch actions.
- **Workspace Manager**: Mounts read-only snapshots for inspection and prepares writable clones/upper layers for branches.

### Recording and Timeline Model

- **Format**: asciinema v2 JSON with events [time, type, data]; optional input events for richer analysis. Idle compression is configurable.
- **Markers**: Auto markers at shell boundaries (preexec/precmd/DEBUG trap) and runtime milestones (provisioned, tests passed). Manual markers via UI/CLI.
- **Random Access**: Web player supports `startAt`, `poster`, and markers; for power users/offline analysis we may store a parallel ttyrec to enable IPBT usage.
- **Alternate Screen Semantics**: Full-screen TUIs (vim, less, nano) switch to the alternate screen; scrollback of earlier output is not available while paused on the alternate screen. Navigation uses timeline seek rather than scrollback.

### Snapshot Anchors and Providers (multi‑OS)

- **Creation Policy**:
  - Default: Create an anchor at each shell command boundary and at important runtime milestones.
  - Max frequency controls and deduplication to avoid thrashing during rapid events.
  - Anchors include: id, ts, label, provider, snapshotRef, notes.

- **Provider Preference (host‑specific)**:
  - Linux:
    - ZFS: instantaneous snapshots and cheap writable clones (branch from snapshot via clone).
    - Btrfs: subvolume snapshots (constant-time), cheap writable snapshots for branching.
    - NILFS2: continuous checkpoints; promote relevant checkpoints to snapshots (mkcp -s); mount past checkpoints read-only (`-o ro,cp=<cno>`).
    - Overlay fallback: lower = base tree, upper/work on fast storage (tmpfs or RAM-backed NILFS2/zram/brd) for ephemeral branches.
    - Copy fallback: `cp --reflink=auto` when possible; otherwise deep copy (last resort).
  - macOS:
    - APFS snapshots: read-only, instantaneous; mountable for inspection. For branch, create an overlay-style writable workspace using a read-only snapshot as lower with a writable upper (FSKit/macFUSE backend when available) or fast copy-on-write file clones where feasible.
  - Windows:
    - VSS shadow copies: read-only snapshots at volume level; expose snapshot content for inspection. For branch, materialize a writable workspace via differencing VHD(X) layered over the snapshot materialization or by copying-on-write using a WinFsp-backed overlay.

- **Branch Semantics**:
  - Writable clones are native on ZFS/Btrfs. On APFS/VSS, branching is emulated via overlay or virtual disk differencing over the read-only snapshot view.
  - Branches are isolated workspaces; original session remains immutable.

### Syncing Terminal Time to Filesystem State

- **Shell Integration (default)**:
  - zsh: `preexec`/`precmd` hooks to emit markers and trigger snapshot anchors.
  - bash: `trap DEBUG` + `PROMPT_COMMAND` pair to delimit commands.
  - fish: `fish_preexec`/`fish_postexec` equivalents.
- **Runtime Integration**: The runner emits timeline events (SSE) at milestones; the anchor manager aligns nearest anchor ≤ timestamp.
- **Advanced (future)**: eBPF capture of PTY I/O and/or FS mutations; rr-based post‑facto reconstruction of casts; out of scope for v1 but compatible with this model.

### REST API Extensions

- `GET /api/v1/sessions/{id}/timeline`
  - Returns markers and anchors ordered by time.
  - Response:
  ```json
  {
    "sessionId": "...",
    "durationSec": 1234.5,
    "recording": {"format": "cast", "uri": "s3://.../cast.json"},
    "markers": [
      {"id": "m1", "ts": 12.34, "label": "git clone", "kind": "auto"}
    ],
    "anchors": [
      {"id": "a1", "ts": 12.40, "label": "post-clone", "provider": "btrfs", "snapshot": {"id": "repo@tt-001", "mount": "/.snapshots/..."}}
    ]
  }
  ```

- `POST /api/v1/sessions/{id}/anchors`
  - Create a manual anchor near a timestamp; returns anchor with snapshot ref.

- `POST /api/v1/sessions/{id}/seek`
  - Parameters: `ts`, or `anchorId`.
  - Returns a short‑lived read‑only mount (host path and/or container path) for inspection; optionally pauses the session player at `ts`.

- `POST /api/v1/sessions/{id}/branch`
  - Parameters: `fromTs` or `anchorId`, `name`, optional `injectedMessage`.
  - Creates a new session with a writable workspace cloned/overlaid from the anchor snapshot.
  - Response includes new `sessionId` and workspace mount info.

- `GET /api/v1/sessions/{id}/snapshots`
  - Lists underlying provider snapshots/checkpoints with metadata (for diagnostics and retention tooling).

- SSE additions on `/sessions/{id}/events`
  - New event types: `timeline.marker`, `timeline.anchor.created`, `timeline.branch.created`.

### CLI Additions

- `aw timeline list <SESSION_ID>` — Show markers and anchors.
- `aw timeline anchor add <SESSION_ID> [--ts <sec>] [--label <str>]` — Create manual anchor.
- `aw timeline seek <SESSION_ID> (--ts <sec> | --anchor <ID>) [--open-ide]` — Mount read‑only view; optionally open IDE.
- `aw timeline branch <SESSION_ID> (--ts <sec> | --anchor <ID>) --name <branch-name> [--message <chat>]` — Start a branched session from that point.

### WebUI UX

- **Player Panel**: Embed `<asciinema-player>` with `poster`, markers, and a scrubber. Time cursor shows nearest anchor and label.
- **Pause & Intervene**: On pause, surface “Inspect snapshot” and “Branch from here”.
- **Inspect Snapshot**: Mounts read‑only view; open a lightweight file browser and offer “Open IDE at this point”.
- **Branch From Here**: Dialog to enter an injected message and name; creates a new session; link both sessions for side‑by‑side comparison.
- **History View**: Timeline list with filters (auto/manual markers, anchors only).

### TUI UX

- **Timeline Bar**: Keyboard scrubbing with markers (jump prev/next), current time, and anchor badges.
- **Keys**:
  - Space: pause/resume
  - [ / ]: prev/next marker; { / }: prev/next anchor
  - i: Intervene (branch dialog)
  - s: Seek and open read‑only snapshot in left pane; right pane keeps the player/logs

### Data Model Additions (Session)

- `recording`: `{ format: "cast"|"ttyrec", uri, width, height, hasInput }`
- `timeline`: `{ durationSec, markers: [...], anchors: [...] }`
- `anchors[*]`: `{ id, ts, label, provider, snapshot: { id, mount?, details? } }`
- `branchOf` (optional): parent session id and anchor id when branched.

### Security and Privacy

- **Keystrokes**: If input capture is enabled, redact known password prompts (heuristics based on ECHO off and common prompts). Make input capture opt‑in.
- **Access Control**: Timeline/seek/branch require the same permissions as session access; snapshot mounts use least‑privilege read‑only where applicable.
- **Data Retention**: Separate retention for recordings vs snapshots; defaults minimize data exposure. Encrypt at rest when stored remotely.

### Performance, Retention, and Limits

- **Snapshot Rate Limits**: Min interval between anchors; coalesce within a small window (e.g., 250–500 ms) to avoid bursty commands creating many anchors.
- **Retention**: Policies by count/age/size. Prune unreferenced checkpoints (e.g., NILFS2) and expired provider snapshots.
- **Storage**: Cast files compressed; offload to object storage. Mounts are short‑lived and garbage‑collected.

### Failure Modes and Recovery

- **Snapshot Creation Fails**: Create a marker with `anchor=false` and reason; continue recording; allow manual retry.
- **Seek Failure**: Report provider error and suggest nearest valid anchor.
- **Provider Degraded**: Fall back per provider preference, with explicit event logged to the timeline.

### Provider Semantics Matrix (summary)

- **ZFS**: Snapshots and clones — ideal for anchors and branches.
- **Btrfs**: Subvolume snapshots — ideal for anchors and branches.
- **NILFS2**: Continuous checkpoints; promote to snapshots; mount via `cp=<cno>`; branch via overlay.
- **APFS**: Read‑only snapshots; branch via overlay or file clones (no native writable clone of snapshot).
- **VSS**: Read‑only shadow copies; branch via differencing VHD/overlay.
- **Overlay/Copy**: Universal fallbacks when CoW is unavailable.

### Open Issues and Future Work

- eBPF PTY and FS hooks for automatic, runner‑independent capture.
- rr‑based post‑facto reconstruction of casts and fine‑grained anchors.
- IPBT integration for advanced timeline browsing on ttyrec recordings.
- FSKit backend maturation on macOS for robust overlay branching without kexts.
- Windows containers integration to provide stronger per‑session isolation when branching.


